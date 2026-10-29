// SPDX-License-Identifier: AGPL-3.0-only
package org.rstudio.studio.client.workbench.views.visual;

import org.rstudio.studio.client.application.events.EventBus;
import org.rstudio.studio.client.workbench.commands.Commands;
import org.rstudio.studio.client.workbench.events.SessionInitEvent;
import org.rstudio.studio.client.workbench.model.Session;
import org.rstudio.studio.client.workbench.model.SessionInfo;
import org.rstudio.studio.client.workbench.ui.DelayLoadTabShim;
import org.rstudio.studio.client.workbench.ui.DelayLoadWorkbenchTab;
import org.rstudio.studio.client.workbench.views.superrstudio.SuperRStudioLanguage;

import com.google.inject.Inject;

// SuperRStudio's Visual workbench tab: hosts the plot editor inside the IDE's
// panes. It exists only with SUPER_RSTUDIO_EXPERIMENTAL=1 (reported by the
// session at client init); otherwise it is suppressed like upstream's
// conditional tabs and its commands are removed. New layouts keep it in the
// hidden tab set, so no default pane location changes (see PaneConfig).
public class VisualTab extends DelayLoadWorkbenchTab<VisualPresenter>
{
   public abstract static class Shim extends DelayLoadTabShim<VisualPresenter, VisualTab>
   {
   }

   @Inject
   public VisualTab(Shim shim, Session session, Commands commands, EventBus events)
   {
      super(SuperRStudioLanguage.scatter().visualTab(), shim);
      session_ = session;
      events.addHandler(SessionInitEvent.TYPE, (SessionInitEvent event) ->
      {
         if (isSuppressed())
         {
            commands.activateVisual().remove();
            commands.layoutZoomVisual().remove();
         }
      });
   }

   @Override
   public boolean isSuppressed()
   {
      SessionInfo info = session_.getSessionInfo();
      return info == null || !info.getSuperRStudioExperimental();
   }

   private final Session session_;
}
