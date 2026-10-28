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

.rs.addFunction('superrstudioData', function(operation, dataset = '', revision = '',
                                           x = '', y = '', available = character())
{
   state <- .rs.superrstudioState
   plainFrame <- function(value) identical(class(value), 'data.frame') &&
      !anyNA(names(value)) && !anyDuplicated(names(value)) && all(nzchar(names(value)))
   numericColumn <- function(value) (is.double(value) || is.integer(value)) &&
      !is.object(value) && is.null(dim(value))
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
   if (operation == 'inspect')
   {
      state$counter <- state$counter + 1L
      state$revision <- as.character(state$counter)
      state$dataset <- dataset
      state$snapshot <- bytes
      return(list(revision = I(state$revision), columns = unname(columns), rows = I(nrow(data))))
   }
   if (!identical(revision, state$revision) || !identical(dataset, state$dataset) ||
       !identical(bytes, state$snapshot))
      fail('Dataset changed after selection. Refresh and select the columns again.')
   if (!x %in% columns || !y %in% columns) fail('Select two ordinary numeric columns.')
   if (!requireNamespace('ggplot2', quietly = TRUE))
      fail('ggplot2 is required in the active R library. Install it explicitly, then retry.')

   # Build language objects, never parse concatenated names or executable text.
   expression <- substitute(ggplot2::ggplot(DATA,
      ggplot2::aes(x = .data[[X]], y = .data[[Y]])) + ggplot2::geom_point(),
      list(DATA = as.name(dataset), X = x, Y = y))
   code <- paste(deparse(expression, width.cutoff = 90L, backtick = TRUE), collapse = '\n')
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
        spec = list(schema_version = I(1L), kind = I('scatter'), dataset = I(dataset),
                    x = I(x), y = I(y)),
        r_version = I(as.character(getRversion())),
        ggplot2_version = I(as.character(utils::packageVersion('ggplot2'))))
})
