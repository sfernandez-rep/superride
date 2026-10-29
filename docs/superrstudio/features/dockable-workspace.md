# Dockable scientific workspace: investigation (phase 4, Milestone D)

Status 2026-10-29: **investigated, not yet implemented.** The plot editor and the length-frequency window stay non-modal floating windows. They are the supported path, and the console, editor and panes remain usable while they are open.

## How RStudio's panes work (pinned sources)

| Concern | Where |
| --- | --- |
| Tab identity | `PaneManager.Tab` enum. Its names are what the `panes` preference stores. `PaneManager` maps tabs to widgets, labels, zoom commands and pane-layout commands in `getTab`, `getAllTabs`, `tabForName`, `getLayoutCommandForTab` and `getLayoutCommands`. |
| Valid layouts | `PaneConfig.getAllTabs()` is the master list. `PaneConfig.createDefault()` is the default layout. |
| Validation | `PaneConfig.validateAndAutoCorrect()` → `PaneManager.validateConfig()`. |
| Widgets | One `WorkbenchTab` per tab (usually `DelayLoadWorkbenchTab` with a presenter and pane), bound with `bindTab(name, Class)` in `RStudioGinModule`. |
| Commands | `activateXxx` and `layoutZoomXxx` are defined in `Commands.cmd.xml`, plus `.MD5`, `Commands.java`, `CmdConstants*` and `AppCommands.R`. Handlers live in `WorkbenchScreen`. |
| Hidden or conditional tabs | `WorkbenchTab.isSuppressed()`, used by Connections, Build, VCS and Presentation. Alternatively, the flag checks used for Chat in `PaneManager` and `PaneLayoutPreferencesPane`. |
| Preference defaults | `user-prefs-schema.json` (`panes`). The generated `UserPrefsAccessor` and `UserPrefValues` hold the fallbacks. |

A new tab touches about ten upstream files (Java, the command XML and its checksum, constants, and the R command list).

**Finding that matters for safety:** a saved layout that lacks a new tab name is accepted by validation, but the tab is then placed in no panel. `activateTab` and `zoomTab` dereference the missing panel, which causes an NPE. Upstream avoided this for Chat by adding a new `sidebar` field whose default holds the tab. A SuperRStudio tab therefore needs a migration step that adds the name to `hiddenTabSet` when it is absent. That needs a setter, because `getHiddenTabSet()` returns a fresh array when the field is missing.

## Recommended smallest safe foundation

1. Add a **"Visual" workbench tab** that hosts the plot editor's content (preview, settings tabs, code, export).
   - It is a `DelayLoadWorkbenchTab` that is suppressed unless `SUPER_RSTUDIO_EXPERIMENTAL=1` is reported by the session (`isSuppressed()`, as for Connections).
   - Its pane-layout checkbox is hidden while suppressed.
   - Its `activateVisual` and `layoutZoomVisual` commands are hidden on session start when suppressed (as Presentation2 does).
2. **Default placement:** `hiddenTabSet` in `PaneConfig.createDefault()` and in the schema default. A fix-up in `validateAndAutoCorrect()` adds "Visual" to `hiddenTabSet` for saved layouts that do not mention it. Activation moves it into a visible pane with RStudio's own `moveTabToVisiblePanel`.
3. **Refactor the editor once** so that its body is a widget that can live either in the existing floating `DialogBox` or in the tab. Keep the floating window as the fallback; the toolbar button keeps opening it.
4. **Tests:**
   - A desktop scenario: activate the tab, render, zoom the pane, move it between quadrants in Pane Layout, then restart with a saved layout that predates the tab.
   - With the feature off, the IDE must be byte-for-byte unchanged in behaviour, so the `disabled` scenario must still pass.

Not done in this session: the change spans the command registry, its checksum and the pane configuration, which every IDE start depends on. It needs its own focused session with the restart and migration tests above.
