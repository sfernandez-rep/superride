# Rolling back an upstream update

Every step of an upstream update can be undone without rewriting history.
Never use `git reset --hard` on a shared branch, `git push --force`, or tag
deletion to roll back. Use the commands below.

## Before the merge is committed

The branch exists only locally and the merge is uncommitted.

```powershell
# worktree (default prepare)
git -C ..\SuperRStudio-sync-2026.10.1 merge --abort
git worktree remove ..\SuperRStudio-sync-2026.10.1
git branch -D upstream-sync/rstudio-2026.10.1     # -D: the branch was never merged anywhere

# --in-place prepare
git merge --abort
git switch -                                        # back to the previous branch
git branch -D upstream-sync/rstudio-2026.10.1
```

`git merge --abort` also restores the pin files and removes the staged
review record, because they are part of the merge's index. The fetched
upstream tag can stay; it is upstream's.

## Committed on the sync branch, not merged into develop

Abandon the branch: close its pull request with the reason, then delete the
branch (`git push origin --delete upstream-sync/rstudio-2026.10.1`, and
`git branch -D` locally). Before deleting, keep a record: add an entry to
[history.md](history.md) under "Assessments not incorporated" with the
reason, and commit the review record to `develop` if it holds findings worth
keeping.

## Merged into develop, not yet in main

Revert the merge commit on `develop` through a pull request:

```powershell
git switch develop; git pull --ff-only
git log --grep "^Upstream-Tag: v2026.10.1+239" --format="%H %s"   # the merge commit
git switch -c revert/rstudio-2026.10.1
git revert -m 1 <merge commit>
```

`-m 1` keeps SuperR's side. The revert also restores the previous pin,
`product.json` and history file, because they changed in the merge. Then:

- the revert also removes the release's entry from `upstream-history.json`.
  Add it back at the end with status `reverted`, plus `reverted` (date) and
  `reason`. `check-baseline.py` compares the pin with the last entry that is
  not reverted, which is again the previous baseline;
- push the branch and open a pull request into `develop`;
- run gates A2, A4 and A5 on the result.

To retry the same release later, revert the revert (`git revert <revert commit>`)
on a new `upstream-sync/*` branch, or prepare the next release. Do not merge
the old sync branch again: Git considers it merged.

## Released from main

1. **Users:** the previous installer stays available as a GitHub release
   asset. Users uninstall the new version and install the previous one.
   SuperR's settings live in `%APPDATA%\SuperR` and `%LOCALAPPDATA%\SuperR`.
   Newer RStudio code can migrate state files forward, so tell users to back
   those folders up before installing a release with a new upstream base, and
   to restore the backup after a downgrade if the older version misbehaves.
   RStudio's own folders are never touched.
2. **Source:** revert the upstream merge on `develop` as above, then merge
   `develop` into `main` by pull request. Release a new version with a
   **higher** SuperR version number (never reuse a released version or tag)
   that states the base it returned to.
3. **Record:** the history entry gets status `reverted` with the date and
   the reason (as above); the release notes say so.

## Toolchain

New dependency versions install in versioned folders next to the old ones
([toolchain.md](toolchain.md)), and host tools are installed side by side
until the update is accepted, so going back to the previous pin needs no
reinstallation. Rebuild after switching (`dev-build.ps1 -Reconfigure`).
SuperR's copies of version numbers return with the reverted merge.

## Verifying a rollback

```powershell
python tools\superrstudio\check-baseline.py      # pin == history's last entry, tag present
python tools\superrstudio\check-integration.py   # SuperR changes intact against the restored pin
git log --oneline --first-parent -5               # the revert is a normal commit; nothing was rewritten
```
