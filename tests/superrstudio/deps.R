# Contract tests for SuperR's on-demand installation of optional packages.
# SPDX-License-Identifier: AGPL-3.0-only
#
#   Rscript tests/superrstudio/deps.R
#
# Uses the local repository from make-local-repo.R (built on first use; that
# step downloads from CRAN once) and temporary libraries only: no library of
# the R installation or of the user is written. Checks: missing packages are
# reported with the plan (packages, dependencies, repository, target
# library); installation succeeds into the first library only and
# revalidates; unavailable and broken packages fail with a message; an
# installation can be cancelled; an unwritable library is refused; under
# renv the project library is the target and renv.lock is untouched.
args <- commandArgs(FALSE)
script <- sub('^--file=', '', args[grepl('^--file=', args)])
root <- normalizePath(file.path(dirname(script), '../..'), winslash = '/')
toolsEnv <- new.env(parent = globalenv())
.rs.toolsEnv <- function() toolsEnv
.rs.addFunction <- function(name, FN) {
   environment(FN) <- toolsEnv
   assign(paste0('.rs.', name), FN, envir = toolsEnv)
}
for (file in c('SessionSuperRStudio.R', 'SessionSuperRStudioLfq.R', 'SessionSuperRStudioDeps.R'))
   sys.source(file.path(root, 'src/cpp/session/modules', file), envir = toolsEnv)
repo <- file.path(root, '.cache/superrstudio/local-repo')
if (!file.exists(file.path(repo, 'full')))
   system2(file.path(R.home('bin'), 'Rscript'), c(shQuote(file.path(root, 'tests/superrstudio/make-local-repo.R')), shQuote(repo)))
url <- function(name) paste0('file:///', normalizePath(file.path(repo, name), winslash = '/'))
deps <- function(op, feature = 'plot', settings = list())
   toolsEnv$.rs.superrstudioDataRpc(op, feature, '', '', '', character(), settings)
ok <- function(result) { if (!is.null(result$error)) stop(result$error); result }
expect <- function(condition, message) if (!isTRUE(condition)) stop(message, call. = FALSE)
newLib <- function() { lib <- tempfile('superr-lib-'); dir.create(lib); normalizePath(lib, winslash = '/') }
wait <- function(job, timeout = 600) {
   started <- Sys.time()
   repeat {
      result <- ok(deps('deps_poll', settings = list(job = job)))
      if (!identical(unclass(result$status), 'running')) return(result)
      if (difftime(Sys.time(), started, units = 'secs') > timeout) stop('installation did not finish')
      Sys.sleep(1)
   }
}
systemLib <- .Library
systemState <- file.info(list.files(systemLib, full.names = TRUE))$mtime

# missing: reported, with what an installation would do
lib <- newLib()
.libPaths(c(lib, .Library))
options(repos = c(LOCAL = url('full')))
check <- ok(deps('deps_check'))
expect(!isTRUE(unclass(check$ready)) && identical(unclass(check$packages[[1L]]$status), 'missing'), 'ggplot2 should be missing')
plan <- ok(deps('deps_plan'))
expect(identical(plan$install, 'ggplot2') && length(plan$dependencies) > 5L && 'scales' %in% plan$dependencies,
       paste('plan:', paste(plan$dependencies, collapse = ' ')))
expect(identical(unclass(plan$library), lib) && isTRUE(unclass(plan$writable)) && identical(unclass(plan$problem), ''),
       'plan target library')
expect(identical(plan$repos, url('full')) && identical(unclass(plan$renv), ''), 'plan repository')
reject <- function(result, pattern)
   expect(!is.null(result$error) && grepl(pattern, result$error), paste('expected error', pattern, ':', result$error))
reject(deps('deps_check', 'nothing'), 'Unknown SuperR feature')
cat('PASS: missing package reported with the plan (package, dependencies, repository, target library)\n')

# success: installed into the first library only, then revalidated
started <- ok(deps('deps_install'))
expect(identical(unclass(started$status), 'started'), 'install did not start')
reject(deps('deps_install'), 'already running')
done <- wait(started$job)
expect(identical(unclass(done$status), 'done') && isTRUE(unclass(done$ready)), paste('install failed:', done$message))
expect(dir.exists(file.path(lib, 'ggplot2')) && dir.exists(file.path(lib, 'scales')), 'not installed into the target library')
expect(isTRUE(unclass(ok(deps('deps_check'))$ready)), 'revalidation failed')
again <- ok(deps('deps_plan'))
expect(!length(again$install), 'a compatible installed package must not be offered again')
expect(identical(systemState, file.info(list.files(systemLib, full.names = TRUE))$mtime), 'the R library changed')
cat('PASS: installation into the first library only; revalidated; not offered again; R library untouched\n')

# unavailable from the repository: refused before anything runs
.libPaths(c(newLib(), .Library))
options(repos = c(LOCAL = url('empty')))
plan <- ok(deps('deps_plan'))
expect(identical(unclass(plan$problem), 'unavailable'), 'empty repository should be reported')
reject(deps('deps_install'), 'cannot be installed')
options(repos = c(LOCAL = 'file:///nonexistent/superr-repo'))
expect(unclass(ok(deps('deps_plan'))$problem) %in% c('repository', 'unavailable'), 'unreachable repository')
cat('PASS: unavailable package and unreachable repository refused with a reason\n')

# broken package file: the installation runs and fails with a message
broken <- file.path(tempfile('superr-broken-'), 'bin', 'windows', 'contrib',
                    basename(dirname(list.files(file.path(repo, 'full'), pattern = 'PACKAGES$', recursive = TRUE, full.names = TRUE)[[1L]])))
dir.create(broken, recursive = TRUE)
source <- dirname(list.files(file.path(repo, 'full'), pattern = 'PACKAGES$', recursive = TRUE, full.names = TRUE)[[1L]])
invisible(file.copy(list.files(source, full.names = TRUE), broken))
zip <- list.files(broken, pattern = '^ggplot2_.*\\.zip$', full.names = TRUE)
writeBin(as.raw(1:100), zip)
lib <- newLib()
.libPaths(c(lib, .Library))
options(repos = c(LOCAL = paste0('file:///', normalizePath(dirname(dirname(dirname(dirname(broken)))), winslash = '/'))))
failed <- wait(ok(deps('deps_install'))$job)
expect(identical(unclass(failed$status), 'failed') && nzchar(failed$message) && !isTRUE(unclass(failed$ready)),
       'a broken package must fail with a message')
cat('PASS: broken package: installation fails, message reported, feature still not ready\n')

# cancel
lib <- newLib()
.libPaths(c(lib, .Library))
options(repos = c(LOCAL = url('full')))
started <- ok(deps('deps_install'))
Sys.sleep(1)
cancelled <- ok(deps('deps_cancel', settings = list(job = started$job)))
expect(identical(unclass(cancelled$status), 'cancelled'), 'cancel')
expect(identical(unclass(ok(deps('deps_poll', settings = list(job = started$job)))$status), 'cancelled'), 'poll after cancel')
cat('PASS: installation cancelled; the session is free for another installation\n')

# a library that is not writable is refused (here: one that does not exist)
.libPaths(c(lib, .Library))
toolsEnv$.libPaths <- function(...) c(file.path(tempdir(), 'missing-library'), .Library)
plan <- ok(deps('deps_plan'))
expect(!isTRUE(unclass(plan$writable)), 'missing library reported writable')
reject(deps('deps_install'), 'not writable')
rm('.libPaths', envir = toolsEnv)
cat('PASS: unwritable target library refused with a message\n')

# renv: a real renv project (renv from the local repository, initialised
# bare, loaded in this process and snapshotted); the project library is the target and
# renv.lock is not changed
renvLib <- newLib()
utils::install.packages('renv', lib = renvLib, repos = url('full'), type = .Platform$pkgType, quiet = TRUE)
.libPaths(c(renvLib, .Library))
# normalised after creation: a temporary directory under an 8.3 short path
# (GitHub's Windows runners) only resolves to its long form once it exists
project <- tempfile('superr-renv-')
dir.create(project)
project <- normalizePath(project, winslash = '/', mustWork = TRUE)
invisible(utils::capture.output(renv::init(project = project, bare = TRUE, restart = FALSE, load = FALSE)))
invisible(utils::capture.output(renv::load(project, quiet = TRUE)))
invisible(utils::capture.output(renv::snapshot(project = project, prompt = FALSE)))
lock <- file.path(project, 'renv.lock')
expect(file.exists(lock), 'renv.lock not created')
lockHash <- tools::md5sum(lock)
projectLib <- normalizePath(renv::paths$library(project = project), winslash = '/', mustWork = FALSE)
options(repos = c(LOCAL = url('full')))
plan <- ok(deps('deps_plan'))
expect(identical(unclass(plan$renv), project) && identical(unclass(plan$library), projectLib),
       paste('renv project library not the target:', plan$renv, project, plan$library, projectLib))
done <- wait(ok(deps('deps_install'))$job)
expect(identical(unclass(done$status), 'done') && dir.exists(file.path(projectLib, 'ggplot2')), 'renv install')
expect(identical(unclass(done$renv), project) && identical(tools::md5sum(lock), lockHash), 'renv.lock changed')
expect(!dir.exists(file.path(renvLib, 'ggplot2')), 'installed outside the project library')
cat('PASS: renv project (renv', as.character(utils::packageVersion('renv')), '): installed into the project library; renv.lock unchanged\n')
