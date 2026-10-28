# Upstream baseline

Verified on **2026-10-27** (America/Montevideo):

| Item | Value |
| --- | --- |
| Project | RStudio Desktop Open Source, Blue Mistflower |
| Latest stable release identified | **2026.10.0+233**, released 2026-10-14 |
| Source tag | `v2026.10.0+233` |
| Exact commit | `e961c6137d92315437caf5af53959f7110b517f9` |
| Upstream | https://github.com/rstudio/rstudio |
| Fork | https://github.com/sfernandez-rep/superrstudio |
| Build acceptance | Windows 11 source build PASS; desktop GUI acceptance pending; known locale-sensitive test and npm audit findings |

The machine-readable pin is [superrstudio/upstream.json](superrstudio/upstream.json).
This is a source baseline under assessment, not a tested SuperRStudio release.

## Evidence

- [Posit release notes](https://docs.posit.co/ide/news/#2026.10.0) identify the release date and codename.
- [Posit user guide](https://docs.posit.co/ide/user/) identifies 2026.10.0 as the current documentation release.
- [GitHub tag ref API](https://api.github.com/repos/rstudio/rstudio/git/refs/tags/v2026.10.0%2B233) identifies a lightweight tag pointing directly to the commit above.
- [Source commit](https://github.com/rstudio/rstudio/commit/e961c6137d92315437caf5af53959f7110b517f9) is dated 2026-10-14, with message `update notice file for Blue Mistflower (#19103)`.
- `git ls-remote --tags https://github.com/rstudio/rstudio.git 'refs/tags/v2026.10*'` independently returned the same revision.
- GitHub's releases endpoint is not the release authority here; this project publishes source tags and Posit installers.

## Branches and history

`main` starts at the pinned release and carries reviewed SuperRStudio work;
`develop` is the integration branch. Use `feature/*` for isolated features and
`upstream-sync/*` for an explicit upstream upgrade assessment. No release is
considered stable until the build and compatibility gates pass.

GitHub initially copied upstream's current `main` at
`758ba570f0850efab375a8b213162452f092d3c5`. That newly created fork branch was
renamed to `upstream-initial-main` before creating our pinned `main`, preserving
the original tip without a force-push. `baseline/rstudio-2026.10.0` retains the
unmodified release commit. Existing upstream branch and tag history is retained.
The local clone is partial (`--filter=blob:none`), not shallow; Git fetches
historical blobs on demand.

Remotes: `origin` is the SuperRStudio fork; `upstream` is `rstudio/rstudio`.
Fetch upstream tags, investigate a candidate on `upstream-sync/*`, build it
unmodified, execute the compatibility matrix, then update the pin and evidence
in a dedicated review. Never silently advance the baseline or force-push history.

## Attribution and distribution

Keep upstream [COPYING](COPYING), [NOTICE](NOTICE), copyright headers, and
[SOURCE.in](SOURCE.in). New fork code uses AGPL-3.0-only unless a documented
compatible third-party license applies. See the license text for the applicable
terms; distribution review must include modified-source notices, Corresponding
Source and build instructions, bundled component licenses, and the network-use
source provisions when applicable. Do not imply endorsement by Posit.

Before distributing, review generated `SOURCE`, `NOTICE`, installer identity,
trademarks, update endpoints and crash-reporting destinations. Source-build
metadata still uses upstream branding and paths; no installer is ready for release.
