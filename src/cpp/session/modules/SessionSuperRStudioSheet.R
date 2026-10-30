#
# SessionSuperRStudioSheet.R
#
# SPDX-License-Identifier: AGPL-3.0-only
#
# Data table window: a small table typed or pasted in the window, a text or
# Excel file, or a copy of a data frame of the session becomes a data frame
# through R code. The window sends that code to the console, so the object is
# created visibly, in the history and reproducibly; nothing here assigns into
# the user's environment or changes a file.
#
#   sheet_list   data frames of the session (to copy into the table)
#   sheet_shape  whether a data frame exists, with its rows and columns (the
#                window checks the result of the code it ran)
#   sheet_get    one data frame as table cells (at most 2,000 rows)
#   sheet_build  the table's cells -> column types and data.frame() code
#   sheet_file   a text or Excel file -> detected settings, preview, code
#
# Values: numbers accept a decimal point or a decimal comma (12.5 or 12,5);
# dates accept 2024-03-15, 2024/03/15, 15/03/2024, 15-03-2024 and 15.03.2024
# (day first); empty cells and NA are missing values.

.rs.addFunction('superrstudioSheet', function(operation, dataset, settings, available)
{
   switch(operation,
      sheet_list = list(datasets = .rs.superrstudioSheetFrames(available)),
      sheet_shape = .rs.superrstudioSheetShape(dataset, available),
      sheet_get = .rs.superrstudioSheetGet(dataset, available),
      sheet_build = .rs.superrstudioSheetBuild(settings),
      sheet_file = .rs.superrstudioSheetFile(settings),
      stop('Unsupported operation.', call. = FALSE))
})

.rs.addFunction('superrstudioSheetLimits', function()
   list(rows = 2000L, columns = 100L, preview = 50L, read = 50 * 1024^2))

.rs.addFunction('superrstudioSheetFrames', function(available)
{
   frames <- Filter(function(name) {
      value <- get(name, envir = .GlobalEnv, inherits = FALSE)
      is.data.frame(value)
   }, as.character(available))
   sort(unname(unlist(frames)))
})

.rs.addFunction('superrstudioSheetShape', function(dataset, available)
{
   if (!.rs.superrstudioIsText(dataset) || !dataset %in% .rs.superrstudioSheetFrames(available))
      return(list(exists = I(FALSE)))
   data <- get(dataset, envir = .GlobalEnv, inherits = FALSE)
   list(exists = I(TRUE), rows = I(nrow(data)), columns = I(ncol(data)))
})

#' Check the name of the object to create
#'
#' @param name A syntactic R name that does not start with a dot.
.rs.addFunction('superrstudioSheetName', function(name)
{
   if (!.rs.superrstudioIsText(name) || !nzchar(name) || !identical(make.names(name), name) ||
       startsWith(name, '.'))
      stop('The name must be a syntactic R name, such as datos or catch_2024.', call. = FALSE)
   name
})

#' Read numbers typed with a decimal point or a decimal comma
#'
#' @param x Character vector.
#' @return A list: value (numeric) and ok (TRUE where x is a number or missing).
.rs.addFunction('superrstudioSheetNumber', function(x)
{
   x <- trimws(x)
   missing <- !nzchar(x) | x == 'NA'
   comma <- grepl('^[+-]?[0-9]*,[0-9]+([eE][+-]?[0-9]+)?$', x)
   x[comma] <- sub(',', '.', x[comma], fixed = TRUE)
   number <- grepl('^[+-]?([0-9]+[.]?[0-9]*|[.][0-9]+)([eE][+-]?[0-9]+)?$', x)
   value <- rep(NA_real_, length(x))
   value[number] <- as.numeric(x[number])
   list(value = value, ok = number | missing)
})

#' Read dates (year first in ISO form, otherwise day first)
#'
#' @param x Character vector.
#' @return A list: value (Date) and ok (TRUE where x is a valid date or missing).
.rs.addFunction('superrstudioSheetDate', function(x)
{
   x <- trimws(x)
   missing <- !nzchar(x) | x == 'NA'
   formats <- list(c('^[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}$', '%Y-%m-%d'),
                   c('^[0-9]{4}/[0-9]{1,2}/[0-9]{1,2}$', '%Y/%m/%d'),
                   c('^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}$', '%d/%m/%Y'),
                   c('^[0-9]{1,2}-[0-9]{1,2}-[0-9]{4}$', '%d-%m-%Y'),
                   c('^[0-9]{1,2}[.][0-9]{1,2}[.][0-9]{4}$', '%d.%m.%Y'))
   value <- rep(as.Date(NA), length(x))
   for (format in formats)
   {
      use <- is.na(value) & grepl(format[[1L]], x)
      value[use] <- as.Date(x[use], format = format[[2L]])
   }
   list(value = value, ok = !is.na(value) | missing)
})

#' One column of the table: resolve its type and convert its values
#'
#' @param values Character vector of cells.
#' @param type One of auto, number, text, date.
#' @param label Column name used in messages.
.rs.addFunction('superrstudioSheetColumn', function(values, type, label)
{
   values[is.na(values)] <- ''
   missing <- !nzchar(trimws(values)) | trimws(values) == 'NA'
   number <- .rs.superrstudioSheetNumber(values)
   date <- .rs.superrstudioSheetDate(values)
   if (identical(type, 'auto'))
      type <- if (all(missing)) 'text' else if (all(number$ok)) 'number'
              else if (all(date$ok)) 'date' else 'text'
   bad <- switch(type, number = which(!number$ok), date = which(!date$ok), integer())
   if (length(bad))
      stop(sprintf("Column '%s', row %d: '%s' is not a %s%s.", label, bad[[1L]], values[[bad[[1L]]]], type,
                   if (type == 'date') ' (write it as 2024-03-15 or 15/03/2024)' else ''), call. = FALSE)
   value <- switch(type,
      number = number$value,
      date = date$value,
      text = { text <- values; text[missing] <- NA_character_; text })
   list(type = type, value = value)
})

#' data.frame() code, one column per line
#'
#' @param name Object name (checked).
#' @param columns Named list of column values (numeric, character or Date).
.rs.addFunction('superrstudioSheetCode', function(name, columns)
{
   symbol <- function(text)
      if (identical(make.names(text), text)) text
      else paste0('`', gsub('`', '\\`', text, fixed = TRUE), '`')
   argument <- function(label, value)
   {
      expression <- if (inherits(value, 'Date')) call('as.Date', format(value)) else value
      lines <- deparse(expression, width.cutoff = 70L)
      paste0('   ', symbol(label), ' = ', paste(lines, collapse = '\n      '))
   }
   parts <- mapply(argument, names(columns), columns, USE.NAMES = FALSE)
   if (!all(make.names(names(columns)) == names(columns)))
      parts <- c(parts, '   check.names = FALSE')
   # before R 4.0 text columns would become factors
   if (getRversion() < '4.0.0' && any(vapply(columns, is.character, TRUE)))
      parts <- c(parts, '   stringsAsFactors = FALSE')
   code <- paste0(name, ' <- data.frame(\n', paste(parts, collapse = ',\n'), '\n)')
   parse(text = code)
   code
})

#' The table typed or pasted in the window as data.frame() code
#'
#' @param settings name, columns (list of name/type) and rows (lists of cells).
.rs.addFunction('superrstudioSheetBuild', function(settings)
{
   fail <- function(message) stop(message, call. = FALSE)
   # NULL defaults: modifyList() would merge (and drop) the unnamed lists
   s <- .rs.superrstudioSettings(settings, list(name = 'datos', columns = NULL, rows = NULL), 'Table')
   name <- .rs.superrstudioSheetName(s$name)
   limits <- .rs.superrstudioSheetLimits()
   field <- function(value, default) if (is.null(value) || !length(value)) default else as.character(value)[[1L]]
   columns <- lapply(s$columns, function(column) {
      column <- as.list(column)
      list(name = trimws(field(column$name, '')), type = field(column$type, 'auto'))
   })
   rows <- lapply(s$rows, function(row) as.character(unlist(row)))
   width <- length(columns)
   if (!width) fail('Name at least one column and type its values.')
   if (width > limits$columns) fail(sprintf('The table has more than %d columns.', limits$columns))
   cells <- vapply(rows, function(row) c(row, rep('', width))[seq_len(width)], character(width))
   cells <- matrix(cells, ncol = width, byrow = TRUE)
   # trailing rows with no value are not data
   filled <- which(vapply(seq_len(nrow(cells)), function(i) any(nzchar(trimws(cells[i, ]))), TRUE))
   cells <- cells[seq_len(if (length(filled)) max(filled) else 0L), , drop = FALSE]
   if (nrow(cells) > limits$rows)
      fail(sprintf('The table has %d rows; type or paste at most %d (load larger data from a file).',
                   nrow(cells), limits$rows))
   # columns with neither a name nor a value are ignored
   used <- vapply(seq_len(width), function(j) nzchar(columns[[j]]$name) || any(nzchar(trimws(cells[, j]))), TRUE)
   for (j in which(used))
   {
      if (!nzchar(columns[[j]]$name)) fail(sprintf('Column %d has values but no name.', j))
      if (!columns[[j]]$type %in% c('auto', 'number', 'text', 'date'))
         fail(sprintf("Unknown type for column '%s'.", columns[[j]]$name))
   }
   labels <- vapply(columns[used], `[[`, '', 'name')
   if (!length(labels)) fail('Name at least one column and type its values.')
   if (anyDuplicated(labels)) fail(sprintf("Two columns are named '%s'.", labels[anyDuplicated(labels)]))
   if (!nrow(cells)) fail('Type or paste at least one row of values.')
   resolved <- lapply(which(used), function(j)
      .rs.superrstudioSheetColumn(cells[, j], columns[[j]]$type, columns[[j]]$name))
   values <- stats::setNames(lapply(resolved, `[[`, 'value'), labels)
   list(name = I(name),
        code = I(.rs.superrstudioSheetCode(name, values)),
        columns = labels,
        types = vapply(resolved, `[[`, '', 'type'),
        rows = I(nrow(cells)),
        exists = I(exists(name, envir = .GlobalEnv, inherits = FALSE)))
})

#' Cells of a data frame as text (dates in ISO form)
#'
#' @param data A data frame.
#' @param na Text for missing values.
.rs.addFunction('superrstudioSheetCells', function(data, na)
{
   text <- lapply(data, function(x) {
      value <- if (inherits(x, 'POSIXt')) format(x, '%Y-%m-%d %H:%M:%S')
               else if (inherits(x, 'Date')) format(x)
               else as.character(x)
      value[is.na(x)] <- na
      value
   })
   lapply(seq_len(nrow(data)), function(i) unname(vapply(text, `[[`, '', i)))
})

.rs.addFunction('superrstudioSheetType', function(x)
   if (inherits(x, 'POSIXt')) 'datetime' else if (inherits(x, 'Date')) 'date'
   else if (is.factor(x)) 'factor' else if (is.logical(x)) 'logical'
   else if (is.numeric(x)) 'number' else 'text')

#' A data frame of the session as table cells, to edit a copy
#'
#' @param dataset Name of a data frame in the global environment.
#' @param available Data frames listed by the session.
.rs.addFunction('superrstudioSheetGet', function(dataset, available)
{
   fail <- function(message) stop(message, call. = FALSE)
   if (!.rs.superrstudioIsText(dataset) || !dataset %in% .rs.superrstudioSheetFrames(available))
      fail('Choose a data frame of this session.')
   data <- get(dataset, envir = .GlobalEnv, inherits = FALSE)
   limits <- .rs.superrstudioSheetLimits()
   if (nrow(data) > limits$rows || ncol(data) > limits$columns)
      fail(sprintf('%s has %d rows and %d columns; the table holds at most %d rows and %d columns. Use it directly in the plot editor or the length-frequency window.',
                   dataset, nrow(data), ncol(data), limits$rows, limits$columns))
   types <- vapply(data, .rs.superrstudioSheetType, '')
   list(dataset = I(dataset),
        columns = names(data),
        types = ifelse(types %in% c('number', 'date'), types, 'text'),
        rows = .rs.superrstudioSheetCells(data, ''))
})

#' Detect how a text file is written
#'
#' @param path File path.
#' @param encoding auto, UTF-8, UTF-8-BOM or latin1.
#' @return A list: encoding, lines (decoded, non-empty, at most 30).
.rs.addFunction('superrstudioSheetSample', function(path, encoding)
{
   raw <- readBin(path, 'raw', n = 65536L)
   if (any(raw == as.raw(0L)))
      stop('The file looks like UTF-16 or a binary file; save it as CSV (UTF-8) and try again.', call. = FALSE)
   if (identical(encoding, 'auto'))
   {
      bom <- length(raw) >= 3L && identical(raw[1:3], as.raw(c(0xef, 0xbb, 0xbf)))
      # a cut multi-byte character at the end of the sample is not an error
      breaks <- which(raw == as.raw(10L))
      sample <- if (length(raw) == 65536L && length(breaks)) raw[seq_len(max(breaks))] else raw
      encoding <- if (bom) 'UTF-8-BOM' else if (validUTF8(rawToChar(sample))) 'UTF-8' else 'latin1'
   }
   connection <- file(path, encoding = encoding)
   on.exit(close(connection))
   lines <- readLines(connection, n = 30L, warn = FALSE)
   list(encoding = encoding, lines = lines[nzchar(trimws(lines))])
})

#' Separator, decimal mark and header of a text file
#'
#' @param lines Decoded sample lines.
.rs.addFunction('superrstudioSheetDetect', function(lines)
{
   clean <- gsub('"[^"]*"', '', lines)
   separators <- c(tab = '\t', semicolon = ';', comma = ',', pipe = '|')
   counts <- lapply(separators, function(sep) lengths(regmatches(clean, gregexpr(sep, clean, fixed = TRUE))))
   consistent <- vapply(counts, function(n) length(n) > 0L && min(n) > 0L && length(unique(n)) == 1L, TRUE)
   sep <- if (any(consistent)) names(separators)[consistent][[1L]]
          else if (length(clean) && all(grepl('[^[:space:]][[:space:]]+[^[:space:]]', trimws(clean)))) 'space'
          else 'comma'
   dec <- if (sep != 'comma' && any(grepl('[0-9],[0-9]', clean))) ',' else '.'
   first <- if (!length(lines)) character()
            else if (sep == 'space') strsplit(trimws(lines[[1L]]), '[[:space:]]+')[[1L]]
            else strsplit(lines[[1L]], separators[[sep]], fixed = TRUE)[[1L]]
   first <- gsub('^"|"$', '', trimws(first))
   header <- !any(nzchar(first) & .rs.superrstudioSheetNumber(first)$ok)
   list(sep = sep, dec = dec, header = header)
})

#' The read call for a text file, with the simplest standard reader
#'
#' @param path Normalised path.
#' @param sep comma, semicolon, tab, pipe or space.
#' @param dec Decimal mark.
#' @param header Logical.
#' @param encoding UTF-8, UTF-8-BOM or latin1.
.rs.addFunction('superrstudioSheetReadCall', function(path, sep, dec, header, encoding)
{
   value <- c(comma = ',', semicolon = ';', tab = '\t', pipe = '|', space = '')[[sep]]
   reader <- if (sep == 'comma' && dec == '.') quote(utils::read.csv)
             else if (sep == 'semicolon' && dec == ',') quote(utils::read.csv2)
             else if (sep == 'tab' && dec == '.') quote(utils::read.delim)
             else if (sep == 'tab' && dec == ',') quote(utils::read.delim2)
             else NULL
   args <- list(path)
   if (is.null(reader))
   {
      reader <- quote(utils::read.table)
      args <- c(args, list(header = header, sep = value, dec = dec))
      if (sep != 'space') args <- c(args, list(quote = '"', fill = TRUE, comment.char = ''))
   }
   else if (!header)
      args <- c(args, list(header = FALSE))
   if (encoding != 'UTF-8') args <- c(args, list(fileEncoding = encoding))
   # before R 4.0 text columns would become factors
   if (getRversion() < '4.0.0') args <- c(args, list(stringsAsFactors = FALSE))
   as.call(c(reader, args))
})

#' A text or Excel file: detected settings, a preview and the code that reads it
#'
#' @param settings path, name, sep, dec, header, encoding (auto or a value) and
#'   sheet (Excel; empty for the first one).
.rs.addFunction('superrstudioSheetFile', function(settings)
{
   fail <- function(message) stop(message, call. = FALSE)
   s <- .rs.superrstudioSettings(settings, list(path = '', name = 'datos', sep = 'auto', dec = 'auto',
                                                header = 'auto', encoding = 'auto', sheet = ''), 'File')
   name <- .rs.superrstudioSheetName(s$name)
   if (!.rs.superrstudioIsText(s$path) || !nzchar(s$path) || !file.exists(path.expand(s$path)))
      fail('Choose an existing file.')
   path <- normalizePath(path.expand(s$path), winslash = '/', mustWork = TRUE)
   limits <- .rs.superrstudioSheetLimits()
   size <- file.size(path)
   excel <- tolower(tools::file_ext(path)) %in% c('xlsx', 'xls')
   warnings <- character()
   collect <- function(expression)
      withCallingHandlers(expression, warning = function(w) {
         warnings <<- c(warnings, conditionMessage(w))
         invokeRestart('muffleWarning')
      })
   result <- list(name = I(name), path = I(path), kind = I(if (excel) 'excel' else 'text'),
                  exists = I(exists(name, envir = .GlobalEnv, inherits = FALSE)))

   if (excel)
   {
      if (!length(find.package('readxl', quiet = TRUE)))
         return(c(result, list(need = I('readxl'))))
      sheets <- readxl::excel_sheets(path)
      sheet <- if (nzchar(s$sheet) && s$sheet %in% sheets) s$sheet else sheets[[1L]]
      read <- call('as.data.frame', as.call(list(quote(readxl::read_excel), path, sheet = sheet)))
      data <- collect(eval(read, baseenv()))
      result <- c(result, list(sheets = sheets, sheet = I(sheet), approximate = I(FALSE)))
   }
   else
   {
      if (!s$encoding %in% c('auto', 'UTF-8', 'UTF-8-BOM', 'latin1')) fail('Unknown encoding.')
      if (!s$sep %in% c('auto', 'comma', 'semicolon', 'tab', 'pipe', 'space')) fail('Unknown separator.')
      if (!s$dec %in% c('auto', '.', ',')) fail('Unknown decimal mark.')
      if (!s$header %in% c('auto', 'yes', 'no')) fail('Unknown header setting.')
      sample <- .rs.superrstudioSheetSample(path, s$encoding)
      if (!length(sample$lines)) fail('The file is empty.')
      detected <- .rs.superrstudioSheetDetect(sample$lines)
      sep <- if (s$sep == 'auto') detected$sep else s$sep
      dec <- if (s$dec == 'auto') (if (sep == 'comma') '.' else detected$dec) else s$dec
      header <- if (s$header == 'auto') detected$header else s$header == 'yes'
      if (sep == 'comma' && dec == ',') fail('The separator and the decimal mark cannot both be a comma.')
      read <-.rs.superrstudioSheetReadCall(path, sep, dec, header, sample$encoding)
      # large files: the preview reads the first rows; the code reads them all
      large <- size > limits$read
      preview <- read
      if (large) preview$nrows <- 1000L
      data <- collect(eval(preview, baseenv()))
      result <- c(result, list(sep = I(sep), dec = I(dec), header = I(header),
                               encoding = I(sample$encoding), approximate = I(large)))
   }
   total <- nrow(data)
   if (isTRUE(result$approximate))
   {
      connection <- file(path, 'rb')
      on.exit(close(connection))
      total <- 0
      repeat {
         chunk <- readBin(connection, 'raw', n = 8388608L)
         if (!length(chunk)) break
         total <- total + sum(chunk == as.raw(10L))
      }
      total <- total - isTRUE(result$header)
   }
   code <- paste0(name, ' <- ', paste(deparse(read, width.cutoff = 70L), collapse = '\n   '))
   parse(text = code)
   preview <- utils::head(data, limits$preview)
   c(result, list(code = I(code),
                  columns = names(data),
                  types = vapply(data, .rs.superrstudioSheetType, '', USE.NAMES = FALSE),
                  rows = .rs.superrstudioSheetCells(preview, 'NA'),
                  total = I(total),
                  warnings = unique(warnings)))
})
