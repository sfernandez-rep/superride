# Builds the local package repository used by the dependency tests.
# SPDX-License-Identifier: AGPL-3.0-only
#
#   Rscript tests/superrstudio/make-local-repo.R <repo folder>
#
# Downloads the Windows binaries of ggplot2 (with every dependency outside
# base R) and renv from CRAN once, into a CRAN-style folder:
#   <repo>/full    ggplot2 and its dependencies, renv
#   <repo>/empty   an empty repository (installation failure)
# Nothing is installed; the tests point options(repos) at these folders.
args <- commandArgs(TRUE)
root <- normalizePath(args[[1L]], winslash = '/', mustWork = FALSE)
cran <- 'https://cloud.r-project.org'
contrib <- function(name) file.path(root, name, 'bin', 'windows', 'contrib',
                                    paste(R.version$major, strsplit(R.version$minor, '.', fixed = TRUE)[[1L]][[1L]], sep = '.'))
available <- utils::available.packages(repos = cran, type = 'win.binary')
wanted <- c('ggplot2', 'renv')
needed <- unique(c(wanted, unlist(tools::package_dependencies(wanted, db = available, recursive = TRUE,
                                                              which = c('Depends', 'Imports', 'LinkingTo')))))
needed <- setdiff(needed, rownames(utils::installed.packages(priority = 'base')))
dir.create(contrib('full'), recursive = TRUE, showWarnings = FALSE)
dir.create(contrib('empty'), recursive = TRUE, showWarnings = FALSE)
have <- sub('_.*$', '', list.files(contrib('full'), pattern = '\\.zip$'))
missing <- setdiff(needed, have)
if (length(missing))
   utils::download.packages(missing, destdir = contrib('full'), repos = cran, type = 'win.binary', available = available)
tools::write_PACKAGES(contrib('full'), type = 'win.binary')
# an index without packages (write_PACKAGES() writes none for an empty folder)
file.create(file.path(contrib('empty'), 'PACKAGES'))
cat('local repository:', root, '-', length(needed), 'packages\n')
