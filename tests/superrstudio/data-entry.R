# Contract tests for SuperR's data table window (SessionSuperRStudioSheet.R).
# SPDX-License-Identifier: AGPL-3.0-only
#
#   Rscript tests/superrstudio/data-entry.R
#
# Every generated code is parsed and evaluated in a scratch environment and
# compared with the expected data frame. Checks: typed tables (decimal point
# and comma, day-first and ISO dates, text, missing values, trailing empty
# rows, unused columns, non-syntactic names), explicit types and their
# errors, object and column name checks, copies of session data frames, text
# files (comma, semicolon with decimal comma in Latin-1, tab, UTF-8 BOM, no
# header, spaces, overrides, large files, refused files) and Excel files
# (readxl's example workbook when readxl is installed). No file of the user
# or of the project is written; temporary files only.
args <- commandArgs(FALSE)
script <- sub('^--file=', '', args[grepl('^--file=', args)])
root <- normalizePath(file.path(dirname(script), '../..'), winslash = '/')
toolsEnv <- new.env(parent = globalenv())
.rs.toolsEnv <- function() toolsEnv
.rs.addFunction <- function(name, FN) {
   environment(FN) <- toolsEnv
   assign(paste0('.rs.', name), FN, envir = toolsEnv)
}
for (file in c('SessionSuperRStudio.R', 'SessionSuperRStudioLfq.R', 'SessionSuperRStudioDeps.R',
               'SessionSuperRStudioSheet.R'))
   sys.source(file.path(root, 'src/cpp/session/modules', file), envir = toolsEnv)

frames <- function() Filter(function(n) is.data.frame(get(n, envir = globalenv())), ls(globalenv()))
sheet <- function(op, settings = list(), dataset = '')
   toolsEnv$.rs.superrstudioDataRpc(op, dataset, '', '', '', frames(), settings)
ok <- function(result) { if (!is.null(result$error)) stop(result$error, call. = FALSE); result }
expect <- function(condition, message) if (!isTRUE(condition)) stop(message, call. = FALSE)
reject <- function(result, pattern)
   expect(!is.null(result$error) && grepl(pattern, result$error), paste('expected an error matching', pattern, '- got', if (is.null(result$error)) 'no error' else result$error))
run <- function(code) {
   env <- new.env(parent = globalenv())
   eval(parse(text = code), env)
   objects <- ls(env)
   expect(length(objects) == 1L, 'the code must create exactly one object')
   get(objects, envir = env)
}
table <- function(columns, rows, name = 'datos', types = NULL)
   list(name = name,
        columns = lapply(seq_along(columns), function(i)
           list(name = columns[[i]], type = if (is.null(types)) 'auto' else types[[i]])),
        rows = rows)
# expected tables keep text as text on every R version
df <- function(...) data.frame(..., stringsAsFactors = FALSE)
same <- function(actual, expected, message) {
   difference <- all.equal(actual, expected, check.attributes = TRUE)
   if (!isTRUE(difference)) {
      print(difference); str(actual); str(expected)
      stop(message, call. = FALSE)
   }
}

# typed table: decimal point and comma, dates in several forms, text with
# accents, missing values, a trailing empty row and an unused column
built <- ok(sheet('sheet_build', table(
   c('talla', 'fecha', 'sexo', ''),
   list(c('12.5', '15/03/2024', 'H', ''),
        c('13,25', '2024-03-16', 'M', ''),
        c('', '17.03.2024', 'a\u00f1o', ''),
        c('14', 'NA', '', ''),
        c('', '', '', '')))))
expect(identical(unclass(built$types), c('number', 'date', 'text')), 'resolved types')
expect(identical(unclass(built$rows), 4L), 'trailing empty rows are not data')
expect(identical(unclass(built$name), 'datos') && identical(unclass(built$exists), FALSE), 'name and exists')
same(run(built$code), df(talla = c(12.5, 13.25, NA, 14),
                                 fecha = as.Date(c('2024-03-15', '2024-03-16', '2024-03-17', NA)),
                                 sexo = c('H', 'M', 'a\u00f1o', NA)), 'typed table')
expect(grepl('^datos <- data.frame\\(\n   talla = ', built$code), 'one column per line')
cat('PASS: typed table (decimal comma, day-first dates, text, missing values, empty rows and columns)\n')

# explicit types, numbers typed as text, invalid dates
same(run(ok(sheet('sheet_build', table(c('codigo', 'n'), list(c('007', '1'), c('012', '2')),
                                       types = c('text', 'number'))))$code),
     df(codigo = c('007', '012'), n = c(1, 2)), 'explicit text type keeps leading zeros')
reject(sheet('sheet_build', table('n', list('1', 'abc'), types = 'number')), "row 2: 'abc' is not a number")
reject(sheet('sheet_build', table('d', list('31/02/2024'), types = 'date')), 'is not a date')
expect(identical(unclass(ok(sheet('sheet_build', table('d', list('31/02/2024'))))$types), 'text'),
       'an impossible date in an automatic column is text')
cat('PASS: explicit types and value errors\n')

# names: non-syntactic column names are kept; object and column names checked
odd <- ok(sheet('sheet_build', table(c('Talla (cm)', 'peso'), list(c('1', '2')))))
expect(grepl('`Talla (cm)` = ', odd$code, fixed = TRUE) && grepl('check.names = FALSE', odd$code, fixed = TRUE),
       'non-syntactic names quoted')
expect(identical(names(run(odd$code)), c('Talla (cm)', 'peso')), 'non-syntactic names kept')
for (bad in c('2x', 'my data', '.hidden', 'if', ''))
   reject(sheet('sheet_build', table('x', list('1'), name = bad)), 'syntactic R name')
reject(sheet('sheet_build', table(c('x', 'x'), list(c('1', '2')))), "Two columns are named 'x'")
reject(sheet('sheet_build', table(c('x', ''), list(c('1', '2')))), 'Column 2 has values but no name')
reject(sheet('sheet_build', table(c('x'), list(c('')))), 'at least one row')
reject(sheet('sheet_build', list(name = 'datos', columns = list(), rows = list())), 'at least one column')
reject(sheet('sheet_build', list(name = 'datos', unknown = 1)), 'Unknown table setting')
reject(sheet('sheet_unknown'), 'Unsupported operation')
cat('PASS: object and column name checks\n')

# a data frame of the session: listed, copied as cells, rebuilt unchanged
captura <- data.frame(talla = c(10.5, NA, 12), fecha = as.Date(c('2024-01-02', '2024-02-03', NA)),
                      especie = factor(c('a', 'b', 'a')), stringsAsFactors = FALSE)
assign('captura', captura, envir = globalenv())
expect('captura' %in% unclass(ok(sheet('sheet_list'))$datasets), 'session data frames listed')
copy <- ok(sheet('sheet_get', dataset = 'captura'))
expect(identical(unclass(copy$types), c('number', 'date', 'text')), 'copied types')
expect(identical(copy$rows[[2L]], c('', '2024-02-03', 'b')), 'missing values are empty cells')
rebuilt <- ok(sheet('sheet_build', list(name = 'captura2', columns = lapply(seq_along(copy$columns), function(i)
   list(name = copy$columns[[i]], type = copy$types[[i]])), rows = copy$rows)))
expectedCopy <- captura
expectedCopy$especie <- as.character(expectedCopy$especie)
same(run(rebuilt$code), expectedCopy, 'copy rebuilt (factor as text)')
expect(isTRUE(unclass(ok(sheet('sheet_build', table('x', list('1'), name = 'captura')))$exists)),
       'an existing object is reported')
reject(sheet('sheet_get', dataset = 'nothing'), 'Choose a data frame')
shape <- ok(sheet('sheet_shape', dataset = 'captura'))
expect(isTRUE(unclass(shape$exists)) && identical(unclass(shape$rows), 3L) && identical(unclass(shape$columns), 3L),
       'shape of a data frame')
expect(identical(unclass(ok(sheet('sheet_shape', dataset = 'nothing'))$exists), FALSE), 'shape of a missing object')
cat('PASS: session data frames copied into the table and rebuilt\n')

# text files
dir <- tempfile('superr-sheet-')
dir.create(dir)
write <- function(name, lines, encoding = 'UTF-8', bom = FALSE) {
   path <- file.path(dir, name)
   bytes <- unlist(lapply(paste0(lines, '\n'), function(l) charToRaw(iconv(l, 'UTF-8', encoding))))
   writeBin(c(if (bom) as.raw(c(0xef, 0xbb, 0xbf)), bytes), path)
   normalizePath(path, winslash = '/')
}
load <- function(path, ...) ok(sheet('sheet_file', list(path = path, ...)))
expected <- df(talla = c(12.5, 13.25), sexo = c('H', 'M'))

comma <- load(write('comma.csv', c('talla,sexo', '12.5,H', '13.25,M')))
expect(identical(unclass(comma$sep), 'comma') && identical(unclass(comma$dec), '.') && isTRUE(unclass(comma$header)),
       'comma file detected')
expect(grepl('^datos <- utils::read.csv\\("', comma$code), 'read.csv for comma files')
same(run(comma$code), expected, 'comma file')
expect(identical(unclass(comma$total), 2L) && length(comma$rows) == 2L, 'row count and preview')

latin <- load(write('latin.csv', c('talla;especie', '12,5;Merluza', '13,25;Sard\u00edna'), encoding = 'latin1'))
expect(identical(unclass(latin$encoding), 'latin1') && identical(unclass(latin$sep), 'semicolon') &&
       identical(unclass(latin$dec), ','), 'Latin-1 semicolon file detected')
expect(grepl('read.csv2(', latin$code, fixed = TRUE) && grepl('fileEncoding = "latin1"', latin$code, fixed = TRUE),
       'read.csv2 with the encoding')
same(run(latin$code), df(talla = c(12.5, 13.25), especie = c('Merluza', 'Sard\u00edna')), 'Latin-1 file')

tab <- load(write('tab.txt', c('talla\tsexo', '12.5\tH', '13.25\tM')))
expect(grepl('read.delim(', tab$code, fixed = TRUE), 'read.delim for tab files')
same(run(tab$code), expected, 'tab file')

bom <- load(write('bom.csv', c('talla,sexo', '12.5,H', '13.25,M'), bom = TRUE))
expect(identical(unclass(bom$encoding), 'UTF-8-BOM'), 'BOM detected')
same(run(bom$code), expected, 'BOM file (clean first column name)')

bare <- load(write('bare.csv', c('12.5,H', '13.25,M')))
expect(identical(unclass(bare$header), FALSE) && grepl('header = FALSE', bare$code, fixed = TRUE), 'no header detected')
expect(identical(names(run(bare$code)), c('V1', 'V2')), 'columns named V1, V2')

space <- load(write('space.txt', c('talla sexo', '12.5 H', '13.25 M')))
expect(identical(unclass(space$sep), 'space') && grepl('read.table(', space$code, fixed = TRUE), 'space-separated')
same(run(space$code), expected, 'space-separated file')

semi <- write('semi-dot.csv', c('talla;sexo', '12.5;H', '13.25;M'))
override <- load(semi, sep = 'semicolon', dec = '.', header = 'yes')
expect(grepl('sep = ";"', override$code, fixed = TRUE) && grepl('dec = "."', override$code, fixed = TRUE),
       'explicit separator and decimal mark')
same(run(override$code), expected, 'overridden settings')
reject(sheet('sheet_file', list(path = semi, sep = 'comma', dec = ',')), 'cannot both be a comma')
reject(sheet('sheet_file', list(path = file.path(dir, 'missing.csv'))), 'existing file')
utf16 <- file.path(dir, 'utf16.csv')
writeBin(c(as.raw(c(0xff, 0xfe)), iconv('a,b\n1,2\n', 'UTF-8', 'UTF-16LE', toRaw = TRUE)[[1L]]), utf16)
reject(sheet('sheet_file', list(path = utf16)), 'UTF-16')
reject(sheet('sheet_file', list(path = semi, sep = 'colon')), 'Unknown separator')
cat('PASS: text files (comma, semicolon/decimal comma/Latin-1, tab, BOM, no header, spaces, overrides, refusals)\n')

# a large file: the preview reads 1,000 rows, the row count comes from the file
limits <- toolsEnv$.rs.superrstudioSheetLimits
toolsEnv$.rs.superrstudioSheetLimits <- function() utils::modifyList(limits(), list(read = 1000))
big <- load(write('big.csv', c('n,v', sprintf('%d,%d', 1:5000, 5000:1))))
toolsEnv$.rs.superrstudioSheetLimits <- limits
expect(isTRUE(unclass(big$approximate)) && identical(unclass(big$total), 5000), 'large file counted')
expect(length(big$rows) == 50L, 'preview limited to 50 rows')
expect(nrow(run(big$code)) == 5000L, 'the code reads the whole file')
cat('PASS: large file (preview of the first rows, whole file in the code)\n')

# Excel
example <- if (length(find.package('readxl', quiet = TRUE))) readxl::readxl_example('datasets.xlsx') else ''
if (nzchar(example)) {
   sheets <- readxl::excel_sheets(example)
   excel <- load(example, sheet = 'chickwts')
   expect(identical(unclass(excel$kind), 'excel') && identical(unclass(excel$sheets), sheets) &&
          identical(unclass(excel$sheet), 'chickwts'), 'Excel sheets listed and chosen')
   expect(grepl('readxl::read_excel(', excel$code, fixed = TRUE) && grepl('sheet = "chickwts"', excel$code, fixed = TRUE),
          'read_excel code names the sheet')
   same(run(excel$code), as.data.frame(readxl::read_excel(example, sheet = 'chickwts')), 'Excel sheet')
   expect(identical(unclass(load(example)$sheet), sheets[[1L]]), 'first sheet by default')
   cat('PASS: Excel workbook (readxl', as.character(utils::packageVersion('readxl')), ')\n')
} else {
   xlsx <- file.path(dir, 'book.xlsx')
   writeBin(as.raw(c(0x50, 0x4b, 0x03, 0x04)), xlsx)
   need <- load(xlsx)
   expect(identical(unclass(need$need), 'readxl'), 'readxl requested for Excel files')
   cat('PASS: Excel file asks for readxl (readxl not installed: reading SKIPPED)\n')
}
unlink(dir, recursive = TRUE)
