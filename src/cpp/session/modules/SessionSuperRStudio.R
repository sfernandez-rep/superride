# SuperRStudio experimental visual workflow. SPDX-License-Identifier: AGPL-3.0-only
# One bounded validation snapshot per session; never used as the plot's data.
# For data frames and tibbles the snapshot is the object itself (no copy:
# copy-on-modify gives any change a new object, compared with identical());
# data.table objects can be modified in place with `:=`, so for them the
# snapshot is their serialized content.
assign('.rs.superrstudioState', new.env(parent = emptyenv()), envir = .rs.toolsEnv())
.rs.superrstudioState$counter <- 0L

# RPC entry point. Validation failures are returned as data rather than raised,
# so the dialog reports them without R also printing them in the console.
#' The product name in generated comments and notes
#'
#' The single place to change for a future name (see docs/superrstudio/
#' BRANDING.md). File-format identifiers such as "# SuperRStudio scatter v5"
#' and "superrstudio-lfq-analyses" are formats, not branding: they never
#' change, so that saved scripts and files keep loading.
# product name in generated comments and messages; saved-file format
# identifiers (superrstudio-lfq-analyses, '# SuperRStudio <kind> v6') stay
# unchanged for compatibility
.rs.addFunction('superrstudioBrand', function() 'SuperR')

.rs.addFunction('superrstudioDataRpc', function(operation, dataset = '', revision = '', x = '', y = '',
                                              available = character(), appearance = list())
{
   tryCatch(
      # the length-frequency module (SessionSuperRStudioLfq.R) shares this RPC
      if (startsWith(operation, 'lfq_'))
         .rs.superrstudioLfq(operation, dataset, appearance, available)
      else
         .rs.superrstudioData(operation, dataset, revision, x, y, available, appearance),
      error = function(e) list(error = I(conditionMessage(e))))
})

#' Validate a group of plot settings against their defaults
#'
#' Shared checks for the settings groups below; text is only ever embedded
#' into generated code as R strings (never parsed).
#'
#' @param values A named list (from the dialog's JSON object).
#' @param defaults The complete named list of defaults.
#' @param label Group name used in messages.
.rs.addFunction('superrstudioSettings', function(values, defaults, label)
{
   fail <- function(message) stop(message, call. = FALSE)
   if (is.null(values)) values <- list()
   if (!is.list(values) || (length(values) && is.null(names(values))))
      fail(paste0(label, ' settings must be named.'))
   unknown <- setdiff(names(values), names(defaults))
   if (length(unknown)) fail(paste0('Unknown ', tolower(label), ' setting: ', unknown[[1L]], '.'))
   utils::modifyList(defaults, values)
})

.rs.addFunction('superrstudioIsText', function(value)
   is.character(value) && length(value) == 1L && !is.na(value))

.rs.addFunction('superrstudioIsNumber', function(value, low, high)
   is.numeric(value) && length(value) == 1L && is.finite(value) && value >= low && value <= high)

.rs.addFunction('superrstudioIsColour', function(value)
   .rs.superrstudioIsText(value) && (value == '' || value %in% grDevices::colors() ||
                                     grepl('^#[0-9A-Fa-f]{6}$', value)))

#' Validate scatter appearance settings
#'
#' Returns the complete, normalized appearance (defaults filled in) or stops
#' with a message for the user.
#'
#' @param appearance A named list (from the dialog's JSON object).
.rs.addFunction('superrstudioScatterAppearance', function(appearance = list())
{
   fail <- function(message) stop(message, call. = FALSE)
   defaults <- list(title = '', x_label = '', y_label = '', colour = '',
                    size = 1.5, alpha = 1, theme = 'grey',
                    line_colour = '', line_width = 0.5, line_type = 'solid', fit_colour = '',
                    fill = '', legend_position = 'right',
                    canvas_width = 5, canvas_height = 3.75, canvas_aspect = 'free', canvas_lock = FALSE)
   result <- .rs.superrstudioSettings(appearance, defaults, 'Appearance')
   for (field in c('title', 'x_label', 'y_label'))
      if (!.rs.superrstudioIsText(result[[field]]) || nchar(result[[field]]) > 200L)
         fail('Titles and axis labels must be text of at most 200 characters.')
   if (!.rs.superrstudioIsColour(result$colour)) fail('Point colour must be an R colour name or #RRGGBB.')
   if (!.rs.superrstudioIsColour(result$line_colour)) fail('Line colour must be an R colour name or #RRGGBB.')
   if (!.rs.superrstudioIsColour(result$fit_colour)) fail('Fit colour must be an R colour name or #RRGGBB.')
   if (!.rs.superrstudioIsColour(result$fill)) fail('Fill colour must be an R colour name or #RRGGBB.')
   if (!.rs.superrstudioIsNumber(result$size, 0.5, 10)) fail('Point size must be between 0.5 and 10.')
   if (!.rs.superrstudioIsNumber(result$alpha, 0.05, 1)) fail('Point opacity must be between 0.05 and 1.')
   if (!.rs.superrstudioIsNumber(result$line_width, 0.1, 5)) fail('Line width must be between 0.1 and 5.')
   if (!.rs.superrstudioIsText(result$line_type) ||
       !result$line_type %in% c('solid', 'dashed', 'dotted', 'dotdash', 'longdash', 'twodash'))
      fail('Unsupported line type.')
   if (!.rs.superrstudioIsText(result$theme) || !result$theme %in% c('grey', 'bw', 'minimal', 'classic', 'light'))
      fail('Unsupported theme.')
   if (!.rs.superrstudioIsText(result$legend_position) ||
       !result$legend_position %in% c('right', 'bottom', 'top', 'left', 'none'))
      fail('Legend position must be right, bottom, top, left or none.')
   # the canvas is the plot's physical size (inches): the preview is drawn at
   # it, so its layout (text relative to panels) is what an export of the
   # same size shows; it changes only through explicit resizing
   for (side in c('canvas_width', 'canvas_height'))
      if (!.rs.superrstudioIsNumber(result[[side]], 1, 20))
         fail('The preview canvas must be between 1 and 20 inches wide and high.')
   ratios <- c(`1:1` = 1, `4:3` = 4 / 3, `3:2` = 3 / 2, `16:9` = 16 / 9)
   if (!.rs.superrstudioIsText(result$canvas_aspect) || !result$canvas_aspect %in% c('free', names(ratios)))
      fail('Canvas proportions must be free, 1:1, 4:3, 3:2 or 16:9.')
   if (!is.logical(result$canvas_lock) || length(result$canvas_lock) != 1L || is.na(result$canvas_lock))
      fail('The canvas proportion lock must be true or false.')
   if (result$canvas_aspect != 'free' &&
       abs(result$canvas_width / result$canvas_height / ratios[[result$canvas_aspect]] - 1) > 0.02)
      fail(sprintf('The canvas is not %s; choose free proportions or resize it.', result$canvas_aspect))
   for (field in c('size', 'alpha', 'line_width', 'canvas_width', 'canvas_height'))
      result[[field]] <- as.numeric(result[[field]])
   result[names(defaults)]
})

#' Validate scatter layer settings (geometry, line ordering and fitted curves)
#'
#' Connected lines must state their order explicitly: "x" joins observations
#' in increasing x within each group (geom_line), "data" in data-row order
#' (geom_path). Fits are "lm" (ordinary least squares, y ~ x) or "loess"
#' (local regression, stats::loess).
.rs.addFunction('superrstudioScatterOptions', function(options = list())
{
   fail <- function(message) stop(message, call. = FALSE)
   defaults <- list(kind = 'scatter', geometry = 'points', line_order = 'x', fit = 'none',
                    fit_se = TRUE, fit_level = 0.95, fit_span = 0.75,
                    bins = 30, bin_width = 0, show_outliers = TRUE, show_points = FALSE,
                    bar_position = 'stack', adjust = 1)
   result <- .rs.superrstudioSettings(options, defaults, 'Layer')
   flag <- function(value) is.logical(value) && length(value) == 1L && !is.na(value)
   if (!.rs.superrstudioIsText(result$kind) ||
       !result$kind %in% c('scatter', 'histogram', 'boxplot', 'bar', 'density'))
      fail('Plot type must be scatter, histogram, boxplot, bar or density.')
   if (!.rs.superrstudioIsText(result$bar_position) || !result$bar_position %in% c('stack', 'dodge', 'fill'))
      fail('Bar position must be stack, dodge or fill.')
   if (!.rs.superrstudioIsNumber(result$adjust, 0.25, 4))
      fail('Bandwidth adjustment must be between 0.25 and 4.')
   if (!.rs.superrstudioIsNumber(result$bins, 1, 200) || result$bins != round(result$bins))
      fail('Number of bins must be a whole number between 1 and 200.')
   if (!.rs.superrstudioIsNumber(result$bin_width, 0, Inf))
      fail('Bin width must be zero (use the number of bins) or a positive number.')
   if (!flag(result$show_outliers) || !flag(result$show_points))
      fail('Outlier and point display must be true or false.')
   if (!.rs.superrstudioIsText(result$geometry) || !result$geometry %in% c('points', 'lines', 'lines_points'))
      fail('Geometry must be points, lines, or lines and points.')
   if (!.rs.superrstudioIsText(result$line_order) || !result$line_order %in% c('x', 'data'))
      fail('Line order must be "x" (increasing x) or "data" (row order).')
   if (!.rs.superrstudioIsText(result$fit) || !result$fit %in% c('none', 'lm', 'loess'))
      fail('Fit must be none, lm (linear regression) or loess.')
   if (!is.logical(result$fit_se) || length(result$fit_se) != 1L || is.na(result$fit_se))
      fail('Confidence band must be true or false.')
   if (!.rs.superrstudioIsNumber(result$fit_level, 0.5, 0.999))
      fail('Confidence level must be between 0.5 and 0.999.')
   if (!.rs.superrstudioIsNumber(result$fit_span, 0.1, 1))
      fail('LOESS span must be between 0.1 and 1.')
   result$fit_level <- as.numeric(result$fit_level)
   result$fit_span <- as.numeric(result$fit_span)
   result$bins <- as.numeric(result$bins)   # whole number; deparses as 30, not 30L
   result$bin_width <- as.numeric(result$bin_width)
   result$adjust <- as.numeric(result$adjust)
   result[names(defaults)]
})

#' Labels and theme layers shared by every plot kind
.rs.addFunction('superrstudioCommonLayers', function(appearance, blank_x = FALSE)
{
   layers <- list()
   labels <- list()
   if (nzchar(appearance$title)) labels$title <- appearance$title
   if (nzchar(appearance$x_label)) labels$x <- appearance$x_label
   if (nzchar(appearance$y_label)) labels$y <- appearance$y_label
   if (length(labels)) layers <- c(layers, as.call(c(quote(ggplot2::labs), labels)))
   if (appearance$theme != 'grey')
      layers <- c(layers, as.call(list(call('::', as.name('ggplot2'),
                                             as.name(paste0('theme_', appearance$theme))))))
   # a single ungrouped box has no meaningful x axis
   if (blank_x)
      layers <- c(layers, quote(ggplot2::theme(axis.text.x = ggplot2::element_blank(),
                                               axis.ticks.x = ggplot2::element_blank())))
   # after the complete theme, which would otherwise reset it
   if (appearance$legend_position != 'right')
      layers <- c(layers, substitute(ggplot2::theme(legend.position = P),
                                     list(P = appearance$legend_position)))
   layers
})

#' Render a ggplot to SVG together with a map of its editable elements
#'
#' The image is drawn by R's own svg() device from the same gtable that
#' print() draws. Elements are located through documented structures rather
#' than the SVG's unlabelled drawing order: the named cells of the gtable
#' layout (title, axis titles, axes, legend, strips, panels) are measured
#' with grid::deviceLoc(), and each layer's geometry is its ggplot_build()
#' data mapped through the ranges of its panel. Panels are matched to the
#' layout's ROW/COL by the rank of their cell positions, not by grob names.
#' Coordinates are fractions of the image, origin at the top left. The
#' session's current graphics device is restored afterwards.
#'
#' Plots with many drawn rows are rendered as a double-resolution PNG
#' instead: an SVG holds one element per point and would grow to megabytes.
#'
#' @param plot A ggplot object.
#' @param width,height Image size in inches (displayed at 96 pixels per inch).
#' @param svg_rows Largest number of layer rows rendered as SVG.
#' @return A list with the image (SVG text or base64 PNG), its format and
#'   pixel size, and the element map.
.rs.addFunction('superrstudioInteractive', function(plot, width = 5, height = 3.75,
                                                  svg_rows = 5000L, svg_vertices = 100000L)
{
   built <- ggplot2::ggplot_build(plot)
   # SVG holds one element per point or bar but a single element per path, so
   # paths are counted separately: a 100,000-vertex line is a 1.5 MB SVG drawn
   # in 0.14 s, whereas antialiased Cairo PNG takes 4.3 s (benchmarks record)
   path <- vapply(plot$layers, function(layer)
      inherits(layer$geom, c('GeomPath', 'GeomLine', 'GeomStep', 'GeomSmooth', 'GeomDensity', 'GeomArea')), NA)
   rows <- vapply(built$data, NROW, 0)
   vector <- sum(rows[!path]) <= svg_rows && sum(rows[path]) <= svg_vertices
   file <- tempfile('superrstudio-', fileext = if (vector) '.svg' else '.png')
   res <- min(192, 2400 / max(width, height))   # double resolution, at most 2400 pixels a side
   previous <- grDevices::dev.cur()
   if (vector)
      grDevices::svg(file, width = width, height = height)
   else
      grDevices::png(file, width = width * res, height = height * res, res = res,
                     type = if (capabilities('cairo')) 'cairo' else getOption('bitmapType'))
   device <- grDevices::dev.cur()
   on.exit({
      if (device %in% grDevices::dev.list()) grDevices::dev.off(device)
      if (previous > 1L && previous %in% grDevices::dev.list()) grDevices::dev.set(previous)
      unlink(file)
   })
   table <- ggplot2::ggplot_gtable(built)
   grid::grid.newpage()
   grid::grid.draw(table)
   grid::seekViewport(table$name)

   # cell box as c(left, top, right, bottom)
   box <- function(entry)
   {
      grid::pushViewport(grid::viewport(layout.pos.row = entry$t:entry$b,
                                        layout.pos.col = entry$l:entry$r))
      on.exit(grid::popViewport())
      low <- grid::deviceLoc(grid::unit(0, 'npc'), grid::unit(0, 'npc'), valueOnly = TRUE)
      high <- grid::deviceLoc(grid::unit(1, 'npc'), grid::unit(1, 'npc'), valueOnly = TRUE)
      c(low$x / width, 1 - high$y / height, high$x / width, 1 - low$y / height)
   }
   number <- function(values) round(as.numeric(values), 4L)
   layout <- table$layout
   regionRole <- function(name)
      if (name == 'title') 'title'
      else if (name == 'xlab-b') 'x_label'
      else if (name == 'ylab-l') 'y_label'
      else if (grepl('^axis-b', name)) 'x_axis'
      else if (grepl('^axis-l', name)) 'y_axis'
      else if (grepl('^guide-box', name)) 'legend'
      else if (grepl('^strip', name)) 'strip'
      else if (grepl('^panel', name)) 'panel'
      else ''
   regions <- list()
   for (i in seq_len(nrow(layout)))
   {
      role <- regionRole(layout$name[[i]])
      if (!nzchar(role) || inherits(table$grobs[[i]], 'zeroGrob')) next
      bounds <- box(layout[i, ])
      if (bounds[3L] - bounds[1L] < 1e-3 || bounds[4L] - bounds[2L] < 1e-3) next
      regions[[length(regions) + 1L]] <- list(role = I(role), box = number(bounds))
   }

   panels <- layout[grepl('^panel', layout$name), , drop = FALSE]
   panelRow <- match(panels$t, sort(unique(panels$t)))
   panelCol <- match(panels$l, sort(unique(panels$l)))
   panelBoxes <- lapply(seq_len(nrow(built$layout$layout)), function(p)
   {
      hit <- which(panelRow == built$layout$layout$ROW[[p]] & panelCol == built$layout$layout$COL[[p]])
      if (length(hit) == 1L) box(panels[hit, ])
   })
   # data (scale) coordinates to image fractions within a panel
   place <- function(values, range, low, high)
   {
      values <- as.numeric(values)
      values[values == -Inf] <- range[1L]
      values[values == Inf] <- range[2L]
      low + (values - range[1L]) / diff(range) * (high - low)
   }
   locate <- function(p, x, y)
   {
      params <- built$layout$panel_params[[p]]
      bounds <- panelBoxes[[p]]
      cbind(place(x, params$x.range, bounds[1L], bounds[3L]),
            place(y, params$y.range, bounds[4L], bounds[2L]))
   }
   thin <- function(rows, limit) if (length(rows) > limit)
      rows[unique(round(seq(1, length(rows), length.out = limit)))] else rows
   flat <- function(matrix) number(t(matrix))

   roles <- c(GeomPoint = 'points', GeomLine = 'lines', GeomPath = 'lines', GeomStep = 'lines',
              GeomSmooth = 'fit', GeomBar = 'bars', GeomCol = 'bars', GeomRect = 'bars',
              GeomBoxplot = 'boxes', GeomDensity = 'density', GeomArea = 'density')
   elements <- list()
   add <- function(role, shape, layer, coords)
      if (length(coords) && all(is.finite(coords)))
         elements[[length(elements) + 1L]] <<- list(role = I(role), shape = I(shape),
                                                    layer = I(layer), coords = coords)
   for (i in seq_along(plot$layers))
   {
      # the most specific known class: GeomSmooth before GeomLine, etc.
      known <- intersect(class(plot$layers[[i]]$geom), names(roles))
      if (!length(known)) next
      role <- roles[[known[[1L]]]]
      data <- built$data[[i]]
      for (p in unique(data$PANEL))
      {
         p <- as.integer(p)
         if (p > length(panelBoxes) || is.null(panelBoxes[[p]])) next
         part <- data[as.integer(data$PANEL) == p, , drop = FALSE]
         if (role == 'points')
         {
            part <- part[is.finite(part$x) & is.finite(part$y), , drop = FALSE]
            rows <- thin(seq_len(nrow(part)), 4000L)
            add(role, 'points', i, flat(locate(p, part$x[rows], part$y[rows])))
         }
         else if (role %in% c('bars', 'boxes'))
         {
            # (left, top, right, bottom); a box spans its whiskers
            corners <- cbind(locate(p, part$xmin, part$ymax), locate(p, part$xmax, part$ymin))
            corners <- corners[apply(is.finite(corners), 1L, all), , drop = FALSE]
            add(role, 'rects', i, flat(corners))
         }
         else
         {
            for (g in split(part, part$group))
            {
               g <- g[is.finite(g$x) & is.finite(g$y), , drop = FALSE]
               if (nrow(g) < 2L) next
               rows <- thin(seq_len(nrow(g)), 1000L)
               if (role == 'density')
               {
                  base <- if (is.null(g$ymin)) rep(0, nrow(g)) else g$ymin
                  outline <- rbind(locate(p, g$x[rows], g$y[rows]),
                                   locate(p, rev(g$x[rows]), rev(base[rows])))
                  add(role, 'polygon', i, flat(outline))
               }
               else
               {
                  add(role, 'path', i, flat(locate(p, g$x[rows], g$y[rows])))
                  if (role == 'fit' && !is.null(g$ymin) && all(is.finite(c(g$ymin, g$ymax))))
                     add(role, 'polygon', i, flat(rbind(locate(p, g$x[rows], g$ymin[rows]),
                                                        locate(p, rev(g$x[rows]), rev(g$ymax[rows])))))
               }
            }
         }
      }
   }
   grDevices::dev.off(device)
   image <- if (vector) paste(readLines(file, warn = FALSE, encoding = 'UTF-8'), collapse = '\n')
            else .rs.rBase64Encode(readBin(file, 'raw', file.size(file)))
   list(image = I(image), format = I(if (vector) 'svg' else 'png'),
        width = I(round(width * 96)), height = I(round(height * 96)),
        regions = regions, elements = elements)
})

#' Validate image export settings
#'
#' The file is written with ggplot2::ggsave(): PNG through ggsave's own
#' bitmap device at the given resolution, SVG through R's svg() device and
#' PDF through cairo_pdf() (embedded fonts), so no extra packages are needed.
#' @param canvas c(width, height) of the preview canvas in inches; with
#'   export_mode "preview" the height follows the canvas proportions.
.rs.addFunction('superrstudioExportOptions', function(export = list(), canvas = c(5, 3.75))
{
   fail <- function(message) stop(message, call. = FALSE)
   defaults <- list(export_path = '', export_format = 'png', export_width = 16,
                    export_height = 12, export_units = 'cm', export_dpi = 300, export_mode = 'exact')
   result <- .rs.superrstudioSettings(export, defaults, 'Export')
   if (!.rs.superrstudioIsText(result$export_format) || !result$export_format %in% c('png', 'svg', 'pdf'))
      fail('Export format must be PNG, SVG or PDF.')
   if (!.rs.superrstudioIsText(result$export_units) || !result$export_units %in% c('cm', 'mm', 'in'))
      fail('Export size units must be cm, mm or in.')
   inches <- c(cm = 2.54, mm = 25.4, `in` = 1)[[result$export_units]]
   if (!.rs.superrstudioIsText(result$export_mode) || !result$export_mode %in% c('exact', 'preview'))
      fail('Export size must be exact dimensions or the preview proportions.')
   # preview proportions: the given width, the canvas's aspect ratio (no
   # screen pixels involved); the height is stated in the export script
   if (result$export_mode == 'preview' && .rs.superrstudioIsNumber(result$export_width, 0, Inf))
      result$export_height <- signif(as.numeric(result$export_width) * canvas[[2L]] / canvas[[1L]], 4L)
   for (side in c('export_width', 'export_height'))
      if (!.rs.superrstudioIsNumber(result[[side]], 0.5 * inches, 50 * inches))
         fail('Image width and height must be between 0.5 and 50 inches (1.27 to 127 cm).')
   if (!.rs.superrstudioIsNumber(result$export_dpi, 72, 1200) || result$export_dpi != round(result$export_dpi))
      fail('Resolution must be a whole number of dots per inch between 72 and 1200.')
   path <- result$export_path
   if (!.rs.superrstudioIsText(path) || !nzchar(path)) fail('Choose a file to export to.')
   path <- gsub('\\\\', '/', path.expand(path))
   extension <- tolower(tools::file_ext(path))
   if (!identical(extension, result$export_format))
      fail(paste0('The file name must end in .', result$export_format, ' for this format.'))
   if (!dir.exists(dirname(path))) fail('The folder for the exported file does not exist.')
   if (dir.exists(path)) fail('The export path is a folder; choose a file name.')
   result$export_path <- path
   for (field in c('export_width', 'export_height', 'export_dpi'))
      result[[field]] <- as.numeric(result[[field]])
   result[names(defaults)]
})

#' The ggsave() call that writes an exported image of `plot`
.rs.addFunction('superrstudioExportCall', function(export)
{
   args <- list(filename = export$export_path, plot = as.name('plot'))
   if (export$export_format == 'svg') args$device <- quote(grDevices::svg)
   if (export$export_format == 'pdf') args$device <- quote(grDevices::cairo_pdf)
   args$width <- export$export_width
   args$height <- export$export_height
   args$units <- export$export_units
   if (export$export_format == 'png') args$dpi <- export$export_dpi
   as.call(c(quote(ggplot2::ggsave), args))
})

#' Evaluate a plot expression on a private copy of the binding: print it to
#' the Plots pane ("preview") and render the interactive preview ("preview"
#' and "render"). Warnings are collected once each instead of printed.
.rs.addFunction('superrstudioRender', function(operation, expression, dataset, data, export = NULL,
                                             canvas = c(5, 3.75))
{
   warnings <- character()
   interactive <- NULL
   saved <- NULL
   if (operation == 'export')
   {
      withCallingHandlers({
         env <- new.env(parent = baseenv())
         assign(dataset, data, envir = env)
         assign('plot', eval(expression, envir = env), envir = env)
         eval(.rs.superrstudioExportCall(export), envir = env)
         saved <- list(path = I(export$export_path), bytes = I(file.size(export$export_path)))
      }, warning = function(w) {
         warnings <<- c(warnings, conditionMessage(w))
         invokeRestart('muffleWarning')
      })
   }
   if (operation %in% c('preview', 'render'))
   {
      withCallingHandlers({
         # Resolve exactly the current object in a private evaluation frame.
         # The user's objects and search path are not assigned or attached to.
         env <- new.env(parent = baseenv())
         assign(dataset, data, envir = env)
         plot <- eval(expression, envir = env)
         if (operation == 'preview') print(plot)
         interactive <- .rs.superrstudioInteractive(plot, width = canvas[[1L]], height = canvas[[2L]])
      }, warning = function(w) {
         warnings <<- c(warnings, conditionMessage(w))
         invokeRestart('muffleWarning')
      })
   }
   list(warnings = unique(warnings), interactive = interactive, saved = saved)
})

#' Histogram layers: explicit bins (or bin width) so the binning is never an
#' implicit default; an optional discrete fill column stacks the counts.
.rs.addFunction('superrstudioHistogramLayers', function(dataset, x, appearance, options, fill_by = '')
{
   aesthetics <- list(x = substitute(.data[[X]], list(X = x)))
   if (nzchar(fill_by)) aesthetics$fill <- substitute(.data[[F]], list(F = fill_by))
   layers <- list(substitute(ggplot2::ggplot(DATA, MAPPING),
                             list(DATA = as.name(dataset),
                                  MAPPING = as.call(c(quote(ggplot2::aes), aesthetics)))))
   bars <- if (options$bin_width > 0) list(binwidth = options$bin_width) else list(bins = options$bins)
   if (nzchar(appearance$fill)) bars$fill <- appearance$fill
   if (nzchar(appearance$line_colour)) bars$colour <- appearance$line_colour
   if (appearance$alpha != 1) bars$alpha <- appearance$alpha
   layers <- c(layers, as.call(c(quote(ggplot2::geom_histogram), bars)))
   if (nzchar(fill_by)) layers <- c(layers, quote(ggplot2::scale_fill_viridis_d()))
   c(layers, .rs.superrstudioCommonLayers(appearance))
})

#' Boxplot layers: a numeric response, optionally by a discrete group.
#' Outliers can be hidden (they still count in the statistics), and the raw
#' observations can be overlaid with a seeded, reproducible horizontal jitter.
.rs.addFunction('superrstudioBoxplotLayers', function(dataset, group, y, appearance, options, fill_by = '')
{
   aesthetics <- list()
   if (nzchar(group)) aesthetics$x <- substitute(.data[[G]], list(G = group))
   aesthetics$y <- substitute(.data[[Y]], list(Y = y))
   if (nzchar(fill_by)) aesthetics$fill <- substitute(.data[[F]], list(F = fill_by))
   layers <- list(substitute(ggplot2::ggplot(DATA, MAPPING),
                             list(DATA = as.name(dataset),
                                  MAPPING = as.call(c(quote(ggplot2::aes), aesthetics)))))
   box <- list()
   if (!options$show_outliers) box$outlier.shape <- NA
   if (nzchar(appearance$fill)) box$fill <- appearance$fill
   if (nzchar(appearance$line_colour)) box$colour <- appearance$line_colour
   if (appearance$alpha != 1) box$alpha <- appearance$alpha
   layers <- c(layers, as.call(c(quote(ggplot2::geom_boxplot), box)))
   if (options$show_points)
   {
      point <- list(position = quote(ggplot2::position_jitter(width = 0.15, height = 0, seed = 1)))
      if (nzchar(appearance$colour)) point$colour <- appearance$colour
      if (appearance$size != 1.5) point$size <- appearance$size
      layers <- c(layers, as.call(c(quote(ggplot2::geom_point), point)))
   }
   if (nzchar(fill_by)) layers <- c(layers, quote(ggplot2::scale_fill_viridis_d()))
   c(layers, .rs.superrstudioCommonLayers(appearance, blank_x = !nzchar(group)))
})

#' Bar chart of counts of a categorical variable (geom_bar). Bars of summed
#' values (geom_col over several rows per category) are deliberately not
#' offered; "fill" shows proportions within each bar.
.rs.addFunction('superrstudioBarLayers', function(dataset, x, appearance, options, fill_by = '')
{
   aesthetics <- list(x = substitute(.data[[X]], list(X = x)))
   if (nzchar(fill_by)) aesthetics$fill <- substitute(.data[[F]], list(F = fill_by))
   layers <- list(substitute(ggplot2::ggplot(DATA, MAPPING),
                             list(DATA = as.name(dataset),
                                  MAPPING = as.call(c(quote(ggplot2::aes), aesthetics)))))
   bars <- list()
   if (options$bar_position != 'stack') bars$position <- options$bar_position
   if (nzchar(appearance$fill)) bars$fill <- appearance$fill
   if (nzchar(appearance$line_colour)) bars$colour <- appearance$line_colour
   if (appearance$alpha != 1) bars$alpha <- appearance$alpha
   layers <- c(layers, as.call(c(quote(ggplot2::geom_bar), bars)))
   if (nzchar(fill_by)) layers <- c(layers, quote(ggplot2::scale_fill_viridis_d()))
   # proportions are not counts: label the axis accordingly unless set
   if (options$bar_position == 'fill' && !nzchar(appearance$y_label)) appearance$y_label <- 'proportion'
   c(layers, .rs.superrstudioCommonLayers(appearance))
})

#' Kernel density estimate (geom_density, ggplot2's default "nrd0"
#' bandwidth times `adjust`); a fill column gives one curve per group.
.rs.addFunction('superrstudioDensityLayers', function(dataset, x, appearance, options, fill_by = '')
{
   aesthetics <- list(x = substitute(.data[[X]], list(X = x)))
   if (nzchar(fill_by)) aesthetics$fill <- substitute(.data[[F]], list(F = fill_by))
   layers <- list(substitute(ggplot2::ggplot(DATA, MAPPING),
                             list(DATA = as.name(dataset),
                                  MAPPING = as.call(c(quote(ggplot2::aes), aesthetics)))))
   curve <- list()
   if (options$adjust != 1) curve$adjust <- options$adjust
   if (nzchar(appearance$fill)) curve$fill <- appearance$fill
   if (nzchar(appearance$line_colour)) curve$colour <- appearance$line_colour
   if (appearance$alpha != 1) curve$alpha <- appearance$alpha
   layers <- c(layers, as.call(c(quote(ggplot2::geom_density), curve)))
   if (nzchar(fill_by)) layers <- c(layers, quote(ggplot2::scale_fill_viridis_d()))
   c(layers, .rs.superrstudioCommonLayers(appearance))
})

#' Group keys as ggplot2 forms them: missing values form their own group.
#' Several columns (a group plus facet columns) are joined with " / ".
.rs.addFunction('superrstudioGroupKey', function(data, columns)
{
   columns <- columns[nzchar(columns)]
   if (!length(columns)) return(factor(rep('all', nrow(data))))
   values <- lapply(columns, function(column) {
      value <- as.character(data[[column]])
      value[is.na(value)] <- 'NA'
      value
   })
   if (length(values) == 1L) factor(values[[1L]])
   else interaction(values, drop = TRUE, sep = ' / ', lex.order = TRUE)
})

#' Box statistics exactly as ggplot2's stat_boxplot() computes them:
#' quantile(type = 7) quartiles, outliers beyond 1.5 IQR, and whiskers spanning
#' range(c(quartiles, non-outlying values)).
.rs.addFunction('superrstudioBoxSummary', function(data, group, y)
{
   values <- split(data[[y]], .rs.superrstudioGroupKey(data, group), drop = TRUE)
   lapply(names(values), function(name)
   {
      v <- values[[name]]
      v <- v[is.finite(v)]
      if (!length(v))
         return(list(group = I(name), n = I(0L)))
      q <- stats::quantile(v, c(0, 0.25, 0.5, 0.75, 1), type = 7, names = FALSE)
      iqr <- q[4L] - q[2L]
      outliers <- v < q[2L] - 1.5 * iqr | v > q[4L] + 1.5 * iqr
      whiskers <- range(c(q[2L:4L], v[!outliers]))
      list(group = I(name), n = I(length(v)), lower_whisker = I(whiskers[1L]),
           q1 = I(q[2L]), median = I(q[3L]), q3 = I(q[4L]), upper_whisker = I(whiskers[2L]),
           outliers = I(sum(outliers)))
   })
})

#' Build the scatter plot as ggplot2 layers (language objects)
#'
#' Only settings that differ from ggplot2's defaults are emitted. A colour
#' column is mapped inside aes() with a colour-blind-safe viridis scale
#' (discrete or continuous according to the column).
.rs.addFunction('superrstudioScatterLayers', function(dataset, x, y, appearance,
                                                    colour_by = '', discrete = TRUE,
                                                    options = .rs.superrstudioScatterOptions(),
                                                    group_by = '')
{
   aesthetics <- list(x = substitute(.data[[X]], list(X = x)),
                      y = substitute(.data[[Y]], list(Y = y)))
   if (nzchar(colour_by)) aesthetics$colour <- substitute(.data[[C]], list(C = colour_by))
   if (nzchar(group_by)) aesthetics$group <- substitute(.data[[G]], list(G = group_by))
   layers <- list(substitute(ggplot2::ggplot(DATA, MAPPING),
                             list(DATA = as.name(dataset),
                                  MAPPING = as.call(c(quote(ggplot2::aes), aesthetics)))))

   if (options$geometry %in% c('lines', 'lines_points'))
   {
      line <- list()
      if (nzchar(appearance$line_colour)) line$colour <- appearance$line_colour
      if (appearance$line_width != 0.5) line$linewidth <- appearance$line_width
      if (appearance$line_type != 'solid') line$linetype <- appearance$line_type
      geom <- if (options$line_order == 'x') quote(ggplot2::geom_line) else quote(ggplot2::geom_path)
      layers <- c(layers, as.call(c(geom, line)))
   }
   if (options$geometry %in% c('points', 'lines_points'))
   {
      point <- list()
      if (nzchar(appearance$colour)) point$colour <- appearance$colour
      if (appearance$size != 1.5) point$size <- appearance$size
      if (appearance$alpha != 1) point$alpha <- appearance$alpha
      layers <- c(layers, as.call(c(quote(ggplot2::geom_point), point)))
   }
   if (options$fit != 'none')
   {
      smooth <- list(method = options$fit, formula = quote(y ~ x))
      if (!options$fit_se) smooth$se <- FALSE
      else if (options$fit_level != 0.95) smooth$level <- options$fit_level
      if (options$fit == 'loess' && options$fit_span != 0.75) smooth$span <- options$fit_span
      if (nzchar(appearance$fit_colour)) smooth$colour <- appearance$fit_colour
      layers <- c(layers, as.call(c(quote(ggplot2::geom_smooth), smooth)))
   }
   if (nzchar(colour_by))
      layers <- c(layers, if (discrete) quote(ggplot2::scale_colour_viridis_d())
                          else quote(ggplot2::scale_colour_viridis_c()))
   c(layers, .rs.superrstudioCommonLayers(appearance))
})

#' Summarise the fitted model(s) behind a scatter fit
#'
#' Fits exactly what geom_smooth() fits (y ~ x on the finite observations of
#' each group defined by the discrete grouping columns), with stats::lm() or
#' stats::loess(). Statistics are only reported when they are estimable:
#' at least three observations and a non-constant x.
#'
#' @return A list with one entry per group.
.rs.addFunction('superrstudioFitSummary', function(data, x, y, method, groups = character(),
                                                 span = 0.75, x_name = x, y_name = y)
{
   frame <- data.frame(x = data[[x]], y = data[[y]])
   # missing group values form their own group, as in ggplot2
   key <- if (length(groups))
      interaction(lapply(groups, function(g) {
         value <- as.character(data[[g]])
         value[is.na(value)] <- 'NA'
         value
      }), drop = TRUE, sep = ' / ', lex.order = TRUE)
   else
      factor(rep('all', nrow(frame)))
   number <- function(value) if (length(value) == 1L && is.finite(value)) I(unname(value))
   parts <- split(frame, key, drop = TRUE)
   lapply(names(parts), function(name)
   {
      part <- parts[[name]]
      part <- part[is.finite(part$x) & is.finite(part$y), , drop = FALSE]
      row <- list(group = I(name), n = I(nrow(part)), method = I(method))
      if (nrow(part) < 3L || length(unique(part$x)) < 2L)
         return(c(row, note = I('Too few observations or constant x: no fit statistics.')))
      if (method == 'loess')
         return(c(row, span = I(span), note = I('Local regression (stats::loess, degree 2): a descriptive smoother; no equation or R-squared.')))
      notes <- character()
      model <- withCallingHandlers(stats::lm(y ~ x, data = part), warning = function(w) {
         notes <<- c(notes, conditionMessage(w)); invokeRestart('muffleWarning')
      })
      summary <- withCallingHandlers(summary(model), warning = function(w) {
         notes <<- c(notes, conditionMessage(w)); invokeRestart('muffleWarning')
      })
      coefficients <- stats::coef(summary)
      intercept <- coefficients[1L, 1L]
      slope <- coefficients[2L, 1L]
      equation <- sprintf('%s = %s %s %s * %s', y_name, format(signif(intercept, 4L)),
                          if (slope < 0) '-' else '+', format(signif(abs(slope), 4L)), x_name)
      # NULL entries (non-finite statistics) are dropped rather than serialized
      Filter(Negate(is.null), c(row, list(
        intercept = number(intercept), slope = number(slope),
        slope_p_value = number(coefficients[2L, 4L]),
        r_squared = number(summary$r.squared), adj_r_squared = number(summary$adj.r.squared),
        sigma = number(summary$sigma), df = number(summary$df[[2L]]),
        equation = I(equation), note = I(paste(unique(notes), collapse = ' ')))))
   })
})

#' Code that reproduces the model(s) summarised for a linear fit
#'
#' On log10 axes ggplot2 fits on the transformed scale, and filtering
#' limits remove observations first; the code states both explicitly.
.rs.addFunction('superrstudioFitCode', function(dataset, x, y, groups = character(), axes = NULL)
{
   time <- if (is.null(axes) || is.null(attr(axes, 'time'))) '' else attr(axes, 'time')
   # dates enter the model as days (date-times as seconds) since 1970-01-01,
   # the numbers ggplot2 fits on
   xValue <- if (nzchar(time)) substitute(as.numeric(DATA[[X]]), list(DATA = as.name(dataset), X = x))
      else substitute(DATA[[X]], list(DATA = as.name(dataset), X = x))
   frame <- substitute(data.frame(x = XV, y = DATA[[Y]]),
                       list(DATA = as.name(dataset), XV = xValue, Y = y))
   timeNote <- if (time == 'date') '# x: days since 1970-01-01 (the slope is per day).'
      else if (time == 'datetime') '# x: seconds since 1970-01-01 00:00 UTC (the slope is per second).'
   conditions <- list()
   formula <- quote(y ~ x)
   for (axis in c('x', 'y'))
   {
      if (is.null(axes)) break
      variable <- as.name(axis)
      if (axes$limits_mode == 'filter')
      {
         low <- axes[[paste0(axis, '_min')]]
         high <- axes[[paste0(axis, '_max')]]
         if (axis == 'x' && nzchar(time))
         {
            zone <- if (nzchar(axes$x_timezone)) axes$x_timezone else attr(axes, 'tz')
            limit <- function(value) call('as.numeric', .rs.superrstudioTimeCall(value, time, zone))
            if (!identical(low, '')) low <- limit(low)
            if (!identical(high, '')) high <- limit(high)
         }
         if (!identical(low, '')) conditions <- c(conditions, call('>=', variable, low))
         if (!identical(high, '')) conditions <- c(conditions, call('<=', variable, high))
      }
      if (axes[[paste0(axis, '_scale')]] == 'log10')
      {
         conditions <- c(conditions, call('>', variable, 0))
         formula[[if (axis == 'y') 2L else 3L]] <- call('log10', variable)
      }
   }
   if (length(conditions))
   {
      keep <- Reduce(function(lhs, rhs) call('&', lhs, rhs), conditions)
      if (length(groups))
      {
         keys <- as.call(c(quote(interaction), lapply(groups, function(g)
            substitute(DATA[[G]], list(DATA = as.name(dataset), G = g))),
            list(drop = TRUE, sep = ' / ', lex.order = TRUE)))
         frame[['group']] <- keys
      }
      frame <- substitute(subset(FRAME, KEEP), list(FRAME = frame, KEEP = keep))
      call <- if (!length(groups))
         substitute(summary(stats::lm(FORMULA, data = FRAME)), list(FORMULA = formula, FRAME = frame))
      else
         substitute(local({
            d <- FRAME
            lapply(split(d, d$group, drop = TRUE), function(d) summary(stats::lm(FORMULA, data = d)))
         }), list(FRAME = frame, FORMULA = formula))
      return(paste(c('# Linear model(s) behind the fitted line: exploratory; check linearity,',
                     '# independence, constant variance and residual normality before inference.',
                     '# Fitted on the plotted scale and observations, as ggplot2 does.', timeNote,
                     deparse(call, width.cutoff = 90L, backtick = TRUE)), collapse = '\n'))
   }
   call <- if (!length(groups))
      substitute(summary(stats::lm(y ~ x, data = FRAME)), list(FRAME = frame))
   else
   {
      keys <- as.call(c(quote(list), lapply(groups, function(g)
         substitute(DATA[[G]], list(DATA = as.name(dataset), G = g)))))
      substitute(lapply(split(FRAME, KEYS, drop = TRUE), function(d) summary(stats::lm(y ~ x, data = d))),
                 list(FRAME = frame, KEYS = keys))
   }
   paste(c('# Linear model(s) behind the fitted line: exploratory; check linearity,',
           '# independence, constant variance and residual normality before inference.', timeNote,
           deparse(call, width.cutoff = 90L, backtick = TRUE)), collapse = '\n')
})

#' Validate axis, scale and facet settings for a plot kind
#'
#' Limits either zoom (coord_cartesian: every observation still enters the
#' statistics) or filter (scale limits: observations outside are removed
#' before statistics, as ggplot2 does). Log scales need positive limits.
.rs.addFunction('superrstudioAxisOptions', function(axes = list(), kind = 'scatter', time = '', tz = '')
{
   fail <- function(message) stop(message, call. = FALSE)
   defaults <- list(x_scale = 'linear', y_scale = 'linear', x_min = '', x_max = '',
                    y_min = '', y_max = '', limits_mode = 'zoom', x_format = 'default',
                    y_format = 'default', grid_major = TRUE, grid_minor = TRUE,
                    facet_scales = 'fixed', facet_ncol = 0,
                    x_date_breaks = '', x_date_labels = '', x_timezone = '')
   result <- .rs.superrstudioSettings(axes, defaults, 'Axis')
   flag <- function(value) is.logical(value) && length(value) == 1L && !is.na(value)
   choice <- function(value, allowed) .rs.superrstudioIsText(value) && value %in% allowed
   for (key in c('x_date_breaks', 'x_date_labels', 'x_timezone'))
      if (!.rs.superrstudioIsText(result[[key]])) fail('Date axis settings must be text.')
   if (nzchar(time))
      result <- .rs.superrstudioTimeAxisOptions(result, time, tz)
   else if (nzchar(result$x_date_breaks) || nzchar(result$x_date_labels) || nzchar(result$x_timezone))
      fail('Date breaks, date labels and time zones apply to a date or date-time X column.')
   for (axis in if (nzchar(time)) 'y' else c('x', 'y'))
   {
      label <- toupper(axis)
      if (!choice(result[[paste0(axis, '_scale')]], c('linear', 'log10')))
         fail(paste0(label, ' scale must be linear or log10.'))
      if (!choice(result[[paste0(axis, '_format')]], c('default', 'comma', 'scientific', 'percent')))
         fail(paste0(label, ' tick labels must be default, comma, scientific or percent.'))
      for (end in c('_min', '_max'))
      {
         value <- result[[paste0(axis, end)]]
         if (!(identical(value, '') || .rs.superrstudioIsNumber(value, -Inf, Inf)))
            fail(paste0(label, ' axis limits must be numbers or left empty.'))
         if (!identical(value, '')) result[[paste0(axis, end)]] <- as.numeric(value)
      }
      low <- result[[paste0(axis, '_min')]]
      high <- result[[paste0(axis, '_max')]]
      if (is.numeric(low) && is.numeric(high) && low >= high)
         fail(paste0(label, ' axis minimum must be below its maximum.'))
      if (result[[paste0(axis, '_scale')]] == 'log10' &&
          ((is.numeric(low) && low <= 0) || (is.numeric(high) && high <= 0)))
         fail(paste0(label, ' axis limits on a log scale must be positive.'))
   }
   if (!choice(result$limits_mode, c('zoom', 'filter'))) fail('Axis limits must zoom or filter.')
   if (!flag(result$grid_major) || !flag(result$grid_minor)) fail('Gridline settings must be true or false.')
   if (!choice(result$facet_scales, c('fixed', 'free', 'free_x', 'free_y')))
      fail('Facet scales must be fixed, free, free_x or free_y.')
   if (!.rs.superrstudioIsNumber(result$facet_ncol, 0, 12) || result$facet_ncol != round(result$facet_ncol))
      fail('Facet columns must be a whole number from 0 (automatic) to 12.')
   result$facet_ncol <- as.numeric(result$facet_ncol)
   if (nzchar(time) && kind != 'scatter') fail('Date and date-time X columns apply to scatter and line plots.')

   # what applies to each kind: continuous X for scatter, histogram and
   # density; raw (not computed) Y for scatter and boxplot
   continuousX <- kind %in% c('scatter', 'histogram', 'density')
   rawY <- kind %in% c('scatter', 'boxplot')
   if (!continuousX && (result$x_scale != 'linear' || result$x_format != 'default' ||
                        !identical(result$x_min, '') || !identical(result$x_max, '')))
      fail('X scale, limits and tick labels apply to a continuous X (scatter, histogram, density).')
   if (!rawY && result$y_scale != 'linear')
      fail('A log Y scale applies to measured values (scatter, boxplot), not to counts or densities.')
   if (!rawY && result$limits_mode == 'filter' &&
       (!identical(result$y_min, '') || !identical(result$y_max, '')))
      fail('Y limits on counts or densities can only zoom: filtering would remove bars or curves.')
   result <- result[names(defaults)]
   # the X column's type travels with the settings (not part of the spec)
   attr(result, 'time') <- time
   attr(result, 'tz') <- tz
   result
})

#' Validate X axis settings for a Date ("date") or POSIXct ("datetime") column
#'
#' Limits are ISO text ("2020-03-01"; date-times may add " 14:30"), read in
#' the axis time zone: the chosen display zone, else the column's own.
.rs.addFunction('superrstudioTimeAxisOptions', function(result, time, tz)
{
   fail <- function(message) stop(message, call. = FALSE)
   if (result$x_scale != 'linear') fail('A log scale does not apply to dates and times.')
   if (result$x_format != 'default') fail('Number formats do not apply to dates; choose date labels instead.')
   units <- if (time == 'date') 'day|week|month|year' else 'sec|min|hour|day|week|month|year'
   if (nzchar(result$x_date_breaks) &&
       !grepl(sprintf('^[1-9][0-9]{0,2} (%s)s?$', units), result$x_date_breaks))
      fail(if (time == 'date') 'Date breaks are written like "1 month", "2 weeks" or "1 year".'
           else 'Date-time breaks are written like "6 hours", "1 day" or "1 month".')
   labels <- c('%Y-%m-%d', '%d/%m/%Y', '%m/%d/%Y', '%Y-%m', '%b %Y', '%B %Y', '%Y', '%d %b',
               if (time == 'datetime') c('%H:%M', '%d %b %H:%M', '%Y-%m-%d %H:%M'))
   if (nzchar(result$x_date_labels) && !result$x_date_labels %in% labels)
      fail('Unsupported date label format.')
   if (nzchar(result$x_timezone))
   {
      if (time == 'date') fail('A time zone applies to date-time columns only.')
      if (!result$x_timezone %in% OlsonNames()) fail('Unknown time zone; use a name such as "UTC" or "America/Montevideo".')
   }
   zone <- if (nzchar(result$x_timezone)) result$x_timezone else tz
   for (end in c('x_min', 'x_max'))
   {
      value <- result[[end]]
      if (identical(value, '')) next
      if (!.rs.superrstudioIsText(value) ||
          is.na(.rs.superrstudioTimeValue(value, time, zone)))
         fail(if (time == 'date') 'Date axis limits must be dates written as YYYY-MM-DD, or left empty.'
              else 'Date-time axis limits must be written as YYYY-MM-DD or YYYY-MM-DD HH:MM, or left empty.')
   }
   if (!identical(result$x_min, '') && !identical(result$x_max, '') &&
       .rs.superrstudioTimeValue(result$x_min, time, zone) >= .rs.superrstudioTimeValue(result$x_max, time, zone))
      fail('X axis minimum must be before its maximum.')
   result
})

#' An ISO date or date-time text as Date / POSIXct (NA when invalid)
.rs.addFunction('superrstudioTimeValue', function(text, time, tz)
{
   if (time == 'date')
      return(if (grepl('^[0-9]{4}-[0-9]{2}-[0-9]{2}$', text)) as.Date(text, format = '%Y-%m-%d') else as.Date(NA))
   format <- if (grepl('^[0-9]{4}-[0-9]{2}-[0-9]{2}$', text)) '%Y-%m-%d'
      else if (grepl('^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}$', text)) '%Y-%m-%d %H:%M'
      else if (grepl('^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$', text)) '%Y-%m-%d %H:%M:%S'
   if (is.null(format)) return(as.POSIXct(NA))
   as.POSIXct(text, format = format, tz = tz)
})

#' The call that converts axis limits for the code (as.Date / as.POSIXct)
.rs.addFunction('superrstudioTimeCall', function(values, time, tz)
{
   if (time == 'date') return(call('as.Date', values))
   as.call(c(quote(as.POSIXct), list(values), list(tz = tz)))
})

#' Scale, coordinate, facet and gridline layers for the axis settings
.rs.addFunction('superrstudioAxisLayers', function(axes, facet_by = '', facet_rows = '')
{
   layers <- list()
   value <- function(v) if (identical(v, '')) NA else v
   filter <- axes$limits_mode == 'filter'
   zoom <- list()
   time <- attr(axes, 'time')
   if (is.null(time)) time <- ''
   for (axis in c('x', 'y'))
   {
      low <- value(axes[[paste0(axis, '_min')]])
      high <- value(axes[[paste0(axis, '_max')]])
      limited <- !is.na(low) || !is.na(high)
      if (axis == 'x' && nzchar(time))
      {
         zone <- if (nzchar(axes$x_timezone)) axes$x_timezone else attr(axes, 'tz')
         args <- list()
         if (nzchar(axes$x_date_breaks)) args$date_breaks <- axes$x_date_breaks
         if (nzchar(axes$x_date_labels)) args$date_labels <- axes$x_date_labels
         if (time == 'datetime' && nzchar(axes$x_timezone)) args$timezone <- axes$x_timezone
         limits <- if (limited) .rs.superrstudioTimeCall(call('c', low, high), time, zone)
         if (limited && filter) args$limits <- limits
         if (limited && !filter) zoom$xlim <- limits
         if (length(args))
            layers <- c(layers, as.call(c(call('::', as.name('ggplot2'),
               as.name(if (time == 'date') 'scale_x_date' else 'scale_x_datetime')), args)))
         next
      }
      args <- list()
      if (limited && filter) args$limits <- call('c', low, high)
      if (limited && !filter) zoom[[paste0(axis, 'lim')]] <- call('c', low, high)
      format <- axes[[paste0(axis, '_format')]]
      if (format != 'default')
         args$labels <- switch(format, comma = quote(scales::label_comma()),
                               scientific = quote(scales::label_scientific()),
                               percent = quote(scales::label_percent()))
      log <- axes[[paste0(axis, '_scale')]] == 'log10'
      if (log || length(args))
      {
         name <- paste0('scale_', axis, if (log) '_log10' else '_continuous')
         layers <- c(layers, as.call(c(call('::', as.name('ggplot2'), as.name(name)), args)))
      }
   }
   if (length(zoom)) layers <- c(layers, as.call(c(quote(ggplot2::coord_cartesian), zoom)))
   facet <- function(column) substitute(ggplot2::vars(.data[[C]]), list(C = column))
   if (nzchar(facet_rows))
   {
      args <- list(rows = facet(facet_rows))
      if (nzchar(facet_by)) args$cols <- facet(facet_by)
      if (axes$facet_scales != 'fixed') args$scales <- axes$facet_scales
      layers <- c(layers, as.call(c(quote(ggplot2::facet_grid), args)))
   }
   else if (nzchar(facet_by))
   {
      args <- list(facet(facet_by))
      if (axes$facet_ncol > 0) args$ncol <- axes$facet_ncol
      if (axes$facet_scales != 'fixed') args$scales <- axes$facet_scales
      layers <- c(layers, as.call(c(quote(ggplot2::facet_wrap), args)))
   }
   # after the complete theme, which would otherwise reset them
   grid <- list()
   if (!axes$grid_major) grid$panel.grid.major <- quote(ggplot2::element_blank())
   if (!axes$grid_minor) grid$panel.grid.minor <- quote(ggplot2::element_blank())
   if (length(grid)) layers <- c(layers, as.call(c(quote(ggplot2::theme), grid)))
   layers
})

#' The observations as ggplot2's statistics see them
#'
#' Filtering limits remove observations outside them; log10 scales transform
#' the values (non-positive ones have no logarithm and are dropped), exactly
#' as ggplot2 does before computing fits, boxes, bins and densities. Returns
#' a small frame of the needed columns and notes describing what was removed.
.rs.addFunction('superrstudioStatData', function(data, kind, x, y, columns, axes)
{
   columns <- unique(c(x, y, columns))
   columns <- columns[nzchar(columns)]
   frame <- lapply(columns, function(column) data[[column]])
   names(frame) <- columns
   frame <- structure(frame, class = 'data.frame', row.names = .set_row_names(nrow(data)))
   notes <- character()
   rawX <- nzchar(x) && kind %in% c('scatter', 'histogram', 'density')
   rawY <- nzchar(y) && kind %in% c('scatter', 'boxplot')
   time <- attr(axes, 'time')
   if (is.null(time)) time <- ''
   if (rawX && nzchar(time) && any(is.na(frame[[x]])))
      notes <- c(notes, sprintf('%d observation(s) have no %s and are not drawn.', sum(is.na(frame[[x]])),
                                if (time == 'date') 'date' else 'date-time'))
   if (axes$limits_mode == 'filter')
   {
      keep <- rep(TRUE, nrow(frame))
      inside <- function(column, axis)
      {
         v <- frame[[column]]
         low <- axes[[paste0(axis, '_min')]]
         high <- axes[[paste0(axis, '_max')]]
         if (axis == 'x' && nzchar(time))
         {
            zone <- if (nzchar(axes$x_timezone)) axes$x_timezone else attr(axes, 'tz')
            if (!identical(low, '')) low <- .rs.superrstudioTimeValue(low, time, zone)
            if (!identical(high, '')) high <- .rs.superrstudioTimeValue(high, time, zone)
         }
         (identical(low, '') | is.na(v) | v >= low) & (identical(high, '') | is.na(v) | v <= high)
      }
      if (rawX) keep <- keep & inside(x, 'x')
      if (rawY) keep <- keep & inside(y, 'y')
      if (any(!keep))
         notes <- c(notes, sprintf(paste('Axis limits (filter) remove %d observation(s) before statistics',
                                         'are computed; choose zoom to keep them.'), sum(!keep)))
      frame <- frame[keep, , drop = FALSE]
   }
   for (axis in c('x', 'y'))
   {
      column <- if (axis == 'x') x else y
      if (!(if (axis == 'x') rawX else rawY) || axes[[paste0(axis, '_scale')]] != 'log10') next
      v <- frame[[column]]
      bad <- !is.na(v) & v <= 0
      if (any(bad))
         notes <- c(notes, sprintf(paste('Log scale: %d %s value(s) at or below zero have no logarithm;',
                                         'they are not drawn and are excluded from statistics.'),
                                   sum(bad), toupper(axis)))
      v[bad] <- NA
      frame[[column]] <- log10(v)
      notes <- c(notes, sprintf('%s statistics are computed on the log10 scale, as drawn.', toupper(axis)))
   }
   list(data = frame, notes = unique(notes))
})

.rs.addFunction('superrstudioData', function(operation, dataset = '', revision = '',
                                           x = '', y = '', available = character(),
                                           appearance = list())
{
   state <- .rs.superrstudioState
   # data frames, tibbles (also grouped) and data.tables; other data.frame
   # subclasses (e.g. sf) carry semantics this editor does not handle
   tableFrame <- function(value) is.data.frame(value) &&
      all(class(value) %in% c('data.frame', 'tbl_df', 'tbl', 'grouped_df', 'data.table')) &&
      !anyNA(names(value)) && !anyDuplicated(names(value)) && all(nzchar(names(value)))
   tableKind <- function(value) if (inherits(value, 'data.table')) 'data.table'
      else if (inherits(value, 'tbl_df')) 'tibble' else 'data.frame'
   snapshot <- function(value) if (inherits(value, 'data.table')) serialize(value, NULL, version = 2) else value
   numericColumn <- function(value) (is.double(value) || is.integer(value)) &&
      !is.object(value) && is.null(dim(value))
   # categories: factors, plain character and logical vectors
   discreteColumn <- function(value) is.null(dim(value)) &&
      (is.factor(value) || ((is.character(value) || is.logical(value)) && !is.object(value)))
   # columns that can be mapped to colour: plain numbers or categories
   colourColumn <- function(value) numericColumn(value) || discreteColumn(value)
   # dates and date-times (a continuous X for time series)
   timeColumn <- function(value) is.null(dim(value)) && (inherits(value, 'Date') || inherits(value, 'POSIXct'))
   fail <- function(message) stop(message, call. = FALSE)
   if (operation == 'list')
   {
      state$snapshot <- NULL
      frames <- available[vapply(available, function(name)
         tableFrame(get(name, envir = .GlobalEnv, inherits = FALSE)), logical(1))]
      kinds <- vapply(frames, function(name) tableKind(get(name, envir = .GlobalEnv, inherits = FALSE)), '')
      return(list(datasets = unname(frames), dataset_kinds = unname(kinds)))
   }
   if (operation == 'release')
   {
      # An older dialog must not release another dialog's selection.
      if (identical(revision, state$revision)) state$snapshot <- NULL
      return(list(released = I(TRUE)))
   }
   if (!operation %in% c('inspect', 'code', 'preview', 'render', 'export')) fail('Unsupported operation.')
   if (!dataset %in% available) fail('Dataset no longer exists or is not a data frame. Refresh the selection.')
   data <- get(dataset, envir = .GlobalEnv, inherits = FALSE)
   if (!tableFrame(data))
      fail('Select a data frame, tibble or data.table with unique, nonempty column names.')
   if (nrow(data) > 100000L || as.numeric(object.size(data)) > 16 * 1024^2)
      fail('This experimental preview supports up to 100,000 rows and 16 MiB.')
   current <- snapshot(data)
   columns <- names(data)[vapply(data, numericColumn, logical(1))]
   colourColumns <- names(data)[vapply(data, colourColumn, logical(1))]
   discreteColumns <- names(data)[vapply(data, discreteColumn, logical(1))]
   timeColumns <- names(data)[vapply(data, timeColumn, logical(1))]
   datetimeColumns <- timeColumns[vapply(timeColumns, function(name) inherits(data[[name]], 'POSIXct'), NA)]
   if (operation == 'inspect')
   {
      state$counter <- state$counter + 1L
      state$revision <- as.character(state$counter)
      state$dataset <- dataset
      state$snapshot <- current
      return(list(revision = I(state$revision), columns = unname(columns),
                  colour_columns = unname(colourColumns),
                  discrete_columns = unname(discreteColumns), time_columns = unname(timeColumns),
                  datetime_columns = unname(datetimeColumns), rows = I(nrow(data))))
   }
   if (!identical(revision, state$revision) || !identical(dataset, state$dataset) ||
       !identical(current, state$snapshot))
      fail('Dataset changed after selection. Refresh and select the columns again.')

   # One flat settings object from the dialog: column mappings (data, so they
   # are validated against this dataset), layer options and appearance.
   if (is.null(appearance)) appearance <- list()
   if (!is.list(appearance)) fail('Appearance settings must be named.')
   mappingKeys <- c('colour_by', 'group_by', 'facet_by', 'facet_rows')
   optionKeys <- c('kind', 'geometry', 'line_order', 'fit', 'fit_se', 'fit_level', 'fit_span',
                   'bins', 'bin_width', 'show_outliers', 'show_points', 'bar_position', 'adjust')
   axisKeys <- c('x_scale', 'y_scale', 'x_min', 'x_max', 'y_min', 'y_max', 'limits_mode',
                 'x_format', 'y_format', 'grid_major', 'grid_minor', 'facet_scales', 'facet_ncol',
                 'x_date_breaks', 'x_date_labels', 'x_timezone')
   mapping <- appearance[intersect(names(appearance), mappingKeys)]
   options <- .rs.superrstudioScatterOptions(appearance[intersect(names(appearance), optionKeys)])
   exportKeys <- c('export_path', 'export_format', 'export_width', 'export_height',
                   'export_units', 'export_dpi', 'export_mode')
   axes <- appearance[intersect(names(appearance), axisKeys)]
   export <- appearance[intersect(names(appearance), exportKeys)]
   appearance <- .rs.superrstudioScatterAppearance(
      appearance[setdiff(names(appearance), c(mappingKeys, optionKeys, axisKeys, exportKeys))])
   canvas <- c(appearance$canvas_width, appearance$canvas_height)
   export <- if (operation == 'export') .rs.superrstudioExportOptions(export, canvas)
   column <- function(value, allowed, message)
   {
      if (is.null(value)) return('')
      if (!.rs.superrstudioIsText(value) || !(value == '' || value %in% allowed)) fail(message)
      value
   }
   colourBy <- column(mapping$colour_by, colourColumns,
                      'Select a numeric, character, factor or logical column to colour by.')
   groupBy <- column(mapping$group_by, discreteColumns,
                     'Group lines by a character, factor or logical column.')
   facetBy <- column(mapping$facet_by, discreteColumns,
                     'Facet by a character, factor or logical column.')
   facetRows <- column(mapping$facet_rows, discreteColumns,
                       'Facet rows by a character, factor or logical column.')
   if (nzchar(facetBy) && identical(facetBy, facetRows))
      fail('Facet rows and columns must use different columns.')
   kind <- options$kind
   time <- if (!x %in% timeColumns) '' else if (x %in% datetimeColumns) 'datetime' else 'date'
   zone <- if (time == 'datetime' && !is.null(attr(data[[x]], 'tzone'))) attr(data[[x]], 'tzone')[[1L]] else ''
   axes <- .rs.superrstudioAxisOptions(axes, kind, time, zone)
   facets <- c(facetBy, facetRows)
   if (kind == 'scatter' && (!x %in% c(columns, timeColumns) || !y %in% columns))
      fail('Select two ordinary numeric columns (X may also be a date or date-time).')
   if (kind == 'histogram' && (!x %in% columns || nzchar(y)))
      fail('A histogram needs one ordinary numeric column (X) and no Y column.')
   if (kind == 'boxplot' && (!y %in% columns || !(x == '' || x %in% discreteColumns)))
      fail('A boxplot needs a numeric response (Y) and optionally a character, factor or logical group (X).')
   if (kind == 'bar' && (!x %in% discreteColumns || nzchar(y)))
      fail('A bar chart counts one character, factor or logical column (X) and has no Y column.')
   if (kind == 'density' && (!x %in% columns || nzchar(y)))
      fail('A density plot needs one ordinary numeric column (X) and no Y column.')
   # invalid selections are reported first, whatever packages are installed
   if (!requireNamespace('ggplot2', quietly = TRUE))
      fail('ggplot2 is required in the active R library. Install it explicitly, then retry.')
   if (kind != 'scatter')
   {
      if (nzchar(groupBy)) fail('Grouping lines applies to scatter plots only.')
      if (nzchar(colourBy) && !colourBy %in% discreteColumns)
         fail('Fill by a character, factor or logical column.')
      if (nzchar(colourBy) && nzchar(appearance$fill))
         fail('Choose either a fixed fill colour or a fill column, not both.')
      return(.rs.superrstudioPlotResult(operation, kind, dataset, data, x, y, colourBy, options,
                                        appearance, axes, facetBy, facetRows, export))
   }
   if (nzchar(colourBy) && nzchar(appearance$colour))
      fail('Choose either a fixed point colour or a colour column, not both.')
   lines <- options$geometry != 'points'
   if (nzchar(groupBy) && !lines && options$fit == 'none')
      fail('Grouping applies to connected lines and fits; choose lines or a fit, or clear the group.')
   discrete <- !nzchar(colourBy) || !colourBy %in% columns

   # Build language objects, never parse concatenated names or executable text.
   # The displayed code joins the deparsed layers; the evaluated expression is
   # the same left-associated sum that R parses from that text.
   layers <- c(.rs.superrstudioScatterLayers(dataset, x, y, appearance, colourBy, discrete,
                                             options, groupBy),
               .rs.superrstudioAxisLayers(axes, facetBy, facetRows))
   expression <- Reduce(function(lhs, rhs) call('+', lhs, rhs), layers)
   code <- paste(vapply(layers, function(layer)
      paste(deparse(layer, width.cutoff = 90L, backtick = TRUE), collapse = '\n'), ''),
      collapse = ' +\n  ')

   # Fits follow ggplot2's grouping: discrete colour and explicit groups.
   fitGroups <- c(if (nzchar(colourBy) && discrete) colourBy, if (nzchar(groupBy)) groupBy)
   # Facets fit each panel separately.
   fitGroups <- unique(c(fitGroups, facets[nzchar(facets)]))
   stat <- .rs.superrstudioStatData(data, 'scatter', x, y, fitGroups, axes)
   name <- function(column, axis) if (axes[[paste0(axis, '_scale')]] == 'log10')
      paste0('log10(', column, ')')
      else if (axis == 'x' && time == 'date') paste0(column, ' [days since 1970-01-01]')
      else if (axis == 'x' && time == 'datetime') paste0(column, ' [seconds since 1970-01-01 UTC]')
      else column
   fitSummary <- if (options$fit != 'none')
      .rs.superrstudioFitSummary(stat$data, x, y, options$fit, fitGroups, options$fit_span,
                                 name(x, 'x'), name(y, 'y'))
   modelCode <- if (options$fit == 'lm') .rs.superrstudioFitCode(dataset, x, y, fitGroups, axes) else ''

   rendered <- .rs.superrstudioRender(operation, expression, dataset, data, export,
                                      c(appearance$canvas_width, appearance$canvas_height))
   # The revision is a session-scoped staleness token, not part of the
   # reproducible specification: the same selection yields the same record.
   list(code = I(paste0(code, '\n')), model_code = I(modelCode),
        export_code = I(.rs.superrstudioExportCode(code, export)), saved = rendered$saved,
        fit_summary = if (is.null(fitSummary)) list() else fitSummary,
        notes = if (options$fit != 'none') stat$notes
                else grep('statistics are computed', stat$notes, value = TRUE, invert = TRUE, fixed = TRUE),
        warnings = rendered$warnings, interactive = rendered$interactive,
        spec = list(schema_version = I(6L), kind = I('scatter'), dataset = I(dataset),
                    x = I(x), y = I(y), colour_by = I(colourBy), group_by = I(groupBy),
                    facet_by = I(facetBy), facet_rows = I(facetRows),
                    layers = lapply(options[.rs.superrstudioKindOptions('scatter')], I),
                    appearance = lapply(appearance, I), axes = lapply(axes, I)),
        r_version = I(as.character(getRversion())),
        ggplot2_version = I(as.character(utils::packageVersion('ggplot2'))))
})

#' Script that recreates the plot and writes the exported file
.rs.addFunction('superrstudioExportCode', function(code, export)
{
   if (is.null(export)) return('')
   paste0('plot <- ', code, '\n',
          paste(deparse(.rs.superrstudioExportCall(export), width.cutoff = 90L), collapse = '\n'), '\n')
})

#' Layer options that apply to each plot kind (recorded in the specification)
.rs.addFunction('superrstudioKindOptions', function(kind)
{
   switch(kind,
          scatter = c('kind', 'geometry', 'line_order', 'fit', 'fit_se', 'fit_level', 'fit_span'),
          histogram = c('kind', 'bins', 'bin_width'),
          boxplot = c('kind', 'show_outliers', 'show_points'),
          bar = c('kind', 'bar_position'),
          density = c('kind', 'adjust'))
})

#' Code, preview and summary for the histogram and boxplot kinds
.rs.addFunction('superrstudioPlotResult', function(operation, kind, dataset, data, x, y, fill_by,
                                                 options, appearance, axes = .rs.superrstudioAxisOptions(),
                                                 facet_by = '', facet_rows = '', export = NULL)
{
   layers <- c(switch(kind,
      histogram = .rs.superrstudioHistogramLayers(dataset, x, appearance, options, fill_by),
      boxplot = .rs.superrstudioBoxplotLayers(dataset, x, y, appearance, options, fill_by),
      bar = .rs.superrstudioBarLayers(dataset, x, appearance, options, fill_by),
      density = .rs.superrstudioDensityLayers(dataset, x, appearance, options, fill_by)),
      .rs.superrstudioAxisLayers(axes, facet_by, facet_rows))
   facets <- c(facet_by, facet_rows)
   facets <- facets[nzchar(facets)]
   stat <- .rs.superrstudioStatData(data, kind, x, y, c(fill_by, facets), axes)
   expression <- Reduce(function(lhs, rhs) call('+', lhs, rhs), layers)
   code <- paste(vapply(layers, function(layer)
      paste(deparse(layer, width.cutoff = 90L, backtick = TRUE), collapse = '\n'), ''),
      collapse = ' +\n  ')
   summary <- if (kind == 'histogram')
   {
      v <- stat$data[[x]]
      # exactly one of bins / bin_width is reported, matching the emitted code
      list(Filter(Negate(is.null), list(
         n = I(sum(is.finite(v))), removed = I(nrow(data) - sum(is.finite(v))),
         bins = if (options$bin_width == 0) I(options$bins),
         bin_width = if (options$bin_width > 0) I(options$bin_width))))
   }
   else if (kind == 'boxplot') .rs.superrstudioBoxSummary(stat$data, c(x, facets), y)
   else if (kind == 'bar')
   {
      # one bar per category, NA included as ggplot2 draws it
      counts <- table(.rs.superrstudioGroupKey(stat$data, c(x, facets)))
      lapply(names(counts), function(name) list(group = I(name), n = I(as.integer(counts[[name]]))))
   }
   else
   {
      # bandwidth as stats::density(bw = "nrd0", adjust) uses it; ggplot2
      # drops groups with fewer than two finite values
      values <- split(stat$data[[x]], .rs.superrstudioGroupKey(stat$data, c(fill_by, facets)), drop = TRUE)
      lapply(names(values), function(name)
      {
         v <- values[[name]]
         v <- v[is.finite(v)]
         if (length(v) < 2L) return(list(group = I(name), n = I(length(v))))
         list(group = I(name), n = I(length(v)), bandwidth = I(stats::bw.nrd0(v) * options$adjust))
      })
   }
   rendered <- .rs.superrstudioRender(operation, expression, dataset, data, export,
                                      c(appearance$canvas_width, appearance$canvas_height))
   list(code = I(paste0(code, '\n')), model_code = I(''),
        export_code = I(.rs.superrstudioExportCode(code, export)), saved = rendered$saved,
        fit_summary = list(), summary = summary, notes = stat$notes,
        warnings = rendered$warnings, interactive = rendered$interactive,
        spec = list(schema_version = I(6L), kind = I(kind), dataset = I(dataset),
                    x = I(x), y = I(y), fill_by = I(fill_by),
                    facet_by = I(facet_by), facet_rows = I(facet_rows),
                    layers = lapply(options[.rs.superrstudioKindOptions(kind)], I),
                    appearance = lapply(appearance, I), axes = lapply(axes, I)),
        r_version = I(as.character(getRversion())),
        ggplot2_version = I(as.character(utils::packageVersion('ggplot2'))))
})
