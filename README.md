SuperRStudio
=============================================================================

An independent fork of RStudio Desktop for reproducible visual scientific
workflows, with a focus on biology, ecology and fisheries research.

**Status: unmodified baseline builds on Windows 11.** The source is pinned to
RStudio **2026.10.0+233** (`e961c6137d92315437caf5af53959f7110b517f9`). The
toolchain, upstream dependencies, GWT, native backend and Electron package have
built successfully. R-session tests pass with R 3.6.3 and 4.6.1; one core test
assumes English Windows error messages and fails on this Spanish host. Desktop
GUI workflows and full compatibility remain unverified. Visual dataset and
ggplot2 editors remain planned. See the
[current provisioning and build assessment](docs/superrstudio/baseline/windows-dependencies-2026-10-27.md).

- [Fork and upstream pin](UPSTREAM.md)
- [Build instructions and actual blockers](BUILDING.md)
- [Architecture and extension decisions](ARCHITECTURE.md)
- [Milestones and next tasks](ROADMAP.md)
- [Compatibility matrix and test plan](COMPATIBILITY.md)
- [Initial execution evidence](docs/superrstudio/baseline/2026-10-27.md)
- [Contribution instructions](CONTRIBUTING.md) and [agent instructions](AGENTS.md)

Preserve the traditional RStudio workbench and active R session. Add visual
operations incrementally, using established R packages and reproducible code.
Existing research datasets and project environments must never change silently.

Upstream AGPLv3 and third-party terms remain in [COPYING](COPYING) and
[NOTICE](NOTICE). This fork is not endorsed by Posit. The original upstream
README is preserved below.

RStudio
=============================================================================

RStudio is an integrated development environment (IDE) for the
[R programming language](https://www.r-project.org). Some of its
features include:

- Customizable workbench with all of the tools required to work with R in one
  place (console, terminal, source, plots, environment, history, help, files,
  packages, etc.).
- Syntax highlighting editor with code completion.
- Execute code directly from the source editor (line, selection, or file).
- Authoring of reproducible documents and reports with Quarto and R Markdown.
- Optional AI features, including GitHub Copilot completions, Posit AI Pass
  Next Edit Suggestions, and the [Posit Assistant](https://assistant.posit.co/).
- Support for authoring Sweave and TeX documents.
- Runs on Windows, Mac, and Linux, and has a community-maintained
  [FreeBSD port](https://www.freshports.org/devel/RStudio/).
- Can also be run as a server, enabling multiple users to access the RStudio
  IDE using a web browser.

For more information on RStudio please visit the
[project website](https://posit.co/products/open-source/rstudio).

Getting the Code
-----------------------------------------------------------------------------

RStudio is licensed under the AGPLv3, the terms of which are included in
the file COPYING. You can find our source code repository on GitHub at [https://github.com/rstudio/rstudio](https://github.com/rstudio/rstudio).

Documentation
-----------------------------------------------------------------------------

For information on how to use RStudio, see the
[RStudio User Guide](https://docs.posit.co/ide/user/).

See also the following files included with the distribution:

- COPYING - RStudio license (AGPLv3)
- NOTICE  - Additional open source software included with RStudio
- SOURCE  - How to obtain the source code for RStudio
- INSTALL - How to build and install RStudio from source

If you have problems or want to share feedback with us please visit our
[community forum](https://forum.posit.co/c/rstudio-ide). For other
inquiries you can also email us at [info@posit.co](mailto:info@posit.co).

Contributing
-----------------------------------------------------------------------------

We welcome contributions to RStudio. Please see
[CONTRIBUTING.md](CONTRIBUTING.md) for details on filing bugs, requesting
enhancements, and submitting code.
