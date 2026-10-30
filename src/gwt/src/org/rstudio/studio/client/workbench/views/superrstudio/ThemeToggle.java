// SPDX-License-Identifier: AGPL-3.0-only
package org.rstudio.studio.client.workbench.views.superrstudio;

import com.google.gwt.dom.client.StyleInjector;
import com.google.gwt.user.client.ui.Button;
import org.rstudio.core.client.StringUtil;
import org.rstudio.core.client.widget.NullProgressIndicator;
import org.rstudio.studio.client.RStudioGinjector;
import org.rstudio.studio.client.application.events.ThemeChangedEvent;
import org.rstudio.studio.client.workbench.prefs.model.UserPrefs;
import org.rstudio.studio.client.workbench.prefs.model.UserState;
import org.rstudio.studio.client.workbench.views.source.editors.text.themes.AceTheme;
import org.rstudio.studio.client.workbench.views.source.editors.text.themes.AceThemes;

// One-click switch between a light and a dark editor theme, in the global
// toolbar. It uses RStudio's own theme machinery exactly as Appearance >
// Apply does (the global editor_theme preference and the applied theme in
// user state), so the IDE, the editor and SuperRStudio windows change
// together and the choice persists across restarts. The last light and the
// last dark theme in use are remembered, so a custom theme returns when the
// user switches back; until a theme of the other kind has been used, the
// built-in defaults (Textmate, Tomorrow Night) are chosen.
public class ThemeToggle extends Button
{
   public ThemeToggle()
   {
      SuperRStudioTheme.ensureInjected();
      injectStyles();
      prefs_ = RStudioGinjector.INSTANCE.getUserPrefs();
      state_ = RStudioGinjector.INSTANCE.getUserState();
      themes_ = RStudioGinjector.INSTANCE.getAceThemes();
      getElement().setId("rstudio_superrstudio_theme_toggle");
      setStyleName("srs-theme-toggle");
      addClickHandler(event -> toggle());
      RStudioGinjector.INSTANCE.getEventBus().addHandler(ThemeChangedEvent.TYPE, event -> update());
      update();
   }

   private AceTheme current()
   {
      return state_.theme().getValue() == null ? null : (AceTheme) state_.theme().getValue().cast();
   }

   private boolean dark()
   {
      AceTheme theme = current();
      return theme != null && theme.getIsDark();
   }

   // the icon shows what a click does: a moon switches to dark, a sun to light
   private void update()
   {
      AceTheme theme = current();
      boolean dark = dark();
      if (theme != null)
         remember(dark, theme.getName());
      String target = remembered(!dark);
      String text = dark ? messages_.themeToLight(target) : messages_.themeToDark(target);
      getElement().setInnerHTML(dark ? SUN : MOON);
      setTitle(text);
      getElement().setAttribute("aria-label", text);
      getElement().setAttribute("data-theme-dark", String.valueOf(dark));
   }

   private void toggle()
   {
      boolean dark = dark();
      String wanted = remembered(!dark);
      themes_.getThemes(themes ->
      {
         AceTheme target = themes.get(wanted);
         if (target == null || target.getIsDark() == dark)
            target = themes.get(AceTheme.createDefault(!dark).getName());
         if (target == null)
            return;
         prefs_.editorTheme().setGlobalValue(target.getName(), false);
         state_.theme().setGlobalValue(target);
         prefs_.writeUserPrefs();
         state_.writeState();
      }, new NullProgressIndicator());
   }

   private static String key(boolean dark)
   {
      return dark ? "superrstudio.theme.dark" : "superrstudio.theme.light";
   }

   private static void remember(boolean dark, String name)
   {
      if (!StringUtil.isNullOrEmpty(name))
         setItem(key(dark), name);
   }

   private static String remembered(boolean dark)
   {
      String name = getItem(key(dark));
      return StringUtil.isNullOrEmpty(name) ? AceTheme.createDefault(dark).getName() : name;
   }

   // the browser's local storage of this desktop profile (absent: defaults)
   private static native String getItem(String key) /*-{
      try { return $wnd.localStorage.getItem(key); } catch (e) { return null; }
   }-*/;

   private static native void setItem(String key, String value) /*-{
      try { $wnd.localStorage.setItem(key, value); } catch (e) {}
   }-*/;

   private static void injectStyles()
   {
      if (injected_)
         return;
      injected_ = true;
      StyleInjector.inject(
         ".srs-theme-toggle { display: inline-flex; align-items: center; justify-content: center;" +
         " width: 24px; height: 22px; margin: 0 4px; padding: 0; border: 1px solid transparent;" +
         " border-radius: 4px; background: transparent; color: inherit; cursor: pointer; }\n" +
         ".srs-theme-toggle:hover { border-color: rgba(127, 127, 127, 0.55); }\n" +
         ".srs-theme-toggle:focus-visible { outline: 2px solid #0b5cad; outline-offset: 1px; }\n" +
         ".rstudio-themes-dark-menus .srs-theme-toggle:focus-visible { outline-color: #a8d4ff; }\n" +
         ".srs-theme-toggle svg { width: 16px; height: 16px; display: block; }\n");
   }

   private final UserPrefs prefs_;
   private final UserState state_;
   private final AceThemes themes_;
   private static boolean injected_ = false;
   private static final ScatterMessages messages_ = SuperRStudioLanguage.scatter();
   private static final String MOON =
      "<svg viewBox='0 0 16 16' aria-hidden='true' focusable='false'><path fill='none' stroke='currentColor'" +
      " stroke-width='1.4' stroke-linejoin='round' d='M13.5 9.6A5.6 5.6 0 0 1 6.4 2.5a5.6 5.6 0 1 0 7.1 7.1z'/></svg>";
   private static final String SUN =
      "<svg viewBox='0 0 16 16' aria-hidden='true' focusable='false'><g fill='none' stroke='currentColor'" +
      " stroke-width='1.4' stroke-linecap='round'><circle cx='8' cy='8' r='3'/><path d='M8 1.2v1.6M8 13.2v1.6" +
      "M1.2 8h1.6M13.2 8h1.6M3.2 3.2l1.1 1.1M11.7 11.7l1.1 1.1M3.2 12.8l1.1-1.1M11.7 4.3l1.1-1.1'/></g></svg>";
}
