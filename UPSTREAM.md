# Upstream baseline

SuperR is an independent product built on RStudio. It moves to a newer
official RStudio release only by a reviewed, tested and approved pull
request. Policy, branching model, update procedure, acceptance gates,
toolchain updates, rollback and history:
**[docs/superrstudio/upstream/](docs/superrstudio/upstream/README.md)**.

Current base, verified on **2026-10-27** (America/Montevideo):

| Item | Value |
| --- | --- |
| Project | RStudio Desktop Open Source, Blue Mistflower |
| Release | **2026.10.0+233**, released 2026-10-14 |
| Source tag | `v2026.10.0+233` |
| Exact commit | `e961c6137d92315437caf5af53959f7110b517f9` |
| Upstream | https://github.com/rstudio/rstudio (remote `upstream`) |
| Fork | https://github.com/sfernandez-rep/superride (remote `origin`; renamed from `superrstudio` on 2026-10-29; the old URL redirects) |
| Acceptance | Windows 11 source build, version checks, upstream R-session suites and live desktop smoke PASS (2026-10-28); known locale-sensitive core test and npm audit findings |

Machine-readable: the pin [superrstudio/upstream.json](superrstudio/upstream.json),
the history [superrstudio/upstream-history.json](superrstudio/upstream-history.json)
and SuperR's changes to upstream files
[superrstudio/integration-points.json](superrstudio/integration-points.json),
checked by `tools/superrstudio/check-baseline.py` and `check-integration.py`.
Newer upstream releases are assessed with `tools/superrstudio/upstream-sync.py`
([history](docs/superrstudio/upstream/history.md)).

## Evidence

- [Posit release notes](https://docs.posit.co/ide/news/#2026.10.0) identify the release date and codename.
- [Posit user guide](https://docs.posit.co/ide/user/) identifies 2026.10.0 as the current documentation release.
- [GitHub tag ref API](https://api.github.com/repos/rstudio/rstudio/git/refs/tags/v2026.10.0%2B233) identifies a lightweight tag pointing directly to the commit above.
- [Source commit](https://github.com/rstudio/rstudio/commit/e961c6137d92315437caf5af53959f7110b517f9) is dated 2026-10-14, with message `update notice file for Blue Mistflower (#19103)`.
- `git ls-remote --tags https://github.com/rstudio/rstudio.git 'refs/tags/v2026.10*'` independently returned the same revision.
- GitHub's releases endpoint is not the release authority here; this project publishes source tags and Posit installers.

## Branches and history

`main` starts at the pinned release and carries reviewed SuperR work;
`develop` is the integration branch. Use `feature/*` for features and
`upstream-sync/rstudio-<version>` for an upstream update; see the
[branching model](docs/superrstudio/upstream/README.md#branching-model).

GitHub initially copied upstream's current `main` at
`758ba570f0850efab375a8b213162452f092d3c5`. That newly created fork branch was
renamed to `upstream-initial-main` before creating our pinned `main`, preserving
the original tip without a force-push. `baseline/rstudio-2026.10.0` retains the
unmodified release commit. Existing upstream branch and tag history is retained.
The local clone is partial (`--filter=blob:none`), not shallow; Git fetches
historical blobs on demand.

Never reset a SuperR branch to upstream, force-push, use GitHub's "Sync
fork", or merge upstream `main`. Never silently advance the pin.

## Attribution and distribution

Keep upstream [COPYING](COPYING), [NOTICE](NOTICE), copyright headers, and
[SOURCE.in](SOURCE.in). New fork code uses AGPL-3.0-only unless a documented
compatible third-party license applies. See the license text for the applicable
terms; distribution review must include modified-source notices, Corresponding
Source and build instructions, bundled component licenses, and the network-use
source provisions when applicable. Do not imply endorsement by Posit.

The installer's `MODIFIED-FILES.txt` and the release workflow's
`SOURCE.txt` list SuperR's changes against the pin and the corresponding
source. Before distributing, review the generated `SOURCE`, `NOTICE`, the
installer identity, trademarks, update endpoints and crash-reporting
destinations. The Windows preview installer is built and tested but not
published ([release checklist](docs/superrstudio/release/RELEASE-CHECKLIST.md)).
