# SuperRStudio experimental visual workflow. SPDX-License-Identifier: AGPL-3.0-only
# One bounded validation snapshot per session; never used as the plot's data.
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
                    line_colour = '', line_width = 0.5, line_type = 'solid', fit_colour = '')
   result <- .rs.superrstudioSettings(appearance, defaults, 'Appearance')
   for (field in c('title', 'x_label', 'y_label'))
      if (!.rs.superrstudioIsText(result[[field]]) || nchar(result[[field]]) > 200L)
         fail('Titles and axis labels must be text of at most 200 characters.')
   if (!.rs.superrstudioIsColour(result$colour)) fail('Point colour must be an R colour name or #RRGGBB.')
   if (!.rs.superrstudioIsColour(result$line_colour)) fail('Line colour must be an R colour name or #RRGGBB.')
   if (!.rs.superrstudioIsColour(result$fit_colour)) fail('Fit colour must be an R colour name or #RRGGBB.')
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
   defaults <- list(geometry = 'points', line_order = 'x', fit = 'none',
                    fit_se = TRUE, fit_level = 0.95, fit_span = 0.75)
   result <- .rs.superrstudioSettings(options, defaults, 'Layer')
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
   result[names(defaults)]
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
   labels <- list()
   if (nzchar(appearance$title)) labels$title <- appearance$title
   if (nzchar(appearance$x_label)) labels$x <- appearance$x_label
   if (nzchar(appearance$y_label)) labels$y <- appearance$y_label
   if (length(labels)) layers <- c(layers, as.call(c(quote(ggplot2::labs), labels)))
   if (appearance$theme != 'grey')
      layers <- c(layers, as.call(list(call('::', as.name('ggplot2'),
                                             as.name(paste0('theme_', appearance$theme))))))
   layers
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
   plainFrame <- function(value) identical(class(value), 'data.frame') &&
      !anyNA(names(value)) && !anyDuplicated(names(value)) && all(nzchar(names(value)))
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
         plainFrame(get(name, envir = .GlobalEnv, inherits = FALSE)), logical(1))]
      return(list(datasets = unname(frames)))
   }
   if (operation == 'release')
   {
      # An older dialog must not release another dialog's selection.
      if (identical(revision, state$revision)) state$snapshot <- NULL
      return(list(released = I(TRUE)))
   }
   if (!operation %in% c('inspect', 'code', 'preview')) fail('Unsupported operation.')
   if (!dataset %in% available) fail('Dataset no longer exists or is not an ordinary data frame. Refresh the selection.')
   data <- get(dataset, envir = .GlobalEnv, inherits = FALSE)
   if (!plainFrame(data)) fail('Select a plain data frame with unique, nonempty column names.')
   if (nrow(data) > 100000L || as.numeric(object.size(data)) > 16 * 1024^2)
      fail('This experimental preview supports up to 100,000 rows and 16 MiB.')
   bytes <- serialize(data, NULL, version = 2)
   if (length(bytes) > 16 * 1024^2) fail('The serialized dataset exceeds the 16 MiB preview limit.')
   columns <- names(data)[vapply(data, numericColumn, logical(1))]
   colourColumns <- names(data)[vapply(data, colourColumn, logical(1))]
   discreteColumns <- names(data)[vapply(data, discreteColumn, logical(1))]
   if (operation == 'inspect')
   {
      state$counter <- state$counter + 1L
      state$revision <- as.character(state$counter)
      state$dataset <- dataset
      state$snapshot <- bytes
      return(list(revision = I(state$revision), columns = unname(columns),
                  colour_columns = unname(colourColumns),
                  discrete_columns = unname(discreteColumns), rows = I(nrow(data))))
   }
   if (!identical(revision, state$revision) || !identical(dataset, state$dataset) ||
       !identical(bytes, state$snapshot))
      fail('Dataset changed after selection. Refresh and select the columns again.')
   if (!x %in% columns || !y %in% columns) fail('Select two ordinary numeric columns.')
   if (!requireNamespace('ggplot2', quietly = TRUE))
      fail('ggplot2 is required in the active R library. Install it explicitly, then retry.')

   # One flat settings object from the dialog: column mappings (data, so they
   # are validated against this dataset), layer options and appearance.
   if (is.null(appearance)) appearance <- list()
   if (!is.list(appearance)) fail('Appearance settings must be named.')
   mappingKeys <- c('colour_by', 'group_by')
   optionKeys <- c('geometry', 'line_order', 'fit', 'fit_se', 'fit_level', 'fit_span')
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
                    layers = lapply(options, I), appearance = lapply(appearance, I)),
        r_version = I(as.character(getRversion())),
        ggplot2_version = I(as.character(utils::packageVersion('ggplot2'))))
})
