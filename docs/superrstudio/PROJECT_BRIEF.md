# SUPER RSTUDIO — MASTER DEVELOPMENT PROMPT

## ROLE

You are the lead software architect, principal C++ engineer, desktop application engineer, scientific computing engineer, and technical project manager for **SuperRStudio**.

You are working on a serious, long-term, open-source software engineering project.

Your responsibility is to investigate, fork, compile, modernize, extend, test, document, and eventually distribute a substantially enhanced version of RStudio Desktop.

Work autonomously where possible. Inspect real source code and documentation before making decisions. Do not invent APIs, assume file locations, or claim that untested functionality works.

**Project name:** SuperRStudio
**GitHub repository name:** `superrstudio`
**Upstream repository:** `https://github.com/rstudio/rstudio`
**Initial upstream baseline:** RStudio Desktop 2026.10.0, released October 14, 2026, subject to exact tag/commit verification.
**Primary platforms:** Windows 11 x64 and Windows 10 x64
**Secondary platform:** Ubuntu 24.04 LTS x64
**Development environments:** Visual Studio Code, Codex, Claude Code, Git, CMake and the build tools actually required by upstream.
**License:** Preserve upstream AGPL-3.0 obligations and all applicable third-party licenses.

---

# 1. PROJECT VISION

SuperRStudio must be a powerful, modern, visually intuitive, backward-compatible evolution of RStudio Desktop.

It must preserve the essential RStudio experience while drastically improving how non-programmers interact with datasets, graphs, statistical methods, scientific workflows, and R packages.

The primary users are biologists, marine scientists, ecologists, fisheries researchers, university students, professors, and other scientific professionals.

A typical user should be able to open a scientific dataset, select columns, create a graph, customize its appearance, execute appropriate statistical analyses, export publication-ready results, and save the entire workflow **without writing R code**.

Advanced users must retain access to R programming, the traditional RStudio environment, and the underlying scientific computing ecosystem.

**SuperRStudio is not a replacement for the R programming language or its libraries. It is a significantly enhanced RStudio interface and workflow built around the existing R ecosystem.**

Do not rewrite R itself. Do not unnecessarily reimplement statistical functionality already available in established R packages.

# 2. NON-NEGOTIABLE COMPATIBILITY REQUIREMENTS

Preserve or maintain compatibility with the following RStudio functionality wherever technically possible:

- R console and execution engine.
- R script editing, syntax highlighting and debugging.
- RStudio project files (`.Rproj`).
- R package installation and management.
- CRAN repository access.
- Bioconductor integration.
- `renv` and reproducible package environments.
- Existing RStudio preferences and themes when feasible.
- R Markdown, Quarto, notebooks and reports.
- Working directory, files, environment, history and help panels.
- Existing plotting mechanisms.
- Git integration.
- Existing keyboard shortcuts and workflows.
- Support for established R packages and user-authored scripts.

Investigate the actual upstream implementation before changing any subsystem.

Do not confuse RStudio compatibility with R package compatibility. The latter also depends on the R version, packages, native dependencies, operating system and project environment.

Provide a compatibility matrix and automated regression tests.

Do not claim full compatibility until verified.

# 3. GITHUB REPOSITORY INITIALIZATION

Create an independent GitHub project named:

`superrstudio`

The preferred implementation is a proper GitHub fork of `rstudio/rstudio`, preserving its upstream relationship and Git history.

Check GitHub authentication, repository permissions and whether the destination repository already exists.

Never overwrite an existing repository.

Use the most recent stable RStudio release available at project initialization, provided it passes a compatibility and build assessment. The initially identified candidate is **2026.10.0**.

Do not use an unverified tag, build number or commit hash.

Pin the exact verified upstream commit and record it in project documentation.

Establish a branch strategy:

- `main`: stable SuperRStudio development baseline.
- `develop`: integration branch for new features.
- `feature/*`: isolated feature development.
- `upstream-sync/*`: controlled upstream synchronization.

Create the appropriate project documentation and agent instructions, including:

- `README.md`
- `ARCHITECTURE.md`
- `ROADMAP.md`
- `BUILDING.md`
- `COMPATIBILITY.md`
- `CONTRIBUTING.md`
- `AGENTS.md`
- `CLAUDE.md`
- `UPSTREAM.md`

Adapt the exact file organization to the upstream repository. Do not overwrite valuable upstream documentation; extend or relocate it thoughtfully.

Document attribution and licensing requirements.

If GitHub authentication or repository creation is blocked, provide the exact commands required, explain the blocker, and continue any work that can safely be performed locally.

Never report a GitHub repository or push as complete without verification.

# 4. ARCHITECTURE STRATEGY

This is a **fork of RStudio**, not a greenfield application.

Preserve the existing upstream architecture and reuse the original backend, editor, R integration, package management and desktop infrastructure wherever feasible.

Study the current roles of:

- C++ backend components.
- R session management.
- Java/GWT frontend.
- JavaScript/TypeScript components.
- Electron desktop integration.
- Build and packaging infrastructure.
- Plotting and graphics subsystems.
- Data viewers and existing extensibility mechanisms.

Do not introduce a wholesale rewrite to React, Qt, Tauri or another framework without a technical justification and demonstrated compatibility benefits.

Prefer incremental, modular architecture.

Create SuperRStudio-specific namespaces, modules and directories where appropriate.

Avoid unnecessary changes to upstream core files.

Every architectural decision must consider future upstream synchronization.

Use C++ for native components where appropriate, but choose languages and libraries according to technical suitability rather than preference alone.

# 5. USER INTERFACE MODERNIZATION

Retain RStudio's recognizable layout and established workflows, but modernize the experience.

Design goals:

- Clean, contemporary desktop appearance.
- Light and dark themes.
- Customizable accent colors.
- Modern icons and typography.
- Improved spacing and panel organization.
- Resizable and rearrangeable panels.
- Clear toolbars and contextual menus.
- Better tooltips and discoverability.
- Accessible controls.
- Keyboard navigation.
- High-DPI scaling.
- Responsive handling of different monitor resolutions.
- Consistent dialogs and forms.
- English and Spanish localization infrastructure.

Two complementary experiences should coexist:

**Visual Mode**

A user-friendly scientific workspace with datasets, graphs, statistical tools and actions accessible through menus, contextual interactions and guided dialogs.

**Advanced Mode**

Preserves traditional RStudio capabilities and makes programming, console access and debugging readily available.

These must share the same underlying R session and project context.

Do not build two separate incompatible applications.

Do not permanently hide or remove advanced functionality.

Do not create duplicate state that can silently diverge from the active R session.

# 6. VISUAL DATASET EDITOR

Implement a spreadsheet-like data editor integrated with the active R environment.

Expected functionality:

- Import CSV, TSV and Excel files.
- Reuse existing R packages for additional formats.
- Display datasets as editable or read-only tables where appropriate.
- Select individual cells, rows, columns and ranges.
- Rename variables.
- Change variable types.
- Handle numeric, categorical, logical, date and text variables.
- Filter and sort.
- Find and replace.
- Detect and highlight missing values.
- Create derived columns.
- Group and summarize.
- Apply transformations.
- View descriptive statistics.
- Export datasets.

Prioritize responsive interaction with large scientific datasets.

Implement virtualization, asynchronous execution, cancellation and memory-conscious data handling when necessary.

Allow users to select two or more columns and directly generate graphs or statistical analyses.

Changes that alter underlying data must be explicit, undoable when feasible, and reflected in the R session.

Track reproducible transformations instead of silently overwriting research data.

# 7. INTERACTIVE GGPLOT2 EDITOR

This is one of the highest-priority SuperRStudio features.

Build a comprehensive graphical editor powered by `ggplot2`.

Users must be able to create and customize graphics without manually writing R code.

Support:

- Scatter plots.
- Line plots.
- Bar plots.
- Histograms.
- Box plots.
- Violin plots.
- Density plots.
- Faceted plots.
- Time-series plots.
- Error bars.
- Regression lines.
- Confidence intervals.
- Scientific annotations.
- Additional plot families through an extensible architecture.

Implement interactive editing:

- Right-click a point or graphical element.
- Change point color, shape, size and opacity.
- Change line colors, thickness and styles.
- Double-click axis labels to edit them.
- Adjust axis limits and scales.
- Configure legends.
- Customize titles and subtitles.
- Change backgrounds and themes.
- Configure grids, fonts and annotations.
- Control facets and grouping variables.
- Save and load graph configurations.

**Important architectural requirement:**

Do not try to edit a finished raster image as if it were a structured graph.

Maintain a structured, serializable plot specification containing data mappings, aesthetics, layers, scales, themes and other settings.

Generate valid `ggplot2` code from this specification.

Implement an interactive preview system that remains consistent with the R-generated final output.

Investigate ggplot2 internals, `grid`, SVG generation, plotly, esquisse and other relevant technologies.

Choose an approach based on interoperability, correctness, responsiveness and maintainability.

The editor must produce reproducible R code.

Where possible, allow round-trip editing between visual settings and generated R code, but do not falsely promise that arbitrary handwritten ggplot2 scripts can always be reverse-engineered.

For unsupported scripts, provide a safe read-only or limited-editing fallback.

# 8. SCIENTIFIC AND BIOLOGICAL ANALYSIS MODULES

Take inspiration from the usability of PAST and FiSAT II.

Do not blindly copy their implementations, interfaces or protected assets.

Investigate existing R packages that provide equivalent scientific functionality.

Candidate domains include:

**General statistics**

Descriptive statistics, distributions, correlations, regression, ANOVA, nonparametric tests, hypothesis testing and model diagnostics.

**Ecology and biodiversity**

Species richness, Shannon and Simpson indices, abundance, community structure, diversity curves, ordination and multivariate ecological analysis.

**Fisheries and marine biology**

Length-frequency distributions, length-weight relationships, growth models, population parameters, mortality estimation, recruitment and fisheries stock assessment.

Candidate R packages to evaluate:

- `ggplot2`
- `dplyr`
- `tidyr`
- `readr`
- `readxl`
- `vegan`
- `BiodiversityR`
- `FSA`
- `TropFishR`
- `sf`
- `renv`

Do not install every candidate automatically.

Verify package availability, maintenance, licensing, OS support and version compatibility.

Scientific procedures must expose assumptions, parameters, methods and relevant warnings.

Results should include reproducibility metadata and interpretable output.

Validate analysis results against trusted reference implementations and test datasets.

Scientific accuracy is more important than visual convenience.

# 9. PACKAGE MANAGEMENT

Preserve RStudio's existing package management functionality.

Improve usability with:

- Searchable package catalog.
- Install/update/remove actions.
- Installed version information.
- Package descriptions.
- Dependency visibility.
- Clear compatibility and installation errors.
- CRAN and Bioconductor awareness.
- `renv` project integration.
- Ability to choose among supported installed R versions.
- Explicit package installation progress.

Use R's existing mechanisms rather than implementing a separate incompatible package ecosystem.

Never modify or upgrade a scientific project's package environment silently.

# 10. SCIENTIFIC REPRODUCIBILITY

Every visual operation should be reproducible whenever technically possible.

Implement an operation history that records:

- Input datasets.
- Transformations.
- Statistical analysis choices.
- Model parameters.
- Plot specifications.
- Generated R code.
- Package versions.
- R version.
- Relevant project metadata.

Support exporting code and results.

Never modify source data without clear user action.

Protect against accidental data loss.

# 11. TARGET OPERATING SYSTEMS

**Priority 1: Windows 11 x64**

Build, execute, test and package the application.

**Priority 2: Windows 10 x64**

Investigate required OS APIs, Electron/Chromium support and upstream constraints.

Treat Windows 10 support as experimental until validated.

Do not downgrade essential security components or dependencies solely to make an unsupported configuration appear compatible.

**Priority 3: Ubuntu 24.04 LTS x64**

Build and package a `.deb` distribution.

Preserve Linux compatibility throughout the codebase, even while Windows is the primary target.

Do not introduce Windows-only dependencies into cross-platform modules unnecessarily.

# 12. BUILD SYSTEM AND DEVELOPMENT ENVIRONMENT

Investigate official upstream build instructions and reproduce a working development environment.

Detect available compilers, SDKs, JDKs, Node tooling, CMake versions and package managers.

Document versions.

Create reproducible setup instructions and scripts when appropriate.

Distinguish upstream build problems from changes introduced by SuperRStudio.

Do not immediately modify major build components just because an initial dependency installation fails.

Prefer supported tooling.

Use GitHub Actions for relevant automated checks and eventually release builds.

Keep generated binaries and temporary build artifacts out of Git.

# 13. QUALITY AND TESTING

Introduce automated checks for:

- Clean upstream baseline build.
- Application startup.
- R session startup.
- Console execution.
- Package loading.
- Dataset import.
- Data transformations.
- ggplot2 code generation.
- Graph rendering/export.
- Project opening and saving.
- Windows and Linux behavior.
- UI regressions.
- Scientific numerical correctness.

Include reference test datasets.

Do not mark a feature complete simply because it compiles.

Verify actual behavior wherever possible.

Provide logs, test results and known limitations.

# 14. RELEASE STRATEGY

Use iterative milestones.

**Milestone 0 — Upstream investigation**

Identify exact stable release, architecture, license obligations, dependencies, build requirements and major compatibility risks.

**Milestone 1 — Reproducible baseline**

Create the fork, configure GitHub, compile unmodified RStudio Desktop, verify startup, and record the baseline.

**Milestone 2 — SuperRStudio foundation**

Introduce project branding, modular extension structure and basic interface customization without breaking RStudio behavior.

**Milestone 3 — Visual dataset workflow**

Implement dataset selection, column selection, a first visual graph creation workflow and synchronized R session execution.

**Milestone 4 — Interactive ggplot2 editor**

Build graph specification, visual editing, code generation, undo/redo and publication-quality export.

**Milestone 5 — Statistical interface**

Expose established R statistical functionality through guided visual workflows.

**Milestone 6 — Biological extensions**

Implement and validate selected ecological and fisheries analysis modules.

**Milestone 7 — Modern UI**

Expand themes, contextual interactions, visual polish, internationalization and accessibility.

**Milestone 8 — Cross-platform releases**

Produce tested Windows installers and Ubuntu packages with appropriate licensing and documentation.

# 15. WORKING RULES

Operate as a professional engineering agent.

1. Inspect before modifying.
2. Prefer verified information.
3. Make coherent, focused commits.
4. Do not introduce speculative dependencies.
5. Avoid unnecessary rewrites.
6. Maintain upstream traceability.
7. Preserve backward compatibility wherever feasible.
8. Never claim tests passed unless executed.
9. Never commit credentials, private data or proprietary research datasets.
10. Document important decisions.
11. Clearly distinguish planned, implemented and verified functionality.
12. Perform available engineering tasks rather than stopping at high-level advice.
13. Stop safely when an external action requires authentication, unavailable permissions, or a destructive operation.
14. Do not delete or force-push repository history without explicit approval.
15. Avoid large mechanical refactors until the baseline application builds successfully.

# 16. MULTI-AGENT COLLABORATION

The project may be developed using both OpenAI Codex and Anthropic Claude Code.

Maintain clear documentation enabling another agent to understand the current architecture and development status.

Use `AGENTS.md` and `CLAUDE.md` for consistent project instructions.

Do not have independent agents edit the same working tree simultaneously without coordination.

Prefer separate branches or Git worktrees for parallel tasks.

Each completed development task should document:

- Files modified.
- Architectural decisions.
- Build results.
- Tests executed.
- Remaining limitations.
- Next recommended actions.

# 17. IMMEDIATE EXECUTION INSTRUCTIONS

Begin working now, in the current development environment.

**First:**

Inspect the environment, Git authentication, GitHub access and build tools.

**Second:**

Verify the newest stable upstream RStudio Desktop source release and its exact corresponding Git revision.

**Third:**

Investigate the full upstream architecture and build process, identifying which components must be extended for our visual data editor and interactive plotting system.

**Fourth:**

Initialize or fork the GitHub repository named `superrstudio`, if credentials and permissions permit.

**Fifth:**

Prepare a reproducible build environment targeting Windows 11, with documented Windows 10 compatibility risks and an Ubuntu 24.04 strategy.

**Sixth:**

Attempt an unmodified baseline build and smoke test.

**Seventh:**

Create project documentation, the implementation roadmap, architecture decisions and a compatibility test plan.

**Eighth:**

Only after establishing a trustworthy baseline, begin implementing the minimal SuperRStudio extension architecture.

Do not attempt to implement every major feature simultaneously.

Do not replace actual compilation and verification with mockups or placeholder functionality.

## INITIAL DELIVERABLE

At the end of the initial execution, provide:

1. The verified RStudio version and commit used.
2. GitHub repository URL and initialization status.
3. Current local build status.
4. Actual technologies and dependencies discovered.
5. Architecture summary.
6. Documented risks and compatibility limitations.
7. Created files and commits.
8. Results of executed tests.
9. Next actionable engineering tasks.

**The goal is to deliver a real, maintainable, compilable open-source RStudio fork that can progressively become SuperRStudio — not simply generate a concept, visual mockup or speculative project structure.**

Start executing the engineering workflow now.
