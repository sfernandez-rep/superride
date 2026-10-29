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
# the session's base64 encoder (Tools.R), used for PNG previews
for (expr in parse(file.path(root, 'src/cpp/r/R/Tools.R')))
   if (is.call(expr) && identical(expr[[1L]], as.name('.rs.addFunction')) &&
       expr[[2L]] %in% c('rBase64EncodeMain', 'rBase64EncodeRest', 'rBase64Encode'))
      eval(expr)
data <- data.frame(x = c(1, 2, NA, 4), y = c(3, 5, 7, 9), group = letters[1:4])
original <- data
request <- function(op, name = 'data', rev = '', x = 'x', y = 'y', appearance = list())
   toolsEnv$.rs.superrstudioData(op, name, as.character(rev), x, y,
      intersect(c('data', 'odd name', 'bad', 'huge', 'series', 'ref', 'boxes', 'tb', 'dt', 'myframe', 'inter', 'axdat', 'monthly', 'hourly'), ls(globalenv())), appearance)
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

# Tibbles and data.tables (real packages, isolated test library only).
if (requireNamespace('tibble', quietly = TRUE) && requireNamespace('data.table', quietly = TRUE)) {
   tb <- tibble::as_tibble(original)
   dt <- data.table::as.data.table(original)
   myframe <- structure(original, class = c('myframe', 'data.frame'))
   listed <- request('list')
   stopifnot(all(c('data', 'tb', 'dt') %in% listed$datasets), !'myframe' %in% listed$datasets,
             identical(listed$dataset_kinds[match(c('data', 'tb', 'dt'), listed$datasets)],
                       c('data.frame', 'tibble', 'data.table')))
   chosen <- request('inspect', 'tb')
   stopifnot(identical(chosen$columns, c('x', 'y')),
             identical(toolsEnv$.rs.superrstudioState$snapshot, tb),     # a reference: no serialization
             !is.raw(toolsEnv$.rs.superrstudioState$snapshot))
   tb$y[2] <- 50                                                        # copy-on-modify: a new object
   reject(request('code', 'tb', chosen$revision), 'changed')
   chosen <- request('inspect', 'dt')
   stopifnot(is.raw(toolsEnv$.rs.superrstudioState$snapshot))           # data.table: content snapshot
   data.table::set(dt, j = 'y', value = dt$y * 2)                       # modified in place, same object
   reject(request('code', 'dt', chosen$revision), 'changed')
   chosen <- request('inspect', 'dt')
   if (requireNamespace('ggplot2', quietly = TRUE))
   {
      fromDt <- request('code', 'dt', chosen$revision, 'x', 'y', list(fit = 'lm'))
      stopifnot(fromDt$fit_summary[[1L]]$n == 3L)
      suppressWarnings(ggplot2::ggplot_build(eval(parse(text = fromDt$code), envir = environment())))
      chosen <- request('inspect', 'tb')
      fromTb <- request('code', 'tb', chosen$revision, 'y', '', list(kind = 'histogram', bins = 3))
      suppressWarnings(ggplot2::ggplot_build(eval(parse(text = fromTb$code), envir = environment())))
      chosen <- request('inspect', 'dt')
   }
   rm(dt)
   reject(request('code', 'dt', chosen$revision), 'no longer exists')
   rm(tb, myframe)
   cat('PASS: tibble/data.table discovery and kinds, reference snapshot (no copy), in-place data.table change detected, deletion\n')
} else {
   cat('SKIP: tibble/data.table (packages absent)\n')
}

# Appearance validation (independent of ggplot2).
look <- toolsEnv$.rs.superrstudioScatterAppearance
defaults <- look(list())
stopifnot(identical(defaults, list(title = '', x_label = '', y_label = '', colour = '',
                                   size = 1.5, alpha = 1, theme = 'grey', line_colour = '',
                                   line_width = 0.5, line_type = 'solid', fit_colour = '',
                                   fill = '', legend_position = 'right', canvas_width = 5, canvas_height = 3.75,
                                   canvas_aspect = 'free', canvas_lock = FALSE)),
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
reject(look(list(stroke = 'red')), 'Unknown appearance setting: stroke')
reject(look(list('red')), 'named')
reject(look(list(line_type = 'wavy')), 'line type')
reject(look(list(line_width = 9)), 'Line width')
reject(look(list(fit_colour = 'nope')), 'Fit colour')
# Layer options: geometry, explicit line order, fit method and parameters.
opts <- toolsEnv$.rs.superrstudioScatterOptions
stopifnot(identical(opts(list()), list(kind = 'scatter', geometry = 'points', line_order = 'x',
                                       fit = 'none', fit_se = TRUE, fit_level = 0.95, fit_span = 0.75,
                                       bins = 30, bin_width = 0, show_outliers = TRUE,
                                       show_points = FALSE, bar_position = 'stack', adjust = 1)))
reject(opts(list(bar_position = 'pile')), 'Bar position')
reject(opts(list(adjust = 10)), 'Bandwidth')
reject(opts(list(kind = 'pie')), 'Plot type')
reject(opts(list(bins = 0)), 'bins')
reject(opts(list(bins = 2.5)), 'bins')
reject(opts(list(bins = 500)), 'bins')
reject(opts(list(bin_width = -1)), 'Bin width')
reject(opts(list(show_outliers = 'no')), 'Outlier')
reject(look(list(fill = 'nope')), 'Fill colour')
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
# invalid settings are rejected before (and regardless of) the ggplot2 check
reject(request('code', rev = selected$revision, appearance = list(theme = 'void')), 'theme')
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
             !exists('INJECTED', globalenv()), result$spec$schema_version == 6L,
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

   # Histogram: explicit bins or bin width, counts of finite values, optional
   # discrete fill column; invalid column combinations are rejected.
   chosen <- request('inspect', 'ref')
   hist5 <- request('code', 'ref', chosen$revision, 'u', '', list(kind = 'histogram', bins = 5))
   cat(hist5$code)
   stopifnot(grepl('ggplot2::geom_histogram(bins = 5)', hist5$code, fixed = TRUE),
             identical(hist5$spec$kind, I('histogram')), identical(names(hist5$spec$layers), c('kind', 'bins', 'bin_width')),
             hist5$summary[[1L]]$n == 8L, hist5$summary[[1L]]$removed == 1L, hist5$summary[[1L]]$bins == 5L)
   built <- suppressWarnings(ggplot2::ggplot_build(eval(parse(text = hist5$code), envir = globalenv())))
   stopifnot(sum(built$data[[1]]$count) == 8, nrow(built$data[[1]]) == 5L)
   histWidth <- request('code', 'ref', chosen$revision, 'u', '',
                        list(kind = 'histogram', bin_width = 2, fill = '#56B4E9', line_colour = 'black', alpha = 0.8))
   stopifnot(grepl('geom_histogram(binwidth = 2, fill = "#56B4E9", colour = "black", alpha = 0.8)', histWidth$code, fixed = TRUE),
             is.null(histWidth$summary[[1L]]$bins), histWidth$summary[[1L]]$bin_width == 2)
   histFill <- request('code', 'ref', chosen$revision, 'u', '', list(kind = 'histogram', colour_by = 'g'))
   stopifnot(grepl('fill = .data[["g"]]', histFill$code, fixed = TRUE),
             grepl('ggplot2::scale_fill_viridis_d()', histFill$code, fixed = TRUE))
   suppressWarnings(ggplot2::ggplot_build(eval(parse(text = histFill$code), envir = globalenv())))
   reject(request('code', 'ref', chosen$revision, 'u', 'w', list(kind = 'histogram')), 'no Y column')
   reject(request('code', 'ref', chosen$revision, 'g', '', list(kind = 'histogram')), 'one ordinary numeric')
   reject(request('code', 'ref', chosen$revision, 'u', '', list(kind = 'histogram', colour_by = 'w')), 'Fill by')
   reject(request('code', 'ref', chosen$revision, 'u', '', list(kind = 'histogram', colour_by = 'g', fill = 'red')), 'not both')
   cat('PASS: histogram (explicit bins/width, counts, fill column, validation)\n')

   # Boxplot: statistics equal ggplot2's stat_boxplot (quantile type 7,
   # 1.5 IQR outliers, whiskers over quartiles and non-outliers).
   boxes <<- data.frame(v = c(1, 2, 3, 4, 5, 6, 7, 30, NA), g = c('a', 'a', 'a', 'a', 'b', 'b', 'b', 'b', 'b'))
   chosen <- request('inspect', 'boxes')
   byGroup <- request('code', 'boxes', chosen$revision, 'g', 'v', list(kind = 'boxplot'))
   cat(byGroup$code)
   stopifnot(grepl('ggplot2::ggplot(boxes, ggplot2::aes(x = .data[["g"]], y = .data[["v"]])) +\n  ggplot2::geom_boxplot()',
                   byGroup$code, fixed = TRUE))
   built <- suppressWarnings(ggplot2::ggplot_build(eval(parse(text = byGroup$code), envir = globalenv())))$data[[1]]
   for (i in 1:2)
   {
      entry <- byGroup$summary[[i]]
      stopifnot(isTRUE(all.equal(c(entry$lower_whisker, entry$q1, entry$median, entry$q3, entry$upper_whisker),
                                 unlist(built[i, c('ymin', 'lower', 'middle', 'upper', 'ymax')]), check.attributes = FALSE)),
                entry$outliers == length(built$outliers[[i]]))
   }
   stopifnot(byGroup$summary[[2L]]$outliers == 1L, byGroup$summary[[2L]]$n == 4L)
   styled <- request('code', 'boxes', chosen$revision, 'g', 'v',
                     list(kind = 'boxplot', show_outliers = FALSE, show_points = TRUE, colour_by = 'g'))
   stopifnot(grepl('geom_boxplot(outlier.shape = NA)', styled$code, fixed = TRUE),
             grepl('position = ggplot2::position_jitter(width = 0.15, height = 0, seed = 1)', styled$code, fixed = TRUE),
             grepl('ggplot2::scale_fill_viridis_d()', styled$code, fixed = TRUE))
   one <- suppressWarnings(ggplot2::ggplot_build(eval(parse(text = styled$code), envir = globalenv())))$data[[2]]
   two <- suppressWarnings(ggplot2::ggplot_build(eval(parse(text = styled$code), envir = globalenv())))$data[[2]]
   stopifnot(identical(one$x, two$x))
   single <- request('code', 'boxes', chosen$revision, '', 'v', list(kind = 'boxplot'))
   stopifnot(grepl('axis.text.x = ggplot2::element_blank()', single$code, fixed = TRUE),
             identical(single$summary[[1L]]$group, I('all')), single$summary[[1L]]$n == 8L)
   suppressWarnings(ggplot2::ggplot_build(eval(parse(text = single$code), envir = globalenv())))
   reject(request('code', 'boxes', chosen$revision, 'v', 'v', list(kind = 'boxplot')), 'numeric response')
   reject(request('code', 'boxes', chosen$revision, 'g', 'g', list(kind = 'boxplot')), 'numeric response')
   reject(request('code', 'boxes', chosen$revision, 'g', 'v', list(kind = 'boxplot', group_by = 'g')), 'scatter plots only')
   cat('PASS: boxplot (stat_boxplot-equal statistics, outliers, seeded jitter, single box, validation)\n')

   # Bar chart: counts of a category (NA as its own bar), positions, and the
   # proportion axis label for position = "fill".
   chosen <- request('inspect', 'boxes')
   bars <- request('code', 'boxes', chosen$revision, 'g', '', list(kind = 'bar'))
   cat(bars$code)
   stopifnot(grepl('ggplot2::geom_bar()', bars$code, fixed = TRUE),
             identical(vapply(bars$summary, function(e) as.integer(e$n), 1L), as.vector(table(boxes$g))))
   built <- ggplot2::ggplot_build(eval(parse(text = bars$code), envir = globalenv()))$data[[1]]
   stopifnot(identical(as.integer(built$count), as.vector(table(boxes$g))))
   proportions <- request('code', 'boxes', chosen$revision, 'g', '',
                          list(kind = 'bar', bar_position = 'fill', colour_by = 'g'))
   stopifnot(grepl('geom_bar(position = "fill")', proportions$code, fixed = TRUE),
             grepl('ggplot2::labs(y = "proportion")', proportions$code, fixed = TRUE))
   ggplot2::ggplot_build(eval(parse(text = proportions$code), envir = globalenv()))
   reject(request('code', 'boxes', chosen$revision, 'v', '', list(kind = 'bar')), 'bar chart counts')
   reject(request('code', 'boxes', chosen$revision, 'g', 'v', list(kind = 'bar')), 'bar chart counts')
   cat('PASS: bar chart (counts vs table(), positions, proportion label, validation)\n')

   # Density: bandwidth equals stats::bw.nrd0() * adjust and the curve equals
   # stats::density() on the same grid; per-group curves with a fill column.
   chosen <- request('inspect', 'ref')
   dens <- request('code', 'ref', chosen$revision, 'w', '', list(kind = 'density', adjust = 1.5, alpha = 0.6))
   cat(dens$code)
   complete <- ref$w[is.finite(ref$w)]
   stopifnot(grepl('ggplot2::geom_density(adjust = 1.5, alpha = 0.6)', dens$code, fixed = TRUE),
             isTRUE(all.equal(as.numeric(dens$summary[[1L]]$bandwidth), stats::bw.nrd0(complete) * 1.5)))
   built <- ggplot2::ggplot_build(eval(parse(text = dens$code), envir = globalenv()))$data[[1]]
   reference <- stats::density(complete, bw = 'nrd0', adjust = 1.5, n = nrow(built),
                               from = min(complete), to = max(complete))
   stopifnot(isTRUE(all.equal(built$x, reference$x)), isTRUE(all.equal(built$density, reference$y)))
   perGroup <- request('code', 'ref', chosen$revision, 'w', '', list(kind = 'density', colour_by = 'g'))
   stopifnot(length(perGroup$summary) == 2L, grepl('fill = .data[["g"]]', perGroup$code, fixed = TRUE))
   reject(request('code', 'ref', chosen$revision, 'g', '', list(kind = 'density')), 'density plot')
   cat('PASS: density (bandwidth vs bw.nrd0, curve vs stats::density, groups, validation)\n')

   # Axes, scales and facets. Statistics must describe exactly what ggplot2
   # computes: on the log10 scale, after filtering limits, per facet panel.
   axdat <- data.frame(u = c(-1, 0.5, 1, 2, 4, 8, 16, 32, 64, 128),
                       w = c(1, 2, 3, 5, 7, 11, 13, 17, 19, 23), k = rep(c('p', 'q'), 5))
   chosen <- request('inspect', 'axdat')
   built <- function(result) ggplot2::ggplot_build(eval(parse(text = result$code), envir = globalenv()))
   quiet <- function(expr) suppressWarnings(expr)
   # log10 X and Y with a linear fit: lm(log10(w) ~ log10(u)) on positive values
   logged <- request('code', 'axdat', chosen$revision, 'u', 'w',
                     list(fit = 'lm', x_scale = 'log10', y_scale = 'log10'))
   positive <- axdat[axdat$u > 0, ]
   reference <- stats::lm(log10(w) ~ log10(u), data = positive)
   entry <- logged$fit_summary[[1L]]
   stopifnot(grepl('ggplot2::scale_x_log10()', logged$code, fixed = TRUE),
             grepl('ggplot2::scale_y_log10()', logged$code, fixed = TRUE),
             entry$n == 9L, isTRUE(all.equal(as.numeric(entry$slope), unname(stats::coef(reference)[2L]))),
             grepl('^log10\\(w\\) = .+ \\* log10\\(u\\)$', entry$equation),
             any(grepl('1 X value', logged$notes)))
   smooth <- quiet(built(logged))$data[[2L]]
   stopifnot(isTRUE(all.equal(smooth$y, unname(stats::predict(reference, data.frame(u = 10^smooth$x))))))
   modelText <- sub('^.*inference\\.\n# Fitted[^\n]*\n', '', logged$model_code)
   model <- eval(parse(text = modelText), envir = globalenv())
   stopifnot(isTRUE(all.equal(stats::coef(model)[, 1L], stats::coef(summary(reference))[, 1L],
                              check.attributes = FALSE)))
   # filtering limits remove observations before the fit; zooming does not
   filtered <- request('code', 'axdat', chosen$revision, 'u', 'w',
                       list(fit = 'lm', x_min = 1, x_max = 64, limits_mode = 'filter'))
   inside <- axdat[axdat$u >= 1 & axdat$u <= 64, ]
   stopifnot(grepl('ggplot2::scale_x_continuous(limits = c(1, 64))', filtered$code, fixed = TRUE),
             filtered$fit_summary[[1L]]$n == nrow(inside),
             isTRUE(all.equal(as.numeric(filtered$fit_summary[[1L]]$slope),
                              unname(stats::coef(stats::lm(w ~ u, data = inside))[2L]))),
             any(grepl('remove 3 observation', filtered$notes)))
   smooth <- quiet(built(filtered))$data[[2L]]
   stopifnot(isTRUE(all.equal(smooth$y, unname(stats::predict(stats::lm(w ~ u, data = inside),
                                                                data.frame(u = smooth$x))))))
   model <- eval(parse(text = sub('^.*observations, as ggplot2 does\\.\n', '', filtered$model_code)), envir = globalenv())
   stopifnot(isTRUE(all.equal(stats::coef(model)[2L, 1L], unname(stats::coef(stats::lm(w ~ u, data = inside))[2L]))))
   zoomed <- request('code', 'axdat', chosen$revision, 'u', 'w', list(fit = 'lm', x_min = 1, x_max = 64))
   zoomBuild <- quiet(built(zoomed))
   stopifnot(grepl('ggplot2::coord_cartesian(xlim = c(1, 64))', zoomed$code, fixed = TRUE),
             zoomed$fit_summary[[1L]]$n == 10L, !length(zoomed$notes),
             isTRUE(all.equal(zoomBuild$layout$panel_params[[1L]]$x.range, c(1, 64) + c(-1, 1) * 0.05 * 63)))
   # zoom limits on a log scale are data values (the panel spans log10 of them)
   logZoom <- quiet(built(request('code', 'axdat', chosen$revision, 'u', 'w',
                                  list(x_scale = 'log10', x_min = 1, x_max = 100))))
   stopifnot(isTRUE(all.equal(logZoom$layout$panel_params[[1L]]$x.range, c(0, 2) + c(-1, 1) * 0.05 * 2)))
   # facets: one fit per panel, equal to lm() on each subset
   faceted <- request('code', 'axdat', chosen$revision, 'u', 'w',
                      list(fit = 'lm', facet_by = 'k', facet_ncol = 2, facet_scales = 'free_y'))
   stopifnot(grepl('ggplot2::facet_wrap(ggplot2::vars(.data[["k"]]), ncol = 2, scales = "free_y")',
                   faceted$code, fixed = TRUE),
             length(faceted$fit_summary) == 2L,
             identical(vapply(faceted$fit_summary, function(e) as.character(e$group), ''), c('p', 'q')))
   for (entry in faceted$fit_summary) {
      part <- axdat[axdat$k == entry$group, ]
      stopifnot(isTRUE(all.equal(as.numeric(entry$slope), unname(stats::coef(stats::lm(w ~ u, data = part))[2L]))))
   }
   facetBuild <- built(faceted)
   stopifnot(nrow(facetBuild$layout$layout) == 2L)
   gridded <- request('code', 'axdat', chosen$revision, 'u', 'w', list(facet_rows = 'k'))
   stopifnot(grepl('ggplot2::facet_grid(rows = ggplot2::vars(.data[["k"]]))', gridded$code, fixed = TRUE),
             nrow(built(gridded)$layout$layout) == 2L)
   map <- request('render', 'axdat', chosen$revision, 'u', 'w', list(facet_by = 'k'))$interactive
   roles <- vapply(map$regions, function(r) as.character(r$role), '')
   stopifnot(sum(roles == 'panel') == 2L, 'strip' %in% roles,
             sum(vapply(map$elements, function(e) e$role == 'points', NA)) == 2L)
   # tick labels and gridlines
   styled <- request('code', 'axdat', chosen$revision, 'u', 'w',
                     list(x_format = 'comma', y_format = 'scientific', grid_minor = FALSE, theme = 'bw'))
   plot <- eval(parse(text = styled$code), envir = globalenv())
   stopifnot(grepl('ggplot2::scale_x_continuous(labels = scales::label_comma())', styled$code, fixed = TRUE),
             grepl('ggplot2::scale_y_continuous(labels = scales::label_scientific())', styled$code, fixed = TRUE),
             inherits(plot$theme$panel.grid.minor, 'element_blank'),
             !inherits(plot$theme$panel.grid.major, 'element_blank'))
   # boxplot on a log10 Y: statistics on the transformed values, as drawn
   box <- request('code', 'axdat', chosen$revision, 'k', 'w', list(kind = 'boxplot', y_scale = 'log10'))
   middle <- quiet(built(box))$data[[1L]]$middle
   stopifnot(isTRUE(all.equal(vapply(box$summary, function(e) as.numeric(e$median), 0), middle)),
             isTRUE(all.equal(middle, as.vector(tapply(log10(axdat$w), axdat$k, stats::median)))))
   # density on a log10 X: bandwidth of the log values
   dens <- request('code', 'axdat', chosen$revision, 'u', '', list(kind = 'density', x_scale = 'log10'))
   stopifnot(isTRUE(all.equal(as.numeric(dens$summary[[1L]]$bandwidth), stats::bw.nrd0(log10(positive$u)))))
   # histogram counts only what the filter keeps
   hist <- request('code', 'axdat', chosen$revision, 'u', '',
                   list(kind = 'histogram', x_min = 0, x_max = 20, limits_mode = 'filter'))
   stopifnot(hist$summary[[1L]]$n == sum(axdat$u >= 0 & axdat$u <= 20))
   # combinations that would be meaningless are refused
   reject(request('code', 'axdat', chosen$revision, 'k', 'w', list(kind = 'boxplot', x_scale = 'log10')), 'continuous X')
   reject(request('code', 'axdat', chosen$revision, 'u', '', list(kind = 'histogram', y_scale = 'log10')), 'log Y')
   reject(request('code', 'axdat', chosen$revision, 'u', '',
                  list(kind = 'histogram', y_max = 3, limits_mode = 'filter')), 'only zoom')
   reject(request('code', 'axdat', chosen$revision, 'u', 'w', list(x_min = 5, x_max = 5)), 'below its maximum')
   reject(request('code', 'axdat', chosen$revision, 'u', 'w', list(x_scale = 'log10', x_min = 0)), 'positive')
   reject(request('code', 'axdat', chosen$revision, 'u', 'w', list(facet_by = 'k', facet_rows = 'k')), 'different')
   reject(request('code', 'axdat', chosen$revision, 'u', 'w', list(facet_by = 'u')), 'Facet by')
   reject(request('code', 'axdat', chosen$revision, 'u', 'w', list(x_min = 'a')), 'numbers')
   reject(request('code', 'axdat', chosen$revision, 'u', 'w', list(facet_ncol = 1.5)), 'whole number')
   cat('PASS: axes and facets (log10 fits vs lm on log values, filter vs zoom, panel ranges, per-panel fits, formats, gridlines, log boxplot/density, validation)\n')

   # Date and date-time X (time series): ggplot2's date scales, ISO text
   # limits, chronological lines, fits on days / seconds since 1970-01-01.
   monthly <- data.frame(day = as.Date('2020-01-15') + c(0, 31, 60, 91, 121, 152, 182, 213, NA),
                         count = c(3, 5, 4, 8, 9, 12, 11, 15, 7), site = rep(c('a', 'b', 'c'), 3))
   monthly <- monthly[c(3, 1, 2, 5, 4, 6, 8, 7, 9), ]   # rows out of date order
   monthly_original <- monthly
   chosen <- request('inspect', 'monthly')
   stopifnot(identical(chosen$time_columns, 'day'), length(chosen$datetime_columns) == 0L,
             !'day' %in% chosen$columns)
   series <- request('code', 'monthly', chosen$revision, 'day', 'count',
                     list(geometry = 'lines_points', fit = 'lm', x_date_breaks = '2 months', x_date_labels = '%b %Y'))
   stopifnot(grepl('ggplot2::scale_x_date(date_breaks = "2 months", date_labels = "%b %Y")', series$code, fixed = TRUE),
             grepl('ggplot2::geom_line()', series$code, fixed = TRUE), series$spec$schema_version == 6L)
   b <- quiet(built(series))
   lineX <- b$data[[1L]]$x
   stopifnot(!is.unsorted(lineX[!is.na(lineX)]))   # lines join observations in date order
   dated <- monthly[!is.na(monthly$day), ]
   reference <- stats::lm(count ~ as.numeric(day), data = dated)
   entry <- series$fit_summary[[1L]]
   stopifnot(entry$n == 8L, isTRUE(all.equal(as.numeric(entry$slope), unname(stats::coef(reference)[2L]))),
             grepl('day [days since 1970-01-01]', entry$equation, fixed = TRUE),
             any(grepl('1 observation(s) have no date', series$notes, fixed = TRUE)))
   smooth <- b$data[[3L]]
   stopifnot(isTRUE(all.equal(smooth$y, unname(stats::predict(reference, data.frame(day = smooth$x))))))
   model <- eval(parse(text = series$model_code), envir = globalenv())
   stopifnot(isTRUE(all.equal(stats::coef(model)[2L, 1L], unname(stats::coef(reference)[2L]))),
             grepl('days since 1970-01-01', series$model_code, fixed = TRUE))
   # labels are ggplot2's own: the date format applied to the breaks (in R's locale)
   xs <- b$layout$panel_params[[1L]]$x
   breaks <- xs$breaks[!is.na(xs$breaks)]
   stopifnot(length(breaks) > 1L, all(diff(breaks) >= 59),
             identical(as.character(xs$get_labels()[!is.na(xs$breaks)]), format(as.Date(breaks), '%b %Y')))
   # zoom keeps every observation; filter removes them before the fit
   zoomed <- request('code', 'monthly', chosen$revision, 'day', 'count',
                     list(fit = 'lm', x_min = '2020-03-01', x_max = '2020-07-01'))
   limits <- as.numeric(as.Date(c('2020-03-01', '2020-07-01')))
   stopifnot(grepl('ggplot2::coord_cartesian(xlim = as.Date(c("2020-03-01", "2020-07-01")))', zoomed$code, fixed = TRUE),
             zoomed$fit_summary[[1L]]$n == 8L,
             isTRUE(all.equal(quiet(built(zoomed))$layout$panel_params[[1L]]$x.range,
                              limits + c(-1, 1) * 0.05 * diff(limits))))
   filtered <- request('code', 'monthly', chosen$revision, 'day', 'count',
                       list(fit = 'lm', x_min = '2020-03-01', limits_mode = 'filter'))
   inside <- dated[dated$day >= as.Date('2020-03-01'), ]
   insideFit <- stats::lm(count ~ as.numeric(day), data = inside)
   stopifnot(grepl('ggplot2::scale_x_date(limits = as.Date(c("2020-03-01", NA)))', filtered$code, fixed = TRUE),
             filtered$fit_summary[[1L]]$n == nrow(inside),
             isTRUE(all.equal(as.numeric(filtered$fit_summary[[1L]]$slope), unname(stats::coef(insideFit)[2L]))),
             any(grepl('remove 2 observation', filtered$notes)))
   model <- eval(parse(text = filtered$model_code), envir = globalenv())
   stopifnot(isTRUE(all.equal(stats::coef(model)[2L, 1L], unname(stats::coef(insideFit)[2L]))))
   map <- request('render', 'monthly', chosen$revision, 'day', 'count', list(geometry = 'lines_points'))$interactive
   stopifnot(all(c('points', 'lines') %in% vapply(map$elements, function(e) as.character(e$role), '')))
   # date-times: display time zone, breaks and labels; limits read in that zone
   hourly <- data.frame(time = as.POSIXct('2021-06-01 06:00', tz = 'UTC') + 3600 * c(0, 1, 2, 3, 4, 5),
                        level = c(1, 2, 2, 3, 5, 4))
   chosen <- request('inspect', 'hourly')
   stopifnot(identical(chosen$datetime_columns, 'time'), identical(chosen$time_columns, 'time'))
   timed <- request('code', 'hourly', chosen$revision, 'time', 'level',
                    list(fit = 'lm', x_date_breaks = '2 hours', x_date_labels = '%H:%M',
                         x_timezone = 'America/Montevideo', x_min = '2021-06-01 04:00'))
   stopifnot(grepl('ggplot2::scale_x_datetime(date_breaks = "2 hours", date_labels = "%H:%M", timezone = "America/Montevideo")',
                   timed$code, fixed = TRUE),
             grepl('ggplot2::coord_cartesian(xlim = as.POSIXct(c("2021-06-01 04:00", NA), tz = "America/Montevideo"))',
                   timed$code, fixed = TRUE))
   tb <- quiet(built(timed))
   xs <- tb$layout$panel_params[[1L]]$x
   shown <- !is.na(xs$breaks)
   low <- as.numeric(as.POSIXct('2021-06-01 07:00', tz = 'UTC'))   # 04:00 in Montevideo (UTC-3)
   high <- max(as.numeric(hourly$time))
   stopifnot(identical(as.character(xs$get_labels()[shown]),
                       format(as.POSIXct(xs$breaks[shown], origin = '1970-01-01', tz = 'UTC'), '%H:%M',
                              tz = 'America/Montevideo')),
             isTRUE(all.equal(tb$layout$panel_params[[1L]]$x.range, c(low, high) + c(-1, 1) * 0.05 * (high - low))),
             isTRUE(all.equal(as.numeric(timed$fit_summary[[1L]]$slope),
                              unname(stats::coef(stats::lm(level ~ as.numeric(time), data = hourly))[2L]))),
             grepl('[seconds since 1970-01-01 UTC]', timed$fit_summary[[1L]]$equation, fixed = TRUE))
   # combinations that do not apply to dates are refused
   axisReject <- function(settings, pattern, name = 'monthly', x = 'day', y = 'count')
      reject(request('code', name, request('inspect', name)$revision, x, y, settings), pattern)
   axisReject(list(x_scale = 'log10'), 'log scale does not apply')
   axisReject(list(x_format = 'comma'), 'Number formats')
   axisReject(list(x_min = '01/03/2020'), 'YYYY-MM-DD')
   axisReject(list(x_min = '2020-02-30'), 'YYYY-MM-DD')
   axisReject(list(x_min = '2020-06-01', x_max = '2020-03-01'), 'before its maximum')
   axisReject(list(x_date_breaks = '2 fortnights'), 'Date breaks')
   axisReject(list(x_date_breaks = '6 hours'), 'Date breaks')
   axisReject(list(x_date_labels = '%H:%M'), 'Unsupported date label')
   axisReject(list(x_timezone = 'UTC'), 'date-time columns only')
   axisReject(list(kind = 'histogram'), 'apply to scatter and line plots', y = '')
   axisReject(list(), 'ordinary numeric', x = 'count', y = 'day')
   axisReject(list(x_timezone = 'Mars/Base'), 'Unknown time zone', 'hourly', 'time', 'level')
   axisReject(list(x_min = '2021-06-01 25:00'), 'YYYY-MM-DD HH:MM', 'hourly', 'time', 'level')
   axisReject(list(x_date_breaks = '1 month'), 'apply to a date', 'axdat', 'u', 'w')
   stopifnot(identical(monthly, monthly_original))
   chosen <- request('inspect', 'axdat')   # the selection the next sections use
   cat('PASS: date and date-time X (scale_x_date/datetime, breaks, labels, time zone, zoom vs filter, chronological lines, fits per day/second, model code, validation)\n')

   # Export: the files themselves are checked (signatures, pixel/page sizes),
   # and the returned export script reproduces them.
   folder <- gsub('\\', '/', tempfile('srs-export-'), fixed = TRUE)   # as the export path is normalized
   dir.create(folder)
   exportSettings <- function(format, path, extra = list())
      c(list(title = 'Exported', export_path = path, export_format = format), extra)
   pngPath <- file.path(folder, 'plot.png')
   exported <- request('export', 'axdat', chosen$revision, 'u', 'w',
                       exportSettings('png', pngPath, list(export_width = 10, export_height = 5,
                                                           export_units = 'cm', export_dpi = 150)))
   bytes <- readBin(pngPath, 'raw', file.size(pngPath))
   dimension <- function(at) sum(as.integer(bytes[at:(at + 3L)]) * 256^(3:0))
   stopifnot(identical(bytes[1:8], as.raw(c(0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A))),
             abs(dimension(17L) - 10 / 2.54 * 150) < 1, abs(dimension(21L) - 5 / 2.54 * 150) < 1,
             exported$saved$bytes == file.size(pngPath),
             grepl('ggplot2::ggsave(filename = ', exported$export_code, fixed = TRUE),
             grepl('units = "cm", dpi = 150)', exported$export_code, fixed = TRUE))
   # the export script reproduces the same file
   again <- sub(pngPath, file.path(folder, 'again.png'), exported$export_code, fixed = TRUE)
   local(eval(parse(text = again)), envir = new.env(parent = globalenv()))
   stopifnot(identical(unname(tools::md5sum(pngPath)), unname(tools::md5sum(file.path(folder, 'again.png')))))
   svgPath <- file.path(folder, 'plot.svg')
   exported <- request('export', 'axdat', chosen$revision, 'u', 'w',
                       exportSettings('svg', svgPath, list(export_width = 4, export_height = 3, export_units = 'in')))
   svgText <- paste(readLines(svgPath, warn = FALSE), collapse = '\n')
   stopifnot(grepl('width="288pt" height="216pt"', svgText, fixed = TRUE),
             grepl('device = grDevices::svg', exported$export_code, fixed = TRUE))
   again <- sub(svgPath, file.path(folder, 'again.svg'), exported$export_code, fixed = TRUE)
   local(eval(parse(text = again)), envir = new.env(parent = globalenv()))
   stopifnot(identical(unname(tools::md5sum(svgPath)), unname(tools::md5sum(file.path(folder, 'again.svg')))))
   pdfPath <- file.path(folder, 'plot.pdf')
   exported <- request('export', 'axdat', chosen$revision, 'u', 'w',
                       exportSettings('pdf', pdfPath, list(export_width = 180, export_height = 120, export_units = 'mm')))
   # cairo writes PDF 1.7 object streams: inflate each stream to find the page box
   pdfBytes <- readBin(pdfPath, 'raw', file.size(pdfPath))
   starts <- grepRaw('stream\n', pdfBytes, fixed = TRUE, all = TRUE) + 7L
   ends <- grepRaw('endstream', pdfBytes, fixed = TRUE, all = TRUE)
   inflated <- unlist(lapply(seq_along(starts), function(i) {
      part <- tryCatch(memDecompress(pdfBytes[starts[i]:(ends[ends > starts[i]][1L] - 1L)], 'gzip'),
                       error = function(e) raw())
      part[part >= as.raw(32) & part < as.raw(127)]
   }))
   at <- grepRaw('/MediaBox', c(pdfBytes, inflated), fixed = TRUE)[1L]
   mediaBox <- rawToChar(c(pdfBytes, inflated)[at:(at + 60L)])
   box <- as.numeric(regmatches(mediaBox, gregexpr('[0-9.]+', mediaBox))[[1L]])
   stopifnot(identical(rawToChar(pdfBytes[1:5]), '%PDF-'),
             isTRUE(all.equal(box[3:4], c(180, 120) / 25.4 * 72, tolerance = 1e-3)),
             grepl('device = grDevices::cairo_pdf', exported$export_code, fixed = TRUE))
   # nothing is written for invalid requests
   reject(request('export', 'axdat', chosen$revision, 'u', 'w', exportSettings('png', file.path(folder, 'plot.pdf'))), 'end in .png')
   reject(request('export', 'axdat', chosen$revision, 'u', 'w', exportSettings('png', file.path(folder, 'missing', 'p.png'))), 'folder')
   reject(request('export', 'axdat', chosen$revision, 'u', 'w', exportSettings('png', file.path(folder, 'p.png'),
                                                                                 list(export_width = 500))), 'between')
   reject(request('export', 'axdat', chosen$revision, 'u', 'w', exportSettings('tiff', file.path(folder, 'p.tiff'))), 'PNG, SVG or PDF')
   reject(request('export', 'axdat', chosen$revision, 'u', 'w', exportSettings('png', '')), 'Choose a file')
   stopifnot(!file.exists(file.path(folder, 'p.png')), identical(axdat, get('axdat')))
   # The preview canvas: the preview is drawn at the canvas's physical size;
   # "preview proportions" exports keep its aspect ratio at a given width,
   # "exact" exports use the entered width and height.
   wide <- request('render', 'axdat', chosen$revision, 'u', 'w', list(canvas_width = 6, canvas_height = 3))$interactive
   stopifnot(wide$width == 576L, wide$height == 288L)
   square <- request('render', 'axdat', chosen$revision, 'u', 'w',
                     list(canvas_width = 4, canvas_height = 4, canvas_aspect = '1:1', canvas_lock = TRUE))
   stopifnot(square$interactive$width == 384L, square$interactive$height == 384L,
             square$spec$appearance$canvas_aspect == '1:1', isTRUE(unclass(square$spec$appearance$canvas_lock)),
             square$spec$appearance$canvas_width == 4, square$spec$schema_version == 6L)
   # large canvases: the bitmap preview stays within 2400 pixels a side
   big <- toolsEnv$.rs.superrstudioInteractive(ggplot2::ggplot(data.frame(a = 1:6000, b = 1:6000), ggplot2::aes(a, b)) +
                                               ggplot2::geom_point(), width = 16, height = 8)
   # the PNG header (first 24 bytes) from the base64 image
   header <- function(text) {
      digits <- match(strsplit(substr(text, 1L, 32L), '')[[1L]], c(LETTERS, letters, 0:9, '+', '/')) - 1L
      bits <- unlist(lapply(digits, function(d) as.integer(intToBits(d))[6:1]))
      as.raw(vapply(seq(1L, length(bits), 8L), function(i) sum(bits[i:(i + 7L)] * 2^(7:0)), 0))
   }
   bigBytes <- header(big$image)
   stopifnot(big$format == 'png', big$width == 1536L,
             sum(as.integer(bigBytes[17:20]) * 256^(3:0)) == 2400, sum(as.integer(bigBytes[21:24]) * 256^(3:0)) == 1200)
   # preview proportions: 16 cm wide at a 6 x 3 inch canvas gives 16 x 8 cm
   proportional <- file.path(folder, 'proportional.png')
   exported <- request('export', 'axdat', chosen$revision, 'u', 'w',
                       exportSettings('png', proportional, list(canvas_width = 6, canvas_height = 3, export_mode = 'preview',
                                                                export_width = 16, export_height = 99, export_units = 'cm',
                                                                export_dpi = 150)))
   bytes <- readBin(proportional, 'raw', file.size(proportional))
   stopifnot(abs(dimension(17L) - 16 / 2.54 * 150) < 1, abs(dimension(21L) - 8 / 2.54 * 150) < 1,
             grepl('width = 16, height = 8, units = "cm"', exported$export_code, fixed = TRUE))
   # the same proportions as SVG (vector page size) and PDF
   proportionalSvg <- file.path(folder, 'proportional.svg')
   invisible(request('export', 'axdat', chosen$revision, 'u', 'w',
                     exportSettings('svg', proportionalSvg, list(canvas_width = 4, canvas_height = 4, canvas_aspect = '1:1',
                                                                 export_mode = 'preview', export_width = 3,
                                                                 export_units = 'in'))))
   stopifnot(grepl('width="216pt" height="216pt"', paste(readLines(proportionalSvg, warn = FALSE), collapse = '\n'),
                   fixed = TRUE))
   # exact dimensions ignore the canvas
   exact <- file.path(folder, 'exact.png')
   invisible(request('export', 'axdat', chosen$revision, 'u', 'w',
                     exportSettings('png', exact, list(canvas_width = 6, canvas_height = 3, export_mode = 'exact',
                                                       export_width = 10, export_height = 10, export_units = 'cm',
                                                       export_dpi = 150))))
   bytes <- readBin(exact, 'raw', file.size(exact))
   stopifnot(abs(dimension(17L) - dimension(21L)) < 1)
   reject(request('render', 'axdat', chosen$revision, 'u', 'w', list(canvas_width = 0.5)), 'between 1 and 20')
   reject(request('render', 'axdat', chosen$revision, 'u', 'w', list(canvas_height = 25)), 'between 1 and 20')
   reject(request('render', 'axdat', chosen$revision, 'u', 'w',
                  list(canvas_width = 6, canvas_height = 3, canvas_aspect = '4:3')), 'not 4:3')
   reject(request('render', 'axdat', chosen$revision, 'u', 'w', list(canvas_aspect = '2:1')), 'free, 1:1')
   reject(request('export', 'axdat', chosen$revision, 'u', 'w',
                  exportSettings('png', file.path(folder, 'm.png'), list(export_mode = 'fit'))), 'exact dimensions')
   cat('PASS: preview canvas (drawn at its physical size, presets validated, bitmap cap) and export by preview proportions or exact dimensions\n')
   unlink(folder, recursive = TRUE)
   cat('PASS: export (PNG pixel size at dpi, SVG and PDF page sizes, scripts reproduce identical PNG/SVG, validation)\n')

   # Interactive preview: an SVG plus an element map located through the
   # gtable layout and ggplot_build() data. Checked against ggplot2's
   # documented 5% continuous expansion, independently of the mapping code.
   inter <- data.frame(a = c(0, 10, 4), b = c(0, 20, 5), k = c('p', 'q', 'p'))
   chosen <- request('inspect', 'inter')
   grDevices::pdf(NULL)
   device <- grDevices::dev.cur()
   rendered <- request('render', 'inter', chosen$revision, 'a', 'b',
                       list(fit = 'lm', title = 'Map', colour_by = 'k', legend_position = 'bottom'))
   stopifnot(grDevices::dev.cur() == device)
   grDevices::dev.off()
   map <- rendered$interactive
   stopifnot(map$format == 'svg', grepl('<svg', map$image, fixed = TRUE), map$width == 480, map$height == 360)
   roles <- vapply(map$regions, function(r) as.character(r$role), '')
   stopifnot(all(c('title', 'panel', 'x_axis', 'y_axis', 'x_label', 'y_label', 'legend') %in% roles))
   region <- function(role) map$regions[[match(role, roles)]]$box
   panel <- region('panel')
   # the legend was moved below the panel; the title sits above it
   stopifnot(region('legend')[2L] > panel[4L], region('title')[4L] <= panel[2L] + 1e-3)
   points <- Filter(function(e) e$role == 'points', map$elements)
   stopifnot(length(points) == 1L, length(points[[1L]]$coords) == 6L)
   xy <- matrix(points[[1L]]$coords, ncol = 2L, byrow = TRUE)
   expected <- function(value, low, high, box)
      box[1L] + (value - low + 0.05 * (high - low)) / (1.1 * (high - low)) * (box[2L] - box[1L])
   stopifnot(isTRUE(all.equal(xy[, 1L], expected(inter$a, 0, 10, panel[c(1L, 3L)]), tolerance = 1e-3)),
             isTRUE(all.equal(xy[, 2L], expected(inter$b, 0, 20, panel[c(4L, 2L)]), tolerance = 1e-3)))
   stopifnot(any(vapply(map$elements, function(e) e$role == 'fit' && e$shape == 'path', NA)))
   reject(request('render', 'inter', chosen$revision, 'a', 'b', list(legend_position = 'middle')), 'Legend position')
   legendCode <- request('code', 'inter', chosen$revision, 'a', 'b', list(colour_by = 'k', legend_position = 'top'))$code
   stopifnot(grepl('ggplot2::theme(legend.position = "top")', legendCode, fixed = TRUE),
             identical(eval(parse(text = legendCode), envir = globalenv())$theme$legend.position, 'top'))
   stopifnot(is.null(request('code', 'inter', chosen$revision, 'a', 'b')$interactive))
   for (kind in list(list(kind = 'histogram', x = 'a', role = 'bars'), list(kind = 'boxplot', x = 'k', role = 'boxes'),
                     list(kind = 'bar', x = 'k', role = 'bars'), list(kind = 'density', x = 'a', role = 'density'))) {
      y <- if (kind$kind == 'boxplot') 'b' else ''
      shown <- request('render', 'inter', chosen$revision, kind$x, y, list(kind = kind$kind))$interactive
      stopifnot(any(vapply(shown$elements, function(e) e$role == kind$role, NA)))
   }
   # many rows: a double-resolution PNG (valid signature) with the same element map
   bitmap <- suppressWarnings(toolsEnv$.rs.superrstudioInteractive(eval(parse(text = rendered$code), envir = globalenv()),
                                                 svg_rows = 2L))
   png <- toolsEnv$.rs.rBase64Encode(as.raw(c(0x89, 0x50, 0x4E, 0x47)))
   stopifnot(bitmap$format == 'png', startsWith(bitmap$image, substr(png, 1L, 5L)),
             isTRUE(all.equal(bitmap$regions, map$regions, tolerance = 0.02)),
             isTRUE(all.equal(bitmap$elements, map$elements, tolerance = 0.02)))
   # paths are counted by vertices, points by rows: a long line stays SVG
   long <- data.frame(t = seq_len(20000L), v = sin(seq_len(20000L) / 500))
   lineMap <- toolsEnv$.rs.superrstudioInteractive(ggplot2::ggplot(long, ggplot2::aes(t, v)) + ggplot2::geom_line())
   pointMap <- toolsEnv$.rs.superrstudioInteractive(ggplot2::ggplot(long, ggplot2::aes(t, v)) + ggplot2::geom_point())
   bothMap <- toolsEnv$.rs.superrstudioInteractive(ggplot2::ggplot(long, ggplot2::aes(t, v)) + ggplot2::geom_line() +
                                                   ggplot2::geom_point())
   stopifnot(lineMap$format == 'svg', pointMap$format == 'png', bothMap$format == 'png',
             any(vapply(lineMap$elements, function(e) e$role == 'lines', NA)))
   cat('PASS: interactive preview (SVG and PNG, element map vs expansion arithmetic, legend position, device restored, all kinds)\n')

   cat('PASS: ggplot2 generated-code equivalence, unusual names/injection, preview/warnings, source preservation, appearance, colour mapping\n')
} else {
   selected <- request('inspect')
   reject(request('code', rev = selected$revision), 'ggplot2 is required')
   cat('SKIP: ggplot2 rendering (package absent); missing-package behavior PASS\n')
}
cat('PASS: dataset/column contracts, stale values, deleted data, revisions/release, limits and invalid operations\n')
