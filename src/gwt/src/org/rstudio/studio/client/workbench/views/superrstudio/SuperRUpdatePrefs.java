// Copyright (C) 2026 SuperR contributors. SPDX-License-Identifier: AGPL-3.0-only
package org.rstudio.studio.client.workbench.views.superrstudio;

import org.rstudio.studio.client.RStudioGinjector;

/** SuperR-only desktop profile preferences; automatic checks require opt-in. */
public class SuperRUpdatePrefs
{
   public static boolean automatic() { return automatic_; }
   public static String channel() { return channel_; }
   private static void received(boolean automatic, String channel)
   {
      automatic_ = automatic;
      channel_ = "preview".equals(channel) ? "preview" : "stable";
   }
   private static void failed()
   {
      RStudioGinjector.INSTANCE.getGlobalDisplay().showErrorMessage("SuperR",
            SuperRStudioLanguage.spanish() ? "No se pudieron guardar las preferencias de actualización." : "Could not save update preferences.");
   }
   public static native void load(Runnable ready) /*-{
      var desktop = $wnd.desktop;
      if (!desktop || !desktop.superrGetUpdatePrefs) { ready.@java.lang.Runnable::run()(); return; }
      desktop.superrGetUpdatePrefs().then(function(value) {
         @org.rstudio.studio.client.workbench.views.superrstudio.SuperRUpdatePrefs::received(ZLjava/lang/String;)(!!value.automatic, value.channel);
         ready.@java.lang.Runnable::run()();
      }, function() { ready.@java.lang.Runnable::run()(); });
   }-*/;
   public static native void save(boolean automatic, String channel) /*-{
      var desktop = $wnd.desktop;
      if (!desktop || !desktop.superrSetUpdatePrefs) {
         @org.rstudio.studio.client.workbench.views.superrstudio.SuperRUpdatePrefs::failed()(); return;
      }
      desktop.superrSetUpdatePrefs(automatic, channel).then(function() {
         @org.rstudio.studio.client.workbench.views.superrstudio.SuperRUpdatePrefs::received(ZLjava/lang/String;)(automatic, channel);
      }, function() { @org.rstudio.studio.client.workbench.views.superrstudio.SuperRUpdatePrefs::failed()(); });
   }-*/;
   private static boolean automatic_ = false;
   private static String channel_ = "stable";
}
