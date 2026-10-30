# Acceptance gates for an upstream update

An upstream update is accepted only when every gate below passes on the
`upstream-sync/*` branch, the results are recorded in its review record
(`reviews/rstudio-<version>.md`, "Acceptance" table) and the owner approves
the pull request. A skipped gate is not a pass: record why it could not run,
and treat the update as not accepted unless the owner explicitly accepts the
gap in the pull request.

The reference values are the last accepted results ([HANDOFF.md](../../../HANDOFF.md),
"Latest test results"), measured on the same Windows 11 x64 host. Commands
are PowerShell, from the checkout being tested. The R tests use the isolated
library: `$env:R_LIBS_USER = "$PWD\.cache\superrstudio\r-library"`.

| Gate | Command | Passes when |
| --- | --- | --- |
| **A1** Source review | Read the review record, upstream's release notes and every "changed on both sides" diff (`git diff <old tag> <new tag> -- <file>`) | Every both-sides file and security-relevant change has been read; findings recorded |
| **A2** Source checks | `python tools\superrstudio\check-baseline.py`; `python tools\superrstudio\check-integration.py`; `tools\superrstudio\check-identity.ps1` | All PASS; no unresolved conflict markers (`git diff --check`) |
| **A3** Toolchain | [toolchain.md](toolchain.md) | Every changed upstream pin is installed and verified; SuperR's own copies of versions are updated |
| **A4** Build | `tools\superrstudio\dev-build.ps1 -Reconfigure` (native + GWT); desktop with upstream's `src\node\desktop` build when Electron or Node changed | Exit 0, no new warnings treated as errors |
| **A5** SuperR R contract tests | `Rscript tests\superrstudio\visual-scatter.R`; `Rscript tests\superrstudio\lfq-tropfishr.R`; `Rscript tests\superrstudio\deps.R` (R 4.6.1); the first two also with R 3.6.3 (missing-package path) | All PASS. Plot specifications and saved analyses written by the previous build still load (the tests include them) |
| **A6** Upstream suites | `tools\superrstudio\test-session.cmd experimental`; `build\superrstudio-windows\src\cpp\rstudio-tests.bat --scope core` | Same or better than the reference (rsession 654 passed / 655, 1 skipped; core: only the known locale failure `LoggingTest.CanJsonLogError`). A new failure must also be checked on the **unmodified** new tag (baseline worktree, below); it is acceptable only if upstream fails identically, and it is recorded |
| **A7** Live desktop GUI | `tools\superrstudio\test-gui-scatter.ps1 -Scenario ggplot2,no-ggplot2,disabled,lfq,es,visual,theme,deps` | All 12 runs PASS (visual and theme are three launches each; one rerun allowed for the known intermittent *Refresh data* timeout in `ggplot2`, recorded) |
| **A8** Installer and packaged app | First raise `version`/`prerelease` in `package/superr/product.json`: a new base is a new SuperR build, and `package-superr.ps1` writes to `dist\superr\`, where it would overwrite a verified or released installer of the same version. Then `tools\superrstudio\package-superr.ps1 -Reconfigure`; `tools\superrstudio\test-packaged.ps1 -Installer dist\superr\SuperR-<version>-Windows-x64.exe` | Package builds; packaged tests 0 failed (66 checks at 0.1.0-preview.1), including side by side, own settings folders, no default-program change, clean uninstall |
| **A9** Benchmarks | `tools\superrstudio\bench.ps1 -Runs 3` (baseline = unmodified new tag, see below) | Compared with [benchmarks.md](../benchmarks.md): start-up to ready, console round trip and session memory with features off within 5 % of the unmodified upstream build, and with features on within 10 % of the previous record. A larger difference is explained or fixed before acceptance |
| **A10** Project compatibility | `tools\superrstudio\test-project-copy.ps1 -Project tests\superrstudio\fixtures\rstudio-project` with the installed package from A8 | [project-compatibility.md](../project-compatibility.md): the copy opens, nothing in the project changes except RStudio's own state files |
| **A11** Licences and attribution | `git diff <old tag> <new tag> -- NOTICE COPYING`; `MODIFIED-FILES.txt` from A8 | New third-party components reviewed for distribution; `COPYING`/`NOTICE` equal upstream's; About dialog shows "Based on RStudio <new version>"; release notes name the new base |
| **A12** Record and approval | Review record complete; history entry and pin `accepted`; CI (`SuperR checks`, `SuperRStudio foundation`) green on the pull request | Owner approves the pull request |

## The unmodified comparison build

A6 and A9 compare against the **unmodified** upstream release, built in the
pristine baseline worktree `D:\Git\SuperRStudio-baseline` (detached, never
edited). Move it to the new tag and rebuild it with the commands in the
[baseline report](../baseline/windows-dependencies-2026-10-27.md):

```powershell
git -C D:\Git\SuperRStudio-baseline switch --detach "v2026.10.1+239"
git -C D:\Git\SuperRStudio-baseline status --short     # must print nothing
```

If the new release changes the dependency set, rerun upstream's dependency
installer for the baseline worktree first ([toolchain.md](toolchain.md)).

## Recording

For each gate, record in the review record's table the result, the date,
and the evidence: a log or screenshot path under `.cache\superrstudio\…` that
stays local, and a summary or count that goes into the record. Never
record a result that was not observed. Copy the summary rows into
[HANDOFF.md](../../../HANDOFF.md) when the update is accepted.
