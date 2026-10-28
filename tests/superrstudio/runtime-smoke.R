# Standalone R reference checks; this does not exercise RStudio or ggplot2.
args <- commandArgs(trailingOnly = FALSE)
script <- sub('^--file=', '', args[grepl('^--file=', args)])
fixture <- file.path(dirname(normalizePath(script)), 'scientific.csv')

main <- function() {
  data <- read.csv(fixture, check.names = FALSE, stringsAsFactors = FALSE,
                   na.strings = 'NA')
  stopifnot(nrow(data) == 5L, 'length cm' %in% names(data),
            is.numeric(data[['length cm']]), is.logical(data$observed),
            sum(is.na(data[['length cm']])) == 1L,
            data$note[2] == 'comma, value')
  data$date <- as.Date(data$date)
  stopifnot(inherits(data$date, 'Date'), data$date[1] == as.Date('2026-01-01'))

  original <- data
  transformed <- data
  transformed$length_mm <- transformed[['length cm']] * 10
  stopifnot(identical(data, original), !('length_mm' %in% names(data)),
            identical(transformed$length_mm[1:4], c(10, 20, 30, 40)))

  model <- lm(mass_g ~ `length cm`, data = data, na.action = na.omit)
  stopifnot(isTRUE(all.equal(unname(coef(model)), c(1, 2), tolerance = 1e-10)),
            nobs(model) == 4L,
            isTRUE(all.equal(mean(data$mass_g, na.rm = TRUE), 6)))

  tsv <- tempfile(fileext = '.tsv')
  csv <- tempfile(fileext = '.csv')
  pdf <- tempfile(fileext = '.pdf')
  on.exit(unlink(c(tsv, csv, pdf)), add = TRUE)
  write.table(data, tsv, sep = '\t', row.names = FALSE, na = 'NA')
  write.csv(data, csv, row.names = FALSE, na = 'NA')
  for (path in c(tsv, csv)) {
    sep <- if (path == tsv) '\t' else ','
    reread <- read.table(path, header = TRUE, sep = sep, check.names = FALSE,
                         stringsAsFactors = FALSE, na.strings = 'NA')
    reread$date <- as.Date(reread$date)
    stopifnot(identical(data, reread))
  }

  grDevices::pdf(pdf, width = 6, height = 4)
  tryCatch(plot(data[['length cm']], data$mass_g,
                xlab = 'Length (cm)', ylab = 'Mass (g)'),
           finally = grDevices::dev.off())
  stopifnot(file.info(pdf)$size > 0,
            identical(readChar(pdf, nchars = 4, useBytes = TRUE), '%PDF'))
  cat('PASS: import, NA/types, CSV/TSV round trip, source preservation, lm reference, PDF export\n')
  print(sessionInfo())
}

main()
