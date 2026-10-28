// SPDX-License-Identifier: AGPL-3.0-only
package org.rstudio.studio.client.workbench.views.superrstudio;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

import com.google.gwt.aria.client.Roles;
import com.google.gwt.core.client.GWT;
import com.google.gwt.core.client.JsArrayString;
import com.google.gwt.json.client.JSONNumber;
import com.google.gwt.json.client.JSONObject;
import com.google.gwt.json.client.JSONString;
import com.google.gwt.json.client.JSONValue;
import com.google.gwt.user.client.ui.*;
import org.rstudio.core.client.widget.FormLabel;
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
      undo_ = new ThemedButton(messages_.undo(), e -> undoAppearance());
      reset_ = new ThemedButton(messages_.reset(), e -> resetAppearance());
      addLeftButton(refresh_, "superrstudio_refresh");
      addLeftButton(preview_, "superrstudio_preview");
      addLeftButton(export_, "superrstudio_export");
      datasets_.addChangeHandler(e -> inspect());
      x_.addChangeHandler(e -> code_.setText(""));
      y_.addChangeHandler(e -> code_.setText(""));

      option(colour_, messages_.colourDefault(), "");
      option(colour_, messages_.colourBlack(), "#000000");
      option(colour_, messages_.colourOrange(), "#E69F00");
      option(colour_, messages_.colourSkyBlue(), "#56B4E9");
      option(colour_, messages_.colourGreen(), "#009E73");
      option(colour_, messages_.colourBlue(), "#0072B2");
      option(colour_, messages_.colourVermillion(), "#D55E00");
      option(colour_, messages_.colourPurple(), "#CC79A7");
      for (String size : new String[] {"1", "1.5", "2", "3", "4", "6"})
         option(size_, size, size);
      option(alpha_, "100%", "1");
      option(alpha_, "80%", "0.8");
      option(alpha_, "60%", "0.6");
      option(alpha_, "40%", "0.4");
      option(alpha_, "20%", "0.2");
      option(theme_, messages_.themeGrey(), "grey");
      option(theme_, messages_.themeBw(), "bw");
      option(theme_, messages_.themeMinimal(), "minimal");
      option(theme_, messages_.themeClassic(), "classic");
      option(theme_, messages_.themeLight(), "light");
      applyAppearance(DEFAULT_APPEARANCE);
      current_ = DEFAULT_APPEARANCE;

      for (TextBox text : new TextBox[] {title_, xLabel_, yLabel_})
         text.addValueChangeHandler(e -> appearanceChanged());
      for (ListBox list : new ListBox[] {colour_, size_, alpha_, theme_})
         list.addChangeHandler(e -> appearanceChanged());
   }

   @Override protected Widget createMainWidget()
   {
      VerticalPanel panel = new VerticalPanel();
      panel.setSpacing(6);
      panel.setWidth("700px");
      Label help = new Label(messages_.help());
      panel.add(help);
      status_.getElement().setId("superrstudio_status");
      status_.getElement().setAttribute("role", "status");
      status_.getElement().setAttribute("aria-live", "polite");
      status_.getElement().setAttribute("tabindex", "-1");
      status_.getElement().getStyle().setProperty("whiteSpace", "pre-line");
      panel.add(status_);

      VerticalPanel data = column(messages_.dataHeading());
      field(data, messages_.dataset(), datasets_, "superrstudio_dataset");
      field(data, messages_.xColumn(), x_, "superrstudio_x");
      field(data, messages_.yColumn(), y_, "superrstudio_y");

      VerticalPanel look = column(messages_.appearanceHeading());
      field(look, messages_.plotTitle(), title_, "superrstudio_title");
      field(look, messages_.xLabel(), xLabel_, "superrstudio_xlabel");
      field(look, messages_.yLabel(), yLabel_, "superrstudio_ylabel");
      field(look, messages_.colour(), colour_, "superrstudio_colour");
      field(look, messages_.size(), size_, "superrstudio_size");
      field(look, messages_.opacity(), alpha_, "superrstudio_alpha");
      field(look, messages_.theme(), theme_, "superrstudio_theme");
      undo_.getElement().setId("superrstudio_undo");
      reset_.getElement().setId("superrstudio_reset");
      HorizontalPanel history = new HorizontalPanel();
      history.setSpacing(2);
      history.add(undo_);
      history.add(reset_);
      look.add(history);

      HorizontalPanel columns = new HorizontalPanel();
      columns.setSpacing(4);
      columns.add(data);
      columns.add(look);
      panel.add(columns);

      code_.setReadOnly(true);
      code_.setVisibleLines(7);
      code_.setWidth("680px");
      code_.getElement().setId("superrstudio_code");
      panel.add(new FormLabel(messages_.codeLabel(), code_));
      panel.add(code_);
      updateUndo();
      return panel;
   }

   private VerticalPanel column(String heading)
   {
      VerticalPanel column = new VerticalPanel();
      column.setWidth("340px");
      Label label = new Label(heading);
      label.getElement().getStyle().setProperty("fontWeight", "bold");
      Roles.getHeadingRole().set(label.getElement());
      Roles.getHeadingRole().setAriaLevelProperty(label.getElement(), 3);
      column.add(label);
      return column;
   }

   private void field(VerticalPanel panel, String text, Widget control, String id)
   {
      control.getElement().setId(id);
      control.setWidth("320px");
      panel.add(new FormLabel(text, control));
      panel.add(control);
   }

   private static void option(ListBox list, String label, String value)
   {
      list.addItem(label, value);
   }

   // Appearance state ------------------------------------------------------
   // Order: title, x label, y label, colour, size, alpha, theme.

   private String[] readAppearance()
   {
      return new String[] {
         title_.getValue(), xLabel_.getValue(), yLabel_.getValue(),
         colour_.getSelectedValue(), size_.getSelectedValue(),
         alpha_.getSelectedValue(), theme_.getSelectedValue()
      };
   }

   private void applyAppearance(String[] values)
   {
      title_.setValue(values[0]);
      xLabel_.setValue(values[1]);
      yLabel_.setValue(values[2]);
      select(colour_, values[3]);
      select(size_, values[4]);
      select(alpha_, values[5]);
      select(theme_, values[6]);
   }

   private static void select(ListBox list, String value)
   {
      for (int i = 0; i < list.getItemCount(); i++)
         if (list.getValue(i).equals(value))
            list.setSelectedIndex(i);
   }

   private void appearanceChanged()
   {
      String[] next = readAppearance();
      if (Arrays.equals(next, current_))
         return;
      history_.add(current_);
      current_ = next;
      code_.setText("");
      updateUndo();
   }

   private void undoAppearance()
   {
      if (history_.isEmpty())
         return;
      current_ = history_.remove(history_.size() - 1);
      applyAppearance(current_);
      code_.setText("");
      updateUndo();
   }

   private void resetAppearance()
   {
      applyAppearance(DEFAULT_APPEARANCE);
      appearanceChanged();
   }

   private void updateUndo()
   {
      undo_.setEnabled(!history_.isEmpty());
      reset_.setEnabled(!Arrays.equals(current_, DEFAULT_APPEARANCE));
   }

   private JSONObject appearanceJson()
   {
      String[] values = readAppearance();
      JSONObject json = new JSONObject();
      json.put("title", new JSONString(values[0]));
      json.put("x_label", new JSONString(values[1]));
      json.put("y_label", new JSONString(values[2]));
      json.put("colour", new JSONString(values[3]));
      json.put("size", new JSONNumber(Double.parseDouble(values[4])));
      json.put("alpha", new JSONNumber(Double.parseDouble(values[5])));
      json.put("theme", new JSONString(values[6]));
      return json;
   }

   // Session requests --------------------------------------------------------

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
      server_.superrstudioData(operation, dataset, revision, x, y, appearanceJson(),
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
         server_.superrstudioData("release", "", revision_, "", "", null,
            new ServerRequestCallback<ScatterResult>() {
               @Override public void onResponseReceived(ScatterResult result) {}
               @Override public void onError(ServerError error) {}
            });
      super.onUnload();
   }

   private static final String[] DEFAULT_APPEARANCE = {"", "", "", "", "1.5", "1", "grey"};

   private final SuperRStudioServerOperations server_;
   private final EventBus events_;
   private final Commands commands_;
   private final ListBox datasets_ = new ListBox(), x_ = new ListBox(), y_ = new ListBox();
   private final TextBox title_ = new TextBox(), xLabel_ = new TextBox(), yLabel_ = new TextBox();
   private final ListBox colour_ = new ListBox(), size_ = new ListBox(), alpha_ = new ListBox(),
                         theme_ = new ListBox();
   private final TextArea code_ = new TextArea();
   private final Label status_ = new Label();
   private final ThemedButton preview_, export_, refresh_, undo_, reset_;
   private final List<String[]> history_ = new ArrayList<>();
   private String[] current_;
   private String revision_ = "";
   private int requestId_ = 0;
   private static final ScatterMessages messages_ = GWT.create(ScatterMessages.class);
}
