# SuperRStudio architecture

Status: source investigation; application extensions are **not implemented**.
The baseline and evidence are in [UPSTREAM.md](UPSTREAM.md).

## Existing architecture verified in source

| Responsibility | Actual implementation |
| --- | --- |
| Desktop shell and R discovery | `src/node/desktop/src/main/`, including `session-launcher.ts`, `detect-r.ts` and `utils.ts` |
| Desktop IPC and native adapters | `src/node/desktop/src/renderer/`, `src/node/desktop/src/native/` |
| IDE workbench | Java/GWT and JavaScript in `src/gwt/`; GIN injection and presenter/view patterns |
| Frontend transport | `src/gwt/src/org/rstudio/studio/client/server/remote/RemoteServer.java`, `server/Server.java` and feature server-operation interfaces |
| Active R session | C++ `src/cpp/session/SessionMain.cpp`, `src/cpp/r/session/RSession.cpp`, `src/cpp/r/RExec.cpp` |
| Module lifecycle and RPC | `SessionMain.cpp` initialization list, `src/cpp/session/include/session/SessionModuleContext.hpp` |
| Dataset import | `src/cpp/session/modules/data/SessionData.cpp`, `SessionDataImport.R`, `SessionDataImportV2.R`; GWT `workbench/views/environment/dataimport/` |
| Data viewer | `src/cpp/session/modules/data/DataViewer.cpp`, `SessionDataViewer.R`; GWT `dataviewer/DataTable.java` and `workbench/views/source/editors/data/` |
| Graphics | `src/cpp/session/modules/SessionPlots.cpp`, `SessionPlots.R`, `src/cpp/r/session/graphics/`; GWT `workbench/views/plots/` |
| Packages and project environment | `SessionPackages.cpp`/`.R`, existing project and renv integrations |
| Background jobs | `src/cpp/session/modules/jobs/` and `SessionAsyncRProcess`; distinct R processes, not the live session |
| Build and packaging | CMake/Ninja, Ant/GWT, npm/Electron Forge; CPack and `package/{win32,linux}/` |

Electron is the existing shell, with TypeScript and some Vue components. The
main IDE remains GWT. `src/node/desktop/README.md` confirms there is no remaining
Qt desktop implementation. We will extend these components incrementally.

The data viewer registers `/grid_data`, an HTTP resource handler, plus
`remove_cached_data`; not every data operation is JSON-RPC. It keeps cached,
working and search-projection R environments. A viewer can outlive deletion of
its original R object. Those caches cannot become the write authority for edits.
The frontend listens for `DataViewChangedEvent`. Reuse and test this refresh
path rather than adding an independent browser-side dataset store.

## Decisions for the first extension (proposed, gated on baseline build)

1. Add one narrowly scoped session module and a GWT view using existing RPC,
   events, commands, theme resources and project context. Use a `superrstudio`
   feature namespace and `superrstudio_` RPC prefix. No second R execution engine.
2. Resolve datasets in the active session. Operations carry an object identifier,
   expected revision, selected columns and explicit parameters. Validate object
   type and revision immediately before applying a change. Reject stale edits,
   renamed/deleted objects, unsupported classes and invalid coercions.
3. Start read-only: dataset/column selection and one scatter plot. Add mutations
   only with explicit apply, reproducible code, source preservation and undo
   semantics. Copy-on-modify can consume substantial memory; measure it.
4. Keep the R API on its owning session thread. An async RPC alone does not make
   R calls thread-safe or cancellable. Background processes may work on explicit,
   versioned snapshots; they must never pretend to share mutable session state.
5. Save operation specifications, generated code, inputs/revisions, parameters,
   R/package versions, warnings and project metadata together. Save through the
   existing project context, using atomic replacement and a recoverable history.
   Specify the file format when the first working operation exists.

## Plot editing investigation and decision

A versioned, serializable specification will own dataset references, mappings,
layers, facets, scales, coordinates, labels, themes and export dimensions.
Generate R expressions from validated fields using R-side construction and
quoting; do not interpolate user text into executable R. Reject unsupported
fields. Arbitrary imported R code remains read-only unless safely recognized.

The [ggplot2 build pipeline](https://ggplot2-book.org/internals.html) transforms
data, computes statistics and creates grid/gtable output. Its internal output
is version-sensitive and is not itself our persistence format. Rendering must
use the project's installed ggplot2 version and record it. Export uses the same
plot object and explicit device, physical dimensions and DPI via
[ggsave](https://ggplot2.tidyverse.org/reference/ggsave.html).

| Candidate | Finding and decision |
| --- | --- |
| R-generated SVG / grid | Preferred experiment for preview fidelity. Built-in SVG is available; [svglite](https://svglite.r-lib.org/) preserves text and offers web-friendly output. Neither provides a guaranteed mapping from every SVG node to source rows. |
| ggplot2/grid metadata | Investigate layer/panel and axis hit regions against pinned package versions. Aggregated statistics and transformed coordinates require explicit selection semantics. |
| [plotly/ggplotly](https://plotly-r.com/overview.html) | Converts to a different rendering system. Evaluate interaction as an optional adapter; do not make it authoritative for publication output without fidelity tests. |
| [esquisse](https://dreamrs.github.io/esquisse/) | Existing Shiny add-in with visual mappings and code export. Evaluate reuse before building equivalent controls; its gadget lifecycle and dependencies need assessment for integrated editing. |

First preview: exact R-rendered output with form controls and layer selection.
Point hit-testing, right-click styles and double-click labels require a tested
semantic overlay keyed to the specification. They are later work; editing a
raster or an SVG element directly must never silently change the plot's model.
Support English and Spanish through existing localization mechanisms when UI
work starts; retain keyboard navigation, theme behavior and console access.

## Synchronization cost

Keep fork changes additive and small. Expected wiring points are the session
initialization list/CMake source list and GWT commands, transport and injection.
Do not modify these until a clean baseline launches. Reassess each upstream
upgrade with the compatibility matrix; there is no evidence of full compatibility yet.
