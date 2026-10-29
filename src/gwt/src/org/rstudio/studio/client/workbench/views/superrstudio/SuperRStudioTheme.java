// SPDX-License-Identifier: AGPL-3.0-only
package org.rstudio.studio.client.workbench.views.superrstudio;

import com.google.gwt.dom.client.Document;
import com.google.gwt.dom.client.Element;
import com.google.gwt.dom.client.StyleInjector;
import com.google.gwt.user.client.ui.Label;
import com.google.gwt.user.client.ui.UIObject;
import com.google.gwt.user.client.ui.Widget;
import org.rstudio.studio.client.RStudioGinjector;

// Design tokens and a few shared styles for SuperRStudio's windows. Colours
// are defined for RStudio's light and dark themes with at least 4.5:1 contrast
// against the dialog backgrounds of the built-in themes; spacing and type
// sizes are relative so the windows follow the IDE's zoom and high-DPI
// scaling. Classes are prefixed "srs-" to stay apart from upstream styles.
public class SuperRStudioTheme
{
   public static final String DIALOG = "srs-dialog";
   public static final String HINT = "srs-hint";
   public static final String STATUS = "srs-status";
   public static final String BUSY = "srs-busy";
   public static final String ERROR = "srs-error";
   public static final String COLUMNS = "srs-columns";
   public static final String SETTINGS_COLUMN = "srs-settings-column";
   public static final String PREVIEW_COLUMN = "srs-preview-column";
   public static final String DOCKED = "srs-docked";

   public static void ensureInjected()
   {
      if (injected_)
         return;
      injected_ = true;
      StyleInjector.inject(
         ".srs-dialog { --srs-space-1: 0.25em; --srs-space-2: 0.5em; --srs-muted: #4d4d4d;" +
         " --srs-error: #a4001f; --srs-accent: #0b5cad; }\n" +
         ".srs-dialog.rstudio-themes-dark { --srs-muted: #e6e6e6; --srs-error: #ffd0d0; --srs-accent: #a8d4ff; }\n" +
         ".srs-dialog .srs-hint { font-size: 90%; color: var(--srs-muted) !important; line-height: 1.35; }\n" +
         ".srs-dialog .srs-status { min-height: 1.35em; padding: var(--srs-space-1) 0; white-space: pre-line; }\n" +
         ".srs-dialog .srs-error { color: var(--srs-error) !important; font-weight: 600; }\n" +
         ".srs-dialog .srs-busy::before { content: ''; display: inline-block; width: 0.8em; height: 0.8em;" +
         " margin-right: var(--srs-space-2); vertical-align: -0.1em; border: 2px solid var(--srs-accent);" +
         " border-right-color: transparent; border-radius: 50%; animation: srs-spin 0.8s linear infinite; }\n" +
         "@media (prefers-reduced-motion: reduce) { .srs-dialog .srs-busy::before { animation: none; } }\n" +
         "@keyframes srs-spin { to { transform: rotate(360deg); } }\n" +
         ".srs-dialog :focus-visible { outline: 2px solid var(--srs-accent); outline-offset: 1px; }\n" +
         ".srs-columns { display: flex; flex-wrap: wrap; align-items: flex-start; }\n" +
         ".srs-docked .srs-preview-column { order: -1; }\n");
   }

   // Like upstream's ModalDialogBase: a theme-aware dialog, dark when the IDE
   // theme is dark and dark modal dialogs are enabled. Popups live outside the
   // themed container, so the class is synchronized whenever the window shows.
   public static void dialog(Widget dialog)
   {
      ensureInjected();
      dialog.addStyleName(DIALOG);
      dialog.addStyleName("rstudio-theme-aware-dialog");
      syncDark(dialog);
      dialog.addAttachHandler(event -> {
         if (event.isAttached())
            syncDark(dialog);
      });
   }

   public static void syncDark(UIObject dialog)
   {
      Element container = Document.get().getElementById("rstudio_container");
      boolean dark = container != null && container.hasClassName("rstudio-themes-dark") &&
         RStudioGinjector.INSTANCE.getUserPrefs().useDarkThemeModalDialogs().getValue();
      dialog.setStyleName("rstudio-themes-dark", dark);
   }

   public static Label hint(Label label)
   {
      label.addStyleName(HINT);
      return label;
   }

   // A status line: busy (with a spinner), an error, or plain information.
   public static void status(Label label, String text, String state)
   {
      label.addStyleName(STATUS);
      label.setStyleName(BUSY, BUSY.equals(state));
      label.setStyleName(ERROR, ERROR.equals(state));
      label.getElement().setAttribute("aria-busy", String.valueOf(BUSY.equals(state)));
      label.setText(text);
   }

   private static boolean injected_ = false;
}
