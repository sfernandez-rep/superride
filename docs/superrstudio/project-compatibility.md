# Using existing RStudio projects in SuperR

SuperR is RStudio 2026.10.0 with additional windows, so it opens RStudio
projects as they are. Nothing is converted to a SuperR format:

- **Project and code files:** `.Rproj`, `.R`, `.Rmd`, `.qmd`, `.Rnw` and
  `.Rhtml` are the same files, with the same project options (`.Rproj`
  fields, `.Rproj.user/`).
- **Data files:** `.RData`, `.rda`, `.rds` and CSV files are read and written
  by R itself.
- **Package environments:** renv (`renv.lock`, `renv/`, `.Rprofile`), packrat
  and user libraries work as in RStudio. SuperR uses the R installation and
  libraries R reports; it does not install, update or move packages.
- **Relative paths:** they resolve against the project directory, the
  working directory when a project opens.

**What can change files.** Running code can change files, in SuperR exactly
as in RStudio:

- scripts write their outputs;
- `save.image()` and the *Save workspace* question write `.RData`;
- renv may restore packages into the project library.

RStudio's per-project state in `.Rproj.user/` is also written. SuperR's own
windows read data from the session, and only write files when you export or
save something there.

## Test a copy of your project

Use a copy first. The helper script copies the project, opens the copy in
the installed SuperR, and checks afterwards that the original is unchanged:

```powershell
tools\superrstudio\test-project-copy.ps1 -Project "D:\research\my-project"
tools\superrstudio\test-project-copy.ps1 -Project "D:\research\my-project" -Destination "E:\scratch"
```

1. The script hashes every file of the original project (SHA-256).
2. It copies the project to `%TEMP%\SuperR-project-tests\<name>-<time>`, or
   to the destination you give.
3. It opens the copy's `.Rproj` in SuperR. Work as usual, then close SuperR.
4. It confirms that the original is unchanged and lists the files that were
   added, changed or removed in the copy. These are usually `.Rproj.user/`
   and whatever your scripts write.

Without the script: copy the project folder in Explorer, then open the
copy's `.Rproj` with *Open with → SuperR*, or from *File → Open Project…* in
SuperR.

## Evidence (synthetic fixture)

`tests/superrstudio/fixtures/rstudio-project` is an invented project. It
holds twelve made-up catch rows, a stations table and a survey description;
no research data is included. It contains:

- a `.Rproj`;
- an R script using relative paths;
- CSV, `.rds` and `.RData` inputs;
- an R Markdown and a Quarto document;
- a `renv.lock`.

`tools/superrstudio/test-packaged.ps1` opens a copy in the installed SuperR
and checks the following:

- the project directory and working directory;
- the script reading CSV, RDS and RData and writing CSV, RDS and a ggplot2
  PNG;
- the documents opening in the editor;
- the plot editor on the script's data.

It also verifies that the fixture files are unchanged after install, use and
uninstall. Results: [release checklist](release/RELEASE-CHECKLIST.md).

The fixture `renv.lock` is not activated: renv itself is not run, because it
would download packages. A project that uses renv behaves as in RStudio,
because the `.Rprofile` that activates renv is run by R. This has not been
tested with a real renv project here.
