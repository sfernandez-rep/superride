# Roadmap

All acceptance checks require recorded execution, not just compilation.

| Milestone | Status | Exit criteria |
| --- | --- | --- |
| 0. Upstream investigation | Initial assessment recorded | Verified source pin, architecture, license inventory, host/toolchain evidence and risks; complete dependency/build assessment with M1 |
| 1. Reproducible baseline | **Blocked locally** by missing MSVC and elevation | Unmodified Windows 11 source build; launch and active R session; core workflow tests; exact tool versions and logs |
| 2. Foundation | Planned; gated on M1 | Small feature module, branding/update endpoint audit, feature switch and no baseline regressions |
| 3. Visual dataset workflow | Planned | Select live data/columns, generate scatter plot in the same session, export R code; stale-object and cancellation tests |
| 4. ggplot2 editor | Planned | Versioned specification, layers/scales/themes/facets, undo/redo, validated preview/export; then semantic element interactions |
| 5. Statistical interface | Planned | Guided methods/assumptions and diagnostics, trusted numerical references and complete reproducibility records |
| 6. Biological extensions | Planned | Evaluate vegan/FSA/TropFishR methods individually with reference datasets, applicability and version checks |
| 7. Modern UI | Planned | Light/dark themes, accents, accessible keyboard interaction, high-DPI and English/Spanish acceptance checks |
| 8. Cross-platform releases | Planned | Windows installer and Ubuntu 24.04 .deb tested in clean machines; license/source/branding review and reproducible release records |

## Next engineering tasks

1. From an administrator-capable Windows environment, install the pinned VS 2026
   toolchain and required SDK. Follow [BUILDING.md](BUILDING.md); do not substitute
   VS 2022 or MinGW for the upstream prebuilts.
2. Install upstream dependencies from the pinned checkout; inventory downloaded
   versions and checksums. Assess the old R build bootstrap separately from the
   R version used for modern scientific packages.
3. Build and launch **unmodified** `baseline/rstudio-2026.10.0`, record logs and
   execute the [compatibility plan](COMPATIBILITY.md). Classify dependency or
   upstream failures before editing build logic.
4. Run the existing source-build CI workflows explicitly against that baseline
   when an appropriate hosted runner is available. No daily installer may stand
   in for a source build.
5. Repeat on a native Ubuntu 24.04 VM and establish the first tested matrix.
6. Only after M1 passes, implement the read-only dataset-to-scatter vertical
   slice described in [ARCHITECTURE.md](ARCHITECTURE.md).

No dataset editor, plot editor, statistical module, package-management extension,
modernized workbench, installer or Linux build is implemented or verified yet.
