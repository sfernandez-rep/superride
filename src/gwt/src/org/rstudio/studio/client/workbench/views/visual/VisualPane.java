// SPDX-License-Identifier: AGPL-3.0-only
package org.rstudio.studio.client.workbench.views.visual;

import org.rstudio.core.client.widget.ThemedButton;
import org.rstudio.studio.client.application.events.EventBus;
import org.rstudio.studio.client.workbench.commands.Commands;
import org.rstudio.studio.client.workbench.ui.WorkbenchPane;
import org.rstudio.studio.client.workbench.views.environment.model.EnvironmentServerOperations;
import org.rstudio.studio.client.workbench.views.superrstudio.ScatterDialog;
import org.rstudio.studio.client.workbench.views.superrstudio.ScatterMessages;
import org.rstudio.studio.client.workbench.views.superrstudio.SuperRStudioLanguage;
import org.rstudio.studio.client.workbench.views.superrstudio.SuperRStudioTheme;

import com.google.gwt.user.client.ui.Label;
import com.google.gwt.user.client.ui.ScrollPanel;
import com.google.gwt.user.client.ui.SimplePanel;
import com.google.gwt.user.client.ui.VerticalPanel;
import com.google.gwt.user.client.ui.Widget;
import com.google.inject.Inject;

// Hosts the plot editor in a workbench pane. Selecting the tab moves the one
// editor (with its data, settings, undo history and preview) into the pane;
// "Open as a floating window" moves it back out. Nothing is copied, so both
// modes always show the same state.
public class VisualPane extends WorkbenchPane implements VisualPresenter.Display
{
   @Inject
   public VisualPane(EnvironmentServerOperations server, EventBus events, Commands commands)
   {
      super(messages_.visualTab(), events);
      server_ = server;
      events_ = events;
      commands_ = commands;
      ensureWidget();
   }

   @Override
   protected Widget createMainWidget()
   {
      SuperRStudioTheme.ensureInjected();
      host_ = new SimplePanel();
      host_.getElement().setId("superrstudio_visual_host");
      host_.addStyleName(SuperRStudioTheme.DIALOG);
      VerticalPanel placeholder = new VerticalPanel();
      placeholder.setSpacing(8);
      placeholder.add(SuperRStudioTheme.hint(new Label(messages_.visualPlaceholder())));
      ThemedButton dock = new ThemedButton(messages_.dockHere(), e -> dock());
      dock.getElement().setId("superrstudio_visual_dock_here");
      placeholder.add(dock);
      placeholder_ = placeholder;
      host_.setWidget(placeholder_);
      ScrollPanel scroll = new ScrollPanel(host_);
      scroll.setSize("100%", "100%");
      return scroll;
   }

   @Override
   public void onSelected()
   {
      super.onSelected();
      dock();
   }

   private void dock()
   {
      ScatterDialog.dock(host_, placeholder_, server_, events_, commands_);
   }

   private SimplePanel host_;
   private Widget placeholder_;
   private final EnvironmentServerOperations server_;
   private final EventBus events_;
   private final Commands commands_;
   private static final ScatterMessages messages_ = SuperRStudioLanguage.scatter();
}
