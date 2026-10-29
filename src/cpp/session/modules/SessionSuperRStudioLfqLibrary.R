# SuperRStudio length-frequency saved analyses. SPDX-License-Identifier: AGPL-3.0-only
#
# Saved analyses are complete, versioned configurations of the
# length-frequency workflow (data mapping, preparation, ELEFAN and mortality
# settings, seeds) together with a fingerprint of the input data and the R
# and TropFishR versions they were made with. They are kept in the session
# and, once the researcher chooses a file, written to it as JSON after every
# change. Restoring never substitutes another dataset or version silently:
# every difference is reported.
.rs.superrstudioLfqState$library <- list(path = '', analyses = list(), counter = 0L)

#' Saved-analysis operations (lfq_lib_*)
#'
#' @param operation lfq_lib (list), lfq_lib_add, lfq_lib_rename,
#'   lfq_lib_duplicate, lfq_lib_delete, lfq_lib_restore, lfq_lib_compare,
#'   lfq_lib_open, lfq_lib_save_as.
#' @param settings The dialog's settings plus name, analysis, other,
#'   run_id and path where the operation needs them.
.rs.addFunction('superrstudioLfqLibrary', function(operation, dataset, settings, available)
{
   fail <- function(message) stop(message, call. = FALSE)
   state <- .rs.superrstudioLfqState
   library <- state$library
   field <- function(key) if (.rs.superrstudioIsText(settings[[key]])) settings[[key]] else ''
   find <- function(id)
   {
      ids <- vapply(library$analyses, function(analysis) analysis$id, '')
      if (!nzchar(id) || !id %in% ids) fail('Unknown saved analysis.')
      match(id, ids)
   }
   name <- function()
   {
      value <- trimws(field('name'))
      if (!nzchar(value) || nchar(value) > 100L) fail('Give the analysis a name of 1 to 100 characters.')
      value
   }
   changed <- function(analyses)
   {
      library$analyses <- analyses
      if (nzchar(library$path)) .rs.superrstudioLfqLibraryWrite(library$path, analyses)
      state$library <- library
      .rs.superrstudioLfqLibraryListing(library)
   }
   now <- function() format(Sys.time(), '%Y-%m-%dT%H:%M:%S')
   newId <- function()
   {
      library$counter <<- library$counter + 1L
      paste0('a', library$counter, '-', format(Sys.time(), '%Y%m%d%H%M%S'))
   }

   if (operation == 'lfq_lib') return(.rs.superrstudioLfqLibraryListing(library))
   if (operation == 'lfq_lib_add')
   {
      label <- name()
      run <- field('run_id')
      if (nzchar(run))
      {
         # the configuration of a recorded run, its seed and its estimates
         runs <- state$runs
         ids <- vapply(runs, function(item) as.character(item$id), '')
         if (!run %in% ids) fail('Unknown run.')
         item <- runs[[match(run, ids)]]
         analysis <- list(id = newId(), name = label, created = now(), source = paste('run', item$id),
                          dataset = as.character(item$dataset), data = item$lfq_signature,
                          environment = list(r = as.character(item$r_version),
                                             tropfishr = as.character(item$tropfishr_version)),
                          settings = .rs.superrstudioLfqStoredSettings(item$lfq_settings),
                          results = list(Filter(Negate(is.null), list(
                             method = as.character(item$method), seed = if (!is.na(item$seed)) as.numeric(item$seed),
                             linf = .rs.superrstudioLfqNumber(item$linf), k = .rs.superrstudioLfqNumber(item$k),
                             t_anchor = .rs.superrstudioLfqNumber(item$t_anchor), c = .rs.superrstudioLfqNumber(item$c),
                             ts = .rs.superrstudioLfqNumber(item$ts), phil = .rs.superrstudioLfqNumber(item$phil),
                             score = .rs.superrstudioLfqNumber(item$score)))))
      }
      else
      {
         if (!dataset %in% available) fail('Select a dataset before saving the analysis.')
         data <- get(dataset, envir = .GlobalEnv, inherits = FALSE)
         s <- .rs.superrstudioLfqSettings(settings)
         analysis <- list(id = newId(), name = label, created = now(), source = 'settings',
                          dataset = dataset, data = .rs.superrstudioLfqSignature(data, s),
                          environment = .rs.superrstudioLfqEnvironment(),
                          settings = .rs.superrstudioLfqStoredSettings(s), results = list())
      }
      return(changed(c(library$analyses, list(analysis))))
   }
   if (operation == 'lfq_lib_rename')
   {
      index <- find(field('analysis'))
      analyses <- library$analyses
      analyses[[index]]$name <- name()
      return(changed(analyses))
   }
   if (operation == 'lfq_lib_duplicate')
   {
      index <- find(field('analysis'))
      copy <- library$analyses[[index]]
      copy$id <- newId()
      copy$name <- if (nzchar(trimws(field('name')))) name() else substr(paste(copy$name, '(copy)'), 1L, 100L)
      copy$created <- now()
      copy$source <- paste('copy of', library$analyses[[index]]$name)
      copy$results <- list()   # a copy is a configuration to run again, not a result
      return(changed(c(library$analyses, list(copy))))
   }
   if (operation == 'lfq_lib_delete')
   {
      index <- find(field('analysis'))
      return(changed(library$analyses[-index]))
   }
   if (operation == 'lfq_lib_restore')
      return(.rs.superrstudioLfqLibraryRestore(library$analyses[[find(field('analysis'))]], dataset, available))
   if (operation == 'lfq_lib_compare')
   {
      a <- library$analyses[[find(field('analysis'))]]
      b <- library$analyses[[find(field('other'))]]
      return(.rs.superrstudioLfqLibraryCompare(a, b))
   }
   if (operation %in% c('lfq_lib_open', 'lfq_lib_save_as'))
   {
      path <- field('path')
      if (!nzchar(path)) fail('Choose a file for the saved analyses.')
      path <- gsub('\\\\', '/', path.expand(path))
      if (!grepl('\\.json$', path, ignore.case = TRUE)) fail('Saved analyses are stored in a .json file.')
      if (operation == 'lfq_lib_open')
      {
         analyses <- .rs.superrstudioLfqLibraryRead(path)
         state$library <- list(path = path, analyses = analyses, counter = library$counter)
         return(.rs.superrstudioLfqLibraryListing(state$library))
      }
      if (!dir.exists(dirname(path))) fail('The folder for the saved analyses does not exist.')
      .rs.superrstudioLfqLibraryWrite(path, library$analyses)
      library$path <- path
      state$library <- library
      return(.rs.superrstudioLfqLibraryListing(library))
   }
   fail('Unsupported operation.')
})

.rs.addFunction('superrstudioLfqNumber', function(value)
   if (!is.null(value) && is.numeric(value) && length(value) == 1L && is.finite(value)) as.numeric(value))

.rs.addFunction('superrstudioLfqEnvironment', function()
   list(r = as.character(getRversion()),
        tropfishr = if (requireNamespace('TropFishR', quietly = TRUE))
           as.character(utils::packageVersion('TropFishR')) else ''))

#' Settings as stored: validated, complete, without transient keys
.rs.addFunction('superrstudioLfqStoredSettings', function(settings)
{
   s <- .rs.superrstudioLfqSettings(settings)
   s[setdiff(names(s), c('job', 'run_id', 'aggregate_dates'))]
})

#' The client's view of the saved analyses
.rs.addFunction('superrstudioLfqLibraryListing', function(library)
{
   list(path = I(library$path),
        analyses = lapply(unname(library$analyses), function(analysis) list(
           id = I(analysis$id), name = I(analysis$name), created = I(analysis$created),
           source = I(analysis$source), dataset = I(analysis$dataset),
           method = I(c(ga = 'ELEFAN_GA', sa = 'ELEFAN_SA', elefan = 'ELEFAN')[[analysis$settings$method]]),
           seeds = I(if (analysis$settings$method == 'ga') analysis$settings$seeds else ''),
           tropfishr = I(analysis$environment$tropfishr), r = I(analysis$environment$r),
           results = I(length(analysis$results)),
           linf = I(if (length(analysis$results) && !is.null(analysis$results[[1L]]$linf)) analysis$results[[1L]]$linf else NA),
           k = I(if (length(analysis$results) && !is.null(analysis$results[[1L]]$k)) analysis$results[[1L]]$k else NA))))
})

#' Restore an analysis: its settings plus every difference from the saved state
#'
#' The saved dataset is used only if it exists; otherwise the researcher has
#' to choose one explicitly. Changed data, columns or versions are reported.
.rs.addFunction('superrstudioLfqLibraryRestore', function(analysis, dataset, available)
{
   # each warning has a stable code and the values in its English text
   warnings <- list()
   warn <- function(code, text, values) warnings[[length(warnings) + 1L]] <<-
      list(code = I(code), text = I(text), values = as.character(values))
   found <- analysis$dataset %in% available
   if (!found)
      warn('dataset_missing', sprintf('The saved dataset "%s" does not exist in this session. Choose the dataset to analyse explicitly; nothing was substituted.', analysis$dataset),
           analysis$dataset)
   else
   {
      data <- get(analysis$dataset, envir = .GlobalEnv, inherits = FALSE)
      missing <- setdiff(analysis$data$columns, names(data))
      if (length(missing))
         warn('columns_missing', sprintf('Columns missing from "%s": %s.', analysis$dataset, paste(missing, collapse = ', ')),
              c(analysis$dataset, paste(missing, collapse = ', ')))
      else if (.rs.superrstudioLfqFrame(data))
      {
         current <- .rs.superrstudioLfqSignature(data, analysis$settings)
         if (!identical(as.character(current$md5), as.character(analysis$data$md5)))
            warn('data_changed', sprintf('The data in "%s" differ from when the analysis was saved (%s rows then, %s now); results can differ.',
                                         analysis$dataset, format(analysis$data$rows), format(current$rows)),
                 c(analysis$dataset, format(analysis$data$rows), format(current$rows)))
      }
   }
   now <- .rs.superrstudioLfqEnvironment()
   if (!nzchar(now$tropfishr))
      warn('no_tropfishr', 'TropFishR is not installed in the active R library.', character())
   else if (!identical(now$tropfishr, analysis$environment$tropfishr))
      warn('tropfishr_version', sprintf('Saved with TropFishR %s; this session has %s. Estimates can differ between versions.',
                                        analysis$environment$tropfishr, now$tropfishr),
           c(analysis$environment$tropfishr, now$tropfishr))
   if (!identical(now$r, analysis$environment$r))
      warn('r_version', sprintf('Saved with R %s; this session has R %s.', analysis$environment$r, now$r),
           c(analysis$environment$r, now$r))
   settings <- lapply(analysis$settings, function(value) if (length(value) == 1L) I(value) else value)
   list(analysis = I(analysis$id), name = I(analysis$name), dataset = I(analysis$dataset),
        dataset_found = I(found), settings = settings, warnings = warnings)
})

#' The settings, data and versions that differ between two saved analyses
.rs.addFunction('superrstudioLfqLibraryCompare', function(a, b)
{
   show <- function(value) if (is.null(value)) '' else if (is.logical(value)) tolower(as.character(value))
      else format(value)
   rows <- list()
   add <- function(category, key, x, y)
      rows[[length(rows) + 1L]] <<- list(category = I(category), setting = I(key), a = I(show(x)), b = I(show(y)))
   if (!identical(a$dataset, b$dataset)) add('data', 'dataset', a$dataset, b$dataset)
   if (!identical(as.character(a$data$md5), as.character(b$data$md5)))
      add('data', 'data fingerprint (MD5)', a$data$md5, b$data$md5)
   if (!identical(a$environment$tropfishr, b$environment$tropfishr))
      add('versions', 'TropFishR', a$environment$tropfishr, b$environment$tropfishr)
   if (!identical(a$environment$r, b$environment$r)) add('versions', 'R', a$environment$r, b$environment$r)
   categories <- .rs.superrstudioLfqDifferences(
      list(settings = a$settings, dataset = a$dataset, md5 = a$data$md5, tropfishr = a$environment$tropfishr, r = a$environment$r),
      list(settings = b$settings, dataset = b$dataset, md5 = b$data$md5, tropfishr = b$environment$tropfishr, r = b$environment$r))
   for (key in names(a$settings))
      if (!identical(show(a$settings[[key]]), show(b$settings[[key]])))
         add('settings', key, a$settings[[key]], b$settings[[key]])
   list(a = I(a$name), b = I(b$name), rows = rows, categories = categories)
})

# File format -----------------------------------------------------------------

#' Write the saved analyses (format superrstudio-lfq-analyses, version 1)
#'
#' Written to a temporary file next to the target and renamed, so an
#' interrupted write never leaves a truncated file.
.rs.addFunction('superrstudioLfqLibraryWrite', function(path, analyses)
{
   document <- list(format = 'superrstudio-lfq-analyses', version = 1L,
                    note = sprintf('Saved length-frequency analyses (%s, experimental). Settings are TropFishR arguments; see the generated R code of each run.',
                                   .rs.superrstudioBrand()),
                    analyses = unname(analyses))
   text <- .rs.superrstudioJsonWrite(document)
   temporary <- paste0(path, '.tmp')
   con <- file(temporary, 'wb')
   writeLines(enc2utf8(text), con, useBytes = TRUE)
   close(con)
   if (file.exists(path)) unlink(path)
   if (!file.rename(temporary, path))
   {
      unlink(temporary)
      stop('The saved analyses could not be written to ', path, call. = FALSE)
   }
   invisible(path)
})

#' Read and validate a saved-analyses file
#'
#' Every analysis is validated like the dialog's own settings; a file with
#' any invalid analysis is refused as a whole, naming the analysis.
.rs.addFunction('superrstudioLfqLibraryRead', function(path)
{
   fail <- function(message) stop(message, call. = FALSE)
   if (!file.exists(path)) fail('The file does not exist.')
   if (file.size(path) > 5e6) fail('The file is larger than 5 MB; it is not a saved-analyses file.')
   text <- paste(readLines(path, encoding = 'UTF-8', warn = FALSE), collapse = '\n')
   document <- tryCatch(.rs.superrstudioJsonRead(text), error = function(e) fail('The file is not valid JSON.'))
   if (!is.list(document) || !identical(document$format, 'superrstudio-lfq-analyses'))
      fail(sprintf('This is not a %s saved-analyses file.', .rs.superrstudioBrand()))
   if (!is.numeric(document$version) || length(document$version) != 1L)
      fail('The saved-analyses file has no format version.')
   if (document$version > 1) fail(sprintf('The saved analyses were written by a newer version of %s.', .rs.superrstudioBrand()))
   if (!is.list(document$analyses) || !is.null(names(document$analyses)))
      fail('The saved-analyses file has no list of analyses.')
   text1 <- function(value) .rs.superrstudioIsText(value)
   defaults <- .rs.superrstudioLfqStoredSettings(list())
   analyses <- lapply(seq_along(document$analyses), function(i) {
      analysis <- document$analyses[[i]]
      where <- sprintf('Saved analysis %d', i)
      if (!is.list(analysis) || !text1(analysis$id) || !text1(analysis$name) || !text1(analysis$dataset) ||
          !text1(analysis$created) || !is.list(analysis$settings) || is.null(names(analysis$settings)))
         fail(paste0(where, ' is incomplete (id, name, dataset, created and settings are required).'))
      data <- analysis$data
      if (!is.list(data) || !is.numeric(data$rows) || !text1(data$md5) || !grepl('^[0-9a-f]{32}$', data$md5) ||
          !(is.null(data$columns) || is.list(data$columns) || is.character(data$columns)))
         fail(paste0(where, ' has no valid data fingerprint.'))
      environment <- analysis$environment
      if (!is.list(environment) || !text1(environment$r) || !text1(environment$tropfishr))
         fail(paste0(where, ' does not record the R and TropFishR versions.'))
      # every setting must be known and of its documented type ('' marks an
      # automatic numeric value)
      settings <- analysis$settings
      for (key in names(settings))
      {
         value <- settings[[key]]
         expected <- defaults[[key]]
         if (is.null(expected))
            fail(sprintf('%s ("%s") has an unknown setting "%s".', where, analysis$name, key))
         valid <- length(value) == 1L && !is.na(value) &&
            if (is.logical(expected)) is.logical(value)
            else if (is.numeric(expected)) is.numeric(value) || identical(value, '')
            else is.character(value) || (identical(expected, '') && is.numeric(value))
         if (!valid) fail(sprintf('%s ("%s"): setting "%s" has an invalid value.', where, analysis$name, key))
      }
      settings <- tryCatch(.rs.superrstudioLfqStoredSettings(settings),
                           error = function(e) fail(paste0(where, ' ("', analysis$name, '"): ', conditionMessage(e))))
      if (!settings$method %in% c('ga', 'sa', 'elefan')) fail(paste0(where, ': unknown method.'))
      results <- if (is.null(analysis$results)) list() else analysis$results
      if (!is.list(results) || !all(vapply(results, function(result) is.list(result) &&
            all(vapply(result, function(value) is.null(value) || (length(value) == 1L && (is.numeric(value) || is.character(value))), NA)), NA)))
         fail(paste0(where, ' has invalid recorded results.'))
      list(id = analysis$id, name = substr(analysis$name, 1L, 100L), created = analysis$created,
           source = if (text1(analysis$source)) analysis$source else '',
           dataset = analysis$dataset,
           data = list(rows = as.numeric(data$rows), columns = as.character(unlist(data$columns)), md5 = data$md5),
           environment = list(r = environment$r, tropfishr = environment$tropfishr),
           settings = settings, results = results)
   })
   ids <- vapply(analyses, function(analysis) analysis$id, '')
   if (anyDuplicated(ids)) fail('The saved-analyses file contains duplicate analysis ids.')
   analyses
})

# A small, strict JSON reader and writer, so that saved analyses do not
# depend on optional packages. Objects become named lists, arrays unnamed
# lists, null NULL; numbers are doubles.

.rs.addFunction('superrstudioJsonWrite', function(value, indent = '')
{
   inner <- paste0(indent, '  ')
   string <- function(x)
   {
      x <- enc2utf8(x)
      x <- gsub('\\', '\\\\', x, fixed = TRUE)
      x <- gsub('"', '\\"', x, fixed = TRUE)
      x <- gsub('\n', '\\n', x, fixed = TRUE)
      x <- gsub('\r', '\\r', x, fixed = TRUE)
      x <- gsub('\t', '\\t', x, fixed = TRUE)
      # remaining control characters
      codes <- utf8ToInt(x)
      if (any(codes < 32L))
         x <- paste(vapply(codes, function(code) if (code < 32L) sprintf('\\u%04x', code) else intToUtf8(code), ''),
                    collapse = '')
      paste0('"', x, '"')
   }
   scalar <- function(x)
   {
      if (is.na(x)) return('null')
      if (is.logical(x)) return(if (x) 'true' else 'false')
      if (is.numeric(x)) return(if (is.finite(x)) sprintf('%.15g', x) else 'null')
      string(as.character(x))
   }
   if (is.null(value)) return('null')
   if (is.list(value))
   {
      if (!length(value)) return(if (is.null(names(value))) '[]' else '{}')
      parts <- vapply(seq_along(value), function(i) .rs.superrstudioJsonWrite(value[[i]], inner), '')
      if (is.null(names(value)))
         return(paste0('[\n', inner, paste(parts, collapse = paste0(',\n', inner)), '\n', indent, ']'))
      return(paste0('{\n', inner, paste(paste0(vapply(names(value), string, ''), ': ', parts),
                                         collapse = paste0(',\n', inner)), '\n', indent, '}'))
   }
   value <- unclass(value)
   if (length(value) == 1L) return(scalar(value))
   paste0('[', paste(vapply(seq_along(value), function(i) scalar(value[[i]]), ''), collapse = ', '), ']')
})

.rs.addFunction('superrstudioJsonRead', function(text)
{
   fail <- function() stop('invalid JSON', call. = FALSE)
   pattern <- '"(?:[^"\\\\\\x01-\\x1f]|\\\\.)*"|-?(?:0|[1-9][0-9]*)(?:\\.[0-9]+)?(?:[eE][+-]?[0-9]+)?|true|false|null|[][{}:,]|\\S'
   tokens <- regmatches(text, gregexpr(pattern, text, perl = TRUE))[[1L]]
   n <- length(tokens)
   i <- 1L
   unescape <- function(token)
   {
      x <- substr(token, 2L, nchar(token) - 1L)
      if (!grepl('\\', x, fixed = TRUE)) return(x)
      parts <- regmatches(x, gregexpr('\\\\u[0-9a-fA-F]{4}|\\\\.|[^\\\\]+', x, perl = TRUE))[[1L]]
      if (!identical(paste(parts, collapse = ''), x)) fail()
      decoded <- vapply(parts, function(part) {
         if (!startsWith(part, '\\')) return(part)
         code <- substr(part, 2L, 2L)
         switch(code, '"' = '"', '\\' = '\\', '/' = '/', b = '\b', f = '\f', n = '\n', r = '\r', t = '\t',
                u = {
                   value <- strtoi(substr(part, 3L, 6L), 16L)
                   if (value >= 0xD800 && value <= 0xDFFF) fail()   # surrogates are not used by the writer
                   intToUtf8(value)
                },
                fail())
      }, '')
      paste(decoded, collapse = '')
   }
   value <- function(depth)
   {
      if (depth > 64L || i > n) fail()
      token <- tokens[[i]]
      i <<- i + 1L
      if (token == '{')
      {
         out <- list()
         keys <- character()
         if (i <= n && tokens[[i]] == '}') { i <<- i + 1L; return(structure(list(), names = character())) }
         repeat
         {
            if (i > n || !startsWith(tokens[[i]], '"')) fail()
            keys <- c(keys, unescape(tokens[[i]]))
            i <<- i + 1L
            if (i > n || tokens[[i]] != ':') fail()
            i <<- i + 1L
            out[length(out) + 1L] <- list(value(depth + 1L))
            if (i > n) fail()
            separator <- tokens[[i]]
            i <<- i + 1L
            if (separator == '}') break
            if (separator != ',') fail()
         }
         if (anyDuplicated(keys)) fail()
         names(out) <- keys
         return(out)
      }
      if (token == '[')
      {
         out <- list()
         if (i <= n && tokens[[i]] == ']') { i <<- i + 1L; return(out) }
         repeat
         {
            out[length(out) + 1L] <- list(value(depth + 1L))
            if (i > n) fail()
            separator <- tokens[[i]]
            i <<- i + 1L
            if (separator == ']') break
            if (separator != ',') fail()
         }
         return(out)
      }
      if (startsWith(token, '"')) return(unescape(token))
      if (token == 'true') return(TRUE)
      if (token == 'false') return(FALSE)
      if (token == 'null') return(NULL)
      if (grepl('^-?[0-9]', token)) return(as.numeric(token))
      fail()
   }
   result <- value(0L)
   if (i <= n) fail()
   result
})
