# SuperRStudio

Read [HANDOFF.md](HANDOFF.md) first, then
[supplemental continuity instructions](docs/superrstudio/CONTINUITY.md).
Keep the handoff current, do not repeat verified work, and continue through
roadmap milestones when feasible. Graphify analysis has priority; no external
code transmission or automatic agent transfer is authorized by this handoff.
The Windows 11 development baseline now passes the live desktop smoke. Local
Graphify is available through `tools/superrstudio/graphify-local.ps1`; see its
review record for limits. The visual scatter slice is desktop-verified; continue
with scatter appearance controls (see the handoff's next tasks). Build and run
with `tools/superrstudio/dev-*.ps1` as described in BUILDING.md.

Follow [AGENTS.md](AGENTS.md) for fork-specific instructions and current gates.
Read [UPSTREAM.md](UPSTREAM.md) and the current
[baseline report](docs/superrstudio/baseline/windows-dependencies-2026-10-27.md) before implementation.

The original upstream guidance remains at [.claude/CLAUDE.md](.claude/CLAUDE.md).
Preserve it for upstream synchronization. Verify its examples against the pinned
source; fork status and baseline acceptance are recorded in the root documents.
