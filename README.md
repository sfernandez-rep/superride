SuperR
=============================================================================

![SuperR](assets/branding/generated/png/superr-128.png)

| | |
| --- | --- |
| **Authored by** | sfernandez |
| **Co-authored by** | Claude (Anthropic) & Codex (OpenAI) |

**SuperR** is an independent, experimental fork of RStudio Desktop for
reproducible visual scientific work in biology, ecology, marine science and
fisheries. It keeps the RStudio workbench and the active R session, and adds:

- a visual ggplot2 plot editor (docked in a *Visual* tab or floating) that
  writes clean, reproducible R code;
- length-frequency analysis with TropFishR: ELEFAN growth, catch curves,
  Beverton–Holt Z, yield per recruit and saved analyses;
- optional R packages installed only on request, with consent (renv-aware);
- a one-click light/dark switch and Spanish for the SuperR windows.

SuperR is not developed, endorsed or supported by Posit Software, PBC.
RStudio is a trademark of Posit Software, PBC.

**Status:** first Windows x64 preview (`0.1.0-preview.1`), based on RStudio
**2026.10.0+233** (`e961c6137d92315437caf5af53959f7110b517f9`). It has been
tested on Windows 11 x64 only. No public release has been published yet; see
the [release checklist](docs/superrstudio/release/RELEASE-CHECKLIST.md).

- [Release notes (draft)](docs/superrstudio/release/RELEASE-NOTES.md)
- [Windows packaging and side-by-side installation](docs/superrstudio/packaging-windows.md)
- [Using existing RStudio projects](docs/superrstudio/project-compatibility.md)
- [Branding](docs/superrstudio/BRANDING.md)
- [Fork and upstream pin](UPSTREAM.md)
- [Build instructions](BUILDING.md)
- [Architecture and extension decisions](ARCHITECTURE.md)
- [Milestones and next tasks](ROADMAP.md) and [handoff](HANDOFF.md)
- [Contribution instructions](CONTRIBUTING.md) and [agent instructions](AGENTS.md)

Repository: https://github.com/sfernandez-rep/superride (renamed from
`superrstudio`; the old URL redirects).

Existing research datasets and project environments must never change silently.
Upstream AGPLv3 and third-party terms remain in [COPYING](COPYING) and
[NOTICE](NOTICE). The original upstream README is preserved below.

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
