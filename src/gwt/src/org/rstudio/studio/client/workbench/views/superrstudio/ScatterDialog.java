// SPDX-License-Identifier: AGPL-3.0-only
package org.rstudio.studio.client.workbench.views.superrstudio;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

import com.google.gwt.aria.client.Roles;
import com.google.gwt.core.client.GWT;
import com.google.gwt.core.client.JsArray;
import com.google.gwt.core.client.JsArrayString;
import com.google.gwt.json.client.JSONBoolean;
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
   // An undoable plot setting: its JSON key, editing widget, value type and
   // default. Values are handled as strings and typed when sent to R.
   private static class Setting
   {
      Setting(String key, Widget widget, String type, String defaultValue)
      {
         this.key = key;
         this.widget = widget;
         this.type = type;
         this.defaultValue = defaultValue;
      }

      String get()
      {
         if (widget instanceof TextBox) return ((TextBox) widget).getValue();
         if (widget instanceof CheckBox) return String.valueOf(((CheckBox) widget).getValue());
         return ((ListBox) widget).getSelectedValue();
      }

      void set(String value)
      {
         if (widget instanceof TextBox) ((TextBox) widget).setValue(value);
         else if (widget instanceof CheckBox) ((CheckBox) widget).setValue(Boolean.parseBoolean(value));
         else select((ListBox) widget, value);
      }

      JSONValue json()
      {
         String value = get();
         if (TYPE_NUMBER.equals(type)) return new JSONNumber(Double.parseDouble(value));
         if (TYPE_BOOLEAN.equals(type)) return JSONBoolean.getInstance(Boolean.parseBoolean(value));
         return new JSONString(value);
      }

      final String key, type, defaultValue;
      final Widget widget;
   }

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
      undo_ = new ThemedButton(messages_.undo(), e -> undo());
      reset_ = new ThemedButton(messages_.reset(), e -> reset());
      addLeftButton(refresh_, "superrstudio_refresh");
      addLeftButton(preview_, "superrstudio_preview");
      addLeftButton(export_, "superrstudio_export");
      datasets_.addChangeHandler(e -> inspect());
      x_.addChangeHandler(e -> invalidate());
      y_.addChangeHandler(e -> invalidate());
      colourBy_.addChangeHandler(e -> layoutChanged());
      groupBy_.addChangeHandler(e -> invalidate());

      option(geometry_, messages_.geometryPoints(), "points");
      option(geometry_, messages_.geometryLines(), "lines");
      option(geometry_, messages_.geometryLinesPoints(), "lines_points");
      option(lineOrder_, messages_.lineOrderX(), "x");
      option(lineOrder_, messages_.lineOrderData(), "data");
      option(fit_, messages_.fitNone(), "none");
      option(fit_, messages_.fitLm(), "lm");
      option(fit_, messages_.fitLoess(), "loess");
      for (String level : new String[] {"0.8", "0.9", "0.95", "0.99"})
         option(fitLevel_, Math.round(Double.parseDouble(level) * 100) + "%", level);
      for (String span : new String[] {"0.25", "0.5", "0.75", "1"})
         option(fitSpan_, span, span);
      for (ListBox colours : new ListBox[] {colour_, lineColour_, fitColour_})
         colourOptions(colours);
      for (String size : new String[] {"1", "1.5", "2", "3", "4", "6"})
         option(size_, size, size);
      for (String alpha : new String[] {"1", "0.8", "0.6", "0.4", "0.2"})
         option(alpha_, Math.round(Double.parseDouble(alpha) * 100) + "%", alpha);
      for (String width : new String[] {"0.25", "0.5", "1", "1.5", "2", "3"})
         option(lineWidth_, width, width);
      option(lineType_, messages_.lineTypeSolid(), "solid");
      option(lineType_, messages_.lineTypeDashed(), "dashed");
      option(lineType_, messages_.lineTypeDotted(), "dotted");
      option(lineType_, messages_.lineTypeDotdash(), "dotdash");
      option(lineType_, messages_.lineTypeLongdash(), "longdash");
      option(lineType_, messages_.lineTypeTwodash(), "twodash");
      option(theme_, messages_.themeGrey(), "grey");
      option(theme_, messages_.themeBw(), "bw");
      option(theme_, messages_.themeMinimal(), "minimal");
      option(theme_, messages_.themeClassic(), "classic");
      option(theme_, messages_.themeLight(), "light");
      fitSe_.setText(messages_.fitSe());

      settings_.add(new Setting("geometry", geometry_, TYPE_STRING, "points"));
      settings_.add(new Setting("line_order", lineOrder_, TYPE_STRING, "x"));
      settings_.add(new Setting("fit", fit_, TYPE_STRING, "none"));
      settings_.add(new Setting("fit_se", fitSe_, TYPE_BOOLEAN, "true"));
      settings_.add(new Setting("fit_level", fitLevel_, TYPE_NUMBER, "0.95"));
      settings_.add(new Setting("fit_span", fitSpan_, TYPE_NUMBER, "0.75"));
      settings_.add(new Setting("title", title_, TYPE_STRING, ""));
      settings_.add(new Setting("x_label", xLabel_, TYPE_STRING, ""));
      settings_.add(new Setting("y_label", yLabel_, TYPE_STRING, ""));
      settings_.add(new Setting("colour", colour_, TYPE_STRING, ""));
      settings_.add(new Setting("size", size_, TYPE_NUMBER, "1.5"));
      settings_.add(new Setting("alpha", alpha_, TYPE_NUMBER, "1"));
      settings_.add(new Setting("theme", theme_, TYPE_STRING, "grey"));
      settings_.add(new Setting("line_colour", lineColour_, TYPE_STRING, ""));
      settings_.add(new Setting("line_width", lineWidth_, TYPE_NUMBER, "0.5"));
      settings_.add(new Setting("line_type", lineType_, TYPE_STRING, "solid"));
      settings_.add(new Setting("fit_colour", fitColour_, TYPE_STRING, ""));
      defaults_ = new String[settings_.size()];
      for (int i = 0; i < defaults_.length; i++)
         defaults_[i] = settings_.get(i).defaultValue;
      apply(defaults_);
      current_ = defaults_;

      for (TextBox text : new TextBox[] {title_, xLabel_, yLabel_})
         text.addValueChangeHandler(e -> settingsChanged());
      fitSe_.addValueChangeHandler(e -> settingsChanged());
      for (Setting setting : settings_)
         if (setting.widget instanceof ListBox)
            ((ListBox) setting.widget).addChangeHandler(e -> settingsChanged());
   }

   @Override protected Widget createMainWidget()
   {
      VerticalPanel panel = new VerticalPanel();
      panel.setSpacing(4);
      panel.setWidth("930px");
      panel.add(new Label(messages_.help()));
      status_.getElement().setId("superrstudio_status");
      status_.getElement().setAttribute("role", "status");
      status_.getElement().setAttribute("aria-live", "polite");
      status_.getElement().setAttribute("tabindex", "-1");
      status_.getElement().getStyle().setProperty("whiteSpace", "pre-line");
      panel.add(status_);

      Grid data = section(messages_.dataHeading(), 5);
      row(data, 0, messages_.dataset(), datasets_, "superrstudio_dataset");
      row(data, 1, messages_.xColumn(), x_, "superrstudio_x");
      row(data, 2, messages_.yColumn(), y_, "superrstudio_y");
      row(data, 3, messages_.colourBy(), colourBy_, "superrstudio_colour_by");
      row(data, 4, messages_.groupBy(), groupBy_, "superrstudio_group_by");

      Grid layers = section(messages_.layersHeading(), 6);
      row(layers, 0, messages_.geometry(), geometry_, "superrstudio_geometry");
      row(layers, 1, messages_.lineOrder(), lineOrder_, "superrstudio_line_order");
      row(layers, 2, messages_.fit(), fit_, "superrstudio_fit");
      row(layers, 3, "", fitSe_, "superrstudio_fit_se");
      row(layers, 4, messages_.fitLevel(), fitLevel_, "superrstudio_fit_level");
      row(layers, 5, messages_.fitSpan(), fitSpan_, "superrstudio_fit_span");
      orderHint_.getElement().setId("superrstudio_order_hint");
      orderHint_.setWidth("290px");
      orderHint_.getElement().getStyle().setProperty("fontSize", "90%");

      Grid look = section(messages_.appearanceHeading(), 11);
      row(look, 0, messages_.plotTitle(), title_, "superrstudio_title");
      row(look, 1, messages_.xLabel(), xLabel_, "superrstudio_xlabel");
      row(look, 2, messages_.yLabel(), yLabel_, "superrstudio_ylabel");
      row(look, 3, messages_.colour(), colour_, "superrstudio_colour");
      row(look, 4, messages_.size(), size_, "superrstudio_size");
      row(look, 5, messages_.opacity(), alpha_, "superrstudio_alpha");
      row(look, 6, messages_.lineColour(), lineColour_, "superrstudio_line_colour");
      row(look, 7, messages_.lineWidth(), lineWidth_, "superrstudio_line_width");
      row(look, 8, messages_.lineType(), lineType_, "superrstudio_line_type");
      row(look, 9, messages_.fitColour(), fitColour_, "superrstudio_fit_colour");
      row(look, 10, messages_.theme(), theme_, "superrstudio_theme");

      undo_.getElement().setId("superrstudio_undo");
      reset_.getElement().setId("superrstudio_reset");
      HorizontalPanel history = new HorizontalPanel();
      history.setSpacing(2);
      history.add(undo_);
      history.add(reset_);

      VerticalPanel left = new VerticalPanel();
      left.add(heading(messages_.dataHeading()));
      left.add(data);
      left.add(heading(messages_.layersHeading()));
      left.add(layers);
      left.add(orderHint_);
      left.add(history);
      VerticalPanel right = new VerticalPanel();
      right.add(heading(messages_.appearanceHeading()));
      right.add(look);
      HorizontalPanel columns = new HorizontalPanel();
      columns.setSpacing(4);
      columns.add(left);
      columns.add(right);
      panel.add(columns);

      code_.setReadOnly(true);
      code_.setVisibleLines(6);
      code_.setWidth("910px");
      code_.getElement().setId("superrstudio_code");
      panel.add(new FormLabel(messages_.codeLabel(), code_));
      panel.add(code_);
      model_.getElement().setId("superrstudio_model");
      model_.getElement().setAttribute("role", "status");
      model_.getElement().setAttribute("aria-live", "polite");
      model_.getElement().getStyle().setProperty("whiteSpace", "pre-line");
      model_.setWidth("910px");
      panel.add(model_);
      layoutChanged();
      updateUndo();
      return panel;
   }

   private Grid section(String heading, int rows)
   {
      Grid grid = new Grid(rows, 2);
      grid.setCellSpacing(2);
      grid.getElement().setAttribute("aria-label", heading);
      return grid;
   }

   private Label heading(String text)
   {
      Label label = new Label(text);
      label.getElement().getStyle().setProperty("fontWeight", "bold");
      Roles.getHeadingRole().set(label.getElement());
      Roles.getHeadingRole().setAriaLevelProperty(label.getElement(), 3);
      return label;
   }

   private void row(Grid grid, int row, String text, Widget control, String id)
   {
      control.getElement().setId(id);
      control.setWidth("190px");
      if (!text.isEmpty())
      {
         FormLabel label = new FormLabel(text, control);
         label.setWidth("150px");
         grid.setWidget(row, 0, label);
      }
      grid.setWidget(row, 1, control);
   }

   private static void option(ListBox list, String label, String value)
   {
      list.addItem(label, value);
   }

   private void colourOptions(ListBox list)
   {
      option(list, messages_.colourDefault(), "");
      option(list, messages_.colourBlack(), "#000000");
      option(list, messages_.colourOrange(), "#E69F00");
      option(list, messages_.colourSkyBlue(), "#56B4E9");
      option(list, messages_.colourGreen(), "#009E73");
      option(list, messages_.colourBlue(), "#0072B2");
      option(list, messages_.colourVermillion(), "#D55E00");
      option(list, messages_.colourPurple(), "#CC79A7");
   }

   private static void select(ListBox list, String value)
   {
      for (int i = 0; i < list.getItemCount(); i++)
         if (list.getValue(i).equals(value))
            list.setSelectedIndex(i);
   }

   private static boolean has(ListBox list)
   {
      return list.getItemCount() > 0 && !list.getSelectedValue().isEmpty();
   }

   // Enable only the controls that affect the selected layers, and keep the
   // settings R would reject (fixed colour with a colour column, grouping
   // without lines or a fit) from being combined.
   private void layoutChanged()
   {
      String geometry = geometry_.getSelectedValue();
      boolean points = !"lines".equals(geometry);
      boolean lines = !"points".equals(geometry);
      boolean fit = !"none".equals(fit_.getSelectedValue());
      boolean mapped = has(colourBy_);
      boolean dirty = false;
      if (mapped && !colour_.getSelectedValue().isEmpty())
      {
         select(colour_, "");
         dirty = true;
      }
      if (!lines && !fit && has(groupBy_))
         groupBy_.setSelectedIndex(0);
      colour_.setEnabled(points && !mapped);
      size_.setEnabled(points);
      alpha_.setEnabled(points);
      lineOrder_.setEnabled(lines);
      lineColour_.setEnabled(lines);
      lineWidth_.setEnabled(lines);
      lineType_.setEnabled(lines);
      groupBy_.setEnabled((lines || fit) && groupBy_.getItemCount() > 1);
      fitSe_.setEnabled(fit);
      fitLevel_.setEnabled(fit && fitSe_.getValue());
      fitSpan_.setEnabled("loess".equals(fit_.getSelectedValue()));
      fitColour_.setEnabled(fit);
      orderHint_.setText(!lines ? "" : "x".equals(lineOrder_.getSelectedValue())
         ? messages_.lineOrderHintX() : messages_.lineOrderHintData());
      if (dirty)
         settingsChanged();
      invalidate();
   }

   private void invalidate()
   {
      code_.setText("");
      model_.setText("");
   }

   // Undoable settings -------------------------------------------------------

   private String[] read()
   {
      String[] values = new String[settings_.size()];
      for (int i = 0; i < values.length; i++)
         values[i] = settings_.get(i).get();
      return values;
   }

   private void apply(String[] values)
   {
      for (int i = 0; i < values.length; i++)
         settings_.get(i).set(values[i]);
   }

   private void settingsChanged()
   {
      if (restoring_)
         return;
      String[] next = read();
      if (Arrays.equals(next, current_))
         return;
      history_.add(current_);
      current_ = next;
      layoutChanged();
      updateUndo();
   }

   private void undo()
   {
      if (history_.isEmpty())
         return;
      current_ = history_.remove(history_.size() - 1);
      apply(current_);
      // a restored fixed colour cannot coexist with an active colour column;
      // layoutChanged() may adjust it, which must not be recorded as an edit
      restoring_ = true;
      layoutChanged();
      restoring_ = false;
      current_ = read();
      updateUndo();
   }

   private void reset()
   {
      apply(defaults_);
      settingsChanged();
   }

   private void updateUndo()
   {
      undo_.setEnabled(!history_.isEmpty());
      reset_.setEnabled(!Arrays.equals(current_, defaults_));
   }

   private JSONObject settingsJson()
   {
      JSONObject json = new JSONObject();
      for (Setting setting : settings_)
         json.put(setting.key, setting.json());
      // column mappings are data, validated against the dataset in R
      json.put("colour_by", new JSONString(has(colourBy_) ? colourBy_.getSelectedValue() : ""));
      json.put("group_by", new JSONString(has(groupBy_) ? groupBy_.getSelectedValue() : ""));
      return json;
   }

   private void showModel(ScatterResult result)
   {
      JsArray<ScatterResult.FitEntry> entries = result.fitSummary();
      if (entries.length() == 0)
      {
         model_.setText("");
         return;
      }
      StringBuilder text = new StringBuilder(messages_.modelHeading()).append(":\n");
      boolean linear = false;
      for (int i = 0; i < entries.length(); i++)
      {
         ScatterResult.FitEntry entry = entries.get(i);
         String group = "all".equals(entry.group()) && entries.length() == 1
            ? messages_.allObservations() : entry.group();
         if ("loess".equals(entry.method()))
            text.append(messages_.loessSummary(group, entry.n(), entry.span()));
         else if (!entry.hasStatistics())
            text.append(messages_.tooFewSummary(group, entry.n()));
         else
         {
            linear = true;
            text.append(messages_.lmSummary(group, entry.n(), entry.equation(), entry.rSquared(),
               entry.adjRSquared(), entry.slopePValue(), entry.sigma()));
            if (!entry.note().isEmpty())
               text.append(" (").append(entry.note()).append(")");
         }
         text.append("\n");
      }
      if (linear)
         text.append(messages_.lmCaveat());
      model_.setText(text.toString());
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
      colourBy_.setEnabled(!busy && colourBy_.getItemCount() > 1);
      refresh_.setEnabled(!busy);
      preview_.setEnabled(!busy && !revision_.isEmpty() && x_.getItemCount() > 0);
      export_.setEnabled(!busy && !revision_.isEmpty() && x_.getItemCount() > 0);
      if (!busy)
         layoutChanged();
   }
   private void refresh()
   {
      revision_ = "";
      datasets_.clear(); clearColumns();
      status_.setText(messages_.loading());
      request("list", "", "", "", "", result -> {
         fill(datasets_, result.datasets());
         if (datasets_.getItemCount() > 0) inspect();
         else status_.setText(messages_.noData());
      });
   }
   private void clearColumns()
   {
      x_.clear(); y_.clear(); colourBy_.clear(); groupBy_.clear();
      invalidate();
   }
   private void inspect()
   {
      revision_ = "";
      clearColumns();
      status_.setText(messages_.loading());
      request("inspect", datasets_.getSelectedValue(), "", "", "", result -> {
         revision_ = result.revision();
         fill(x_, result.columns()); fill(y_, result.columns());
         if (y_.getItemCount() > 1) y_.setSelectedIndex(1);
         colourBy_.addItem(messages_.colourByNone(), "");
         groupBy_.addItem(messages_.colourByNone(), "");
         JsArrayString colourColumns = result.colourColumns();
         for (int i = 0; i < colourColumns.length(); i++)
            colourBy_.addItem(colourColumns.get(i));
         JsArrayString discreteColumns = result.discreteColumns();
         for (int i = 0; i < discreteColumns.length(); i++)
            groupBy_.addItem(discreteColumns.get(i));
         status_.setText(x_.getItemCount() > 0 ? messages_.ready() : messages_.noColumns());
         busy(false);
      });
   }
   private void generate(boolean export)
   {
      status_.setText(messages_.working());
      request(export ? "code" : "preview", datasets_.getSelectedValue(), revision_,
         x_.getSelectedValue(), y_.getSelectedValue(), result -> {
            String code = result.provenance() + result.code() +
               (result.modelCode().isEmpty() ? "" : "\n" + result.modelCode() + "\n");
            code_.setText(code);
            showModel(result);
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
      server_.superrstudioData(operation, dataset, revision, x, y, settingsJson(),
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

   private static final String TYPE_STRING = "string";
   private static final String TYPE_NUMBER = "number";
   private static final String TYPE_BOOLEAN = "boolean";

   private final SuperRStudioServerOperations server_;
   private final EventBus events_;
   private final Commands commands_;
   private final ListBox datasets_ = new ListBox(), x_ = new ListBox(), y_ = new ListBox(),
                         colourBy_ = new ListBox(), groupBy_ = new ListBox();
   private final ListBox geometry_ = new ListBox(), lineOrder_ = new ListBox(), fit_ = new ListBox(),
                         fitLevel_ = new ListBox(), fitSpan_ = new ListBox();
   private final CheckBox fitSe_ = new CheckBox();
   private final TextBox title_ = new TextBox(), xLabel_ = new TextBox(), yLabel_ = new TextBox();
   private final ListBox colour_ = new ListBox(), size_ = new ListBox(), alpha_ = new ListBox(),
                         theme_ = new ListBox(), lineColour_ = new ListBox(), lineWidth_ = new ListBox(),
                         lineType_ = new ListBox(), fitColour_ = new ListBox();
   private final TextArea code_ = new TextArea();
   private final Label status_ = new Label(), model_ = new Label(), orderHint_ = new Label();
   private final ThemedButton preview_, export_, refresh_, undo_, reset_;
   private final List<Setting> settings_ = new ArrayList<>();
   private final List<String[]> history_ = new ArrayList<>();
   private final String[] defaults_;
   private String[] current_;
   private boolean restoring_ = false;
   private String revision_ = "";
   private int requestId_ = 0;
   private static final ScatterMessages messages_ = GWT.create(ScatterMessages.class);
}
