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

#' Validate scatter appearance settings
#'
#' Returns the complete, normalized appearance (defaults filled in) or stops
#' with a message for the user. Text is only ever embedded as R strings.
#'
#' @param appearance A named list (from the dialog's JSON object).
.rs.addFunction('superrstudioScatterAppearance', function(appearance = list())
{
   fail <- function(message) stop(message, call. = FALSE)
   defaults <- list(title = '', x_label = '', y_label = '', colour = '',
                    size = 1.5, alpha = 1, theme = 'grey')
   if (is.null(appearance)) appearance <- list()
   if (!is.list(appearance) || (length(appearance) && is.null(names(appearance))))
      fail('Appearance settings must be named.')
   unknown <- setdiff(names(appearance), names(defaults))
   if (length(unknown)) fail(paste0('Unknown appearance setting: ', unknown[[1L]], '.'))
   result <- utils::modifyList(defaults, appearance)

   text <- function(value) is.character(value) && length(value) == 1L && !is.na(value)
   number <- function(value, low, high) is.numeric(value) && length(value) == 1L &&
      is.finite(value) && value >= low && value <= high
   for (field in c('title', 'x_label', 'y_label'))
      if (!text(result[[field]]) || nchar(result[[field]]) > 200L)
         fail('Titles and axis labels must be text of at most 200 characters.')
   if (!text(result$colour) || !(result$colour == '' ||
       result$colour %in% grDevices::colors() || grepl('^#[0-9A-Fa-f]{6}$', result$colour)))
      fail('Point colour must be an R colour name or #RRGGBB.')
   if (!number(result$size, 0.5, 10)) fail('Point size must be between 0.5 and 10.')
   if (!number(result$alpha, 0.05, 1)) fail('Point opacity must be between 0.05 and 1.')
   if (!text(result$theme) || !result$theme %in% c('grey', 'bw', 'minimal', 'classic', 'light'))
      fail('Unsupported theme.')
   result$size <- as.numeric(result$size)
   result$alpha <- as.numeric(result$alpha)
   result[names(defaults)]
})

#' Build the scatter plot as ggplot2 layers (language objects)
#'
#' Only settings that differ from ggplot2's defaults are emitted. A colour
#' column is mapped inside aes() with a colour-blind-safe viridis scale
#' (discrete or continuous according to the column).
.rs.addFunction('superrstudioScatterLayers', function(dataset, x, y, appearance,
                                                    colour_by = '', discrete = TRUE)
{
   mapping <- if (nzchar(colour_by))
      substitute(ggplot2::aes(x = .data[[X]], y = .data[[Y]], colour = .data[[C]]),
                 list(X = x, Y = y, C = colour_by))
   else
      substitute(ggplot2::aes(x = .data[[X]], y = .data[[Y]]), list(X = x, Y = y))
   layers <- list(substitute(ggplot2::ggplot(DATA, MAPPING),
                             list(DATA = as.name(dataset), MAPPING = mapping)))
   point <- list()
   if (nzchar(appearance$colour)) point$colour <- appearance$colour
   if (appearance$size != 1.5) point$size <- appearance$size
   if (appearance$alpha != 1) point$alpha <- appearance$alpha
   layers <- c(layers, as.call(c(quote(ggplot2::geom_point), point)))
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

.rs.addFunction('superrstudioData', function(operation, dataset = '', revision = '',
                                           x = '', y = '', available = character(),
                                           appearance = list())
{
   state <- .rs.superrstudioState
   plainFrame <- function(value) identical(class(value), 'data.frame') &&
      !anyNA(names(value)) && !anyDuplicated(names(value)) && all(nzchar(names(value)))
   numericColumn <- function(value) (is.double(value) || is.integer(value)) &&
      !is.object(value) && is.null(dim(value))
   # columns that can be mapped to colour: plain numbers or categories
   colourColumn <- function(value) numericColumn(value) || (is.null(dim(value)) &&
      (is.factor(value) || ((is.character(value) || is.logical(value)) && !is.object(value))))
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
   if (operation == 'inspect')
   {
      state$counter <- state$counter + 1L
      state$revision <- as.character(state$counter)
      state$dataset <- dataset
      state$snapshot <- bytes
      return(list(revision = I(state$revision), columns = unname(columns),
                  colour_columns = unname(colourColumns), rows = I(nrow(data))))
   }
   if (!identical(revision, state$revision) || !identical(dataset, state$dataset) ||
       !identical(bytes, state$snapshot))
      fail('Dataset changed after selection. Refresh and select the columns again.')
   if (!x %in% columns || !y %in% columns) fail('Select two ordinary numeric columns.')
   if (!requireNamespace('ggplot2', quietly = TRUE))
      fail('ggplot2 is required in the active R library. Install it explicitly, then retry.')

   # The colour mapping travels with the appearance object but is data, so it
   # is validated against this dataset's columns here.
   colourBy <- if (is.list(appearance) && !is.null(appearance$colour_by)) appearance$colour_by else ''
   if (is.list(appearance)) appearance$colour_by <- NULL
   if (!is.character(colourBy) || length(colourBy) != 1L || is.na(colourBy) ||
       !(colourBy == '' || colourBy %in% colourColumns))
      fail('Select a numeric, character, factor or logical column to colour by.')
   appearance <- .rs.superrstudioScatterAppearance(appearance)
   if (nzchar(colourBy) && nzchar(appearance$colour))
      fail('Choose either a fixed point colour or a colour column, not both.')

   # Build language objects, never parse concatenated names or executable text.
   # The displayed code joins the deparsed layers; the evaluated expression is
   # the same left-associated sum that R parses from that text.
   layers <- .rs.superrstudioScatterLayers(dataset, x, y, appearance, colourBy,
                                           discrete = !nzchar(colourBy) || !colourBy %in% columns)
   expression <- Reduce(function(lhs, rhs) call('+', lhs, rhs), layers)
   code <- paste(vapply(layers, function(layer)
      paste(deparse(layer, width.cutoff = 90L, backtick = TRUE), collapse = '\n'), ''),
      collapse = ' +\n  ')
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
   list(code = I(paste0(code, '\n')), warnings = unname(warnings),
        spec = list(schema_version = I(2L), kind = I('scatter'), dataset = I(dataset),
                    x = I(x), y = I(y), colour_by = I(colourBy),
                    appearance = lapply(appearance, I)),
        r_version = I(as.character(getRversion())),
        ggplot2_version = I(as.character(utils::packageVersion('ggplot2'))))
})
