# SuperRStudio agent instructions

Read `HANDOFF.md` first and keep it current at milestones and before stopping.
Follow the supplemental instructions in `docs/superrstudio/CONTINUITY.md` along
with the original project brief. Continue completed work; do not restart or
reinstall verified tools. Advance to the next verified roadmap milestone when
resources permit. Prefer inspected, local Graphify analysis; external model/code
transmission requires user authorization. Do not install Ponytail at this stage.

Read `UPSTREAM.md`, `BUILDING.md`, `ARCHITECTURE.md`, `COMPATIBILITY.md` and
`docs/superrstudio/baseline/2026-10-27.md` before work. The Windows baseline now
builds; its version checks, R-session suites and live desktop GUI smoke pass.
The development baseline is accepted. The localized logging-test failure and
dependency audit remain documented release issues, not reasons to repeat setup.

The host toolchain has been provisioned and the full native/Electron build passes. Read
`docs/superrstudio/baseline/windows-dependencies-2026-10-27.md` for the current
assessment. Use `tools/superrstudio/enter-windows.cmd` in Command Prompt. Do not
infer that MSVC is still missing from the historical initial failure report.
For day-to-day work use `tools/superrstudio/dev-build.ps1` / `dev-run.ps1`
(incremental, isolated profiles; see BUILDING.md) and verify visual features in
the live desktop (`tools/superrstudio/test-gui-scatter.ps1` is the pattern).
SuperRStudio features stay opt-in behind `SUPER_RSTUDIO_EXPERIMENTAL=1`.
TropFishR (with its dependencies) is installed only in the isolated test
library for the length-frequency module; never install it into user or
project libraries. Long analyses run in a separate Rscript process, never on
the session thread.

- This is an RStudio fork. Preserve the existing GWT workbench, Electron shell,
  C++/R session, `.Rproj`, packages, themes, shortcuts and reporting workflows.
- Inspect the real subsystem and callers before editing. Prefer existing modules,
  RPC/events, package APIs and upstream build scripts. Keep diffs small and additive.
- Pin upstream revisions; do not invent versions, paths or APIs. Keep `COPYING`,
  `NOTICE`, copyright attribution and third-party obligations intact.
- Use `feature/*` for features, `develop` for integration and `upstream-sync/*`
  for upstream assessment. No force-push, history deletion or overwriting existing
  repositories. Coordinate separate worktrees for concurrent agents.
- Do not install candidate scientific packages or alter R/renv project libraries
  without an explicit need and user action. No silent dataset or source-file edits
  in product workflows. Keep the active R session authoritative.
- Visual operations must retain structured parameters and reproducible R code.
  Validate and quote user input; never concatenate it into executable R.
- Keep the R API on the session thread. Async transport does not make R thread-safe.
- No placeholder UI, arbitrary-script round-trip promises, independent dataset
  state, framework rewrite or speculative dependency additions.
- Generated binaries, caches, secrets and research data stay out of Git.
- Run `python tools/superrstudio/check-baseline.py`; use `--pristine` for the
  foundation/baseline assessment. Run affected upstream suites for source changes.
  A failed configure is not a compile, and a skipped test is not a pass.
- Each completed task records files, decisions, build/test commands and results,
  limitations and next actions. Update the baseline report when blockers change.

For detailed upstream conventions consult `.claude/CLAUDE.md` where applicable.
Its descriptions are guidance, not proof: verify against source. In particular,
RPC transport wiring and generated command files need inspection before edits.
