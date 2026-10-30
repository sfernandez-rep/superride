# SuperR and upstream RStudio

SuperR is an independent product built on RStudio. It has its own stable
branch, releases, identity, tests and roadmap. It takes upstream RStudio
fixes and improvements **only when the owner decides to move its base to a
newer official RStudio release**, through a reviewed, tested and approved
pull request. Nothing merges upstream changes automatically.

| Document | Content |
| --- | --- |
| This page | Policy, branching model, GitHub settings |
| [sync-process.md](sync-process.md) | Step-by-step upstream update with `tools/superrstudio/upstream-sync.py`, conflict resolution, what must survive |
| [acceptance.md](acceptance.md) | Gates an upstream update must pass before approval (R contract, upstream suites, GUI, packaged app, benchmarks, compatibility, licences) |
| [toolchain.md](toolchain.md) | Updating build dependencies and the toolchain when a new RStudio release needs them |
| [rollback.md](rollback.md) | Undoing an upstream update or a release, at every stage |
| [history.md](history.md) | Upstream releases SuperR has been based on, and assessments |
| [reviews/](reviews/) | One review record per upstream update |

Machine-readable records, in version control:

| File | Content | Checked by |
| --- | --- | --- |
| `superrstudio/upstream.json` | The current upstream pin (version, tag, commit, dates, status) | `check-baseline.py` |
| `superrstudio/upstream-history.json` | Every upstream baseline, oldest first; the last one is the pin | `check-baseline.py` |
| `superrstudio/integration-points.json` | Every upstream file SuperR modifies, with text that must survive a merge | `check-integration.py` |
| `package/superr/product.json` → `upstream` | The upstream version the build reports to R packages and the installer uses | `check-integration.py` |

## Policy

1. **The base is an official release tag**, `vYYYY.MM.PATCH+BUILD` from
   https://github.com/rstudio/rstudio, verified on upstream's server. SuperR
   never takes upstream `main`, a daily build or a pre-release branch.
2. **Never automatically.** Upstream changes reach `develop` and `main` only
   through a pull request after the gates in [acceptance.md](acceptance.md)
   pass and the owner approves. The sync script never commits or pushes.
3. **History is never rewritten.** No force push, no `reset` of SuperR
   branches to upstream, no squash or rebase merges of upstream updates. Every
   upstream commit stays reachable, and every update is one merge commit with
   `Upstream-Tag:` and `Upstream-Commit:` trailers
   (`git log --grep "^Upstream-Tag:"` lists them).
4. **SuperR stays SuperR.** Identity, installer identity, side-by-side
   behaviour, configuration isolation, the session modules, generated-script
   formats and saved-analysis formats survive every update
   ([sync-process.md](sync-process.md#what-must-survive)).
5. **Licences and attribution.** `COPYING`, `NOTICE`, upstream copyright
   headers and the "based on RStudio" attribution are kept; `COPYING` and
   `NOTICE` always equal upstream's at the pin (`check-baseline.py`). The
   installer's `MODIFIED-FILES.txt` lists SuperR's changes against the pin
   (AGPL-3.0 section 5(a)).

## Branching model

| Branch | Purpose | Created from | Merges into | Lifetime |
| --- | --- | --- | --- | --- |
| `main` | Stable SuperR: every commit is releasable and tested | — | — | permanent |
| `develop` | Integration of finished features and accepted upstream updates | `main` | `main` by pull request | permanent |
| `feature/<topic>` | One feature or fix | `develop` | `develop` by pull request | until merged |
| `upstream-sync/rstudio-<YYYY.MM.PATCH>` | One upstream update under review | `develop` | `develop` by pull request | until merged or abandoned |
| `release/<version>` | Optional stabilisation of a release | `develop` | `main` by pull request | until released |
| `baseline/rstudio-<version>` | The unmodified upstream release (reference) | upstream tag | never | permanent, read-only |

Tags:

- Upstream tags keep upstream's names (`v2026.10.0+233`) and point to
  upstream commits. The tag of every accepted baseline is pushed to `origin`
  so CI can verify the pin.
- SuperR release tags use the prefix **`superr-v`** (`superr-v0.1.0-preview.1`,
  created by `superr-release.yml`) so they never collide with upstream's `v`
  tags.

`origin` also holds hundreds of upstream branches (`feature/…`, `bugfix/…`,
release branches) copied when the fork was created. They are upstream's, not
SuperR's. SuperR's own branches are `main`, `develop`, the `feature/*`
branches named in [HANDOFF.md](../../../HANDOFF.md) and the branches above.

Flow: `feature/*` and `upstream-sync/*` → `develop` → (`release/*`) →
`main`. Pull requests into `main` come only from `develop` or `release/*`;
the one exception is the first integration of `feature/visual-scatter`,
because `develop` and `main` were identical when this model was set up.
After a merge into `main`, fast-forward `develop`
(`git push origin main:develop`; it is refused if it is not a fast-forward).

### Merging pull requests

Use **"Create a merge commit"** for every pull request into `develop` and
`main`. *Squash* and *rebase* create new commits: they would drop the
upstream commits from the history and change the commit hashes recorded in
release evidence (for example the release candidate built from
`4d6c72279c`).

## GitHub settings

- **Never use GitHub's "Sync fork" button** (or `gh repo sync`). The repository
  is a GitHub fork of `rstudio/rstudio`, so GitHub offers to merge upstream's
  current `main` (not a release) straight into SuperR's `main`, which
  bypasses every gate here.
- **Inherited upstream workflows are disabled.** The `.github/workflows/os-*.yml`
  files are upstream's CI. They need Posit's runners, secrets, S3 and
  daily-build infrastructure, and failed on the fork every day. They stay in
  the tree, so upstream merges don't conflict, but are disabled in the
  repository's Actions settings (2026-10-30). Re-enable one with
  `gh workflow enable <file> --repo sfernandez-rep/superride`. After an
  upstream update, disable any new `os-*` workflow:
  `gh workflow list --all --repo sfernandez-rep/superride`.
- SuperR's own workflows: `superr-checks.yml` (identity and R contract tests),
  `superrstudio-foundation.yml` (provenance, integration points, R fixture),
  `superr-release.yml` (installer, manual).
- **Recommended, not applied (owner's decision):** a ruleset or branch
  protection on `main` and `develop` that requires a pull request and the
  status checks `checks` (SuperR checks) and `foundation` (both operating
  systems), blocks force pushes and deletion, and allows only merge commits
  (Settings > General > Pull Requests: disable squash and rebase merging).
  With a single maintainer, a required approval count of 1 would block the
  owner's own pull requests; review is recorded in the pull request and the
  review record instead.
