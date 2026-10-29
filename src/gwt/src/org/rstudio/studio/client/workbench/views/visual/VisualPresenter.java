// SPDX-License-Identifier: AGPL-3.0-only
package org.rstudio.studio.client.workbench.views.visual;

import org.rstudio.studio.client.workbench.WorkbenchView;
import org.rstudio.studio.client.workbench.views.BasePresenter;

import com.google.inject.Inject;

// The Visual tab's presenter. The plot editor keeps its own state; the pane
// only hosts it (ScatterDialog.dock / undock).
public class VisualPresenter extends BasePresenter
{
   public interface Display extends WorkbenchView
   {
   }

   @Inject
   public VisualPresenter(Display view)
   {
      super(view);
   }
}
