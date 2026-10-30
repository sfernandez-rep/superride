# Upstream review: RStudio 2026.10.1+239

Generated 2026-10-30 by `tools/superrstudio/upstream-sync.py v2026.10.1+239 --action prepare --base feature/visual-scatter`. Process: [sync-process.md](../sync-process.md); criteria: [acceptance.md](../acceptance.md).

| Item | Value |
| --- | --- |
| Upstream tag | `v2026.10.1+239` (lightweight, verified with `git ls-remote` against https://github.com/rstudio/rstudio.git) |
| Upstream commit | `0b06695c24e10f6de6b9166c35ae24804c21f95f`, committed 2026-10-23 (check the release date in Posit's release notes) |
| Current SuperR baseline | `v2026.10.0+233` (`e961c6137d92315437caf5af53959f7110b517f9`) |
| SuperR base | `feature/visual-scatter` at `bc2d214d03e815fad7d2816b9829dc10399d4f52` |
| Current baseline contained in the new tag | yes |
| Upstream commits | 6 (5 non-merge) |
| Upstream files changed | 13 |
| Changed on both sides | 0 |
| Toolchain/dependency files changed | 2 |
| Comparison | https://github.com/rstudio/rstudio/compare/v2026.10.0%2B233...v2026.10.1%2B239 |

## Upstream release notes

`version/news/os/NEWS-2026.10.1-blue-mistflower.md`:

> ## RStudio 2026.10.1 "Blue Mistflower" Release Notes
>
> ### Fixed
> - ([#19118](https://github.com/rstudio/rstudio/issues/19118)): Fixed an issue where sessions failed to start when a project's `.Rproj.user` directory lived on a filesystem that refuses ACL writes, such as an NTFS mount.

## Files changed on both sides (review first)

None: upstream did not change any file that SuperR modifies.

## SuperR files that upstream now also adds

None.

## Toolchain and dependency changes

Apply them as described in [toolchain.md](../toolchain.md) before building.

- `src/cpp/CMakeLists.txt` (M)
- `version/PATCH` (M)

Version-related lines:

```diff
src/cpp/CMakeLists.txt: +   if(APPLE AND RSTUDIO_PACKAGE_BUILD AND NOT OPENSSL_VERSION MATCHES "^3\\.")
src/cpp/CMakeLists.txt: +      message(FATAL_ERROR "macOS package builds require OpenSSL 3.x, but found ${OPENSSL_VERSION} at '${OPENSSL_ROOT_DIR}'. Install it with '${HOMEBREW_PREFIX}/bin/brew install openssl@3' and reconfigure.")
```

## Generated files changed upstream

None.

## Merge

Prepared on branch `upstream-sync/rstudio-2026.10.1` with `git merge --no-ff --no-commit v2026.10.1+239`.

No conflicts.

Source checks at preparation:

- `check-baseline.py`: PASS
  > PASS: 2026.10.1+239 at 0b06695c24e10f6de6b9166c35ae24804c21f95f (under-review); provenance and licenses
  > This check does not compile or launch RStudio.
- `check-integration.py`: PASS
  > PASS: 46 upstream files carry SuperR changes, all documented and intact against 2026.10.1+239; 23 SuperR files present
- `check-identity.ps1`: PASS
  > Product identity consistent: SuperR 0.1.0-preview.1

## Upstream commits (non-merge)

<details>

```
2f0057aba7 2026-10-23 Update download link for Positron
1ee63fa486 2026-10-22 Backport macOS openssl@3 pin and OpenSSL 4 build fixes to rel-autumn-hawkbit (#19221)
c54d2ec718 2026-10-19 Raise the documented macOS minimum to 15+ (#19180)
d215e41ce8 2026-10-15 fall back to mode bits when a claim directory acl write is denied (#19126)
dab881c6b6 2026-10-14 Bump PATCH version for rel-blue-mistflower (#19112)
```

</details>

## All upstream file changes

<details>

```
M	docs/_snippets/download-desktop-cards.qmd
M	docs/_snippets/install-desktop-pro.qmd
M	docs/user/rstudio/download.qmd
M	docs/user/rstudio/ide/guide/accessibility/screen-reader.qmd
M	docs/user/rstudio/index.qmd
M	src/cpp/CMakeLists.txt
M	src/cpp/core/FileLockTests.cpp
M	src/cpp/core/file_lock/LinkBasedFileLock.cpp
M	src/cpp/core/include/core/FileLock.hpp
M	src/cpp/core/system/Crypto.cpp
M	src/cpp/core/system/CryptoTests.cpp
M	version/PATCH
A	version/news/os/NEWS-2026.10.1-blue-mistflower.md
```

</details>

## Acceptance

Complete every gate before the pull request is approved; record the result and the evidence.

| Gate | Result | Evidence |
| --- | --- | --- |
| A1 Source review (both-sides files, release notes, security fixes) | PASS, 2026-10-30 | No file changed on both sides. `LinkBasedFileLock.cpp`/`FileLock.hpp`: ACL fallback to mode bits only for a foreign-owned new claim directory (#19118), POSIX-only code, keeps refusing other ACL denials; no Windows effect. `Crypto.cpp`: the self-signed certificate subject is built as a separate `X509_NAME` (OpenSSL 4 const API); also compiled on Windows against OpenSSL 3.1.4, same result. `src/cpp/CMakeLists.txt`: UNIX include order and a macOS package guard. Docs, `version/PATCH`, release note. No security advisory |
| A2 Conflicts resolved; check-baseline, check-integration, check-identity | PASS, 2026-10-30 | No conflicts; the three checks pass on the prepared merge (above) |
| A3 Toolchain and dependency changes applied | PASS (none needed), 2026-10-30 | Windows dependency declarations unchanged; the OpenSSL check in `src/cpp/CMakeLists.txt` applies to macOS package builds only |
| A4 Native, GWT and Electron build | | |
| A5 SuperR R contract tests (visual-scatter, lfq-tropfishr, deps) | | |
| A6 Upstream test suites (rsession, core) against the previous baseline | | |
| A7 Live desktop GUI scenarios | | |
| A8 Installer build and packaged-application tests | | |
| A9 Benchmarks against the previous baseline | | |
| A10 Project compatibility (fixture and copied projects) | | |
| A11 Licences, NOTICE, attribution, MODIFIED-FILES | | |
| A12 History status accepted; CI green; owner approval | | |
