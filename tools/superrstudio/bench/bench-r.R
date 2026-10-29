# SuperRStudio R-level benchmarks. SPDX-License-Identifier: AGPL-3.0-only
#
#   Rscript tools/superrstudio/bench/bench-r.R [repetitions] [output.json]
#
# Run with R_LIBS_USER set to the isolated test library (ggplot2, tibble,
# data.table, TropFishR). Loads the session modules as the tests do and times
# the operations the windows call, on generated data with a fixed seed:
# dataset enumeration, inspect (staleness snapshot), code generation, preview
# rendering (SVG and PNG element maps), and the TropFishR workflow (LFQ
# creation, ELEFAN_GA in the background process versus the same call in
# process). Each measurement is the elapsed time of one call; the summary
# reports the median, minimum and maximum over the repetitions.
args <- commandArgs(TRUE)
repetitions <- if (length(args) >= 1L) as.integer(args[[1L]]) else 5L
output <- if (length(args) >= 2L) args[[2L]] else ''
script <- sub('^--file=', '', grep('^--file=', commandArgs(FALSE), value = TRUE))
root <- normalizePath(file.path(dirname(script), '../../..'), winslash = '/')
toolsEnv <- new.env(parent = globalenv())
.rs.toolsEnv <- function() toolsEnv
.rs.addFunction <- function(name, FN) {
   environment(FN) <- toolsEnv
   assign(paste0('.rs.', name), FN, envir = toolsEnv)
}
for (file in c('SessionSuperRStudio.R', 'SessionSuperRStudioLfq.R', 'SessionSuperRStudioLfqLibrary.R',
               'SessionSuperRStudioLfqMortality.R'))
   sys.source(file.path(root, 'src/cpp/session/modules', file), envir = toolsEnv)
for (expr in parse(file.path(root, 'src/cpp/r/R/Tools.R')))
   if (is.call(expr) && identical(expr[[1L]], as.name('.rs.addFunction')) &&
       expr[[2L]] %in% c('rBase64EncodeMain', 'rBase64EncodeRest', 'rBase64Encode'))
      eval(expr)
stopifnot(requireNamespace('ggplot2', quietly = TRUE))

results <- list()
time <- function(name, expr, n = repetitions, setup = NULL)
{
   expr <- substitute(expr)
   setup <- substitute(setup)
   frame <- parent.frame()
   seconds <- vapply(seq_len(n), function(i) {
      if (!is.null(setup)) eval(setup, frame)
      gc(FALSE)
      started <- Sys.time()   # sub-millisecond resolution (proc.time() is ~10 ms on Windows)
      eval(expr, frame)
      as.numeric(difftime(Sys.time(), started, units = 'secs'))
   }, 0)
   results[[name]] <<- list(name = name, n = n, median = stats::median(seconds), min = min(seconds),
                            max = max(seconds))
   cat(sprintf('%-58s median %9.4f s  (min %.4f, max %.4f, n %d)\n', name, stats::median(seconds),
               min(seconds), max(seconds), n))
}
data <- function(op, dataset, rev = '', x = '', y = '', settings = list())
{
   result <- toolsEnv$.rs.superrstudioDataRpc(op, dataset, as.character(rev), x, y, available(), settings)
   if (!is.null(result$error)) stop(result$error)
   result
}
available <- function() Filter(function(name) is.data.frame(get(name, envir = globalenv())), ls(globalenv()))

set.seed(20261029)
frame <- function(n) data.frame(length = round(rnorm(n, 30, 6), 1), mass = round(rgamma(n, 4, 0.1), 2),
                               site = sample(c('north', 'south', 'east'), n, TRUE),
                               day = as.Date('2020-01-01') + sample(0:730, n, TRUE))

# dataset enumeration: data frames among many objects in the global environment
for (count in c(10L, 200L))
{
   for (i in seq_len(count)) assign(sprintf('bench_frame_%03d', i), frame(100L), envir = globalenv())
   time(sprintf('list datasets (%d data frames)', count), data('list', ''))
   rm(list = ls(globalenv(), pattern = '^bench_frame_'), envir = globalenv())
}

sizes <- c(1000L, 10000L, 100000L)
for (n in sizes)
{
   name <- sprintf('rows_%d', n)
   assign(name, frame(n), envir = globalenv())
   assign(paste0(name, '_dt'), data.table::as.data.table(get(name)), envir = globalenv())
   time(sprintf('inspect data.frame (%s rows)', format(n, big.mark = ',')), data('inspect', name))
   time(sprintf('inspect data.table (%s rows; serialized snapshot)', format(n, big.mark = ',')),
        data('inspect', paste0(name, '_dt')))
   rev <- data('inspect', name)$revision
   time(sprintf('code only, scatter + lm (%s rows)', format(n, big.mark = ',')),
        data('code', name, rev, 'length', 'mass', list(fit = 'lm')))
   time(sprintf('preview map, scatter + lm (%s rows)', format(n, big.mark = ',')),
        data('render', name, rev, 'length', 'mass', list(fit = 'lm')), n = max(3L, repetitions %/% 2L))
   time(sprintf('preview map, histogram (%s rows)', format(n, big.mark = ',')),
        data('render', name, rev, 'length', '', list(kind = 'histogram')), n = max(3L, repetitions %/% 2L))
   time(sprintf('preview map, date X lines (%s rows)', format(n, big.mark = ',')),
        data('render', name, rev, 'day', 'mass', list(geometry = 'lines')), n = max(3L, repetitions %/% 2L))
}
# switching datasets: inspect of another frame right after one was selected
time('switch dataset (10,000 -> 100,000 rows) and render',
     { r <- data('inspect', 'rows_100000')$revision; data('render', 'rows_100000', r, 'length', 'mass') },
     n = 3L, setup = data('inspect', 'rows_10000'))
invisible(data('inspect', 'rows_100000_dt'))
snapshotDt <- object.size(toolsEnv$.rs.superrstudioState$snapshot)
memory <- list(snapshot_data_frame_bytes = as.numeric(object.size(get('rows_100000'))),
               snapshot_data_table_bytes = as.numeric(snapshotDt))

# TropFishR workflow
if (requireNamespace('TropFishR', quietly = TRUE))
{
   utils::data('synLFQ7', package = 'TropFishR', envir = environment())
   cells <- which(synLFQ7$catch > 0, arr.ind = TRUE)
   assign('tallas', data.frame(len = rep(synLFQ7$midLengths[cells[, 1L]], synLFQ7$catch[cells]),
                               day = rep(synLFQ7$dates[cells[, 2L]], synLFQ7$catch[cells])), envir = globalenv())
   lfq <- function(op, settings = list()) {
      result <- toolsEnv$.rs.superrstudioDataRpc(op, 'tallas', '', '', '', available(), settings)
      if (!is.null(result$error)) stop(result$error)
      result
   }
   base <- list(length = 'len', date = 'day', bin_size = 2, lmin = 1, ma = 7)
   time(sprintf('LFQ data check (%s rows)', format(nrow(get('tallas')), big.mark = ',')), lfq('lfq_check', base))
   time('LFQ create + restructure + two plots', lfq('lfq_create', base))
   ga <- c(list(method = 'ga', seeds = '1', pop_size = 30, max_iter = 20, run = 20, linf_min = 100,
                linf_max = 140), base)
   prepared <- toolsEnv$.rs.superrstudioLfqState$prepared$lfq
   time('ELEFAN_GA in process (pop 30, 20 generations)', suppressWarnings(utils::capture.output(
      TropFishR::ELEFAN_GA(prepared, seasonalised = FALSE, low_par = list(Linf = 100, K = 0.05, t_anchor = 0),
         up_par = list(Linf = 140, K = 1, t_anchor = 1), popSize = 30, maxiter = 20, run = 20, pmutation = 0.1,
         pcrossover = 0.8, elitism = 3, MA = 7L, addl.sqrt = FALSE, seed = 1, monitor = FALSE, plot = FALSE,
         plot.score = FALSE))), n = 3L)
   time('ELEFAN_GA background run, start to recorded (same call)', {
      job <- lfq('lfq_start', ga)$job
      repeat { polled <- lfq('lfq_poll', list(job = job)); if (polled$status != 'running') break; Sys.sleep(0.05) }
      stopifnot(polled$status == 'done')
   }, n = 3L)
   time('catch curve + M (automatic points)', lfq('lfq_mortality', list(cc_linf = 123, cc_k = 0.2, m_method = 'then_growth')))
}

system <- list(date = format(Sys.time(), '%Y-%m-%dT%H:%M:%S%z'), r = R.version.string,
               platform = R.version$platform, os = utils::osVersion,
               cpu = Sys.getenv('PROCESSOR_IDENTIFIER'), cores = parallel::detectCores(),
               ggplot2 = as.character(utils::packageVersion('ggplot2')),
               tropfishr = if (requireNamespace('TropFishR', quietly = TRUE)) as.character(utils::packageVersion('TropFishR')) else '',
               data.table = as.character(utils::packageVersion('data.table')), repetitions = repetitions)
cat(sprintf('\nsnapshot memory for a 100,000-row frame: data.frame %s MB (a reference, no copy); data.table %s MB (serialized copy)\n',
            format(memory$snapshot_data_frame_bytes / 2^20, digits = 3),
            format(memory$snapshot_data_table_bytes / 2^20, digits = 3)))
if (nzchar(output))
{
   writeLines(toolsEnv$.rs.superrstudioJsonWrite(list(system = system, memory = memory, results = unname(results))), output)
   cat('written to', output, '\n')
}
