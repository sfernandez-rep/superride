# SuperR optional R packages: check, explain and install on request.
# SPDX-License-Identifier: AGPL-3.0-only
#
# SuperR's windows need optional packages (ggplot2 for the plot editor,
# TropFishR for length-frequency analysis). Nothing is installed at start-up
# or without the user's explicit consent:
#
#   deps_check    is every package of a feature installed in a compatible
#                 version, in the session's library paths?
#   deps_plan     what an installation would do: the packages and the
#                 dependencies still missing, the repository, the target
#                 library (the first entry of .libPaths(): the project
#                 library under renv), whether it is writable
#   deps_install  runs utils::install.packages() for exactly that plan in a
#                 separate Rscript process (the session stays usable)
#   deps_poll / deps_cancel
#
# The project's renv.lock and other libraries are never changed; under renv
# the user is told to record the new packages with renv::snapshot().

.rs.addFunction('superrstudioDependencyFeatures', function()
   list(plot = list(packages = list(list(name = 'ggplot2', min = '3.4.0'))),
        lfq = list(packages = list(list(name = 'TropFishR', min = '1.6.0')))))

# state lives in the tools environment, where the functions above look
assign('.rs.superrstudioDepsState', new.env(parent = emptyenv()), envir = .rs.toolsEnv())
.rs.superrstudioDepsState$jobs <- list()
.rs.superrstudioDepsState$counter <- 0L

.rs.addFunction('superrstudioDepsRpc', function(operation, feature, settings)
{
   fail <- function(message) stop(message, call. = FALSE)
   if (operation == 'deps_poll') return(.rs.superrstudioDepsPoll(settings$job))
   if (operation == 'deps_cancel') return(.rs.superrstudioDepsCancel(settings$job))
   features <- .rs.superrstudioDependencyFeatures()
   if (!.rs.superrstudioIsText(feature) || !feature %in% names(features)) fail('Unknown SuperR feature.')
   packages <- features[[feature]]$packages
   if (operation == 'deps_check') return(.rs.superrstudioDepsCheck(feature, packages))
   if (operation == 'deps_plan') return(.rs.superrstudioDepsPlan(feature, packages))
   if (operation == 'deps_install') return(.rs.superrstudioDepsInstall(feature, packages))
   fail('Unsupported operation.')
})

#' Installed version of a package in the session's library paths, or NA
.rs.addFunction('superrstudioDepsVersion', function(name, lib = .libPaths())
{
   version <- suppressWarnings(tryCatch(utils::packageDescription(name, lib.loc = lib, fields = 'Version'),
                                        error = function(e) NA))
   if (is.null(version) || length(version) != 1L || is.na(version)) NA_character_ else as.character(version)
})

.rs.addFunction('superrstudioDepsCheck', function(feature, packages)
{
   rows <- lapply(packages, function(p) {
      installed <- .rs.superrstudioDepsVersion(p$name)
      status <- if (is.na(installed)) 'missing'
                else if (utils::compareVersion(installed, p$min) < 0) 'old' else 'ok'
      list(name = I(p$name), min = I(p$min), installed = I(if (is.na(installed)) '' else installed),
           status = I(status))
   })
   ready <- all(vapply(rows, function(r) identical(unclass(r$status), 'ok'), NA))
   list(feature = I(feature), ready = I(ready), packages = rows)
})

#' The repositories an installation would use: the session's, with the
#' "@CRAN@" placeholder (which would prompt) replaced by the cloud mirror
.rs.addFunction('superrstudioDepsRepos', function()
{
   repos <- getOption('repos')
   if (!length(repos)) repos <- c(CRAN = '@CRAN@')
   repos[repos == '@CRAN@'] <- 'https://cloud.r-project.org'
   repos
})

.rs.addFunction('superrstudioDepsRenvProject', function()
{
   project <- Sys.getenv('RENV_PROJECT', '')
   if (nzchar(project)) normalizePath(project, winslash = '/', mustWork = FALSE) else ''
})

.rs.addFunction('superrstudioDepsPlan', function(feature, packages)
{
   check <- .rs.superrstudioDepsCheck(feature, packages)
   lib <- normalizePath(.libPaths()[[1L]], winslash = '/', mustWork = FALSE)
   writable <- dir.exists(lib) && file.access(lib, 2L) == 0L
   repos <- .rs.superrstudioDepsRepos()
   wanted <- vapply(Filter(function(r) !identical(unclass(r$status), 'ok'), check$packages),
                    function(r) as.character(r$name), '')
   # binary packages where R has them (Windows, macOS), as RStudio's installer
   available <- tryCatch(suppressWarnings(utils::available.packages(repos = repos, type = .Platform$pkgType)),
                         error = function(e) e)
   problem <- ''
   dependencies <- character()
   if (inherits(available, 'error'))
      problem <- 'repository'
   else if (!all(wanted %in% rownames(available)))
      problem <- 'unavailable'
   else
   {
      for (r in check$packages)
         if (as.character(r$name) %in% wanted &&
             utils::compareVersion(available[as.character(r$name), 'Version'], as.character(r$min)) < 0)
            problem <- 'version'
      needed <- unique(unlist(tools::package_dependencies(wanted, db = available, recursive = TRUE,
                                                          which = c('Depends', 'Imports', 'LinkingTo'))))
      base <- rownames(utils::installed.packages(priority = 'base'))
      dependencies <- sort(setdiff(needed[is.na(vapply(needed, .rs.superrstudioDepsVersion, ''))], c(base, wanted)))
   }
   list(feature = I(feature), ready = check$ready, packages = check$packages, install = wanted,
        dependencies = dependencies,
        repos = unname(as.character(repos)), library = I(lib), writable = I(writable),
        renv = I(.rs.superrstudioDepsRenvProject()), problem = I(problem),
        versions = if (!nzchar(problem) && length(wanted)) as.list(stats::setNames(available[wanted, 'Version'], wanted)) else list())
})

# The installer process: installs into one library from the given
# repositories and reports which requested packages are present afterwards.
.rs.superrstudioDepsState$runner <- c(
   'args <- commandArgs(TRUE)',
   'job <- readRDS(args[[1L]])',
   '.libPaths(job$libs)',
   'writeLines(as.character(Sys.getpid()), job$pid)',
   'options(repos = job$repos, install.packages.compile.from.source = "never")',
   'log <- file(job$log, open = "wt")',
   'sink(log); sink(log, type = "message")',
   'warnings <- character()',
   'error <- tryCatch({',
   '   withCallingHandlers(utils::install.packages(job$packages, lib = job$lib, type = job$type,',
   '                                                dependencies = c("Depends", "Imports", "LinkingTo")),',
   '      warning = function(w) { warnings <<- c(warnings, conditionMessage(w)); invokeRestart("muffleWarning") })',
   '   ""',
   '}, error = function(e) conditionMessage(e))',
   'sink(type = "message"); sink()',
   'close(log)',
   'present <- vapply(job$packages, function(p) nzchar(system.file(package = p, lib.loc = job$lib)), NA)',
   'saveRDS(list(error = error, warnings = unique(warnings), present = present), paste0(job$output, ".tmp"))',
   'file.rename(paste0(job$output, ".tmp"), job$output)')

.rs.addFunction('superrstudioDepsInstall', function(feature, packages)
{
   fail <- function(message) stop(message, call. = FALSE)
   state <- .rs.superrstudioDepsState
   if (length(Filter(function(job) is.null(job$finished), state$jobs)))
      fail('A package installation is already running.')
   plan <- .rs.superrstudioDepsPlan(feature, packages)
   if (!length(plan$install)) return(list(job = I(''), status = I('done'), ready = I(TRUE)))
   if (nzchar(plan$problem)) fail('The packages cannot be installed from the configured repositories.')
   if (!isTRUE(unclass(plan$writable)))
      fail(sprintf('The library %s is not writable. Choose a writable library (for example a personal library) and try again.',
                   plan$library))
   folder <- tempfile('superr-install-')
   dir.create(folder)
   state$counter <- state$counter + 1L
   id <- paste0('install', state$counter)
   job <- list(packages = plan$install, lib = as.character(plan$library), libs = .libPaths(),
               repos = .rs.superrstudioDepsRepos(), type = .Platform$pkgType, pid = file.path(folder, 'pid'),
               log = file.path(folder, 'log.txt'), output = file.path(folder, 'result.rds'))
   saveRDS(job, file.path(folder, 'job.rds'))
   writeLines(state$runner, file.path(folder, 'runner.R'))
   rscript <- file.path(R.home('bin'), if (.Platform$OS.type == 'windows') 'Rscript.exe' else 'Rscript')
   system2(rscript, c('--vanilla', shQuote(file.path(folder, 'runner.R')), shQuote(file.path(folder, 'job.rds'))),
           wait = FALSE, stdout = file.path(folder, 'stdout.txt'), stderr = file.path(folder, 'stderr.txt'))
   state$jobs[[id]] <- list(id = id, feature = feature, folder = folder, job = job, started = Sys.time())
   list(job = I(id), status = I('started'), packages = plan$install, library = plan$library)
})

.rs.addFunction('superrstudioDepsPoll', function(id)
{
   fail <- function(message) stop(message, call. = FALSE)
   state <- .rs.superrstudioDepsState
   entry <- if (.rs.superrstudioIsText(id)) state$jobs[[id]]
   if (is.null(entry)) fail('Unknown installation.')
   if (!is.null(entry$finished)) return(list(job = I(id), status = I(entry$finished)))
   log <- if (file.exists(entry$job$log)) readLines(entry$job$log, warn = FALSE) else character()
   last <- utils::tail(log[nzchar(trimws(log))], 1L)
   elapsed <- as.numeric(difftime(Sys.time(), entry$started, units = 'secs'))
   if (!file.exists(entry$job$output))
   {
      if (elapsed > 5 && file.exists(entry$job$pid))
      {
         pid <- as.integer(readLines(entry$job$pid, warn = FALSE))
         alive <- tryCatch(.rs.superrstudioLfqAlive(pid), error = function(e) TRUE)
         if (!alive && !file.exists(entry$job$output))
         {
            state$jobs[[id]]$finished <- 'failed'
            return(list(job = I(id), status = I('failed'), message = I('The installation process stopped unexpectedly.'),
                        log = utils::tail(log, 20L)))
         }
      }
      return(list(job = I(id), status = I('running'), elapsed = I(round(elapsed)),
                  progress = I(if (length(last)) last else 'Starting R...')))
   }
   result <- readRDS(entry$job$output)
   stderr <- file.path(entry$folder, 'stderr.txt')
   errors <- if (file.exists(stderr)) readLines(stderr, warn = FALSE) else character()
   check <- .rs.superrstudioDepsCheck(entry$feature,
                                      .rs.superrstudioDependencyFeatures()[[entry$feature]]$packages)
   status <- if (isTRUE(unclass(check$ready))) 'done' else 'failed'
   state$jobs[[id]]$finished <- status
   unlink(entry$folder, recursive = TRUE)
   message <- if (status == 'failed')
      paste(c(if (nzchar(result$error)) result$error, result$warnings, utils::tail(errors, 10L)), collapse = '\n') else ''
   list(job = I(id), status = I(status), ready = check$ready, packages = check$packages,
        message = I(message), log = utils::tail(log, 20L), renv = I(.rs.superrstudioDepsRenvProject()))
})

.rs.addFunction('superrstudioDepsCancel', function(id)
{
   state <- .rs.superrstudioDepsState
   entry <- if (.rs.superrstudioIsText(id)) state$jobs[[id]]
   if (is.null(entry) || !is.null(entry$finished)) return(list(job = I(id), status = I('finished')))
   if (file.exists(entry$job$pid))
      tools::pskill(as.integer(readLines(entry$job$pid, warn = FALSE)))
   state$jobs[[id]]$finished <- 'cancelled'
   unlink(entry$folder, recursive = TRUE)
   # an interrupted install.packages() can leave lock folders behind
   locks <- list.files(entry$job$lib, pattern = '^00LOCK')
   list(job = I(id), status = I('cancelled'), library = I(entry$job$lib), locks = locks)
})
