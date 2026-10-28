# Focused contract tests for the real session module. SPDX-License-Identifier: AGPL-3.0-only
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
data <- data.frame(x = c(1, 2, NA, 4), y = c(3, 5, 7, 9), group = letters[1:4])
original <- data
request <- function(op, name = 'data', rev = '', x = 'x', y = 'y')
   toolsEnv$.rs.superrstudioData(op, name, as.character(rev), x, y,
      intersect(c('data', 'odd name', 'bad', 'huge'), ls(globalenv())))
reject <- function(expr, pattern) {
   error <- tryCatch({force(expr); NULL}, error = identity)
   if (!inherits(error, 'error') || !grepl(pattern, conditionMessage(error)))
      stop('Expected error ', pattern, '; got: ', if (is.null(error)) 'success' else conditionMessage(error))
}
stopifnot(identical(request('list')$datasets, 'data'))
selected <- request('inspect')
stopifnot(identical(selected$columns, c('x', 'y')), selected$rows == 4L)
data$x[1] <- 10
reject(request('code', rev = selected$revision), 'changed')
data <- original
selected <- request('inspect')
reject(request('code', rev = selected$revision, x = 'group'), 'numeric')
reject(request('code', rev = 'old'), 'changed')
reject(request('unknown'), 'Unsupported')
second <- request('inspect')
request('release', rev = selected$revision)
stopifnot(!is.null(toolsEnv$.rs.superrstudioState$snapshot))
request('release', rev = second$revision)
reject(request('code', rev = second$revision), 'changed')
bad <- data; names(bad)[2] <- 'x'
reject(request('inspect', 'bad'), 'unique')
huge <- data.frame(x = seq_len(100001L))
reject(request('inspect', 'huge'), '100,000')
selected <- request('inspect')
rm(data)
reject(request('preview', rev = selected$revision), 'no longer exists')
data <- original

if (requireNamespace('ggplot2', quietly = TRUE)) {
   # Includes whitespace, quotes, backticks and a would-be executable name.
   assign('odd name', data, globalenv())
   evil <- 'x"; assign("INJECTED", TRUE, .GlobalEnv); #`\n'
   names(`odd name`)[1] <- evil
   selected <- request('inspect', 'odd name')
   result <- request('code', 'odd name', selected$revision, evil, 'y')
   plot <- eval(parse(text = result$code), envir = globalenv())
   built <- ggplot2::ggplot_build(plot)
   stopifnot(identical(built$data[[1]]$x, original$x),
             identical(built$data[[1]]$y, original$y),
             !exists('INJECTED', globalenv()), result$spec$schema_version == 1L,
             identical(result$spec$x, I(evil)))
   pdf <- tempfile(fileext = '.pdf')
   grDevices::pdf(pdf)
   preview <- request('preview', 'odd name', selected$revision, evil, 'y')
   grDevices::dev.off()
   stopifnot(file.info(pdf)$size > 0, length(preview$warnings) == 1L,
             identical(data, original), identical(result$code, preview$code))
   unlink(pdf)
   cat('PASS: ggplot2 generated-code equivalence, unusual names/injection, preview/warnings, source preservation\n')
} else {
   selected <- request('inspect')
   reject(request('code', rev = selected$revision), 'ggplot2 is required')
   cat('SKIP: ggplot2 rendering (package absent); missing-package behavior PASS\n')
}
cat('PASS: dataset/column contracts, stale values, deleted data, revisions/release, limits and invalid operations\n')
