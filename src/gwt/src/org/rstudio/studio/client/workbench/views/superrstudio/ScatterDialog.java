// SPDX-License-Identifier: AGPL-3.0-only
package org.rstudio.studio.client.workbench.views.superrstudio;

import com.google.gwt.aria.client.Roles;
import com.google.gwt.core.client.GWT;
import com.google.gwt.core.client.JsArrayString;
import com.google.gwt.json.client.JSONValue;
import com.google.gwt.user.client.ui.*;
import org.rstudio.core.client.widget.ModalDialog;
import org.rstudio.core.client.widget.OperationWithInput;
import org.rstudio.core.client.widget.ThemedButton;
import org.rstudio.studio.client.application.events.EventBus;
import org.rstudio.studio.client.server.ServerError;
import org.rstudio.studio.client.server.ServerRequestCallback;
import org.rstudio.studio.client.workbench.commands.Commands;
import org.rstudio.studio.client.workbench.views.source.events.NewDocumentWithCodeEvent;
import org.rstudio.studio.client.workbench.views.source.model.SourcePosition;

public class ScatterDialog extends ModalDialog<Void>
{
   public ScatterDialog(SuperRStudioServerOperations server, EventBus events, Commands commands)
   {
      super(messages_.title(), Roles.getDialogRole(), (OperationWithInput<Void>) null);
      server_ = server;
      events_ = events;
      commands_ = commands;
      // A single Close action: the cancel button (also bound to Escape).
      setOkButtonVisible(false);
      setCancelButtonCaption(messages_.close());
      preview_ = new ThemedButton(messages_.preview(), e -> generate(false));
      export_ = new ThemedButton(messages_.exportCode(), e -> generate(true));
      refresh_ = new ThemedButton(messages_.refresh(), e -> refresh());
      addLeftButton(refresh_, "superrstudio_refresh");
      addLeftButton(preview_, "superrstudio_preview");
      addLeftButton(export_, "superrstudio_export");
      datasets_.addChangeHandler(e -> inspect());
      x_.addChangeHandler(e -> code_.setText(""));
      y_.addChangeHandler(e -> code_.setText(""));
   }

   @Override protected Widget createMainWidget()
   {
      VerticalPanel panel = new VerticalPanel();
      panel.setSpacing(8);
      panel.setWidth("480px");
      Label help = new Label(messages_.help());
      help.setWidth("460px");
      panel.add(help);
      status_.getElement().setId("superrstudio_status");
      status_.getElement().setAttribute("role", "status");
      status_.getElement().setAttribute("aria-live", "polite");
      status_.getElement().setAttribute("tabindex", "-1");
      status_.setWidth("460px");
      status_.getElement().getStyle().setProperty("whiteSpace", "pre-line");
      panel.add(status_);
      field(panel, messages_.dataset(), datasets_, "superrstudio_dataset");
      field(panel, messages_.xColumn(), x_, "superrstudio_x");
      field(panel, messages_.yColumn(), y_, "superrstudio_y");
      code_.setReadOnly(true);
      code_.setVisibleLines(7);
      code_.setWidth("460px");
      code_.getElement().setId("superrstudio_code");
      code_.getElement().setAttribute("aria-label", messages_.codeLabel());
      panel.add(new Label(messages_.codeLabel()));
      panel.add(code_);
      return panel;
   }

   private void field(VerticalPanel panel, String text, ListBox control, String id)
   {
      Label label = new Label(text);
      label.getElement().setAttribute("for", id);
      control.getElement().setId(id);
      control.getElement().setAttribute("aria-label", text);
      control.setWidth("460px");
      panel.add(label);
      panel.add(control);
   }

   @Override protected void onDialogShown()
   {
      super.onDialogShown();
      refresh();
   }
   @Override protected Void collectInput() { return null; }

   private void busy(boolean busy)
   {
      datasets_.setEnabled(!busy && datasets_.getItemCount() > 0);
      x_.setEnabled(!busy && x_.getItemCount() > 0);
      y_.setEnabled(!busy && y_.getItemCount() > 0);
      refresh_.setEnabled(!busy);
      preview_.setEnabled(!busy && !revision_.isEmpty() && x_.getItemCount() > 0);
      export_.setEnabled(!busy && !revision_.isEmpty() && x_.getItemCount() > 0);
   }
   private void refresh()
   {
      revision_ = "";
      datasets_.clear(); x_.clear(); y_.clear(); code_.setText("");
      status_.setText(messages_.loading());
      request("list", "", "", "", "", result -> {
         fill(datasets_, result.datasets());
         if (datasets_.getItemCount() > 0) inspect();
         else status_.setText(messages_.noData());
      });
   }
   private void inspect()
   {
      revision_ = "";
      x_.clear(); y_.clear(); code_.setText("");
      status_.setText(messages_.loading());
      request("inspect", datasets_.getSelectedValue(), "", "", "", result -> {
         revision_ = result.revision();
         fill(x_, result.columns()); fill(y_, result.columns());
         if (y_.getItemCount() > 1) y_.setSelectedIndex(1);
         status_.setText(x_.getItemCount() > 0 ? messages_.ready() : messages_.noColumns());
         busy(false);
      });
   }
   private void generate(boolean export)
   {
      status_.setText(messages_.working());
      request(export ? "code" : "preview", datasets_.getSelectedValue(), revision_,
         x_.getSelectedValue(), y_.getSelectedValue(), result -> {
            String code = result.provenance() + result.code();
            code_.setText(code);
            status_.setText(messages_.plotted() + (result.warnings().isEmpty() ? "" : "\n" + result.warnings()));
            if (export)
            {
               closeDialog();
               events_.fireEvent(new NewDocumentWithCodeEvent(
                  NewDocumentWithCodeEvent.R_SCRIPT, code, SourcePosition.create(1, 1), false));
            }
            else
            {
               // plots rendered during an RPC don't activate the Plots pane
               // on their own (see SessionPlots.cpp detectChanges)
               commands_.activatePlots().execute();
            }
         });
   }
   private void fill(ListBox control, JsArrayString values)
   {
      control.clear();
      for (int i = 0; i < values.length(); i++) control.addItem(values.get(i));
   }
   private void request(String operation, String dataset, String revision, String x,
                        String y, OperationWithInput<ScatterResult> done)
   {
      busy(true);
      final int requestId = ++requestId_;
      server_.superrstudioData(operation, dataset, revision, x, y,
         new ServerRequestCallback<ScatterResult>() {
            @Override public void onResponseReceived(ScatterResult result)
            {
               if (!isAttached() || requestId != requestId_) return;
               busy(false);
               done.execute(result);
            }
            @Override public void onError(ServerError error)
            {
               if (!isAttached() || requestId != requestId_) return;
               busy(false);
               JSONValue info = error.getClientInfo();
               status_.setText(info != null && info.isString() != null
                  ? info.isString().stringValue()
                  : error.getUserMessage());
               status_.getElement().focus();
            }
         });
   }
   @Override protected void onUnload()
   {
      ++requestId_;
      if (!revision_.isEmpty())
         server_.superrstudioData("release", "", revision_, "", "",
            new ServerRequestCallback<ScatterResult>() {
               @Override public void onResponseReceived(ScatterResult result) {}
               @Override public void onError(ServerError error) {}
            });
      super.onUnload();
   }
   private final SuperRStudioServerOperations server_;
   private final EventBus events_;
   private final Commands commands_;
   private final ListBox datasets_ = new ListBox(), x_ = new ListBox(), y_ = new ListBox();
   private final TextArea code_ = new TextArea();
   private final Label status_ = new Label();
   private final ThemedButton preview_, export_, refresh_;
   private String revision_ = "";
   private int requestId_ = 0;
   private static final ScatterMessages messages_ = GWT.create(ScatterMessages.class);
}
