# Upstream history

The official RStudio releases SuperR has been based on, oldest first. The
machine-readable record is `superrstudio/upstream-history.json`, and its
last baseline that is not reverted is the pin (`superrstudio/upstream.json`),
which `check-baseline.py` verifies. Each update is one merge commit; list
them with `git log --grep "^Upstream-Tag:" --format="%h %cs %s"`.

## Baselines

| RStudio release | Tag and commit | Incorporated | How | Review and acceptance | Status |
| --- | --- | --- | --- | --- | --- |
| 2026.10.0+233 "Blue Mistflower" (released 2026-10-14) | `v2026.10.0+233`, `e961c6137d92315437caf5af53959f7110b517f9` | 2026-10-27 | Fork baseline: SuperR's `main` starts at this commit (`5f29e2fc4f` is SuperR's first commit) | [baseline assessment](../baseline/2026-10-27.md), [Windows build and tests](../baseline/windows-dependencies-2026-10-27.md), [GUI](../baseline/windows-gui-2026-10-28.md) | accepted |

## Assessments

Upstream releases that were assessed but are not, or not yet, part of
SuperR, with the reason.

| RStudio release | Assessed | Result | Next step |
| --- | --- | --- | --- |
| 2026.10.1+239 (`0b06695c24`, committed 2026-10-23) | 2026-10-30 | 6 upstream commits, 13 files: a session start-up fix for `.Rproj.user` on filesystems that refuse ACL writes (#19118), macOS OpenSSL build fixes, documentation. No file changed on both sides; no Windows toolchain change | Candidate; see [HANDOFF.md](../../../HANDOFF.md) |
