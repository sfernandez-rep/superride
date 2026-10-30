# Updating SuperR to a new RStudio release

Repeatable procedure for moving SuperR's base to a newer **official** RStudio
release. Policy and branches: [README.md](README.md). Commands are for
PowerShell on the Windows development host, from the main checkout
`D:\Git\SuperRStudio`; Python 3 and Git are the only requirements of the
script itself.

## 1. Choose a release and assess it (read-only)

```powershell
git ls-remote --tags upstream "refs/tags/v2026.*"        # official release tags
python tools\superrstudio\upstream-sync.py v2026.10.1+239   # assess against develop
```

`assess` fetches **only that tag** from `upstream`, after checking with
`git ls-remote` that upstream's server has it at the same commit. It refuses a
non-release name (`main`, a branch, a hash), a tag that is not newer than the
current pin, a tag already in the base, and a local tag that differs from
upstream's (it never overwrites tags). It writes a report to
`.cache\superrstudio\upstream-sync\` (not in Git) with:

- upstream's release notes (`version/news/`), commits and changed files;
- **files changed on both sides**: upstream files that SuperR also modifies,
  with the SuperR area and notes from `superrstudio/integration-points.json`
  (review these first);
- SuperR files that upstream now also adds (name collisions);
- toolchain and dependency files changed, with the version lines
  ([toolchain.md](toolchain.md));
- generated files changed upstream, with the command that regenerates them;
- whether the current pin is an ancestor of the new tag (normal for patch
  releases; for a new calendar release check the report carefully if not).

Decide from the report whether to proceed. Patch releases (`2026.10.x`) are
usually small; a new calendar release (`2026.12.0`) can change thousands of
files and the toolchain.

## 2. Prepare the merge on a temporary branch

```powershell
python tools\superrstudio\upstream-sync.py v2026.10.1+239 --action prepare
# or, to build and test in this checkout (clean tree needed; reuses build\ and .cache\):
python tools\superrstudio\upstream-sync.py v2026.10.1+239 --action prepare --in-place
```

`prepare` creates `upstream-sync/rstudio-2026.10.1` from `develop` (`--base`
to change it) in a new worktree `..\SuperRStudio-sync-2026.10.1`, or in this
checkout with `--in-place`, and:

1. runs `git merge --no-ff --no-commit <tag commit>`;
2. moves the pin: `superrstudio/upstream.json` (status `under-review`),
   `package/superr/product.json` → `upstream` and a new
   `superrstudio/upstream-history.json` entry;
3. if there are no conflicts, runs `check-baseline.py`,
   `check-integration.py` and `check-identity.ps1`;
4. writes the review record `docs/superrstudio/upstream/reviews/rstudio-<version>.md`
   (the assessment, conflicts, check results and the acceptance table) and
   stages it with the pin;
5. writes the merge commit message with the trailers `Upstream-Tag`,
   `Upstream-Commit`, `Previous-Upstream`, `Upstream-Commits`, `Review`.

It **does not commit or push**, and never touches `main` or `develop`. Exit
code 2 means conflicts or a failed check. To abandon the attempt, see
[rollback.md](rollback.md#before-the-merge-is-committed).

## 3. Review and resolve

```powershell
cd ..\SuperRStudio-sync-2026.10.1          # or stay, with --in-place
git status
git diff --cached --stat
```

Read every upstream change in the "changed on both sides" list and the
release notes, and look for security fixes in particular. For each conflict,
**keep upstream's change and re-apply SuperR's**. Never discard upstream code
to make a conflict go away, and never discard a SuperR marker. Rules by kind:

| Kind | Resolution |
| --- | --- |
| SuperR hook in an upstream file (`SUPERR CHANGE`, `SuperRStudio:` comments, one-line registrations) | Take upstream's version of the file, then re-add the SuperR lines at the equivalent place. `check-integration.py` lists any marker that went missing |
| Generated files (`UserPrefValues.hpp`, `UserPrefsAccessor.java`, `Commands.cmd.xml.MD5`) | Never merge by hand. Resolve the source (`user-prefs-schema.json`, `Commands.cmd.xml`), then regenerate: `Rscript scripts/generate-prefs.R`; rebuild GWT for the MD5 |
| Translations (`*_en.properties`, `*_fr.properties`) | Keep both sides' keys |
| Installer (`NSIS.template.in`, `package/win32/*`) | Re-apply the `CPACK_SUPERR_*` substitutions. Upstream changes here always need the packaged-app gate (A8) |
| Desktop (`main.ts`, `forge.config.js`, `install-fuses.mjs`) | `applySuperRIdentity()` must still run before `loadAppConfig()`; the Windows packager config still reads `package/superr/product.json` |
| `README.md`, `CONTRIBUTING.md` | Keep the SuperR section on top; take upstream's text below it |
| A new upstream file whose name a SuperR file already uses | Rename the SuperR file (and its references), never upstream's |

If upstream moved or removed the code a SuperR hook attached to, redesign
that hook as a small additive change. Record the decision in the review
record, and update `superrstudio/integration-points.json` (markers, notes)
in the same merge.

Then, until all three pass:

```powershell
python tools\superrstudio\check-baseline.py
python tools\superrstudio\check-integration.py
tools\superrstudio\check-identity.ps1
git add <resolved files>
git commit                                 # uses the prepared message; keep the trailers
```

`check-baseline.py` accepts an uncommitted merge (the pin is in `MERGE_HEAD`).

## 4. Build and run the acceptance gates

Follow [acceptance.md](acceptance.md) and fill in the record's acceptance
table with results and evidence. A worktree has its own `build\` and no
`.cache\`. Either build it from scratch (run `tools\superrstudio\bootstrap-tools.ps1`,
then copy, not link, `.cache\superrstudio\electron-runtime`, `r-library` and
`ui-client` from the main checkout), or remove the worktree after committing
and switch the main checkout to the branch:

```powershell
git worktree remove ..\SuperRStudio-sync-2026.10.1   # refuses if anything is uncommitted
git switch upstream-sync/rstudio-2026.10.1
```

Do **not** use a junction or symbolic link to the main checkout's `.cache`:
Windows PowerShell 5.1's `Remove-Item -Recurse` follows junctions and would
delete the shared tools and R library.

## 5. Publish for review

```powershell
git push origin "refs/tags/v2026.10.1+239"          # CI verifies the pin against this tag
git push -u origin upstream-sync/rstudio-2026.10.1
gh pr create --repo sfernandez-rep/superride --base develop --head upstream-sync/rstudio-2026.10.1 `
  --title "Update the RStudio base to 2026.10.1+239" --body-file <review record>
```

Always pass `--repo sfernandez-rep/superride`. Without it, `gh` targets the
parent repository, `rstudio/rstudio`.

Before approving, the record's acceptance table must be complete. Then set
the history entry to `accepted`, with `incorporated` (date), `superr_commit`
(the merge commit) and `acceptance` (evidence files), and set
`superrstudio/upstream.json` → `assessment` to `accepted`. Commit that on the
branch. The pull request into `main` (from `develop`) runs
`check-baseline.py --accepted`, which fails while any baseline is still
under review.

Merge with **"Create a merge commit"**. Release `main` only after the
`develop` → `main` pull request; record the update in [history.md](history.md)
in the same pull request.

## What must survive

| Concern | Where | Verified by |
| --- | --- | --- |
| Product identity (name, version, About dialog with "Based on RStudio" and the independence notice) | `package/superr/product.json`, `SuperRProduct.java`, `AboutDialogContents.*`, `rStudioEditionName` | `check-identity.ps1`, `check-integration.py`, About dialog in A7 |
| Installer identity and side by side (own folder, ProgIDs, registry key, shortcuts; no default-program change) | `package/win32/superr-registry.cmake`, `NSIS.template.in`, `package/CMakeLists.txt`, `forge.config.js` | `test-packaged.ps1` (A8) |
| Configuration isolation (`%APPDATA%\SuperR`, `%LOCALAPPDATA%\SuperR`, never RStudio's) | `superr-identity.ts`, call in `main.ts` | `test-packaged.ps1` snapshots (A8) |
| Session modules (plot editor, length-frequency, optional packages) and their RPC | `SessionSuperRStudio*.{cpp,hpp,R}`, `SessionMain.cpp`, `SessionClientInit.cpp`, `RemoteServer.java` | R contract tests (A5), GUI (A7) |
| Generated R scripts and saved formats (`# SuperRStudio <kind> v6` plot specs, `superrstudio-lfq-analyses`, `.rs.superrstudioBrand()`) | `SessionSuperRStudio*.R` | `visual-scatter.R`, `lfq-tropfishr.R` (A5): previously saved specifications and analyses still load |
| Workbench integration (Visual tab, commands, preferences, Spanish) | `PaneManager.java`, `PaneConfig.java`, `Commands.cmd.xml`, prefs schema | `test-gui-scatter.ps1 -Scenario visual,theme,es` (A7) |
| Licences and attribution | `COPYING`, `NOTICE`, headers, `MODIFIED-FILES.txt` | `check-baseline.py`, A11 |
