# Windows 11 desktop baseline acceptance

Executed 2026-10-28 against pristine worktree `D:\Git\SuperRStudio-baseline`,
upstream `e961c6137d92315437caf5af53959f7110b517f9`. No baseline source changes.
Used its existing compiled Electron main/renderer and native session, with the
original Electron 43.7.7 runtime ZIP already cached by the successful build.
No complete rebuild, OS change or security setting change was required.

The packaged `rstudio.exe --version-json` check alone was insufficient: CMake's
packaging output does not stage a complete distributable backend. The GUI was
launched in development mode with `RSTUDIO_CPP_BUILD_OUTPUT` pointing at the
existing native build. `ELECTRON_RUN_AS_NODE` inherited from the agent host must
be removed from the child environment. No `--no-sandbox` flag was passed.

The isolated profile/data/library/project live under
`.cache/superrstudio/gui-baseline`. No AI credentials were copied or provisioned.
Playwright 1.61.1 (client only, no browser download/install scripts) connected to
Electron over localhost CDP port 19381. It used the upstream automation bridge,
Ace editor input and actual R commands, not a simulated page or separate Rscript.

Validated: R 4.6.1 console; CSV numeric types and five rows; lm coefficients 1/2;
normal graphics device; CSV and PDF output; source editor open/edit/save with disk
verification; disposable `.Rproj` open and active working directory. No client
exceptions were recorded. Screenshots and runtime logs are in the cache folder.

Reproduction from the fork (substitute paths on another machine):

```powershell
$node = 'D:\Git\rstudio-tools\dependencies\common\node\22.22.2\node.exe'
$env:NODE_PATH = "$PWD\.cache\superrstudio\ui-client\node_modules"
# If absent, install the client only: npm install --prefix .cache/superrstudio/ui-client --ignore-scripts --save-exact playwright@1.61.1
# Extract the existing verified build-cache Electron ZIP into .cache/superrstudio/electron-runtime first.
& $node tools/superrstudio/launch-desktop-smoke.cjs 'D:\Git\SuperRStudio-baseline' "$PWD\.cache\superrstudio\electron-runtime\electron.exe"
# In another shell, with the same NODE_PATH:
& $node tests/superrstudio/desktop-smoke.cjs
```

The launcher remains attached while the IDE is open. The compiled main script
also appears as a source tab on first launch; the smoke closes it without edits.
This is development acceptance, not installer/distribution certification.
The localized logging test and production npm audit findings remain as recorded
in `windows-dependencies-2026-10-27.md`. They were assessed as non-blocking for
additive development; dependency fixes and packaged-installer testing are still
required before a release. Windows 10 and Ubuntu GUI compatibility remain untested.
