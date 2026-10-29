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
sys.source(file.path(root, 'src/cpp/session/modules/SessionSuperRStudioLfqLibrary.R'), envir = toolsEnv)
sys.source(file.path(root, 'src/cpp/session/modules/SessionSuperRStudioLfqMortality.R'), envir = toolsEnv)
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

# --- preprocessing options (sampling period, quarterly samples) -----------------
period <- utils::modifyList(base, list(period_start = '2016-03-01', period_end = '2016-09-30'))
report <- ok(lfq('lfq_check', 'fish', period))
removed <- setNames(vapply(report$steps, function(s) as.integer(s$removed), 0L),
                    vapply(report$steps, function(s) as.character(s$rule), ''))
inPeriod <- reference$dates >= as.Date('2016-03-01') & reference$dates <= as.Date('2016-09-30')
stopifnot(removed[['sampled before 2016-03-01']] == sum(reference$catch[, reference$dates < as.Date('2016-03-01')]),
          removed[['sampled after 2016-09-30']] == sum(reference$catch[, reference$dates > as.Date('2016-09-30')]),
          identical(report$dates, format(reference$dates[inPeriod], '%Y-%m-%d')))
created <- ok(lfq('lfq_create', 'fish', period))
clean2 <- clean[clean$day >= as.Date('2016-03-01') & clean$day <= as.Date('2016-09-30'), ]
direct2 <- TropFishR::lfqRestructure(TropFishR::lfqCreate(clean2, Lname = 'len', Dname = 'day', bin_size = step,
                                                          species = 'Synthetic', Lmin = lower), MA = 7)
prepared <- toolsEnv$.rs.superrstudioLfqState$prepared$lfq
stopifnot(identical(prepared$catch, direct2$catch), identical(prepared$rcounts, direct2$rcounts))
env <- new.env(parent = globalenv())
eval(parse(text = created$code), envir = env)
stopifnot(identical(env$lfq, prepared))

quarterly <- utils::modifyList(base, list(aggregate = 'quarter'))
created <- ok(lfq('lfq_create', 'fish', quarterly))
direct3 <- TropFishR::lfqRestructure(TropFishR::lfqModify(TropFishR::lfqCreate(clean, Lname = 'len', Dname = 'day',
   bin_size = step, species = 'Synthetic', Lmin = lower), aggregate = 'quarter'), MA = 7)
prepared <- toolsEnv$.rs.superrstudioLfqState$prepared$lfq
stopifnot(identical(prepared$catch, direct3$catch), identical(prepared$rcounts, direct3$rcounts),
          identical(prepared$dates, direct3$dates), length(prepared$dates) == 4L,
          any(grepl('lfqModify', created$transformations)), grepl('aggregate = "quarter"', created$code, fixed = TRUE))
env <- new.env(parent = globalenv())
eval(parse(text = created$code), envir = env)
stopifnot(identical(env$lfq, prepared))
# the older monthly flag is the "month" option
monthly <- ok(lfq('lfq_create', 'fish', c(base, aggregate_dates = TRUE)))
stopifnot(grepl('aggregate_dates = TRUE', monthly$code, fixed = TRUE), any(grepl('by month', monthly$transformations)))
reject(lfq('lfq_check', 'fish', c(base, aggregate = 'year')), 'month or by quarter')
reject(lfq('lfq_check', 'fish', c(base, period_start = '01/03/2016')), 'YYYY-MM-DD')
reject(lfq('lfq_check', 'fish', c(base, period_start = '2016-09-01', period_end = '2016-03-01')), 'start before')
reject(lfq('lfq_create', 'fish', c(base, period_start = '2016-12-01')), 'two sampling dates')
cat('PASS: sampling period and quarterly samples (lfqModify) equal direct TropFishR; transformations recorded\n')

# --- what differs between runs ----------------------------------------------------
invisible(ok(lfq('lfq_create', 'fish', base)))
runs <- ok(lfq('lfq_runs'))
stopifnot(all(c('seed', 'method') %in% runs$varies), !'classes' %in% runs$varies,
          length(runs$groups[[1L]]$differs) == 0L, 'method' %in% runs$groups[[2L]]$differs)
wider <- utils::modifyList(base, list(bin_size = 2 * step))
invisible(ok(lfq('lfq_create', 'fish', wider)))
done <- wait(ok(lfq('lfq_start', 'fish', c(search, method = 'ga', seeds = '1', pop_size = 20, max_iter = 8, run = 8)))$job)
last <- done$groups[[length(done$groups)]]
stopifnot('classes' %in% done$varies, 'classes' %in% last$differs, !'method' %in% last$differs)
first <- toolsEnv$.rs.superrstudioLfqState$runs[[1L]]
configuration <- function(run, ...) utils::modifyList(list(settings = run$lfq_settings, dataset = 'fish',
   md5 = run$lfq_signature$md5, tropfishr = '1.6.6', r = '4.6.1'), list(...))
same <- configuration(first)
differences <- function(...) toolsEnv$.rs.superrstudioLfqDifferences(same, configuration(first, ...))
changed <- function(...) differences(settings = utils::modifyList(first$lfq_settings, list(...)))
stopifnot(length(differences()) == 0L,
          identical(differences(tropfishr = '1.6.5'), 'versions'),
          identical(differences(md5 = strrep('0', 32)), 'data'),
          identical(changed(k_max = 2), 'ranges'),
          identical(changed(ma = 5L), 'restructuring'),
          identical(changed(seeds = '7'), 'seed'),
          # options of another method never make two GA runs differ
          length(changed(sa_maxit = 9)) == 0L)
cat('PASS: comparison names what differs (seed, method, classes, ranges, data, versions) and ignores unused options\n')

# --- saved analyses ---------------------------------------------------------------
invisible(ok(lfq('lfq_create', 'fish', base)))
library <- ok(lfq('lfq_lib'))
stopifnot(identical(as.character(library$path), ''), length(library$analyses) == 0L)
named <- 'GA "base" \\ test ó'   # quotes, backslash and a non-ASCII letter survive the file
library <- ok(lfq('lfq_lib_add', 'fish', c(base, search, method = 'ga', seeds = '1-2', pop_size = 20,
                                            max_iter = 8, run = 8, name = named)))
library <- ok(lfq('lfq_lib_add', settings = list(run_id = 'run1', name = 'Run 1')))
stopifnot(length(library$analyses) == 2L, library$analyses[[1L]]$name == named,
          library$analyses[[2L]]$seeds == '1', library$analyses[[2L]]$results == 1L,
          isTRUE(all.equal(as.numeric(library$analyses[[2L]]$linf), as.numeric(ok(lfq('lfq_runs'))$runs[[1L]]$linf))))
reject(lfq('lfq_lib_add', 'fish', c(base, name = '')), 'name')
file <- tempfile('analyses-', fileext = '.json')
library <- ok(lfq('lfq_lib_save_as', settings = list(path = file)))
stopifnot(file.exists(file), identical(as.character(library$path), gsub('\\\\', '/', file)))
reread <- toolsEnv$.rs.superrstudioLfqLibraryRead(file)
stopifnot(identical(reread[[1L]]$settings, toolsEnv$.rs.superrstudioLfqState$library$analyses[[1L]]$settings),
          identical(reread[[1L]]$name, named))
ids <- vapply(library$analyses, function(a) as.character(a$id), '')
library <- ok(lfq('lfq_lib_rename', settings = list(analysis = ids[[2L]], name = 'Seed 1 again')))
library <- ok(lfq('lfq_lib_duplicate', settings = list(analysis = ids[[2L]])))
stopifnot(length(library$analyses) == 3L, library$analyses[[3L]]$name == 'Seed 1 again (copy)',
          library$analyses[[3L]]$results == 0L, length(toolsEnv$.rs.superrstudioLfqLibraryRead(file)) == 3L)
library <- ok(lfq('lfq_lib_delete', settings = list(analysis = library$analyses[[3L]]$id)))
stopifnot(length(toolsEnv$.rs.superrstudioLfqLibraryRead(file)) == 2L,
          toolsEnv$.rs.superrstudioLfqLibraryRead(file)[[2L]]$name == 'Seed 1 again')
# opening the file in a fresh session state gives the same analyses
toolsEnv$.rs.superrstudioLfqState$library <- list(path = '', analyses = list(), counter = 0L)
library <- ok(lfq('lfq_lib_open', settings = list(path = file)))
stopifnot(length(library$analyses) == 2L, library$analyses[[1L]]$name == named)

# restoring: unchanged data and versions give no warnings and the saved settings
restored <- ok(lfq('lfq_lib_restore', settings = list(analysis = ids[[1L]])))
stopifnot(isTRUE(unclass(restored$dataset_found)), length(restored$warnings) == 0L,
          restored$settings$seeds == '1-2', restored$settings$bin_size == step, restored$settings$ma == 7)
restored2 <- ok(lfq('lfq_lib_restore', settings = list(analysis = ids[[2L]])))
# re-running a saved run's configuration reproduces its estimate
rerun <- lapply(restored2$settings, unclass)
invisible(ok(lfq('lfq_create', as.character(restored2$dataset), rerun)))
done <- wait(ok(lfq('lfq_start', as.character(restored2$dataset), rerun))$job)
again <- done$runs[[length(done$runs)]]
stopifnot(again$seed == 1, identical(as.numeric(again$linf), as.numeric(done$runs[[1L]]$linf)),
          identical(as.numeric(again$k), as.numeric(done$runs[[1L]]$k)))
# changed data, a missing dataset and other versions are reported, never substituted
fish$len[5L] <- fish$len[5L] + 1
restored <- ok(lfq('lfq_lib_restore', settings = list(analysis = ids[[1L]])))
warned <- function(result, code) any(vapply(result$warnings, function(w) as.character(w$code) == code, NA))
stopifnot(warned(restored, 'data_changed'),
          any(grepl('differ from when the analysis was saved', vapply(restored$warnings, function(w) as.character(w$text), ''))))
fish <- fish_original
missing <- toolsEnv$.rs.superrstudioLfqLibrary('lfq_lib_restore', '', list(analysis = ids[[1L]]), 'agg')
stopifnot(!isTRUE(unclass(missing$dataset_found)), warned(missing, 'dataset_missing'),
          identical(missing$warnings[[1L]]$values, 'fish'))
text <- readLines(file, encoding = 'UTF-8')
writeLines(sub('"tropfishr": "1.6.6"', '"tropfishr": "1.6.5"', text, fixed = TRUE), file, useBytes = TRUE)
invisible(ok(lfq('lfq_lib_open', settings = list(path = file))))
restored <- ok(lfq('lfq_lib_restore', settings = list(analysis = ids[[1L]])))
stopifnot(warned(restored, 'tropfishr_version'), identical(restored$warnings[[1L]]$values, c('1.6.5', '1.6.6')))
compared <- ok(lfq('lfq_lib_compare', settings = list(analysis = ids[[1L]], other = ids[[2L]])))
settingsRows <- vapply(compared$rows, function(row) as.character(row$setting), '')
stopifnot('seeds' %in% settingsRows, 'seed' %in% compared$categories)
cat('PASS: saved analyses: add, run configuration with estimates, save/open, rename, duplicate, delete\n')
cat('PASS: restoring warns about changed data, missing dataset and other TropFishR versions; re-run reproduces\n')

# invalid files are refused as a whole
bad <- function(content, pattern) {
   path <- tempfile(fileext = '.json')
   writeLines(content, path, useBytes = TRUE)
   reject(lfq('lfq_lib_open', settings = list(path = path)), pattern)
}
good <- paste(readLines(file, encoding = 'UTF-8'), collapse = '\n')
bad('{"format": "superrstudio-lfq-analyses", "version": 1, "analyses": [', 'not valid JSON')
bad('{"format": "other", "version": 1, "analyses": []}', 'not a SuperR')
bad(sub('"version": 1', '"version": 2', good, fixed = TRUE), 'newer version')
bad(sub('"seeds": "1-2"', '"seeds": 3', good, fixed = TRUE), 'invalid value')
bad(sub('"ma": 7', '"ma": 6', good, fixed = TRUE), 'odd')
bad(sub('"bin_size":', '"unknown_key": 1, "bin_size":', good, fixed = TRUE), 'unknown setting')
bad(sub('"md5": "', '"md5": "zz', good, fixed = TRUE), 'fingerprint')
reject(lfq('lfq_lib_open', settings = list(path = sub('json$', 'txt', file))), '.json')
stopifnot(identical(toolsEnv$.rs.superrstudioJsonRead('{"a": [1, 2.5e1, true, null, "x\\u00e9\\n"], "b": {}}'),
                    list(a = list(1, 25, TRUE, NULL, 'xé\n'), b = structure(list(), names = character()))))
cat('PASS: invalid, foreign, newer, mistyped and tampered files refused; JSON reader exact\n')

# --- mortality: catch curves equal direct TropFishR --------------------------------
invisible(ok(lfq('lfq_create', 'fish', base)))
prepared <- toolsEnv$.rs.superrstudioLfqState$prepared$lfq
growth <- list(cc_linf = 123, cc_k = 0.2)
auto <- ok(lfq('lfq_mortality', 'fish', growth))
lfq_cc <- TropFishR::lfqModify(prepared, par = list(Linf = 123, K = 0.2, t0 = 0), plus_group = 'Linf')
invisible(utils::capture.output(direct <- suppressWarnings(TropFishR::catchCurve(lfq_cc, catch_columns = 1:8,
                                                                                auto = TRUE, plot = FALSE))))
stopifnot(auto$first == direct$reg_int[[1L]], auto$last == direct$reg_int[[2L]],
          identical(as.numeric(auto$z), as.numeric(direct$Z)), identical(as.numeric(auto$se), as.numeric(direct$se)),
          any(vapply(auto$diagnostics, function(d) d$code == 'automatic', NA)),
          startsWith(auto$image, 'iVBOR'), length(auto$points) == length(lfq_cc$midLengths))
chosen <- utils::modifyList(growth, list(cc_first = auto$first + 1L, cc_last = auto$last - 2L, cc_ogive = TRUE,
                                         m_method = 'then_growth'))
result <- ok(lfq('lfq_mortality', 'fish', chosen))
direct <- suppressWarnings(TropFishR::catchCurve(lfq_cc, catch_columns = 1:8,
   reg_int = c(auto$first + 1L, auto$last - 2L), calc_ogive = TRUE, plot = FALSE))
M <- as.numeric(TropFishR::M_empirical(Linf = 123, K_l = 0.2, method = 'Then_growth'))
stopifnot(identical(as.numeric(result$z), as.numeric(direct$Z)), identical(as.numeric(result$se), as.numeric(direct$se)),
          isTRUE(all.equal(c(as.numeric(result$ci_low), as.numeric(result$ci_high)), as.numeric(direct$confidenceInt))),
          identical(as.numeric(result$l50), as.numeric(direct$L50)), identical(as.numeric(result$l75), as.numeric(direct$L75)),
          identical(as.numeric(result$m), M), isTRUE(all.equal(as.numeric(result$f), as.numeric(direct$Z) - M)),
          isTRUE(all.equal(as.numeric(result$e), (as.numeric(direct$Z) - M) / as.numeric(direct$Z))),
          isTRUE(all.equal(as.numeric(result$r2), summary(direct$linear_mod)$r.squared)),
          result$n == sum(is.finite(direct$lnC_dt[(auto$first + 1L):(auto$last - 2L)])),
          sum(vapply(result$points, function(p) isTRUE(unclass(p$used)), NA)) == result$n)
# the generated code reproduces Z, M and E from the user's data frame
env <- new.env(parent = globalenv())
invisible(utils::capture.output(suppressWarnings(eval(parse(text = result$code), envir = env))))
stopifnot(identical(as.numeric(env$cc$Z), as.numeric(result$z)), identical(env$M, M),
          isTRUE(all.equal(as.numeric(env$E), as.numeric(result$e))))
cumulative <- ok(lfq('lfq_mortality', 'fish', c(growth, cc_method = 'cumulative', cc_first = 10, cc_last = 30)))
direct <- suppressWarnings(TropFishR::catchCurve(lfq_cc, catch_columns = 1:8, cumulative = TRUE, reg_int = c(10, 30),
                                                 plot = FALSE))
stopifnot(identical(as.numeric(cumulative$z), as.numeric(direct$Z)))
# seasonal growth: catchCurve() uses C and ts only as elements of the data list
seasonal <- ok(lfq('lfq_mortality', 'fish', c(growth, cc_c = 0.5, cc_ts = 0.2, cc_first = 20, cc_last = 40)))
plain <- ok(lfq('lfq_mortality', 'fish', c(growth, cc_first = 20, cc_last = 40)))
lfq_s <- TropFishR::lfqModify(prepared, par = list(Linf = 123, K = 0.2, t0 = 0, C = 0.5, ts = 0.2), plus_group = 'Linf')
lfq_s[c('C', 'ts')] <- lfq_s$par[c('C', 'ts')]
direct <- suppressWarnings(TropFishR::catchCurve(lfq_s, catch_columns = 1:8, reg_int = c(20, 40), plot = FALSE))
stopifnot(identical(as.numeric(seasonal$z), as.numeric(direct$Z)), !identical(seasonal$z, plain$z))
# one sampling year, and no plus group
year <- ok(lfq('lfq_mortality', 'fish', c(growth, cc_year = '2016', cc_first = 20, cc_last = 40)))
stopifnot(identical(year$z, plain$z), identical(year$years, '2016'))
none <- ok(lfq('lfq_mortality', 'fish', c(growth, cc_plus = 'none', cc_first = 20, cc_last = 40)))
stopifnot(any(vapply(none$diagnostics, function(d) d$code == 'no_age', NA)))
# diagnostics are reported, not hidden
ys <- vapply(auto$points, function(p) if (is.na(p$y)) -Inf else as.numeric(p$y), 0)
peak <- which.max(ys)
early <- ok(lfq('lfq_mortality', 'fish', c(growth, cc_first = peak - 2L, cc_last = peak + 1L, m_method = 'manual',
                                            m_value = 9)))
codes <- vapply(early$diagnostics, function(d) as.character(d$code), '')
stopifnot(all(c('before_peak', 'few_points', 'negative_f') %in% codes), as.numeric(early$f) < 0)
pauly <- ok(lfq('lfq_mortality', 'fish', c(growth, cc_first = 20, cc_last = 40, m_method = 'pauly_linf', m_temp = 20)))
stopifnot(identical(as.numeric(pauly$m),
   as.numeric(TropFishR::M_empirical(Linf = 123, K_l = 0.2, temp = 20, schooling = FALSE, method = 'Pauly_Linf'))))
reject(lfq('lfq_mortality', 'fish', c(growth, cc_first = 20, cc_last = 21)), 'three consecutive')
reject(lfq('lfq_mortality', 'fish', c(growth, cc_method = 'cumulative', cc_ogive = TRUE)), 'ogive')
reject(lfq('lfq_mortality', 'fish', c(growth, cc_plus = 'value', cc_plus_value = 100.3)), 'midpoint')
reject(lfq('lfq_mortality', 'fish', list(cc_k = 0.2)), 'Linf')
reject(lfq('lfq_mortality', 'fish', c(growth, cc_c = 0.5)), 'both C and ts')
reject(lfq('lfq_mortality', 'fish', c(growth, cc_year = '1999')), 'no samples in 1999')
reject(lfq('lfq_mortality', 'fish', c(growth, m_method = 'pauly_linf')), 'temperature')
stopifnot(identical(fish, fish_original))
cat('PASS: catch curves (automatic and chosen points, cumulative, seasonal, ogive) and M/F/E equal direct TropFishR\n')
cat('PASS: catch-curve code reproduces Z, M and E; diagnostics reported; invalid settings refused\n')
