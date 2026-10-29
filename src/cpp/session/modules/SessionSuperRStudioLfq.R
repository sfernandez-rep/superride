# SuperRStudio length-frequency (TropFishR) workflow. SPDX-License-Identifier: AGPL-3.0-only
#
# A guided front end for TropFishR: it prepares length-frequency (LFQ) data
# from a data frame in the session, runs the package's own ELEFAN methods in
# a separate R process and records every run with its complete
# configuration for comparison. Nothing here re-implements an estimation
# method, and the user's data frame is never modified: every step is also
# emitted as R code that reproduces it.
assign('.rs.superrstudioLfqState', new.env(parent = emptyenv()), envir = .rs.toolsEnv())
.rs.superrstudioLfqState$runs <- list()
.rs.superrstudioLfqState$jobs <- list()
.rs.superrstudioLfqState$counter <- 0L

#' Dispatch an LFQ operation (called through the superrstudio_data RPC)
#'
#' @param operation One of the "lfq_*" operations below.
#' @param dataset Name of a data frame in the global environment.
#' @param settings Named list of settings from the dialog.
#' @param available Names of data frames in the global environment.
.rs.addFunction('superrstudioLfq', function(operation, dataset = '', settings = list(), available = character())
{
   fail <- function(message) stop(message, call. = FALSE)
   state <- .rs.superrstudioLfqState
   if (is.null(settings)) settings <- list()
   if (!is.list(settings)) fail('LFQ settings must be named.')
   installed <- requireNamespace('TropFishR', quietly = TRUE)
   if (operation == 'lfq_status')
      return(list(tropfishr = I(installed),
                  version = I(if (installed) as.character(utils::packageVersion('TropFishR')) else ''),
                  r_version = I(as.character(getRversion()))))
   if (operation == 'lfq_list')
   {
      frames <- Filter(function(name) .rs.superrstudioLfqFrame(get(name, envir = .GlobalEnv, inherits = FALSE)),
                       available)
      return(list(datasets = unname(as.character(frames)), tropfishr = I(installed)))
   }
   if (operation == 'lfq_runs') return(.rs.superrstudioLfqRuns())
   if (operation == 'lfq_clear')
   {
      state$runs <- list()
      return(.rs.superrstudioLfqRuns())
   }
   if (operation == 'lfq_poll') return(.rs.superrstudioLfqPoll(settings$job))
   if (operation == 'lfq_cancel') return(.rs.superrstudioLfqCancel(settings$job))
   if (operation == 'lfq_run_plot') return(.rs.superrstudioLfqRunPlot(settings$run_id))
   if (!operation %in% c('lfq_columns', 'lfq_check', 'lfq_create', 'lfq_start'))
      fail('Unsupported operation.')
   if (!dataset %in% available) fail('Dataset no longer exists or is not a data frame. Refresh the list.')
   data <- get(dataset, envir = .GlobalEnv, inherits = FALSE)
   if (!.rs.superrstudioLfqFrame(data)) fail('Select a data frame, tibble or data.table with unique column names.')
   if (nrow(data) > 2e6) fail('This experimental module supports up to 2,000,000 rows.')
   if (operation == 'lfq_columns') return(.rs.superrstudioLfqColumns(data))
   # analyses use the prepared data and its recorded settings, not the form's
   if (operation == 'lfq_start')
   {
      if (!installed) fail('TropFishR is not installed in the active R library.')
      return(.rs.superrstudioLfqStart(data, dataset, settings))
   }
   input <- .rs.superrstudioLfqInput(data, dataset, settings)
   if (operation == 'lfq_check') return(input$report)
   if (!installed)
      fail('TropFishR is not installed in the active R library. Install it explicitly (install.packages("TropFishR")), then retry.')
   .rs.superrstudioLfqCreate(data, dataset, input, settings)
})

.rs.addFunction('superrstudioLfqFrame', function(value)
   is.data.frame(value) &&
      all(class(value) %in% c('data.frame', 'tbl_df', 'tbl', 'grouped_df', 'data.table')) &&
      !anyNA(names(value)) && !anyDuplicated(names(value)) && all(nzchar(names(value))))

#' Columns by role: numeric (lengths, frequencies), date-like, categorical
.rs.addFunction('superrstudioLfqColumns', function(data)
{
   numeric <- names(data)[vapply(data, function(v) (is.double(v) || is.integer(v)) && !is.object(v), NA)]
   dates <- names(data)[vapply(data, function(v) inherits(v, c('Date', 'POSIXct')) || is.factor(v) ||
                                  (is.character(v) && !is.object(v)), NA)]
   categories <- names(data)[vapply(data, function(v) is.factor(v) || (is.character(v) && !is.object(v)), NA)]
   list(numeric = unname(numeric), dates = unname(dates), categories = unname(categories),
        rows = I(nrow(data)))
})

#' Validate settings with defaults (shared by every step)
.rs.addFunction('superrstudioLfqSettings', function(settings)
{
   fail <- function(message) stop(message, call. = FALSE)
   defaults <- list(length = '', date = '', date_format = '', freq = '', species_column = '',
                    species = '', unit = 'cm', bin_size = 1, lmin = 0, aggregate_dates = FALSE,
                    plus_group = 0, ma = 5, addl_sqrt = FALSE,
                    method = 'ga', seasonalised = FALSE,
                    linf_min = '', linf_max = '', k_min = 0.05, k_max = 1, t_min = 0, t_max = 1,
                    c_min = 0, c_max = 1, ts_min = 0, ts_max = 1,
                    pop_size = 50, max_iter = 100, run = 100, pmutation = 0.1, pcrossover = 0.8,
                    elitism = 3, seeds = '1',
                    sa_stop = 'iterations', sa_maxit = 300, sa_time = 60, sa_temp = 1e5,
                    linf_init = '', k_init = 0.3, t_init = 0.5,
                    linf_steps = 20, k_steps = 30, label = '', job = '', run_id = '')
   known <- intersect(names(settings), names(defaults))
   values <- utils::modifyList(defaults, settings[known])
   text <- function(key) if (!.rs.superrstudioIsText(values[[key]])) fail(paste0('Setting ', key, ' must be text.'))
   for (key in c('length', 'date', 'date_format', 'freq', 'species_column', 'species', 'unit',
                 'method', 'seeds', 'sa_stop', 'label'))
      text(key)
   flag <- function(key) if (!is.logical(values[[key]]) || length(values[[key]]) != 1L || is.na(values[[key]]))
      fail(paste0('Setting ', key, ' must be true or false.'))
   for (key in c('aggregate_dates', 'addl_sqrt', 'seasonalised')) flag(key)
   number <- function(key, low, high, message)
   {
      value <- values[[key]]
      if (is.character(value) && nzchar(value)) value <- suppressWarnings(as.numeric(value))
      if (!.rs.superrstudioIsNumber(value, low, high)) fail(message)
      values[[key]] <<- as.numeric(value)
   }
   if (!values$unit %in% c('cm', 'mm', 'm')) fail('Length unit must be cm, mm or m.')
   if (!values$date_format %in% c('', '%Y-%m-%d', '%d/%m/%Y', '%m/%d/%Y', '%d-%m-%Y', '%d.%m.%Y'))
      fail('Unsupported date format.')
   number('bin_size', 0.01, 1000, 'Length class width must be a positive number (in cm).')
   number('lmin', 0, 1e5, 'Minimum length must be zero or positive (in cm).')
   number('plus_group', 0, 1e5, 'Plus group must be zero (none) or a length class midpoint (in cm).')
   number('ma', 1, 101, 'Moving average must be an odd whole number of length classes.')
   if (values$ma %% 2 != 1) fail('Moving average must be an odd whole number of length classes (for example 5 or 7).')
   values$ma <- as.integer(values$ma)
   values
})

#' The analysis frame as an explicit, reproducible preparation
#'
#' Builds (never assigns) the code that takes the mapped columns, converts
#' dates, keeps the selected species and drops unusable rows, and reports
#' what each rule removes. Lengths that TropFishR would silently ignore
#' (zero, negative or below the minimum length class) are removed here
#' explicitly so they can be counted.
.rs.addFunction('superrstudioLfqInput', function(data, dataset, settings)
{
   fail <- function(message) stop(message, call. = FALSE)
   s <- .rs.superrstudioLfqSettings(settings)
   if (!s$length %in% names(data)) fail('Select the column with length measurements.')
   if (!s$date %in% names(data)) fail('Select the column with sampling dates.')
   lengths <- data[[s$length]]
   if (!(is.double(lengths) || is.integer(lengths)) || is.object(lengths))
      fail('The length column must be numeric.')
   if (nzchar(s$freq) && (!s$freq %in% names(data) || !(is.double(data[[s$freq]]) || is.integer(data[[s$freq]]))))
      fail('The frequency column must be numeric.')
   if (nzchar(s$species_column) && !s$species_column %in% names(data))
      fail('The species column does not exist.')
   column <- function(name) substitute(D[[N]], list(D = as.name(dataset), N = name))
   rawDates <- data[[s$date]]
   dateCall <- if (inherits(rawDates, 'Date')) column(s$date)
      else if (inherits(rawDates, 'POSIXct')) call('as.Date', call('format', column(s$date), '%Y-%m-%d'))
      else if (is.character(rawDates) || is.factor(rawDates))
      {
         if (!nzchar(s$date_format)) fail('Choose the date format of the text dates (for example day/month/year).')
         call('as.Date', if (is.factor(rawDates)) call('as.character', column(s$date)) else column(s$date),
              format = s$date_format)
      }
      else fail('The date column must hold dates (Date, POSIXct) or text dates.')
   frameCall <- as.call(c(quote(data.frame), list(length = column(s$length), date = dateCall),
                          if (nzchar(s$freq)) list(freq = column(s$freq)),
                          if (nzchar(s$species_column)) list(species = column(s$species_column))))
   env <- new.env(parent = baseenv())
   assign(dataset, data, envir = env)
   frame <- eval(frameCall, envir = env)

   # conversions to cm as lfqCreate() applies them
   factor <- c(cm = 1, mm = 0.1, m = 100)[[s$unit]]
   steps <- list()
   keep <- rep(TRUE, nrow(frame))
   rule <- function(label, test, condition)
   {
      removed <- keep & !test
      steps[[length(steps) + 1L]] <<- list(rule = I(label), removed = I(sum(removed)))
      keep <<- keep & test
      condition
   }
   conditions <- list()
   if (nzchar(s$species_column))
   {
      if (!nzchar(s$species)) fail('Choose the species to analyse (or clear the species column).')
      conditions <- c(conditions, rule(sprintf('other species than "%s" (or no species)', s$species),
                                       !is.na(frame$species) & as.character(frame$species) == s$species,
                                       substitute(lfq_input$species %in% S, list(S = s$species))))
   }
   conditions <- c(conditions,
      rule('missing or non-numeric length', is.finite(frame$length), quote(is.finite(lfq_input$length))),
      rule('length zero or negative', is.finite(frame$length) & frame$length > 0, quote(lfq_input$length > 0)),
      rule(sprintf('length below the minimum length class (%s cm)', format(s$lmin)),
           is.finite(frame$length) & frame$length * factor >= s$lmin,
           if (s$lmin > 0) call('>=', quote(lfq_input$length), s$lmin / factor)),
      rule(if (nzchar(s$date_format)) sprintf('missing date or not in format %s', s$date_format) else 'missing date',
           !is.na(frame$date), quote(!is.na(lfq_input$date))))
   if (nzchar(s$freq))
      conditions <- c(conditions, rule('missing or negative frequency', is.finite(frame$freq) & frame$freq >= 0,
                                       quote(is.finite(lfq_input$freq) & lfq_input$freq >= 0)))
   conditions <- Filter(Negate(is.null), conditions)
   kept <- frame[keep, , drop = FALSE]
   filterCall <- substitute(lfq_input <- lfq_input[KEEP, , drop = FALSE],
                            list(KEEP = Reduce(function(a, b) call('&', a, b), conditions)))
   counts <- if (nzchar(s$freq)) kept$freq else rep(1, nrow(kept))
   perDate <- if (nrow(kept)) tapply(counts, format(kept$date, '%Y-%m-%d'), sum) else numeric()
   speciesCounts <- if (nzchar(s$species_column))
   {
      table <- sort(table(as.character(frame$species), useNA = 'no'), decreasing = TRUE)
      lapply(names(table), function(name) list(species = I(name), rows = I(as.integer(table[[name]]))))
   }
   cm <- kept$length * factor
   report <- list(rows = I(nrow(frame)), kept = I(nrow(kept)), individuals = I(sum(counts)),
                  steps = steps, species = if (is.null(speciesCounts)) list() else speciesCounts,
                  dates = unname(names(perDate)), date_counts = unname(as.numeric(perDate)),
                  length_min = I(if (length(cm)) min(cm) else NA), length_max = I(if (length(cm)) max(cm) else NA),
                  unit = I(s$unit),
                  first_date = I(if (length(perDate)) names(perDate)[1L] else ''),
                  last_date = I(if (length(perDate)) names(perDate)[length(perDate)] else ''),
                  code = I(paste(c(paste(deparse(call('<-', quote(lfq_input), frameCall), width.cutoff = 90L), collapse = '\n'),
                                   paste(deparse(filterCall, width.cutoff = 90L), collapse = '\n')), collapse = '\n')))
   list(settings = s, frame = kept, report = report, frameCall = frameCall, filterCall = filterCall)
})

#' Create the lfq object with TropFishR and restructure it for ELEFAN
.rs.addFunction('superrstudioLfqCreate', function(data, dataset, input, settings)
{
   fail <- function(message) stop(message, call. = FALSE)
   s <- input$settings
   state <- .rs.superrstudioLfqState
   if (input$report$kept < 1L) fail('No usable observations remain; check the columns, date format and species.')
   if (length(input$report$dates) < 2L)
      fail('ELEFAN needs length frequencies from at least two sampling dates.')
   factor <- c(cm = 1, mm = 0.1, m = 100)[[s$unit]]
   breaks <- seq(s$lmin, max(input$frame$length * factor) + s$bin_size, by = s$bin_size)
   mids <- breaks + s$bin_size / 2
   if (s$plus_group > 0 && !any(abs(mids - s$plus_group) < 1e-8))
      fail(sprintf('The plus group must be a length class midpoint, for example %s.',
                   paste(utils::head(format(mids[mids >= s$plus_group]), 3L), collapse = ', ')))
   createCall <- as.call(c(quote(TropFishR::lfqCreate), list(
      quote(lfq_input), Lname = 'length', Dname = 'date'),
      if (nzchar(s$freq)) list(Fname = 'freq'),
      list(bin_size = s$bin_size),
      if (nzchar(s$species)) list(species = s$species),
      list(Lmin = s$lmin, length_unit = s$unit,
           plus_group = if (s$plus_group > 0) call('c', TRUE, s$plus_group) else FALSE,
           aggregate_dates = s$aggregate_dates)))
   restructureCall <- call('<-', quote(lfq), as.call(list(quote(TropFishR::lfqRestructure), quote(lfq),
                                                          MA = s$ma, addl.sqrt = s$addl_sqrt)))
   env <- new.env(parent = baseenv())
   env$lfq_input <- input$frame
   warnings <- character()
   lfq <- withCallingHandlers({
      env$lfq <- eval(createCall, envir = env)
      eval(restructureCall, envir = env)
   }, warning = function(w) {
      warnings <<- c(warnings, conditionMessage(w))
      invokeRestart('muffleWarning')
   })
   lfq <- env$lfq
   code <- paste(c(sprintf('# SuperRStudio length-frequency preparation (TropFishR %s, R %s)',
                           utils::packageVersion('TropFishR'), getRversion()),
                   input$report$code,
                   paste(deparse(call('<-', quote(lfq), createCall), width.cutoff = 90L), collapse = '\n'),
                   paste(deparse(restructureCall, width.cutoff = 90L), collapse = '\n')), collapse = '\n')
   # the prepared object and the exact data it came from (for staleness)
   state$prepared <- list(lfq = lfq, dataset = dataset, data = if (inherits(data, 'data.table'))
                             serialize(data, NULL, version = 2) else data,
                          settings = s, code = code, report = input$report)
   image <- function(draw) .rs.superrstudioLfqImage(draw)
   lmax <- max(lfq$midLengths)
   list(code = I(code), warnings = unique(warnings),
        dates = I(length(lfq$dates)), classes = I(length(lfq$midLengths)),
        total = I(sum(lfq$catch)), asp = I(lfq$ASP), ma = I(lfq$MA),
        max_length = I(lmax), report = input$report,
        # TropFishR's own ELEFAN_GA defaults are derived from the data; shown explicitly
        linf_suggest_min = I(signif(0.8 * lmax, 3)), linf_suggest_max = I(signif(1.2 * lmax, 3)),
        raw_image = I(image(function() graphics::plot(lfq, Fname = 'catch', date.axis = 'modern'))),
        restructured_image = I(image(function() graphics::plot(lfq, Fname = 'rcounts', date.axis = 'modern'))))
})

#' A base-graphics drawing as a base64 PNG (double resolution)
.rs.addFunction('superrstudioLfqImage', function(draw, width = 5.5, height = 3.6)
{
   file <- tempfile('superrstudio-lfq-', fileext = '.png')
   previous <- grDevices::dev.cur()
   grDevices::png(file, width = width * 192, height = height * 192, res = 192,
                  type = if (capabilities('cairo')) 'cairo' else getOption('bitmapType'))
   device <- grDevices::dev.cur()
   on.exit({
      if (device %in% grDevices::dev.list()) grDevices::dev.off(device)
      if (previous > 1L && previous %in% grDevices::dev.list()) grDevices::dev.set(previous)
      unlink(file)
   })
   suppressWarnings(draw())
   grDevices::dev.off(device)
   .rs.rBase64Encode(readBin(file, 'raw', file.size(file)))
})

#' Seeds from text: "1", "1, 2, 5" or "1-10" (at most 50 runs)
.rs.addFunction('superrstudioLfqSeeds', function(text)
{
   fail <- function(message) stop(message, call. = FALSE)
   text <- gsub('\\s+', '', text)
   if (!grepl('^[0-9]+(-[0-9]+)?(,[0-9]+(-[0-9]+)?)*$', text))
      fail('Seeds must be whole numbers such as "1", "1, 2, 3" or "1-10".')
   seeds <- unlist(lapply(strsplit(text, ',', fixed = TRUE)[[1L]], function(part) {
      ends <- as.numeric(strsplit(part, '-', fixed = TRUE)[[1L]])
      if (length(ends) == 2L) seq(ends[1L], ends[2L]) else ends
   }))
   seeds <- unique(seeds)
   if (!length(seeds) || length(seeds) > 50L) fail('Use between 1 and 50 seeds per batch.')
   if (any(seeds > .Machine$integer.max)) fail('Seeds must be smaller than 2147483647.')
   seeds
})

#' The ELEFAN call(s) for the current settings, one per seed
#'
#' Every argument that influences the estimate is written explicitly, so the
#' recorded code shows the complete configuration rather than relying on
#' package defaults. Plotting arguments are switched off (the run is
#' non-interactive) and do not change the estimates.
.rs.addFunction('superrstudioLfqCalls', function(s, lfq)
{
   fail <- function(message) stop(message, call. = FALSE)
   number <- function(key, low, high, label)
   {
      value <- s[[key]]
      if (is.character(value)) value <- suppressWarnings(as.numeric(value))
      if (!.rs.superrstudioIsNumber(value, low, high)) fail(paste0(label, ' must be between ', low, ' and ', high, '.'))
      as.numeric(value)
   }
   if (!s$method %in% c('ga', 'sa', 'elefan')) fail('Method must be ELEFAN_GA, ELEFAN_SA or ELEFAN.')
   lmax <- max(lfq$midLengths)
   if (identical(s$linf_min, '')) s$linf_min <- signif(0.8 * lmax, 3)
   if (identical(s$linf_max, '')) s$linf_max <- signif(1.2 * lmax, 3)
   linf <- c(number('linf_min', 0.01, 1e5, 'Minimum Linf'), number('linf_max', 0.01, 1e5, 'Maximum Linf'))
   k <- c(number('k_min', 1e-4, 50, 'Minimum K'), number('k_max', 1e-4, 50, 'Maximum K'))
   tanc <- c(number('t_min', 0, 1, 'Minimum t_anchor'), number('t_max', 0, 1, 'Maximum t_anchor'))
   if (linf[1L] >= linf[2L] || k[1L] >= k[2L] || tanc[1L] >= tanc[2L])
      fail('Each search range needs a minimum below its maximum.')
   if (linf[2L] < lmax)
      fail(sprintf('The Linf range ends below the largest length class (%s cm); Linf cannot be smaller than observed lengths.', format(lmax)))
   low <- list(Linf = linf[1L], K = k[1L], t_anchor = tanc[1L])
   up <- list(Linf = linf[2L], K = k[2L], t_anchor = tanc[2L])
   if (s$seasonalised && s$method != 'elefan')
   {
      cs <- c(number('c_min', 0, 1, 'Minimum C'), number('c_max', 0, 1, 'Maximum C'))
      ts <- c(number('ts_min', 0, 1, 'Minimum ts'), number('ts_max', 0, 1, 'Maximum ts'))
      if (cs[1L] >= cs[2L] || ts[1L] >= ts[2L]) fail('Each search range needs a minimum below its maximum.')
      low <- c(low, list(C = cs[1L], ts = ts[1L]))
      up <- c(up, list(C = cs[2L], ts = ts[2L]))
   }
   listCall <- function(values) as.call(c(quote(list), values))
   common <- list(MA = s$ma, addl.sqrt = s$addl_sqrt)
   if (s$method == 'ga')
   {
      seeds <- .rs.superrstudioLfqSeeds(s$seeds)
      pop <- number('pop_size', 10, 1000, 'Population size')
      iter <- number('max_iter', 5, 5000, 'Maximum generations')
      run <- number('run', 2, 5000, 'Generations without improvement')
      pmut <- number('pmutation', 0, 1, 'Mutation probability')
      pcross <- number('pcrossover', 0, 1, 'Crossover probability')
      elite <- number('elitism', 0, pop, 'Elitism')
      return(lapply(seeds, function(seed) as.call(c(quote(TropFishR::ELEFAN_GA), list(quote(lfq),
         seasonalised = s$seasonalised, low_par = listCall(low), up_par = listCall(up),
         popSize = pop, maxiter = iter, run = min(run, iter), pmutation = pmut, pcrossover = pcross,
         elitism = round(elite)), common, list(seed = seed, monitor = FALSE, plot = FALSE, plot.score = FALSE)))))
   }
   if (s$method == 'sa')
   {
      init <- list(Linf = if (identical(s$linf_init, '')) mean(linf) else number('linf_init', linf[1L], linf[2L], 'Initial Linf'),
                   K = number('k_init', k[1L], k[2L], 'Initial K'), t_anchor = number('t_init', tanc[1L], tanc[2L], 'Initial t_anchor'))
      if (s$seasonalised) init <- c(init, list(C = mean(c(low$C, up$C)), ts = mean(c(low$ts, up$ts))))
      stop <- if (s$sa_stop == 'time') list(SA_time = number('sa_time', 1, 36000, 'Time limit (seconds)'), maxit = NULL)
         else if (s$sa_stop == 'iterations') list(SA_time = NULL, maxit = number('sa_maxit', 10, 1e6, 'Iterations'))
         else fail('Simulated annealing stops after a number of iterations or a time limit.')
      return(list(as.call(c(quote(TropFishR::ELEFAN_SA), list(quote(lfq), seasonalised = s$seasonalised,
         init_par = listCall(init), low_par = listCall(low), up_par = listCall(up)), stop,
         list(SA_temp = number('sa_temp', 1, 1e9, 'Initial temperature'), verbose = FALSE), common,
         list(plot = FALSE, plot.score = FALSE)))))
   }
   steps <- c(number('linf_steps', 2, 200, 'Linf grid size'), number('k_steps', 2, 500, 'K grid size'))
   list(as.call(c(quote(TropFishR::ELEFAN), list(quote(lfq),
      Linf_range = call('seq', linf[1L], linf[2L], length.out = round(steps[1L])),
      K_range = call('exp', call('seq', call('log', k[1L]), call('log', k[2L]), length.out = round(steps[2L])))),
      common, list(method = 'optimise', hide.progressbar = TRUE, plot = FALSE))))
})

# The background runner: loads the prepared lfq, evaluates each recorded
# call, reports progress through a file and writes the results atomically.
.rs.superrstudioLfqState$runner <- c(
   'args <- commandArgs(TRUE)',
   'job <- readRDS(args[[1L]])',
   '.libPaths(job$libs)',
   'setwd(dirname(args[[1L]]))',
   'grDevices::pdf(NULL)',
   'writeLines(as.character(Sys.getpid()), job$pid)',
   'n <- length(job$calls)',
   'results <- vector("list", n)',
   'for (i in seq_len(n)) {',
   '   writeLines(sprintf("Run %d of %d", i, n), job$progress)',
   '   call <- job$calls[[i]]',
   '   if (identical(call[[1L]], quote(TropFishR::ELEFAN_GA)))',
   '      call$monitor <- function(object) writeLines(sprintf("Run %d of %d: generation %d", i, n, object@iter), job$progress)',
   '   env <- new.env(parent = globalenv())',
   '   env$lfq <- job$lfq',
   '   warnings <- character()',
   '   started <- proc.time()[["elapsed"]]',
   '   results[[i]] <- tryCatch({',
   '      output <- utils::capture.output(fit <- withCallingHandlers(eval(call, envir = env), warning = function(w) {',
   '         warnings <<- c(warnings, conditionMessage(w)); invokeRestart("muffleWarning") }))',
   '      list(par = fit$par, score = fit$Rn_max, warnings = unique(warnings),',
   '           seconds = proc.time()[["elapsed"]] - started)',
   '   }, error = function(e) list(error = conditionMessage(e), seconds = proc.time()[["elapsed"]] - started))',
   '}',
   'saveRDS(results, paste0(job$output, ".tmp"))',
   'file.rename(paste0(job$output, ".tmp"), job$output)')

#' Start ELEFAN in a separate R process
#'
#' The session's R is never blocked: the analysis runs in its own Rscript
#' process (same R and library paths) and can be cancelled. Estimation is
#' entirely TropFishR's; this only transports inputs and results.
.rs.addFunction('superrstudioLfqStart', function(data, dataset, settings)
{
   fail <- function(message) stop(message, call. = FALSE)
   state <- .rs.superrstudioLfqState
   prepared <- state$prepared
   if (is.null(prepared)) fail('Create the length-frequency data first.')
   current <- if (inherits(data, 'data.table')) serialize(data, NULL, version = 2) else data
   if (!identical(prepared$dataset, dataset) || !identical(prepared$data, current))
      fail('The dataset changed after the length-frequency data were created. Create them again.')
   s <- .rs.superrstudioLfqSettings(settings)
   # restructuring settings travel with the prepared data, not the form
   for (key in c('length', 'date', 'date_format', 'freq', 'species_column', 'species', 'unit',
                 'bin_size', 'lmin', 'aggregate_dates', 'plus_group', 'ma', 'addl_sqrt'))
      s[[key]] <- prepared$settings[[key]]
   calls <- .rs.superrstudioLfqCalls(s, prepared$lfq)
   running <- Filter(function(job) is.null(job$finished), state$jobs)
   if (length(running)) fail('An analysis is already running. Wait for it or cancel it.')
   folder <- tempfile('superrstudio-lfq-job-')
   dir.create(folder)
   state$counter <- state$counter + 1L
   id <- paste0('job', state$counter)
   job <- list(lfq = prepared$lfq, calls = calls, libs = .libPaths(),
               pid = file.path(folder, 'pid'), progress = file.path(folder, 'progress'),
               output = file.path(folder, 'result.rds'))
   saveRDS(job, file.path(folder, 'job.rds'))
   writeLines(state$runner, file.path(folder, 'runner.R'))
   rscript <- file.path(R.home('bin'), if (.Platform$OS.type == 'windows') 'Rscript.exe' else 'Rscript')
   system2(rscript, c('--vanilla', shQuote(file.path(folder, 'runner.R')), shQuote(file.path(folder, 'job.rds'))),
           wait = FALSE, stdout = file.path(folder, 'stdout.txt'), stderr = file.path(folder, 'stderr.txt'))
   state$jobs[[id]] <- list(id = id, folder = folder, job = job, settings = s, started = Sys.time(),
                            label = s$label, prepared = prepared[c('dataset', 'settings', 'code', 'report')])
   list(job = I(id), runs = I(length(calls)), status = I('started'))
})

.rs.addFunction('superrstudioLfqPoll', function(id)
{
   fail <- function(message) stop(message, call. = FALSE)
   state <- .rs.superrstudioLfqState
   entry <- if (.rs.superrstudioIsText(id)) state$jobs[[id]]
   if (is.null(entry)) fail('Unknown analysis.')
   if (!is.null(entry$finished)) return(list(job = I(id), status = I(entry$finished)))
   progress <- if (file.exists(entry$job$progress)) readLines(entry$job$progress, warn = FALSE) else character()
   elapsed <- as.numeric(difftime(Sys.time(), entry$started, units = 'secs'))
   if (!file.exists(entry$job$output))
   {
      # a runner that died without results (crash, killed) is reported
      if (elapsed > 5 && file.exists(file.path(entry$folder, 'pid')))
      {
         pid <- as.integer(readLines(file.path(entry$folder, 'pid'), warn = FALSE))
         alive <- tryCatch(.rs.superrstudioLfqAlive(pid), error = function(e) TRUE)
         if (!alive && !file.exists(entry$job$output))
         {
            state$jobs[[id]]$finished <- 'failed'
            errors <- if (file.exists(file.path(entry$folder, 'stderr.txt')))
               readLines(file.path(entry$folder, 'stderr.txt'), warn = FALSE) else character()
            return(list(job = I(id), status = I('failed'),
                        message = I(paste(utils::tail(errors, 5L), collapse = '\n'))))
         }
      }
      return(list(job = I(id), status = I('running'), elapsed = I(round(elapsed)),
                  progress = I(if (length(progress)) progress[[1L]] else 'Starting R...')))
   }
   results <- readRDS(entry$job$output)
   for (i in seq_along(results))
      .rs.superrstudioLfqRecord(entry, entry$job$calls[[i]], results[[i]])
   state$jobs[[id]]$finished <- 'done'
   unlink(entry$folder, recursive = TRUE)
   c(list(job = I(id), status = I('done')), .rs.superrstudioLfqRuns())
})

.rs.addFunction('superrstudioLfqAlive', function(pid)
{
   if (.Platform$OS.type == 'windows')
   {
      out <- suppressWarnings(system2('tasklist', c('/FI', shQuote(paste('PID eq', pid)), '/NH'),
                                      stdout = TRUE, stderr = FALSE))
      any(grepl(paste0('\\b', pid, '\\b'), out))
   }
   else tools::pskill(pid, 0L)
})

.rs.addFunction('superrstudioLfqCancel', function(id)
{
   state <- .rs.superrstudioLfqState
   entry <- if (.rs.superrstudioIsText(id)) state$jobs[[id]]
   if (is.null(entry) || !is.null(entry$finished)) return(list(job = I(id), status = I('finished')))
   pidFile <- entry$job$pid
   if (file.exists(pidFile))
      tools::pskill(as.integer(readLines(pidFile, warn = FALSE)))
   state$jobs[[id]]$finished <- 'cancelled'
   unlink(entry$folder, recursive = TRUE)
   list(job = I(id), status = I('cancelled'))
})

#' Record one finished run with its complete configuration
.rs.addFunction('superrstudioLfqRecord', function(entry, call, result)
{
   state <- .rs.superrstudioLfqState
   s <- entry$settings
   method <- c(ga = 'ELEFAN_GA', sa = 'ELEFAN_SA', elefan = 'ELEFAN')[[s$method]]
   seed <- if (!is.null(call$seed)) call$seed else NA
   # what the score is, and which runs it can be compared with
   preprocessing <- entry$prepared$settings[c('length', 'date', 'date_format', 'freq', 'species_column',
                                               'species', 'unit', 'bin_size', 'lmin', 'aggregate_dates',
                                               'plus_group', 'ma', 'addl_sqrt')]
   search <- call
   search$seed <- NULL
   code <- paste(c(entry$prepared$code, '',
                   sprintf('# %s run recorded by SuperRStudio (TropFishR %s, R %s)', method,
                           utils::packageVersion('TropFishR'), getRversion()),
                   paste(deparse(call('<-', quote(fit), call), width.cutoff = 90L), collapse = '\n'),
                   'fit$par', 'fit$Rn_max'), collapse = '\n')
   par <- result$par
   value <- function(name) if (!is.null(par[[name]]) && is.finite(par[[name]])) I(unname(as.numeric(par[[name]])))
   run <- list(id = I(paste0('run', length(state$runs) + 1L)), label = I(s$label), method = I(method),
               seed = I(seed), dataset = I(entry$prepared$dataset),
               species = I(entry$prepared$settings$species),
               first_date = I(entry$prepared$report$first_date), last_date = I(entry$prepared$report$last_date),
               individuals = I(entry$prepared$report$individuals),
               bin_size = I(preprocessing$bin_size), ma = I(preprocessing$ma), addl_sqrt = I(preprocessing$addl_sqrt),
               seasonalised = I(s$seasonalised),
               search = I(paste(deparse(search, width.cutoff = 500L), collapse = ' ')),
               preprocessing = I(paste(deparse(preprocessing, width.cutoff = 500L), collapse = ' ')),
               linf = value('Linf'), k = value('K'), t_anchor = value('t_anchor'),
               c = value('C'), ts = value('ts'), phil = value('phiL'),
               score = if (is.numeric(result$score) && length(result$score) == 1L && is.finite(result$score)) I(result$score),
               seconds = I(round(result$seconds, 1)),
               error = I(if (is.null(result$error)) '' else result$error),
               warnings = unname(if (is.null(result$warnings)) character() else result$warnings),
               r_version = I(as.character(getRversion())),
               tropfishr_version = I(as.character(utils::packageVersion('TropFishR'))),
               code = I(code), lfq_par = par, lfq_object = entry$job$lfq)
   state$runs[[length(state$runs) + 1L]] <- Filter(Negate(is.null), run)
   invisible(run)
})

#' All recorded runs plus the comparison of each configuration group
#'
#' Runs are grouped by everything except the seed. Within a group the spread
#' of estimates across seeds shows the search's stability; scores are only
#' comparable within a group (same data preparation and method).
.rs.addFunction('superrstudioLfqRuns', function()
{
   runs <- .rs.superrstudioLfqState$runs
   public <- lapply(runs, function(run) run[setdiff(names(run), c('lfq_par', 'lfq_object'))])
   key <- vapply(runs, function(run) paste(run$method, run$dataset, run$preprocessing, run$search, sep = '|'), '')
   groups <- lapply(unique(key), function(k) {
      members <- runs[key == k]
      ok <- Filter(function(run) !nzchar(run$error) && !is.null(run$linf), members)
      spread <- function(field) {
         values <- vapply(ok, function(run) as.numeric(run[[field]]), 0)
         if (!length(values)) return(list())
         list(mean = I(mean(values)), sd = I(if (length(values) > 1L) stats::sd(values) else NA),
              min = I(min(values)), max = I(max(values)))
      }
      list(method = I(members[[1L]]$method), runs = I(length(members)), succeeded = I(length(ok)),
           ids = vapply(members, function(run) as.character(run$id), ''),
           linf = spread('linf'), k = spread('k'), phil = spread('phil'))
   })
   notes <- character()
   if (length(unique(key)) > 1L)
   {
      methods <- unique(vapply(runs, function(run) as.character(run$method), ''))
      if (length(methods) > 1L)
         notes <- c(notes, 'Scores of different ELEFAN methods are not comparable (TropFishR documents the GA fitness as not comparable with ELEFAN or ELEFAN_SA scores).')
      if (length(unique(vapply(runs, function(run) as.character(run$preprocessing), ''))) > 1L)
         notes <- c(notes, 'Runs use different data preparation (dataset, filters, length classes, moving average): their scores are computed on different restructured data and are not comparable.')
      notes <- c(notes, 'A better score does not by itself make an estimate correct; compare stability across seeds, data quality and biological plausibility.')
   }
   list(runs = unname(public), groups = groups, notes = notes)
})

#' Restructured data with the growth curves of one run (TropFishR plotting)
.rs.addFunction('superrstudioLfqRunPlot', function(id)
{
   fail <- function(message) stop(message, call. = FALSE)
   state <- .rs.superrstudioLfqState
   ids <- vapply(state$runs, function(run) as.character(run$id), '')
   if (!.rs.superrstudioIsText(id) || !id %in% ids) fail('Unknown run.')
   run <- state$runs[[match(id, ids)]]
   if (is.null(run$lfq_par) || nzchar(run$error)) fail('This run has no estimates to plot.')
   lfq <- run$lfq_object   # the data this run was fitted to
   list(run = I(id), image = I(.rs.superrstudioLfqImage(function() {
      graphics::plot(lfq, Fname = 'rcounts', date.axis = 'modern')
      TropFishR::lfqFitCurves(lfq, par = run$lfq_par, draw = TRUE, col = 'darkblue', lwd = 1.5)
   })))
})
