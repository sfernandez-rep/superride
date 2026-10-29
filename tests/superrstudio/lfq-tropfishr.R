# Contract tests for the length-frequency (TropFishR) module. SPDX-License-Identifier: AGPL-3.0-only
#
#   Rscript tests/superrstudio/lfq-tropfishr.R     (R_LIBS_USER = isolated test library)
#
# Validates the module against direct TropFishR calls on the package's own
# reference data (synLFQ7): the prepared LFQ must equal the reference catch
# matrix, restructuring must equal lfqRestructure(), and every background
# ELEFAN run must equal the same call evaluated directly.
args <- commandArgs(FALSE)
script <- sub('^--file=', '', args[grepl('^--file=', args)])
root <- normalizePath(file.path(dirname(script), '../..'), winslash = '/')
toolsEnv <- new.env(parent = globalenv())
.rs.toolsEnv <- function() toolsEnv
.rs.addFunction <- function(name, FN) {
   environment(FN) <- toolsEnv
   assign(paste0('.rs.', name), FN, envir = toolsEnv)
}
sys.source(file.path(root, 'src/cpp/session/modules/SessionSuperRStudio.R'), envir = toolsEnv)
sys.source(file.path(root, 'src/cpp/session/modules/SessionSuperRStudioLfq.R'), envir = toolsEnv)
for (expr in parse(file.path(root, 'src/cpp/r/R/Tools.R')))
   if (is.call(expr) && identical(expr[[1L]], as.name('.rs.addFunction')) &&
       expr[[2L]] %in% c('rBase64EncodeMain', 'rBase64EncodeRest', 'rBase64Encode'))
      eval(expr)
names <- c('fish', 'agg', 'textdates', 'other')
lfq <- function(op, dataset = '', settings = list())
   toolsEnv$.rs.superrstudioDataRpc(op, dataset, '', '', '', intersect(names, ls(globalenv())), settings)
ok <- function(result) { if (!is.null(result$error)) stop(result$error); result }
reject <- function(result, pattern)
   if (is.null(result$error) || !grepl(pattern, result$error))
      stop('Expected error ', pattern, '; got: ', if (is.null(result$error)) 'success' else result$error)

if (!requireNamespace('TropFishR', quietly = TRUE)) {
   status <- lfq('lfq_status')
   stopifnot(identical(status$tropfishr, I(FALSE)))
   fish <- data.frame(len = c(10, 12), day = as.Date(c('2020-01-01', '2020-02-01')))
   reject(lfq('lfq_create', 'fish', list(length = 'len', date = 'day')), 'TropFishR is not installed')
   cat('SKIP: TropFishR absent; missing-package behavior PASS\n')
   quit(save = 'no')
}
data('synLFQ7', package = 'TropFishR', envir = environment())
reference <- synLFQ7
step <- diff(reference$midLengths)[1L]
lower <- reference$midLengths[1L] - step / 2

# individual observations at the class midpoints, one row per fish
cells <- which(reference$catch > 0, arr.ind = TRUE)
fish <- data.frame(len = rep(reference$midLengths[cells[, 1L]], reference$catch[cells]),
                   day = rep(reference$dates[cells[, 2L]], reference$catch[cells]),
                   sp = 'Synthetic')
# rows the module must remove and report (TropFishR would drop or ignore them silently)
fish <- rbind(fish, data.frame(len = c(NA, 0, -4, 12), day = as.Date(c('2016-01-01', '2016-01-01', '2016-01-01', NA)),
                               sp = 'Synthetic'),
              data.frame(len = 30, day = reference$dates[1L], sp = 'Other'))
fish_original <- fish

status <- ok(lfq('lfq_status'))
stopifnot(isTRUE(unclass(status$tropfishr)), nzchar(status$version))
stopifnot(identical(ok(lfq('lfq_list'))$datasets, 'fish'))
columns <- ok(lfq('lfq_columns', 'fish'))
stopifnot(identical(columns$numeric, 'len'), identical(columns$dates, c('day', 'sp')), identical(columns$categories, 'sp'))

base <- list(length = 'len', date = 'day', species_column = 'sp', species = 'Synthetic',
             bin_size = step, lmin = lower, ma = 7)
report <- ok(lfq('lfq_check', 'fish', base))
removed <- setNames(vapply(report$steps, function(s) as.integer(s$removed), 0L),
                    vapply(report$steps, function(s) as.character(s$rule), ''))
stopifnot(report$rows == nrow(fish), report$kept == sum(reference$catch),
          removed[[1L]] == 1L,                                  # other species
          removed[['missing or non-numeric length']] == 1L, removed[['length zero or negative']] == 2L,
          removed[['missing date']] == 1L,
          identical(report$dates, format(reference$dates, '%Y-%m-%d')),
          identical(report$date_counts, as.numeric(colSums(reference$catch))),
          length(report$species) == 2L)
cat('PASS: data check (rows removed per rule, sample sizes per date, species)\n')

created <- ok(lfq('lfq_create', 'fish', base))
prepared <- toolsEnv$.rs.superrstudioLfqState$prepared$lfq
# direct TropFishR use on a hand-filtered copy is the reference pipeline
clean <- fish[fish$sp %in% 'Synthetic' & is.finite(fish$len) & fish$len > 0 & !is.na(fish$day), ]
direct <- TropFishR::lfqRestructure(TropFishR::lfqCreate(clean, Lname = 'len', Dname = 'day', bin_size = step,
                                                         species = 'Synthetic', Lmin = lower), MA = 7)
classes <- seq_along(reference$midLengths)
stopifnot(# the reference data's counts, plus the empty class lfqCreate adds above the largest length
          isTRUE(all.equal(unname(prepared$catch[classes, ]), unname(reference$catch) + 0)),
          all(prepared$catch[-classes, ] == 0), nrow(prepared$catch) == length(classes) + 1L,
          isTRUE(all.equal(prepared$midLengths[classes], reference$midLengths)),
          identical(prepared$dates, reference$dates),
          identical(prepared$catch, direct$catch), identical(prepared$rcounts, direct$rcounts),
          identical(prepared$ASP, direct$ASP), created$ma == 7L,
          startsWith(created$raw_image, 'iVBOR'), startsWith(created$restructured_image, 'iVBOR'),
          identical(fish, fish_original))
# the emitted code reproduces exactly the prepared object
env <- new.env(parent = globalenv())
eval(parse(text = created$code), envir = env)
stopifnot(identical(env$lfq, prepared))
cat('PASS: lfqCreate/lfqRestructure equal the synLFQ7 reference (catch, midLengths, dates, rcounts, ASP); code reproduces\n')

# aggregated frequencies and text dates give the same LFQ
agg <- data.frame(length_mm = reference$midLengths[cells[, 1L]] * 10, n = reference$catch[cells],
                  fecha = format(reference$dates[cells[, 2L]], '%d/%m/%Y'))
invisible(ok(lfq('lfq_create', 'agg', list(length = 'length_mm', date = 'fecha', date_format = '%d/%m/%Y',
                                 freq = 'n', unit = 'mm', bin_size = step, lmin = lower, ma = 7))))
stopifnot(identical(unname(toolsEnv$.rs.superrstudioLfqState$prepared$lfq$catch), unname(direct$catch)))
reject(lfq('lfq_create', 'agg', list(length = 'length_mm', date = 'fecha', freq = 'n')), 'date format')
reject(lfq('lfq_create', 'fish', utils::modifyList(base, list(ma = 6))), 'odd')
reject(lfq('lfq_create', 'fish', c(base[setdiff(names(base), 'species')])), 'species')
reject(lfq('lfq_create', 'fish', c(base, plus_group = 100.3)), 'midpoint')
cat('PASS: aggregated counts in mm with text dates; invalid settings refused\n')

# background ELEFAN runs equal the same TropFishR calls evaluated directly
invisible(ok(lfq('lfq_create', 'fish', base)))
wait <- function(job) {
   for (i in 1:600) {
      polled <- ok(lfq('lfq_poll', settings = list(job = job)))
      if (polled$status != 'running') return(polled)
      Sys.sleep(0.5)
   }
   stop('analysis did not finish')
}
search <- list(linf_min = 100, linf_max = 140, k_min = 0.05, k_max = 1)
started <- ok(lfq('lfq_start', 'fish', c(search, method = 'ga', seeds = '1-2', pop_size = 20, max_iter = 8,
                                         run = 8, label = 'GA quick')))
reject(lfq('lfq_start', 'fish', c(search, method = 'ga')), 'already running')
done <- wait(started$job)
stopifnot(done$status == 'done', length(done$runs) == 2L, length(done$groups) == 1L,
          done$groups[[1L]]$runs == 2L)
pdf(NULL)
for (i in 1:2) {
   run <- done$runs[[i]]
   fit <- suppressWarnings(TropFishR::ELEFAN_GA(direct, seasonalised = FALSE,
      low_par = list(Linf = 100, K = 0.05, t_anchor = 0), up_par = list(Linf = 140, K = 1, t_anchor = 1),
      popSize = 20, maxiter = 8, run = 8, pmutation = 0.1, pcrossover = 0.8, elitism = 3, MA = 7L,
      addl.sqrt = FALSE, seed = i, monitor = FALSE, plot = FALSE, plot.score = FALSE))
   stopifnot(run$seed == i, identical(as.numeric(run$linf), fit$par$Linf), identical(as.numeric(run$k), fit$par$K),
             identical(as.numeric(run$score), fit$Rn_max), run$method == 'ELEFAN_GA',
             grepl('TropFishR::ELEFAN_GA(lfq', run$code, fixed = TRUE))
}
stopifnot(isTRUE(all.equal(as.numeric(done$groups[[1L]]$linf$sd),
                           stats::sd(vapply(done$runs, function(r) as.numeric(r$linf), 0)))))
cat('PASS: ELEFAN_GA in a separate process equals direct ELEFAN_GA per seed; spread across seeds\n')

started <- ok(lfq('lfq_start', 'fish', c(search, method = 'sa', sa_stop = 'iterations', sa_maxit = 40)))
done <- wait(started$job)
run <- done$runs[[3L]]
fit <- TropFishR::ELEFAN_SA(direct, seasonalised = FALSE, init_par = list(Linf = 120, K = 0.3, t_anchor = 0.5),
   low_par = list(Linf = 100, K = 0.05, t_anchor = 0), up_par = list(Linf = 140, K = 1, t_anchor = 1),
   SA_time = NULL, maxit = 40, SA_temp = 1e5, verbose = FALSE, MA = 7L, addl.sqrt = FALSE,
   plot = FALSE, plot.score = FALSE)
stopifnot(run$method == 'ELEFAN_SA', identical(as.numeric(run$linf), fit$par$Linf),
          identical(as.numeric(run$k), fit$par$K), any(grepl('not comparable', done$notes)))
started <- ok(lfq('lfq_start', 'fish', c(search, method = 'elefan', linf_steps = 5, k_steps = 6)))
done <- wait(started$job)
run <- done$runs[[4L]]
fit <- TropFishR::ELEFAN(direct, Linf_range = seq(100, 140, length.out = 5),
   K_range = exp(seq(log(0.05), log(1), length.out = 6)), MA = 7L, addl.sqrt = FALSE,
   method = 'optimise', hide.progressbar = TRUE, plot = FALSE)
stopifnot(run$method == 'ELEFAN', identical(as.numeric(run$linf), fit$par$Linf),
          identical(as.numeric(run$k), fit$par$K), length(done$groups) == 3L)
plot <- ok(lfq('lfq_run_plot', settings = list(run_id = 'run1')))
stopifnot(startsWith(plot$image, 'iVBOR'))
cat('PASS: ELEFAN_SA (iteration-limited) and ELEFAN equal direct calls; comparability notes; fitted-curve plot\n')

# the recorded code reproduces a run from the user's data
env <- new.env(parent = globalenv())
invisible(utils::capture.output(eval(parse(text = done$runs[[1L]]$code), envir = env)))
stopifnot(identical(env$fit$par$Linf, as.numeric(done$runs[[1L]]$linf)))
cat('PASS: recorded run code reproduces the estimate\n')

# cancellation stops the process; stale data are refused
started <- ok(lfq('lfq_start', 'fish', c(search, method = 'ga', seeds = '1', pop_size = 200, max_iter = 5000)))
for (i in 1:60) {
   if (file.exists(toolsEnv$.rs.superrstudioLfqState$jobs[[started$job]]$job$pid)) break
   Sys.sleep(0.5)
}
pid <- as.integer(readLines(toolsEnv$.rs.superrstudioLfqState$jobs[[started$job]]$job$pid))
cancelled <- ok(lfq('lfq_cancel', settings = list(job = started$job)))
Sys.sleep(1)
stopifnot(cancelled$status == 'cancelled', !toolsEnv$.rs.superrstudioLfqAlive(pid),
          length(ok(lfq('lfq_runs'))$runs) == 4L)
fish$len[1L] <- 99
reject(lfq('lfq_start', 'fish', c(search, method = 'ga')), 'changed')
fish <- fish_original
reject(lfq('lfq_start', 'fish', utils::modifyList(search, list(method = 'ga', linf_max = 50))), 'largest length class|minimum below')
reject(lfq('lfq_start', 'fish', c(search, method = 'ga', seeds = '1;2')), 'Seeds')
cat('PASS: cancellation kills the runner; stale data and invalid ranges/seeds refused\n')
