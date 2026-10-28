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
      intersect(c('data', 'odd name', 'bad', 'huge', 'series', 'ref'), ls(globalenv())), appearance)
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
                                   size = 1.5, alpha = 1, theme = 'grey', line_colour = '',
                                   line_width = 0.5, line_type = 'solid', fit_colour = '')),
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
reject(look(list(line_type = 'wavy')), 'line type')
reject(look(list(line_width = 9)), 'Line width')
reject(look(list(fit_colour = 'nope')), 'Fit colour')
# Layer options: geometry, explicit line order, fit method and parameters.
opts <- toolsEnv$.rs.superrstudioScatterOptions
stopifnot(identical(opts(list()), list(geometry = 'points', line_order = 'x', fit = 'none',
                                       fit_se = TRUE, fit_level = 0.95, fit_span = 0.75)))
reject(opts(list(geometry = 'bars')), 'Geometry')
reject(opts(list(line_order = 'random')), 'Line order')
reject(opts(list(fit = 'glm')), 'Fit must be')
reject(opts(list(fit_se = 'yes')), 'Confidence band')
reject(opts(list(fit_level = 1)), 'Confidence level')
reject(opts(list(fit_span = 0)), 'span')
reject(opts(list(colour = 'red')), 'Unknown layer setting')
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
             !exists('INJECTED', globalenv()), result$spec$schema_version == 3L,
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

   # Connected lines: the order is explicit (geom_line sorts by x; geom_path
   # keeps row order) and lines can be grouped by a category.
   series <<- data.frame(t = c(3, 1, 2, 5, 4), v = c(30, 10, 20, 50, 40),
                         site = c('a', 'a', 'b', 'b', 'b'))
   chosen <- request('inspect', 'series')
   stopifnot(identical(chosen$discrete_columns, 'site'))
   byX <- request('code', 'series', chosen$revision, 't', 'v', list(geometry = 'lines_points'))
   cat(byX$code)
   stopifnot(grepl('ggplot2::geom_line() +\n  ggplot2::geom_point()', byX$code, fixed = TRUE))
   built <- ggplot2::ggplot_build(eval(parse(text = byX$code), envir = globalenv()))
   stopifnot(identical(built$data[[1]]$x, c(1, 2, 3, 4, 5)))
   byRow <- request('code', 'series', chosen$revision, 't', 'v',
                    list(geometry = 'lines', line_order = 'data', line_colour = '#0072B2',
                         line_width = 1.2, line_type = 'dashed'))
   stopifnot(grepl('ggplot2::geom_path(colour = "#0072B2", linewidth = 1.2, linetype = "dashed")',
                   byRow$code, fixed = TRUE), !grepl('geom_point', byRow$code))
   built <- ggplot2::ggplot_build(eval(parse(text = byRow$code), envir = globalenv()))
   stopifnot(identical(built$data[[1]]$x, series$t))
   grouped <- request('code', 'series', chosen$revision, 't', 'v',
                      list(geometry = 'lines', group_by = 'site'))
   stopifnot(grepl('group = .data[["site"]]', grouped$code, fixed = TRUE),
             identical(grouped$spec$group_by, I('site')))
   built <- ggplot2::ggplot_build(eval(parse(text = grouped$code), envir = globalenv()))
   stopifnot(length(unique(built$data[[1]]$group)) == 2L)
   reject(request('code', 'series', chosen$revision, 't', 'v', list(group_by = 'site')), 'Grouping applies')
   reject(request('code', 'series', chosen$revision, 't', 'v', list(geometry = 'lines', group_by = 't')),
          'Group lines')
   cat('PASS: connected lines (explicit x/row order, grouping, line appearance)\n')

   # Fits are checked against reference R computations: stats::lm(), the
   # closed-form least-squares estimates, predict() intervals and stats::loess().
   ref <<- data.frame(u = c(1, 2, 3, 4, 5, 6, 7, 8, NA),
                      w = c(2.1, 3.9, 6.2, 7.8, 10.1, 12.2, 13.8, 16.1, 5),
                      g = c('p', 'q', 'p', 'q', 'p', 'q', 'p', 'q', 'p'))
   chosen <- request('inspect', 'ref')
   linear <- request('code', 'ref', chosen$revision, 'u', 'w',
                     list(fit = 'lm', fit_level = 0.9, fit_colour = '#D55E00'))
   cat(linear$code, '\n', linear$model_code, '\n', sep = '')
   stopifnot(grepl('ggplot2::geom_smooth(method = "lm", formula = y ~ x, level = 0.9, colour = "#D55E00")',
                   linear$code, fixed = TRUE))
   complete <- ref[is.finite(ref$u) & is.finite(ref$w), ]
   model <- stats::lm(w ~ u, data = complete)
   slope <- stats::cov(complete$u, complete$w) / stats::var(complete$u)
   stats1 <- linear$fit_summary[[1L]]
   stopifnot(length(linear$fit_summary) == 1L, stats1$n == 8L,
             isTRUE(all.equal(as.numeric(stats1$slope), slope)),
             isTRUE(all.equal(as.numeric(stats1$intercept), mean(complete$w) - slope * mean(complete$u))),
             isTRUE(all.equal(as.numeric(stats1$slope), unname(stats::coef(model)[2L]))),
             isTRUE(all.equal(as.numeric(stats1$r_squared), stats::cor(complete$u, complete$w)^2)),
             isTRUE(all.equal(as.numeric(stats1$adj_r_squared), summary(model)$adj.r.squared)),
             isTRUE(all.equal(as.numeric(stats1$slope_p_value), summary(model)$coefficients[2L, 4L])),
             grepl('^w = ', stats1$equation), grepl(' \\* u$', stats1$equation))
   plot <- eval(parse(text = linear$code), envir = globalenv())
   smooth <- suppressWarnings(ggplot2::ggplot_build(plot))$data[[2L]]
   reference <- stats::predict(model, newdata = data.frame(u = smooth$x), interval = 'confidence', level = 0.9)
   stopifnot(isTRUE(all.equal(smooth$y, unname(reference[, 'fit']))),
             isTRUE(all.equal(smooth$ymin, unname(reference[, 'lwr']))),
             isTRUE(all.equal(smooth$ymax, unname(reference[, 'upr']))))
   reproduced <- eval(parse(text = linear$model_code), envir = globalenv())
   stopifnot(isTRUE(all.equal(unname(stats::coef(reproduced)[, 1L]), unname(stats::coef(model)))))
   # Per-group fits follow a discrete colour mapping, like geom_smooth().
   perGroup <- request('code', 'ref', chosen$revision, 'u', 'w', list(fit = 'lm', colour_by = 'g', fit_se = FALSE))
   stopifnot(length(perGroup$fit_summary) == 2L, grepl('se = FALSE', perGroup$code, fixed = TRUE))
   for (entry in perGroup$fit_summary)
   {
      part <- complete[complete$g == entry$group, ]
      stopifnot(isTRUE(all.equal(as.numeric(entry$slope), unname(stats::coef(stats::lm(w ~ u, data = part))[2L]))))
   }
   groupedModels <- eval(parse(text = perGroup$model_code), envir = globalenv())
   stopifnot(identical(sort(names(groupedModels)), c('p', 'q')))
   # LOESS: descriptive smoother, no equation or R-squared; matches stats::loess().
   smoother <- request('code', 'ref', chosen$revision, 'u', 'w', list(fit = 'loess', fit_span = 0.9))
   stopifnot(grepl('method = "loess", formula = y ~ x, span = 0.9', smoother$code, fixed = TRUE),
             is.null(smoother$fit_summary[[1L]]$r_squared), identical(smoother$model_code, I('')))
   smooth <- suppressWarnings(ggplot2::ggplot_build(eval(parse(text = smoother$code), envir = globalenv())))$data[[2L]]
   loessModel <- stats::loess(w ~ u, data = complete, span = 0.9)
   stopifnot(isTRUE(all.equal(smooth$y, unname(stats::predict(loessModel, data.frame(u = smooth$x))))))
   # Too few observations: statistics are withheld, not invented.
   tiny <- toolsEnv$.rs.superrstudioFitSummary(data.frame(a = c(1, 2), b = c(3, 4)), 'a', 'b', 'lm')
   stopifnot(is.null(tiny[[1L]]$r_squared), grepl('Too few', tiny[[1L]]$note))
   cat('PASS: fits (lm and closed-form estimates, R-squared, p-value, confidence band, per-group, loess, too-few)\n')

   cat('PASS: ggplot2 generated-code equivalence, unusual names/injection, preview/warnings, source preservation, appearance, colour mapping\n')
} else {
   selected <- request('inspect')
   reject(request('code', rev = selected$revision), 'ggplot2 is required')
   cat('SKIP: ggplot2 rendering (package absent); missing-package behavior PASS\n')
}
cat('PASS: dataset/column contracts, stale values, deleted data, revisions/release, limits and invalid operations\n')
