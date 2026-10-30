# SuperR length-frequency: Beverton and Holt mean-length Z and yield per
# recruit (TropFishR). SPDX-License-Identifier: AGPL-3.0-only
#
# Both analyses are computed by TropFishR (Z_BevertonHolt() and
# predict_mod(type = 'ypr')); this file validates the inputs, builds
# explicit, reproducible calls and reports facts about the result. The
# diagnostics state assumptions and numerical facts; they do not judge the
# state of a stock, which needs expert review.

#' A validating reader of numeric settings
#'
#' @param s Validated settings (superrstudioLfqSettings()).
#' @return function(key, low, high, label, optional = FALSE) returning the
#'   number, NULL for an empty optional value, or failing with a message.
.rs.addFunction('superrstudioLfqNumberReader', function(s)
{
   function(key, low, high, label, optional = FALSE)
   {
      value <- s[[key]]
      if (identical(value, '') && optional) return(NULL)
      if (is.character(value)) value <- suppressWarnings(as.numeric(value))
      if (!.rs.superrstudioIsNumber(value, low, high))
         stop(sprintf('%s must be a number between %s and %s.', label, format(low), format(high)), call. = FALSE)
      as.numeric(value)
   }
})

#' Evaluate generated steps, collecting warnings and printed output
.rs.addFunction('superrstudioLfqEvalSteps', function(steps, env, what)
{
   warnings <- character()
   output <- tryCatch(utils::capture.output(withCallingHandlers(
      for (step in steps) eval(step, envir = env),
      warning = function(w) {
         warnings <<- c(warnings, conditionMessage(w))
         invokeRestart('muffleWarning')
      })), error = function(e) stop(paste0('TropFishR ', what, ': ', conditionMessage(e)), call. = FALSE))
   list(output = output, warnings = unique(warnings))
})

.rs.addFunction('superrstudioLfqDeparse', function(steps)
   vapply(steps, function(step) paste(deparse(step, width.cutoff = 90L), collapse = '\n'), ''))

#' Beverton and Holt's Z from the mean length above L'
#'
#' @param data,dataset The data frame the LFQ was prepared from (staleness).
#' @param settings cc_linf, cc_k (growth), cc_year ('' for all samples),
#'   bh_lprime (a length class midpoint), m_method and its inputs.
.rs.addFunction('superrstudioLfqBevertonHolt', function(data, dataset, settings)
{
   fail <- function(message) stop(message, call. = FALSE)
   prepared <- .rs.superrstudioLfqPrepared(data, dataset)
   s <- .rs.superrstudioLfqSettings(settings)
   number <- .rs.superrstudioLfqNumberReader(s)
   linf <- number('cc_linf', 0.01, 1e5, 'Linf (cm)')
   k <- number('cc_k', 1e-4, 50, 'K (1/year)')
   lfq <- prepared$lfq
   years <- unique(format(lfq$dates, '%Y'))
   if (nzchar(s$cc_year) && !s$cc_year %in% years)
      fail(sprintf('The prepared data have no samples in %s.', s$cc_year))
   mids <- lfq$midLengths
   lprime <- number('bh_lprime', min(mids), max(mids), "L' (cm)")
   if (!any(abs(mids - lprime) < 1e-8))
      fail(sprintf("L' must be a length class midpoint, for example %s.",
                   paste(utils::head(format(mids[mids >= lprime]), 3L), collapse = ', ')))
   if (lprime >= linf) fail("L' must be smaller than Linf.")

   # Z_BevertonHolt() reads Linf and K from the top level of its argument,
   # not from $par (TropFishR 1.6.6): set them explicitly, or Z is empty
   steps <- list(if (nzchar(s$cc_year)) substitute(lfq_bh <- TropFishR::lfqModify(lfq, years = Y), list(Y = s$cc_year))
                 else quote(lfq_bh <- lfq),
                 substitute(lfq_bh$Linf <- V, list(V = linf)),
                 substitute(lfq_bh$K <- V, list(V = k)))
   env <- new.env(parent = baseenv())
   env$lfq <- lfq
   run <- .rs.superrstudioLfqEvalSteps(steps, env, 'lfqModify()')
   columns <- if (is.matrix(env$lfq_bh$catch)) ncol(env$lfq_bh$catch)
   bhCall <- as.call(c(quote(TropFishR::Z_BevertonHolt), list(quote(lfq_bh)),
                       if (!is.null(columns)) list(catch_columns = call(':', 1L, columns)),
                       list(Lprime_tprime = lprime)))
   bhStep <- call('<-', quote(bh), bhCall)
   run2 <- .rs.superrstudioLfqEvalSteps(list(bhStep), env, 'Z_BevertonHolt()')
   bh <- env$bh
   z <- if (length(bh$Z) == 1L) as.numeric(bh$Z) else NA_real_
   lmean <- as.numeric(bh$Lmean)
   lower <- as.numeric(bh$Lprime)
   if (!is.finite(z) || z <= 0)
      fail(sprintf("Z cannot be computed: the mean length above L' (%.2f cm) must lie between L' and Linf.", lmean))
   mCall <- .rs.superrstudioLfqNaturalMortalityCall(s, linf, k, number)
   m <- if (!is.null(mCall)) { eval(mCall, envir = env); env$M }

   catch <- if (is.null(columns)) env$lfq_bh$catch else rowSums(env$lfq_bh$catch, na.rm = TRUE)
   above <- sum(catch[mids >= lprime - 1e-8], na.rm = TRUE)
   mode <- mids[[which.max(catch)]]
   diagnostics <- list()
   note <- function(code, text, values = character())
      diagnostics[[length(diagnostics) + 1L]] <<- list(code = I(code), text = I(text), values = as.character(values))
   note('bh_equilibrium', "The estimate assumes equilibrium: constant recruitment and mortality, and full selection from L' on.")
   if (lprime < mode)
      note('bh_before_mode', sprintf("L' is below the most frequent length class (%s cm). Smaller fish are usually not fully selected, which biases Z.", format(mode)),
           format(mode))
   if (above < 100)
      note('bh_few_fish', sprintf("Only %s fish are at or above L'; the mean length is poorly determined.", format(above)), format(above))
   if (lmean >= 0.9 * linf)
      note('bh_near_linf', 'The mean length is at least 90% of Linf; Z is very sensitive to Linf.')
   if (!is.null(m) && m > z)
      note('negative_f', 'M is larger than Z, so F would be negative; check M, the growth parameters and the regression.')

   code <- paste(c(prepared$code, '',
                   sprintf("# %s Beverton-Holt Z from mean length (TropFishR %s, R %s)", .rs.superrstudioBrand(),
                           utils::packageVersion('TropFishR'), getRversion()),
                   '# Z_BevertonHolt() reads Linf and K from the top level of its argument',
                   .rs.superrstudioLfqDeparse(c(steps, list(bhStep))),
                   "bh$Z; bh$Lmean; bh$Lprime   # Lprime: lower bound of the L' class",
                   if (!is.null(mCall)) c(.rs.superrstudioLfqDeparse(list(mCall)),
                                          'FM <- bh$Z - M   # fishing mortality', 'E <- FM / bh$Z   # exploitation rate')),
                 collapse = '\n')
   image <- .rs.superrstudioLfqImage(function() {
      graphics::plot(mids, catch, type = 'h', lwd = 4, lend = 1, col = 'grey55',
                     xlab = 'Length (cm)', ylab = 'Catch (all selected samples)', main = 'Beverton-Holt Z from mean length')
      graphics::abline(v = c(lower, lmean, linf), lty = c(2, 1, 3), lwd = 2, col = c('#1f6fb4', '#c0392b', 'grey30'))
      graphics::legend('topright', c("L' (lower bound)", 'Mean length', 'Linf'), lty = c(2, 1, 3), lwd = 2,
                       col = c('#1f6fb4', '#c0392b', 'grey30'), bty = 'n')
   })
   value <- function(v) I(if (!is.null(v) && length(v) == 1L && is.finite(v)) as.numeric(v) else NA)
   list(code = I(code), image = I(image), z = value(z), lmean = value(lmean), lprime = value(lower),
        lprime_class = value(lprime), fish = value(above), m = value(m), f = value(if (!is.null(m)) z - m),
        e = value(if (!is.null(m)) (z - m) / z), years = years, diagnostics = diagnostics,
        warnings = unique(c(run$warnings, run2$warnings)))
})

#' Beverton and Holt yield per recruit
#'
#' @param data,dataset The data frame the LFQ was prepared from: its length
#'   classes are the length grid of the selection ogive.
#' @param settings cc_linf, cc_k (growth), m_method and its inputs (M is
#'   required), ypr_a and ypr_b (weight = a * length^b, g and cm), ypr_lr
#'   (length at recruitment), ypr_selection ('knife' or 'ogive'), ypr_lc
#'   (Lc, or L50 of the ogive), ypr_l75 (ogive only), ypr_fmax and
#'   ypr_fstep (the F grid), optional ypr_curr_e and ypr_curr_lc.
.rs.addFunction('superrstudioLfqYield', function(data, dataset, settings)
{
   fail <- function(message) stop(message, call. = FALSE)
   prepared <- .rs.superrstudioLfqPrepared(data, dataset)
   s <- .rs.superrstudioLfqSettings(settings)
   number <- .rs.superrstudioLfqNumberReader(s)
   linf <- number('cc_linf', 0.01, 1e5, 'Linf (cm)')
   k <- number('cc_k', 1e-4, 50, 'K (1/year)')
   mCall <- .rs.superrstudioLfqNaturalMortalityCall(s, linf, k, number)
   if (is.null(mCall)) fail('Yield per recruit needs natural mortality M: choose a method for M.')
   a <- number('ypr_a', 1e-9, 10, 'Length-weight a')
   b <- number('ypr_b', 1, 5, 'Length-weight b')
   lr <- number('ypr_lr', 0, linf, 'Length at recruitment Lr (cm)')
   if (!s$ypr_selection %in% c('knife', 'ogive')) fail('Choose knife-edge selection or a selection ogive.')
   ogive <- s$ypr_selection == 'ogive'
   lc <- number('ypr_lc', 0, linf, if (ogive) 'L50 (cm)' else 'Lc (cm)')
   l75 <- if (ogive) number('ypr_l75', 0, linf, 'L75 (cm)')
   if (ogive && l75 <= lc) fail('L75 must be larger than L50.')
   if (lr >= lc) fail(if (ogive) 'Lr must be smaller than L50.' else 'Lr must be smaller than Lc.')
   if (lc >= linf) fail('Lc must be smaller than Linf.')
   fmax <- number('ypr_fmax', 0.05, 20, 'Largest F (1/year)')
   fstep <- number('ypr_fstep', 0.001, 1, 'F step')
   if (fmax / fstep > 2000) fail('The F grid may have at most 2,000 steps; increase the step.')
   if (fmax / fstep < 10) fail('The F grid needs at least 10 steps; decrease the step.')
   currE <- number('ypr_curr_e', 0, 0.99, 'Current E', optional = TRUE)
   currLc <- number('ypr_curr_lc', 0, linf, 'Current Lc (cm)', optional = TRUE)
   if (!is.null(currLc) && is.null(currE)) fail('A current Lc needs the current exploitation rate E too.')
   if (!is.null(currE) && is.null(currLc)) currLc <- lc

   paramCall <- substitute(ypr_param <- list(Linf = L, K = K, t0 = 0, M = M, a = A, b = B, Lr = LR,
                                             midLengths = lfq$midLengths),
                           list(L = linf, K = k, A = a, B = b, LR = lr))
   steps <- list(mCall, paramCall)
   if (ogive)
      steps <- c(steps, list(substitute(s_list <- list(selecType = 'trawl_ogive', L50 = L50, L75 = L75),
                                        list(L50 = lc, L75 = l75))))
   yprCall <- as.call(c(quote(TropFishR::predict_mod), list(quote(ypr_param), type = 'ypr',
                        FM_change = call('seq', 0, fmax, fstep), Lc_change = lc),
                        if (ogive) list(s_list = quote(s_list)),
                        if (!is.null(currE)) list(curr.E = currE, curr.Lc = currLc),
                        list(plot = FALSE, hide.progressbar = TRUE)))
   steps <- c(steps, list(call('<-', quote(ypr), yprCall)))
   env <- new.env(parent = baseenv())
   env$lfq <- prepared$lfq
   run <- .rs.superrstudioLfqEvalSteps(steps, env, 'predict_mod()')
   ypr <- env$ypr
   ref <- ypr$df_Es
   if (is.null(ref) || !nrow(ref)) fail('TropFishR returned no reference points for these inputs.')
   pick <- function(name) if (name %in% names(ref)) as.numeric(ref[[name]][[1L]]) else NA_real_
   current <- ypr$currents
   curr <- function(name) if (!is.null(current) && name %in% names(current)) as.numeric(current[[name]][[1L]]) else NA_real_

   diagnostics <- list()
   note <- function(code, text, values = character())
      diagnostics[[length(diagnostics) + 1L]] <<- list(code = I(code), text = I(text), values = as.character(values))
   note('ypr_assumptions', 'Beverton and Holt yield per recruit assumes constant recruitment, von Bertalanffy growth with these parameters, a constant M and the selection chosen here.')
   note('ypr_grid', sprintf('The reference points are read from the F grid, in steps of %s per year.', format(fstep)), format(fstep))
   if (is.finite(pick('Fmax')) && pick('Fmax') >= fmax - fstep / 2)
      note('ypr_fmax_edge', 'Yield per recruit is still rising at the largest F of the grid: Fmax was not reached. Extend the F range.')
   if (!is.null(currE) && is.finite(pick('Emax')) && currE > pick('Emax'))
      note('ypr_above_emax', sprintf('The current exploitation rate E = %.2f is above Emax = %.2f, the E of the largest yield per recruit in this model.',
                                     currE, pick('Emax')), c(sprintf('%.2f', currE), sprintf('%.2f', pick('Emax'))))
   m <- env$M

   code <- paste(c(prepared$code, '',
                   sprintf('# %s yield per recruit, Beverton and Holt (TropFishR %s, R %s)', .rs.superrstudioBrand(),
                           utils::packageVersion('TropFishR'), getRversion()),
                   .rs.superrstudioLfqDeparse(steps),
                   'ypr$df_Es       # reference points (F01, Fmax, F05 and the matching E)',
                   if (!is.null(currE)) 'ypr$currents    # yield and biomass per recruit at the current E and Lc',
                   'plot(ypr, mark = TRUE)'),
                 collapse = '\n')
   image <- .rs.superrstudioLfqImage(function() graphics::plot(ypr, mark = TRUE))
   value <- function(v) I(if (!is.null(v) && length(v) == 1L && is.finite(v)) as.numeric(v) else NA)
   list(code = I(code), image = I(image), m = value(m), lc = value(lc), selection = I(s$ypr_selection),
        f01 = value(pick('F01')), fmax = value(pick('Fmax')), f05 = value(pick('F05')),
        e01 = value(pick('E01')), emax = value(pick('Emax')), e05 = value(pick('E05')),
        curr_e = value(currE), curr_f = value(curr('curr.F')), curr_ypr = value(curr('curr.YPR')),
        curr_bpr = value(curr('curr.BPR')), grid_step = value(fstep), grid_max = value(fmax),
        diagnostics = diagnostics, warnings = run$warnings)
})
