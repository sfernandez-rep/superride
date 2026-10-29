# SuperRStudio length-frequency mortality (TropFishR catch curves). SPDX-License-Identifier: AGPL-3.0-only
#
# Total mortality Z from the prepared length-frequency data with TropFishR's
# length-converted catch curve (Pauly) or cumulative catch curve (Jones and
# van Zalinge), optionally natural mortality M from M_empirical() and the
# derived F = Z - M and E = F / Z. Everything is computed by TropFishR; this
# file only builds explicit, reproducible calls and reports diagnostics. The
# diagnostics describe the regression; they do not declare an estimate
# reliable.

#' The natural mortality call chosen in the dialog
#'
#' @param s Validated settings (m_method and its inputs).
#' @param linf,k Growth parameters for the growth-based methods.
#' @param number The caller's validating reader of numeric settings.
#' @return An assignment `M <- ...` (TropFishR::M_empirical() or the value
#'   entered), or NULL when no M was requested.
.rs.addFunction('superrstudioLfqNaturalMortalityCall', function(s, linf, k, number)
{
   switch(s$m_method,
      none = NULL,
      then_growth = substitute(M <- as.numeric(TropFishR::M_empirical(Linf = L, K_l = K, method = 'Then_growth')),
                               list(L = linf, K = k)),
      pauly_linf = substitute(M <- as.numeric(TropFishR::M_empirical(Linf = L, K_l = K, temp = T, schooling = S,
                                                                    method = 'Pauly_Linf')),
                              list(L = linf, K = k, T = number('m_temp', -5, 40, 'Mean water temperature (C)'),
                                   S = s$m_schooling)),
      then_tmax = substitute(M <- as.numeric(TropFishR::M_empirical(tmax = A, method = 'Then_tmax')),
                             list(A = number('m_tmax', 0.1, 300, 'Maximum age (years)'))),
      manual = substitute(M <- V, list(V = number('m_value', 0, 10, 'Natural mortality M'))),
      stop('Unknown natural mortality method.', call. = FALSE))
})

#' Catch-curve analysis of the prepared LFQ
#'
#' @param data,dataset The data frame the LFQ was prepared from (staleness).
#' @param settings Dialog settings: cc_linf, cc_k (growth), optional cc_c and
#'   cc_ts (seasonal growth), cc_year ('' for all sampling dates), cc_plus
#'   ('linf', 'none' or 'value' with cc_plus_value), cc_method ('pauly' or
#'   'cumulative'), cc_first and cc_last (regression points, '' for
#'   TropFishR's automatic choice), cc_ogive, m_method and its inputs.
.rs.addFunction('superrstudioLfqMortality', function(data, dataset, settings)
{
   fail <- function(message) stop(message, call. = FALSE)
   prepared <- .rs.superrstudioLfqPrepared(data, dataset)
   s <- .rs.superrstudioLfqSettings(settings)
   number <- function(key, low, high, label, optional = FALSE)
   {
      value <- s[[key]]
      if (identical(value, '') && optional) return(NULL)
      if (is.character(value)) value <- suppressWarnings(as.numeric(value))
      if (!.rs.superrstudioIsNumber(value, low, high))
         fail(sprintf('%s must be a number between %s and %s.', label, format(low), format(high)))
      as.numeric(value)
   }
   linf <- number('cc_linf', 0.01, 1e5, 'Linf (cm)')
   k <- number('cc_k', 1e-4, 50, 'K (1/year)')
   seasonalC <- number('cc_c', 0, 1, 'C', optional = TRUE)
   seasonalTs <- number('cc_ts', 0, 1, 'ts', optional = TRUE)
   if (xor(is.null(seasonalC), is.null(seasonalTs))) fail('Seasonal growth needs both C and ts (or neither).')
   lfq <- prepared$lfq
   years <- unique(format(lfq$dates, '%Y'))
   if (nzchar(s$cc_year) && !s$cc_year %in% years)
      fail(sprintf('The prepared data have no samples in %s.', s$cc_year))
   if (!s$cc_method %in% c('pauly', 'cumulative'))
      fail('Choose the length-converted or the cumulative catch curve.')
   if (s$cc_ogive && s$cc_method == 'cumulative')
      fail('TropFishR estimates the selection ogive only with the length-converted catch curve.')
   if (!s$cc_plus %in% c('linf', 'none', 'value')) fail('Unknown plus group option.')
   mids <- lfq$midLengths
   plus <- switch(s$cc_plus, linf = 'Linf', none = NULL, value = {
      value <- number('cc_plus_value', 0, 1e5, 'Plus group')
      if (!any(abs(mids - value) < 1e-8))
         fail(sprintf('The plus group must be a length class midpoint, for example %s.',
                      paste(utils::head(format(mids[mids >= value]), 3L), collapse = ', ')))
      mids[abs(mids - value) < 1e-8][[1L]]
   })

   # growth parameters travel in par (t0 = 0: ages are relative, which does
   # not change the slope); catchCurve() applies C and ts only when they are
   # also elements of the data list
   par <- list(Linf = linf, K = k, t0 = 0)
   if (!is.null(seasonalC)) par <- c(par, list(C = seasonalC, ts = seasonalTs))
   modifyCall <- as.call(c(quote(TropFishR::lfqModify), list(quote(lfq), par = as.call(c(quote(list), par))),
                           if (nzchar(s$cc_year)) list(years = s$cc_year),
                           if (!is.null(plus)) list(plus_group = plus)))
   steps <- list(call('<-', quote(lfq_cc), modifyCall))
   if (!is.null(seasonalC))
      steps <- c(steps, list(quote(lfq_cc[c('C', 'ts')] <- lfq_cc$par[c('C', 'ts')])))
   env <- new.env(parent = baseenv())
   env$lfq <- lfq
   warnings <- character()
   collect <- function(expr) withCallingHandlers(expr, warning = function(w) {
      warnings <<- c(warnings, conditionMessage(w))
      invokeRestart('muffleWarning')
   })
   output <- utils::capture.output(collect(for (step in steps) eval(step, envir = env)))
   classes <- length(env$lfq_cc$midLengths)
   columns <- if (is.matrix(env$lfq_cc$catch)) ncol(env$lfq_cc$catch)
   curve <- function(interval) as.call(c(quote(TropFishR::catchCurve), list(quote(lfq_cc)),
      if (!is.null(columns)) list(catch_columns = call(':', 1L, columns)),
      list(cumulative = s$cc_method == 'cumulative'),
      if (is.null(interval)) list(auto = TRUE) else list(reg_int = call('c', interval[[1L]], interval[[2L]])),
      list(calc_ogive = s$cc_ogive, plot = FALSE)))
   automatic <- identical(s$cc_first, '') && identical(s$cc_last, '')
   interval <- if (!automatic)
   {
      first <- number('cc_first', 1, classes, 'The first regression point')
      last <- number('cc_last', 1, classes, 'The last regression point')
      if (first != round(first) || last != round(last) || last - first < 2)
         fail('The regression needs at least three consecutive points (first < last, whole numbers).')
      c(as.integer(first), as.integer(last))
   }
   curveCall <- call('<-', quote(cc), curve(interval))
   result <- tryCatch({
      output <- c(output, utils::capture.output(collect(eval(curveCall, envir = env))))
      env$cc
   }, error = function(e) fail(paste('TropFishR catchCurve():', conditionMessage(e))))
   if (is.null(result) || !length(result$Z) || !is.finite(result$Z[[1L]]))
      fail('TropFishR could not fit the catch curve with these points; choose the regression points explicitly.')
   used <- as.integer(unlist(result$reg_int))
   if (length(used) != 2L) fail('TropFishR chose an unusual regression range; choose the points explicitly.')

   # natural mortality (optional) with M_empirical()
   mCall <- .rs.superrstudioLfqNaturalMortalityCall(s, linf, k, number)
   z <- as.numeric(result$Z[[1L]])
   m <- if (!is.null(mCall)) { eval(mCall, envir = env); env$M }
   code <- paste(c(prepared$code, '',
                   sprintf('# %s catch curve (TropFishR %s, R %s)', .rs.superrstudioBrand(),
                           utils::packageVersion('TropFishR'), getRversion()),
                   vapply(steps, function(step) paste(deparse(step, width.cutoff = 90L), collapse = '\n'), ''),
                   paste(deparse(call('<-', quote(cc), curve(used)), width.cutoff = 90L), collapse = '\n'),
                   'cc$Z; cc$se; cc$confidenceInt',
                   if (!is.null(mCall)) c(paste(deparse(mCall, width.cutoff = 90L), collapse = '\n'),
                                          'FM <- cc$Z - M   # fishing mortality', 'E <- FM / cc$Z   # exploitation rate')),
                 collapse = '\n')

   x <- as.numeric(result[[if (s$cc_method == 'cumulative') 'ln_Linf_L' else 't_midL']])
   y <- as.numeric(result[[if (s$cc_method == 'cumulative') 'lnC' else 'lnC_dt']])
   inRange <- seq_along(x) >= used[[1L]] & seq_along(x) <= used[[2L]]
   points <- lapply(seq_along(x), function(i) list(
      index = I(i), length = I(env$lfq_cc$midLengths[[i]]),
      x = I(if (is.finite(x[[i]])) x[[i]] else NA), y = I(if (is.finite(y[[i]])) y[[i]] else NA),
      used = I(inRange[[i]] && is.finite(x[[i]]) && is.finite(y[[i]]))))
   n <- sum(vapply(points, function(point) isTRUE(point$used), NA))
   summary <- summary(result$linear_mod)
   r2 <- summary$r.squared
   se <- as.numeric(result$se[[1L]])
   ci <- as.numeric(unlist(result$confidenceInt))

   # diagnostics: facts about the regression, each with a stable code and the
   # values in its English text (so the window can show it in its language)
   diagnostics <- list()
   note <- function(code, text, values = character())
      diagnostics[[length(diagnostics) + 1L]] <<- list(code = I(code), text = I(text), values = as.character(values))
   if (automatic)
      note('automatic', sprintf('Points %d to %d were chosen by TropFishR\'s automatic rule (from the class after the highest point to the last class above 0.2); check them on the plot.', used[[1L]], used[[2L]]),
           used)
   peak <- which.max(replace(y, !is.finite(y), -Inf))
   if (s$cc_method == 'pauly' && length(peak) && used[[1L]] <= peak)
      note('before_peak', 'The regression starts at or before the highest point of the curve. Those length classes are not fully selected by the gear, which biases Z downwards.')
   if (n < 5L) note('few_points', sprintf('Only %d points are in the regression; Z is poorly determined.', n), n)
   if (is.finite(r2) && r2 < 0.8)
      note('low_r2', sprintf('The regression points are far from a straight line (R-squared %.2f).', r2), sprintf('%.2f', r2))
   if (is.finite(se) && z > 0 && se / z > 0.25)
      note('wide_ci', sprintf('The standard error is %.0f%% of Z; the 95%% interval is wide.', 100 * se / z),
           sprintf('%.0f', 100 * se / z))
   near <- inRange & env$lfq_cc$midLengths >= 0.9 * linf
   if (any(near))
      note('near_linf', 'The regression includes lengths of at least 90% of Linf, whose ages are very sensitive to Linf.')
   undefined <- sum(!is.finite(x))
   if (undefined > 0L)
      note('no_age', sprintf('%d length classes are at or above Linf and have no age; they cannot be used.', undefined), undefined)
   if (!is.null(m) && m > z)
      note('negative_f', 'M is larger than Z, so F would be negative; check M, the growth parameters and the regression.')
   if (s$cc_ogive && (is.null(result$L50) || !is.finite(result$L50) || result$L50 <= 0))
      note('ogive', 'The selection ogive could not be estimated from the points before the regression.')

   image <- .rs.superrstudioLfqImage(function() graphics::plot(result, plot_selec = isTRUE(s$cc_ogive)))
   value <- function(v) I(if (!is.null(v) && length(v) == 1L && is.finite(v)) as.numeric(v) else NA)
   list(code = I(code), image = I(image), method = I(s$cc_method), z = value(z), se = value(se),
        ci_low = value(ci[1L]), ci_high = value(ci[2L]), r2 = value(r2), n = I(n),
        first = I(used[[1L]]), last = I(used[[2L]]), classes = I(classes),
        m = value(m), f = value(if (!is.null(m)) z - m), e = value(if (!is.null(m)) (z - m) / z),
        l50 = value(result$L50), l75 = value(result$L75),
        plus_group = I(if (is.null(plus)) '' else format(max(env$lfq_cc$midLengths))),
        years = years, points = points, diagnostics = diagnostics, warnings = unique(warnings))
})
