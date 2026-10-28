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
.rs.addFunction('superrstudioDataRpc', function(...)
{
   tryCatch(.rs.superrstudioData(...),
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
                    fill = '')
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
   for (field in c('size', 'alpha', 'line_width')) result[[field]] <- as.numeric(result[[field]])
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
                    bins = 30, bin_width = 0, show_outliers = TRUE, show_points = FALSE)
   result <- .rs.superrstudioSettings(options, defaults, 'Layer')
   flag <- function(value) is.logical(value) && length(value) == 1L && !is.na(value)
   if (!.rs.superrstudioIsText(result$kind) || !result$kind %in% c('scatter', 'histogram', 'boxplot'))
      fail('Plot type must be scatter, histogram or boxplot.')
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
   layers
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

#' Box statistics exactly as ggplot2's stat_boxplot() computes them:
#' quantile(type = 7) quartiles, outliers beyond 1.5 IQR, and whiskers spanning
#' range(c(quartiles, non-outlying values)).
.rs.addFunction('superrstudioBoxSummary', function(data, group, y)
{
   key <- if (nzchar(group)) {
      value <- as.character(data[[group]])
      value[is.na(value)] <- 'NA'
      factor(value)
   } else factor(rep('all', nrow(data)))
   values <- split(data[[y]], key, drop = TRUE)
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
                                                 span = 0.75)
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
      equation <- sprintf('%s = %s %s %s * %s', y, format(signif(intercept, 4L)),
                          if (slope < 0) '-' else '+', format(signif(abs(slope), 4L)), x)
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
.rs.addFunction('superrstudioFitCode', function(dataset, x, y, groups = character())
{
   frame <- substitute(data.frame(x = DATA[[X]], y = DATA[[Y]]),
                       list(DATA = as.name(dataset), X = x, Y = y))
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
           '# independence, constant variance and residual normality before inference.',
           deparse(call, width.cutoff = 90L, backtick = TRUE)), collapse = '\n')
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
   if (!operation %in% c('inspect', 'code', 'preview')) fail('Unsupported operation.')
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
   if (operation == 'inspect')
   {
      state$counter <- state$counter + 1L
      state$revision <- as.character(state$counter)
      state$dataset <- dataset
      state$snapshot <- current
      return(list(revision = I(state$revision), columns = unname(columns),
                  colour_columns = unname(colourColumns),
                  discrete_columns = unname(discreteColumns), rows = I(nrow(data))))
   }
   if (!identical(revision, state$revision) || !identical(dataset, state$dataset) ||
       !identical(current, state$snapshot))
      fail('Dataset changed after selection. Refresh and select the columns again.')

   # One flat settings object from the dialog: column mappings (data, so they
   # are validated against this dataset), layer options and appearance.
   if (is.null(appearance)) appearance <- list()
   if (!is.list(appearance)) fail('Appearance settings must be named.')
   mappingKeys <- c('colour_by', 'group_by')
   optionKeys <- c('kind', 'geometry', 'line_order', 'fit', 'fit_se', 'fit_level', 'fit_span',
                   'bins', 'bin_width', 'show_outliers', 'show_points')
   mapping <- appearance[intersect(names(appearance), mappingKeys)]
   options <- .rs.superrstudioScatterOptions(appearance[intersect(names(appearance), optionKeys)])
   appearance <- .rs.superrstudioScatterAppearance(appearance[setdiff(names(appearance), c(mappingKeys, optionKeys))])
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
   kind <- options$kind
   if (kind == 'scatter' && (!x %in% columns || !y %in% columns))
      fail('Select two ordinary numeric columns.')
   if (kind == 'histogram' && (!x %in% columns || nzchar(y)))
      fail('A histogram needs one ordinary numeric column (X) and no Y column.')
   if (kind == 'boxplot' && (!y %in% columns || !(x == '' || x %in% discreteColumns)))
      fail('A boxplot needs a numeric response (Y) and optionally a character, factor or logical group (X).')
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
      return(.rs.superrstudioPlotResult(operation, kind, dataset, data, x, y, colourBy, options, appearance))
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
   layers <- .rs.superrstudioScatterLayers(dataset, x, y, appearance, colourBy, discrete,
                                           options, groupBy)
   expression <- Reduce(function(lhs, rhs) call('+', lhs, rhs), layers)
   code <- paste(vapply(layers, function(layer)
      paste(deparse(layer, width.cutoff = 90L, backtick = TRUE), collapse = '\n'), ''),
      collapse = ' +\n  ')

   # Fits follow ggplot2's grouping: discrete colour and explicit groups.
   fitGroups <- c(if (nzchar(colourBy) && discrete) colourBy, if (nzchar(groupBy)) groupBy)
   fitGroups <- unique(fitGroups)
   fitSummary <- if (options$fit != 'none')
      .rs.superrstudioFitSummary(data, x, y, options$fit, fitGroups, options$fit_span)
   modelCode <- if (options$fit == 'lm') .rs.superrstudioFitCode(dataset, x, y, fitGroups) else ''

   warnings <- character()
   if (operation == 'preview')
   {
      withCallingHandlers({
         # Resolve exactly the current object in a private evaluation frame.
         # The user's objects and search path are not assigned or attached to.
         env <- new.env(parent = baseenv())
         assign(dataset, data, envir = env)
         print(eval(expression, envir = env))
      }, warning = function(w) {
         warnings <<- c(warnings, conditionMessage(w))
         invokeRestart('muffleWarning')
      })
   }
   # The revision is a session-scoped staleness token, not part of the
   # reproducible specification: the same selection yields the same record.
   list(code = I(paste0(code, '\n')), model_code = I(modelCode),
        fit_summary = if (is.null(fitSummary)) list() else fitSummary,
        warnings = unname(warnings),
        spec = list(schema_version = I(3L), kind = I('scatter'), dataset = I(dataset),
                    x = I(x), y = I(y), colour_by = I(colourBy), group_by = I(groupBy),
                    layers = lapply(options[.rs.superrstudioKindOptions('scatter')], I),
                    appearance = lapply(appearance, I)),
        r_version = I(as.character(getRversion())),
        ggplot2_version = I(as.character(utils::packageVersion('ggplot2'))))
})

#' Layer options that apply to each plot kind (recorded in the specification)
.rs.addFunction('superrstudioKindOptions', function(kind)
{
   switch(kind,
          scatter = c('kind', 'geometry', 'line_order', 'fit', 'fit_se', 'fit_level', 'fit_span'),
          histogram = c('kind', 'bins', 'bin_width'),
          boxplot = c('kind', 'show_outliers', 'show_points'))
})

#' Code, preview and summary for the histogram and boxplot kinds
.rs.addFunction('superrstudioPlotResult', function(operation, kind, dataset, data, x, y, fill_by,
                                                 options, appearance)
{
   layers <- if (kind == 'histogram')
      .rs.superrstudioHistogramLayers(dataset, x, appearance, options, fill_by)
   else
      .rs.superrstudioBoxplotLayers(dataset, x, y, appearance, options, fill_by)
   expression <- Reduce(function(lhs, rhs) call('+', lhs, rhs), layers)
   code <- paste(vapply(layers, function(layer)
      paste(deparse(layer, width.cutoff = 90L, backtick = TRUE), collapse = '\n'), ''),
      collapse = ' +\n  ')
   summary <- if (kind == 'histogram')
   {
      v <- data[[x]]
      # exactly one of bins / bin_width is reported, matching the emitted code
      list(Filter(Negate(is.null), list(
         n = I(sum(is.finite(v))), removed = I(sum(!is.finite(v))),
         bins = if (options$bin_width == 0) I(options$bins),
         bin_width = if (options$bin_width > 0) I(options$bin_width))))
   }
   else .rs.superrstudioBoxSummary(data, x, y)
   warnings <- character()
   if (operation == 'preview')
   {
      withCallingHandlers({
         env <- new.env(parent = baseenv())
         assign(dataset, data, envir = env)
         print(eval(expression, envir = env))
      }, warning = function(w) {
         warnings <<- c(warnings, conditionMessage(w))
         invokeRestart('muffleWarning')
      })
   }
   list(code = I(paste0(code, '\n')), model_code = I(''),
        fit_summary = list(), summary = summary,
        warnings = unname(warnings),
        spec = list(schema_version = I(3L), kind = I(kind), dataset = I(dataset),
                    x = I(x), y = I(y), fill_by = I(fill_by),
                    layers = lapply(options[.rs.superrstudioKindOptions(kind)], I),
                    appearance = lapply(appearance, I)),
        r_version = I(as.character(getRversion())),
        ggplot2_version = I(as.character(utils::packageVersion('ggplot2'))))
})
