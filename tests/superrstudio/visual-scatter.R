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
request <- function(op, name = 'data', rev = '', x = 'x', y = 'y', appearance = list())
   toolsEnv$.rs.superrstudioData(op, name, as.character(rev), x, y,
      intersect(c('data', 'odd name', 'bad', 'huge'), ls(globalenv())), appearance)
reject <- function(expr, pattern) {
   error <- tryCatch({force(expr); NULL}, error = identity)
   if (!inherits(error, 'error') || !grepl(pattern, conditionMessage(error)))
      stop('Expected error ', pattern, '; got: ', if (is.null(error)) 'success' else conditionMessage(error))
}
stopifnot(identical(request('list')$datasets, 'data'))
selected <- request('inspect')
stopifnot(identical(selected$columns, c('x', 'y')), selected$rows == 4L,
          identical(selected$colour_columns, c('x', 'y', 'group')))
data$x[1] <- 10
reject(request('code', rev = selected$revision), 'changed')
data <- original
selected <- request('inspect')
reject(request('code', rev = selected$revision, x = 'group'), 'numeric')
reject(request('code', rev = 'old'), 'changed')
reject(request('unknown'), 'Unsupported')
# The RPC entry point returns validation failures as data (nothing is printed).
rpc <- toolsEnv$.rs.superrstudioDataRpc('unknown', '', '', '', '', character())
stopifnot(identical(rpc, list(error = I('Unsupported operation.'))))
stopifnot(identical(toolsEnv$.rs.superrstudioDataRpc('list', available = 'data')$datasets, 'data'))
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

# Appearance validation (independent of ggplot2).
look <- toolsEnv$.rs.superrstudioScatterAppearance
defaults <- look(list())
stopifnot(identical(defaults, list(title = '', x_label = '', y_label = '', colour = '',
                                   size = 1.5, alpha = 1, theme = 'grey')),
          identical(look(NULL), defaults),
          identical(look(list(size = 3L))$size, 3),
          identical(look(list(colour = '#0072B2'))$colour, '#0072B2'),
          identical(look(list(colour = 'steelblue'))$colour, 'steelblue'))
reject(look(list(colour = 'red; system("x")')), 'colour')
reject(look(list(colour = '#12345')), 'colour')
reject(look(list(size = 0)), 'size')
reject(look(list(size = Inf)), 'size')
reject(look(list(size = '3')), 'size')
reject(look(list(alpha = 1.5)), 'opacity')
reject(look(list(theme = 'void')), 'theme')
reject(look(list(title = strrep('a', 201L))), '200')
reject(look(list(title = c('a', 'b'))), 'text')
reject(look(list(fill = 'red')), 'Unknown appearance setting: fill')
reject(look(list('red')), 'named')
layers <- toolsEnv$.rs.superrstudioScatterLayers('data', 'x', 'y', defaults)
stopifnot(length(layers) == 2L, identical(layers[[2L]], quote(ggplot2::geom_point())))
selected <- request('inspect')
reject(request('code', rev = selected$revision, appearance = list(theme = 'void')),
       if (requireNamespace('ggplot2', quietly = TRUE)) 'theme' else 'ggplot2 is required')
cat('PASS: appearance validation (types, ranges, colours, themes, unknown keys, defaults)\n')

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
             !exists('INJECTED', globalenv()), result$spec$schema_version == 2L,
             identical(result$spec$x, I(evil)), is.null(result$spec$revision))
   pdf <- tempfile(fileext = '.pdf')
   grDevices::pdf(pdf)
   preview <- request('preview', 'odd name', selected$revision, evil, 'y')
   grDevices::dev.off()
   stopifnot(file.info(pdf)$size > 0, length(preview$warnings) == 1L,
             identical(data, original), identical(result$code, preview$code))
   unlink(pdf)

   # Appearance reaches the plot, is emitted only when not default, and text
   # (including injection-shaped titles) stays literal.
   style <- list(title = evil, x_label = 'Length (cm)', y_label = '', colour = '#D55E00',
                 size = 3, alpha = 0.6, theme = 'minimal')
   styled <- request('code', 'odd name', selected$revision, evil, 'y', style)
   cat(styled$code)
   plot <- eval(parse(text = styled$code), envir = globalenv())
   built <- ggplot2::ggplot_build(plot)
   point <- plot$layers[[1L]]$aes_params
   stopifnot(identical(plot$labels$title, evil), identical(plot$labels$x, 'Length (cm)'),
             identical(point$colour, '#D55E00'), identical(point$size, 3), identical(point$alpha, 0.6),
             isTRUE(all.equal(plot$theme, ggplot2::theme_minimal())),
             identical(built$data[[1]]$x, original$x), !exists('INJECTED', globalenv()),
             !grepl('y = ', strsplit(styled$code, 'labs', fixed = TRUE)[[1L]][2L], fixed = TRUE),
             identical(styled$spec$appearance$theme, I('minimal')),
             grepl(' +\n  ggplot2::theme_minimal()', styled$code, fixed = TRUE))
   # Defaults produce exactly the original minimal code.
   plain <- request('code', 'odd name', selected$revision, evil, 'y', defaults)
   stopifnot(identical(plain$code, result$code), !grepl('labs|theme_', plain$code))
   # (Runs after the odd-name checks: a new inspect replaces the session's
   # single active selection.)
   # Colour mapping: categories get a discrete viridis scale, numbers a
   # continuous one; invalid or conflicting mappings are rejected.
   chosen <- request('inspect')
   byGroup <- request('code', rev = chosen$revision, appearance = list(colour_by = 'group'))
   cat(byGroup$code)
   plot <- eval(parse(text = byGroup$code), envir = globalenv())
   built <- ggplot2::ggplot_build(plot)
   stopifnot(grepl('colour = .data[["group"]]', byGroup$code, fixed = TRUE),
             grepl('ggplot2::scale_colour_viridis_d()', byGroup$code, fixed = TRUE),
             length(unique(built$data[[1]]$colour)) == 4L,
             identical(byGroup$spec$colour_by, I('group')))
   byY <- request('code', rev = chosen$revision, appearance = list(colour_by = 'y', size = 2))
   stopifnot(grepl('ggplot2::scale_colour_viridis_c()', byY$code, fixed = TRUE),
             grepl('geom_point(size = 2)', byY$code, fixed = TRUE))
   ggplot2::ggplot_build(eval(parse(text = byY$code), envir = globalenv()))
   reject(request('code', rev = chosen$revision, appearance = list(colour_by = 'nope')), 'colour by')
   reject(request('code', rev = chosen$revision, appearance = list(colour_by = c('x', 'y'))), 'colour by')
   reject(request('code', rev = chosen$revision,
                  appearance = list(colour_by = 'group', colour = '#000000')), 'not both')
   stopifnot(identical(request('code', rev = chosen$revision)$spec$colour_by, I('')))

   cat('PASS: ggplot2 generated-code equivalence, unusual names/injection, preview/warnings, source preservation, appearance, colour mapping\n')
} else {
   selected <- request('inspect')
   reject(request('code', rev = selected$revision), 'ggplot2 is required')
   cat('SKIP: ggplot2 rendering (package absent); missing-package behavior PASS\n')
}
cat('PASS: dataset/column contracts, stale values, deleted data, revisions/release, limits and invalid operations\n')
