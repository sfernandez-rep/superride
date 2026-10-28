// SPDX-License-Identifier: AGPL-3.0-only
package org.rstudio.studio.client.workbench.views.superrstudio;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import com.google.gwt.aria.client.Roles;
import com.google.gwt.core.client.GWT;
import com.google.gwt.core.client.JsArray;
import com.google.gwt.core.client.JsArrayString;
import com.google.gwt.event.dom.client.KeyCodes;
import com.google.gwt.event.dom.client.KeyDownEvent;
import com.google.gwt.json.client.JSONBoolean;
import com.google.gwt.json.client.JSONNumber;
import com.google.gwt.json.client.JSONObject;
import com.google.gwt.json.client.JSONString;
import com.google.gwt.json.client.JSONValue;
import com.google.gwt.user.client.ui.*;
import org.rstudio.core.client.ElementIds;
import org.rstudio.core.client.theme.res.ThemeStyles;
import org.rstudio.core.client.widget.FormLabel;
import org.rstudio.core.client.widget.OperationWithInput;
import org.rstudio.core.client.widget.ThemedButton;
import org.rstudio.studio.client.application.events.EventBus;
import org.rstudio.studio.client.server.ServerError;
import org.rstudio.studio.client.server.ServerRequestCallback;
import org.rstudio.studio.client.workbench.commands.Commands;
import org.rstudio.studio.client.workbench.views.source.events.NewDocumentWithCodeEvent;
import org.rstudio.studio.client.workbench.views.source.model.SourcePosition;

// Visual plot editor for the active R session: scatter/lines (with fits),
// histograms and boxplots, one shared specification and settings table.
//
// A non-modal, draggable window (not a ModalDialog): the Plots pane, the
// console and the rest of the IDE stay usable while it is open. It is not
// registered with ModalDialogTracker, and handles Escape only for its own
// content, so global shortcuts and console keys are unaffected.
public class ScatterDialog extends DialogBox
{
   // Opens the editor, or brings the already open one to the front.
   public static void open(SuperRStudioServerOperations server, EventBus events, Commands commands)
   {
      if (instance_ != null && instance_.isShowing())
      {
         instance_.show();
         instance_.focusFirst();
         return;
      }
      instance_ = new ScatterDialog(server, events, commands);
      instance_.show();
      instance_.setPopupPosition(16, 40);
      instance_.focusFirst();
      instance_.refresh();
   }

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
         if (widget instanceof TextBox) return ((TextBox) widget).getValue().trim();
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
         if (TYPE_BOOLEAN.equals(type)) return JSONBoolean.getInstance(Boolean.parseBoolean(value));
         if (TYPE_NUMBER.equals(type))
         {
            try
            {
               return new JSONNumber(Double.parseDouble(value));
            }
            catch (NumberFormatException e)
            {
               // sent as text: the session rejects it with a clear message
               return new JSONString(value);
            }
         }
         return new JSONString(value);
      }

      final String key, type, defaultValue;
      final Widget widget;
   }

   private ScatterDialog(SuperRStudioServerOperations server, EventBus events, Commands commands)
   {
      super(false, false);   // no auto-hide, not modal
      setGlassEnabled(false);
      setText(messages_.title());
      addStyleDependentName("ModalDialog");   // same look and z-order as RStudio dialogs
      Roles.getDialogRole().set(getElement());
      getElement().setAttribute("aria-modal", "false");
      server_ = server;
      events_ = events;
      commands_ = commands;
      preview_ = new ThemedButton(messages_.preview(), e -> generate(false));
      export_ = new ThemedButton(messages_.exportCode(), e -> generate(true));
      refresh_ = new ThemedButton(messages_.refresh(), e -> refresh());
      close_ = new ThemedButton(messages_.close(), e -> closeDialog());
      undo_ = new ThemedButton(messages_.undo(), e -> undo());
      reset_ = new ThemedButton(messages_.reset(), e -> reset());
      addDomHandler(e -> {
         if (e.getNativeKeyCode() == KeyCodes.KEY_ESCAPE)
         {
            e.preventDefault();
            closeDialog();
         }
      }, KeyDownEvent.getType());

      option(kind_, messages_.kindScatter(), KIND_SCATTER);
      option(kind_, messages_.kindHistogram(), KIND_HISTOGRAM);
      option(kind_, messages_.kindBoxplot(), KIND_BOXPLOT);
      option(kind_, messages_.kindBar(), KIND_BAR);
      option(kind_, messages_.kindDensity(), KIND_DENSITY);
      // repopulated lists need their enabled state recomputed (busy(false))
      kind_.addChangeHandler(e -> { populateColumns(); busy(false); });
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
      for (String bins : new String[] {"10", "20", "30", "50", "100"})
         option(bins_, bins, bins);
      option(barPosition_, messages_.barStack(), "stack");
      option(barPosition_, messages_.barDodge(), "dodge");
      option(barPosition_, messages_.barFill(), "fill");
      for (String adjust : new String[] {"0.5", "1", "1.5", "2"})
         option(adjust_, adjust, adjust);
      for (ListBox colours : new ListBox[] {colour_, lineColour_, fitColour_, fill_})
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
      showOutliers_.setText(messages_.showOutliers());
      showPoints_.setText(messages_.showPoints());

      settings_.add(new Setting("geometry", geometry_, TYPE_STRING, "points"));
      settings_.add(new Setting("line_order", lineOrder_, TYPE_STRING, "x"));
      settings_.add(new Setting("fit", fit_, TYPE_STRING, "none"));
      settings_.add(new Setting("fit_se", fitSe_, TYPE_BOOLEAN, "true"));
      settings_.add(new Setting("fit_level", fitLevel_, TYPE_NUMBER, "0.95"));
      settings_.add(new Setting("fit_span", fitSpan_, TYPE_NUMBER, "0.75"));
      settings_.add(new Setting("bins", bins_, TYPE_NUMBER, "30"));
      settings_.add(new Setting("bin_width", binWidth_, TYPE_NUMBER, "0"));
      settings_.add(new Setting("show_outliers", showOutliers_, TYPE_BOOLEAN, "true"));
      settings_.add(new Setting("show_points", showPoints_, TYPE_BOOLEAN, "false"));
      settings_.add(new Setting("bar_position", barPosition_, TYPE_STRING, "stack"));
      settings_.add(new Setting("adjust", adjust_, TYPE_NUMBER, "1"));
      settings_.add(new Setting("title", title_, TYPE_STRING, ""));
      settings_.add(new Setting("x_label", xLabel_, TYPE_STRING, ""));
      settings_.add(new Setting("y_label", yLabel_, TYPE_STRING, ""));
      settings_.add(new Setting("colour", colour_, TYPE_STRING, ""));
      settings_.add(new Setting("size", size_, TYPE_NUMBER, "1.5"));
      settings_.add(new Setting("alpha", alpha_, TYPE_NUMBER, "1"));
      settings_.add(new Setting("fill", fill_, TYPE_STRING, ""));
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

      for (TextBox text : new TextBox[] {title_, xLabel_, yLabel_, binWidth_})
         text.addValueChangeHandler(e -> settingsChanged());
      for (CheckBox check : new CheckBox[] {fitSe_, showOutliers_, showPoints_})
         check.addValueChangeHandler(e -> settingsChanged());
      for (Setting setting : settings_)
         if (setting.widget instanceof ListBox)
            ((ListBox) setting.widget).addChangeHandler(e -> settingsChanged());
      setWidget(createMainWidget());
   }

   private void focusFirst()
   {
      datasets_.setFocus(true);
   }

   private void closeDialog()
   {
      hide();
   }

   private Widget createMainWidget()
   {
      VerticalPanel panel = new VerticalPanel();
      panel.setSpacing(4);
      panel.setWidth("720px");
      panel.add(new Label(messages_.help()));
      status_.getElement().setId("superrstudio_status");
      status_.getElement().setAttribute("role", "status");
      status_.getElement().setAttribute("aria-live", "polite");
      status_.getElement().setAttribute("tabindex", "-1");
      status_.getElement().getStyle().setProperty("whiteSpace", "pre-line");
      panel.add(status_);

      Grid data = section(messages_.dataHeading(), 6);
      row(data, 0, messages_.dataset(), datasets_, "superrstudio_dataset");
      row(data, 1, messages_.plotKind(), kind_, "superrstudio_kind");
      xRowLabel_ = row(data, 2, messages_.xColumn(), x_, "superrstudio_x");
      yRowLabel_ = row(data, 3, messages_.yColumn(), y_, "superrstudio_y");
      colourByLabel_ = row(data, 4, messages_.colourBy(), colourBy_, "superrstudio_colour_by");
      row(data, 5, messages_.groupBy(), groupBy_, "superrstudio_group_by");

      Grid layers = section(messages_.layersHeading(), 12);
      row(layers, 0, messages_.geometry(), geometry_, "superrstudio_geometry");
      row(layers, 1, messages_.lineOrder(), lineOrder_, "superrstudio_line_order");
      row(layers, 2, messages_.fit(), fit_, "superrstudio_fit");
      row(layers, 3, "", fitSe_, "superrstudio_fit_se");
      row(layers, 4, messages_.fitLevel(), fitLevel_, "superrstudio_fit_level");
      row(layers, 5, messages_.fitSpan(), fitSpan_, "superrstudio_fit_span");
      row(layers, 6, messages_.bins(), bins_, "superrstudio_bins");
      row(layers, 7, messages_.binWidth(), binWidth_, "superrstudio_bin_width");
      row(layers, 8, "", showOutliers_, "superrstudio_show_outliers");
      row(layers, 9, "", showPoints_, "superrstudio_show_points");
      row(layers, 10, messages_.barPosition(), barPosition_, "superrstudio_bar_position");
      row(layers, 11, messages_.adjust(), adjust_, "superrstudio_adjust");
      orderHint_.getElement().setId("superrstudio_order_hint");
      orderHint_.setWidth("290px");
      orderHint_.getElement().getStyle().setProperty("fontSize", "90%");

      Grid look = section(messages_.appearanceHeading(), 12);
      row(look, 0, messages_.plotTitle(), title_, "superrstudio_title");
      row(look, 1, messages_.xLabel(), xLabel_, "superrstudio_xlabel");
      row(look, 2, messages_.yLabel(), yLabel_, "superrstudio_ylabel");
      row(look, 3, messages_.colour(), colour_, "superrstudio_colour");
      row(look, 4, messages_.size(), size_, "superrstudio_size");
      row(look, 5, messages_.fill(), fill_, "superrstudio_fill");
      row(look, 6, messages_.opacity(), alpha_, "superrstudio_alpha");
      lineColourLabel_ = row(look, 7, messages_.lineColour(), lineColour_, "superrstudio_line_colour");
      row(look, 8, messages_.lineWidth(), lineWidth_, "superrstudio_line_width");
      row(look, 9, messages_.lineType(), lineType_, "superrstudio_line_type");
      row(look, 10, messages_.fitColour(), fitColour_, "superrstudio_fit_colour");
      row(look, 11, messages_.theme(), theme_, "superrstudio_theme");

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
      code_.setWidth("700px");
      code_.getElement().setId("superrstudio_code");
      panel.add(new FormLabel(messages_.codeLabel(), code_));
      panel.add(code_);
      model_.getElement().setId("superrstudio_model");
      model_.getElement().setAttribute("role", "status");
      model_.getElement().setAttribute("aria-live", "polite");
      model_.getElement().getStyle().setProperty("whiteSpace", "pre-line");
      model_.setWidth("700px");
      panel.add(model_);

      HorizontalPanel buttons = new HorizontalPanel();
      buttons.setStyleName(ThemeStyles.INSTANCE.dialogBottomPanel());
      buttons.setWidth("100%");
      HorizontalPanel leftButtons = new HorizontalPanel();
      button(leftButtons, refresh_, "superrstudio_refresh");
      button(leftButtons, preview_, "superrstudio_preview");
      button(leftButtons, export_, "superrstudio_export");
      buttons.add(leftButtons);
      HorizontalPanel rightButtons = new HorizontalPanel();
      button(rightButtons, close_, "superrstudio_close");
      buttons.add(rightButtons);
      buttons.setCellHorizontalAlignment(rightButtons, HasHorizontalAlignment.ALIGN_RIGHT);
      panel.add(buttons);
      layoutChanged();
      updateUndo();
      return panel;
   }

   private static void button(HorizontalPanel panel, ThemedButton button, String id)
   {
      button.addStyleDependentName("DialogAction");
      ElementIds.assignElementId(button, id);
      panel.add(button);
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

   private FormLabel row(Grid grid, int row, String text, Widget control, String id)
   {
      control.getElement().setId(id);
      control.setWidth("180px");
      FormLabel label = null;
      if (!text.isEmpty())
      {
         label = new FormLabel(text, control);
         label.setWidth("150px");
         grid.setWidget(row, 0, label);
      }
      grid.setWidget(row, 1, control);
      rows_.put(control, new Object[] {grid, row});
      return label;
   }

   // Show or hide the grid row holding a control.
   private void showRow(Widget control, boolean visible)
   {
      Object[] location = rows_.get(control);
      if (location != null)
         ((Grid) location[0]).getRowFormatter().setVisible((Integer) location[1], visible);
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

   private static String value(ListBox list)
   {
      return list.getItemCount() > 0 && list.getSelectedValue() != null ? list.getSelectedValue() : "";
   }

   private String kind()
   {
      return value(kind_);
   }

   // Column lists per plot type; selections are kept when still valid.
   private void populateColumns()
   {
      String kind = kind();
      String x = value(x_), y = value(y_), colourBy = value(colourBy_);
      x_.clear(); y_.clear(); colourBy_.clear(); groupBy_.clear();
      colourBy_.addItem(messages_.colourByNone(), "");
      groupBy_.addItem(messages_.colourByNone(), "");
      if (KIND_SCATTER.equals(kind))
      {
         addAll(x_, numericColumns_); addAll(y_, numericColumns_);
         addAll(colourBy_, colourColumns_); addAll(groupBy_, discreteColumns_);
         if (y_.getItemCount() > 1) y_.setSelectedIndex(1);
      }
      else if (KIND_HISTOGRAM.equals(kind) || KIND_DENSITY.equals(kind))
      {
         addAll(x_, numericColumns_);
         addAll(colourBy_, discreteColumns_);
      }
      else if (KIND_BAR.equals(kind))
      {
         addAll(x_, discreteColumns_);
         addAll(colourBy_, discreteColumns_);
      }
      else
      {
         x_.addItem(messages_.colourByNone(), "");
         addAll(x_, discreteColumns_); addAll(y_, numericColumns_);
         addAll(colourBy_, discreteColumns_);
      }
      select(x_, x); select(y_, y); select(colourBy_, colourBy);
      xRowLabel_.setText(KIND_SCATTER.equals(kind) ? messages_.xColumn()
         : KIND_BOXPLOT.equals(kind) ? messages_.groupOptional()
         : KIND_BAR.equals(kind) ? messages_.category() : messages_.variable());
      yRowLabel_.setText(KIND_BOXPLOT.equals(kind) ? messages_.response() : messages_.yColumn());
      colourByLabel_.setText(KIND_SCATTER.equals(kind) ? messages_.colourBy() : messages_.fillBy());
   }

   private static void addAll(ListBox list, JsArrayString values)
   {
      if (values == null) return;
      for (int i = 0; i < values.length(); i++)
         list.addItem(values.get(i));
   }

   // Show only the controls that apply to the plot type, enable only those
   // that affect the selected layers, and keep combinations R would reject
   // (fixed colour with a colour column, grouping without lines or a fit)
   // from being made.
   private void layoutChanged()
   {
      String kind = kind();
      boolean scatter = KIND_SCATTER.equals(kind), histogram = KIND_HISTOGRAM.equals(kind),
              boxplot = KIND_BOXPLOT.equals(kind), bar = KIND_BAR.equals(kind),
              density = KIND_DENSITY.equals(kind);
      // kinds that use one X column only and no points
      boolean single = histogram || bar || density;
      String geometry = geometry_.getSelectedValue();
      boolean points = scatter ? !"lines".equals(geometry) : boxplot && showPoints_.getValue();
      boolean lines = scatter && !"points".equals(geometry);
      boolean fit = scatter && !"none".equals(fit_.getSelectedValue());
      boolean mapped = has(colourBy_);
      boolean dirty = false;
      if (mapped && scatter && !colour_.getSelectedValue().isEmpty())
      {
         select(colour_, "");
         dirty = true;
      }
      if (mapped && !scatter && !fill_.getSelectedValue().isEmpty())
      {
         select(fill_, "");
         dirty = true;
      }
      if ((!lines && !fit) && has(groupBy_))
         groupBy_.setSelectedIndex(0);

      showRow(y_, !single);
      showRow(groupBy_, scatter);
      for (Widget scatterOnly : new Widget[] {geometry_, lineOrder_, fit_, fitSe_, fitLevel_, fitSpan_,
                                              lineWidth_, lineType_, fitColour_})
         showRow(scatterOnly, scatter);
      showRow(bins_, histogram);
      showRow(binWidth_, histogram);
      showRow(showOutliers_, boxplot);
      showRow(showPoints_, boxplot);
      showRow(barPosition_, bar);
      showRow(adjust_, density);
      showRow(colour_, !single);
      showRow(size_, !single);
      showRow(fill_, !scatter);
      lineColourLabel_.setText(scatter ? messages_.lineColour() : messages_.outlineColour());

      colour_.setEnabled(points && !(mapped && scatter));
      size_.setEnabled(points);
      alpha_.setEnabled(points || !scatter);
      fill_.setEnabled(!mapped);
      lineOrder_.setEnabled(lines);
      lineColour_.setEnabled(lines || !scatter);
      lineWidth_.setEnabled(lines);
      lineType_.setEnabled(lines);
      groupBy_.setEnabled((lines || fit) && groupBy_.getItemCount() > 1);
      fitSe_.setEnabled(fit);
      fitLevel_.setEnabled(fit && fitSe_.getValue());
      fitSpan_.setEnabled(fit && "loess".equals(fit_.getSelectedValue()));
      fitColour_.setEnabled(fit);
      bins_.setEnabled(histogram && isZero(binWidth_.getValue()));
      orderHint_.setText(!lines ? "" : "x".equals(lineOrder_.getSelectedValue())
         ? messages_.lineOrderHintX() : messages_.lineOrderHintData());
      if (dirty)
         settingsChanged();
      invalidate();
   }

   private static boolean isZero(String text)
   {
      try
      {
         return Double.parseDouble(text.trim()) == 0;
      }
      catch (NumberFormatException e)
      {
         return false;
      }
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
      // the plot type and column mappings are data, validated against the dataset in R
      json.put("kind", new JSONString(kind().isEmpty() ? KIND_SCATTER : kind()));
      json.put("colour_by", new JSONString(value(colourBy_)));
      json.put("group_by", new JSONString(value(groupBy_)));
      return json;
   }

   private void showModel(ScatterResult result)
   {
      StringBuilder text = new StringBuilder();
      JsArray<ScatterResult.SummaryEntry> summary = result.summary();
      if (summary.length() > 0)
      {
         text.append(messages_.summaryHeading()).append(":\n");
         boolean boxes = false;
         for (int i = 0; i < summary.length(); i++)
         {
            ScatterResult.SummaryEntry entry = summary.get(i);
            String group = "all".equals(entry.group()) && summary.length() == 1
               ? messages_.allObservations() : entry.group();
            if (KIND_HISTOGRAM.equals(kind()))
               text.append(messages_.histSummary(entry.n(), entry.removed(), entry.hasBins()
                  ? messages_.binsText(entry.bins()) : messages_.binWidthText(entry.binWidth())));
            else if (KIND_BAR.equals(kind()))
               text.append(messages_.barSummary(group, entry.n()));
            else if (KIND_DENSITY.equals(kind()))
               text.append(entry.hasBandwidth()
                  ? messages_.densitySummary(group, entry.n(), entry.bandwidth())
                  : messages_.densityTooFew(group, entry.n()));
            else if (entry.hasBox())
            {
               boxes = true;
               text.append(messages_.boxSummary(group, entry.n(), entry.median(), entry.q1(), entry.q3(),
                  entry.lowerWhisker(), entry.upperWhisker(), entry.outliers()));
            }
            else
               text.append(messages_.boxEmpty(group));
            text.append("\n");
         }
         if (boxes)
            text.append(messages_.boxNote());
      }

      JsArray<ScatterResult.FitEntry> entries = result.fitSummary();
      if (entries.length() > 0)
      {
         text.append(messages_.modelHeading()).append(":\n");
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
      }
      model_.setText(text.toString());
   }

   // Session requests --------------------------------------------------------

   private boolean columnsChosen()
   {
      String kind = kind();
      if (!KIND_SCATTER.equals(kind) && !KIND_BOXPLOT.equals(kind)) return x_.getItemCount() > 0;
      if (KIND_BOXPLOT.equals(kind)) return y_.getItemCount() > 0;
      return x_.getItemCount() > 0 && y_.getItemCount() > 0;
   }

   private void busy(boolean busy)
   {
      datasets_.setEnabled(!busy && datasets_.getItemCount() > 0);
      kind_.setEnabled(!busy && !revision_.isEmpty());
      x_.setEnabled(!busy && x_.getItemCount() > 0);
      y_.setEnabled(!busy && y_.getItemCount() > 0);
      colourBy_.setEnabled(!busy && colourBy_.getItemCount() > 1);
      refresh_.setEnabled(!busy);
      preview_.setEnabled(!busy && !revision_.isEmpty() && columnsChosen());
      export_.setEnabled(!busy && !revision_.isEmpty() && columnsChosen());
      if (!busy)
         layoutChanged();
   }
   private void refresh()
   {
      revision_ = "";
      datasets_.clear(); clearColumns();
      status_.setText(messages_.loading());
      request("list", "", "", "", "", result -> {
         // label tibbles and data.tables; the value stays the object's name
         JsArrayString names = result.datasets(), kinds = result.datasetKinds();
         datasets_.clear();
         for (int i = 0; i < names.length(); i++)
            datasets_.addItem(i < kinds.length() && !"data.frame".equals(kinds.get(i))
               ? names.get(i) + " (" + kinds.get(i) + ")" : names.get(i), names.get(i));
         if (datasets_.getItemCount() > 0) inspect();
         else status_.setText(messages_.noData());
      });
   }
   private void clearColumns()
   {
      numericColumns_ = discreteColumns_ = colourColumns_ = null;
      x_.clear(); y_.clear(); colourBy_.clear(); groupBy_.clear();
      invalidate();
   }
   private void inspect()
   {
      revision_ = "";
      clearColumns();
      status_.setText(messages_.loading());
      request("inspect", value(datasets_), "", "", "", result -> {
         revision_ = result.revision();
         numericColumns_ = result.columns();
         discreteColumns_ = result.discreteColumns();
         colourColumns_ = result.colourColumns();
         populateColumns();
         status_.setText(numericColumns_.length() > 0 ? messages_.ready() : messages_.noColumns());
         busy(false);
      });
   }
   private void generate(boolean export)
   {
      status_.setText(messages_.working());
      String kind = kind();
      String y = KIND_SCATTER.equals(kind) || KIND_BOXPLOT.equals(kind) ? value(y_) : "";
      request(export ? "code" : "preview", value(datasets_), revision_, value(x_), y, result -> {
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
   private static final String KIND_SCATTER = "scatter";
   private static final String KIND_HISTOGRAM = "histogram";
   private static final String KIND_BOXPLOT = "boxplot";
   private static final String KIND_BAR = "bar";
   private static final String KIND_DENSITY = "density";

   private final SuperRStudioServerOperations server_;
   private final EventBus events_;
   private final Commands commands_;
   private final ListBox datasets_ = new ListBox(), kind_ = new ListBox(), x_ = new ListBox(),
                         y_ = new ListBox(), colourBy_ = new ListBox(), groupBy_ = new ListBox();
   private final ListBox geometry_ = new ListBox(), lineOrder_ = new ListBox(), fit_ = new ListBox(),
                         fitLevel_ = new ListBox(), fitSpan_ = new ListBox(), bins_ = new ListBox(),
                         barPosition_ = new ListBox(), adjust_ = new ListBox();
   private final CheckBox fitSe_ = new CheckBox(), showOutliers_ = new CheckBox(),
                          showPoints_ = new CheckBox();
   private final TextBox title_ = new TextBox(), xLabel_ = new TextBox(), yLabel_ = new TextBox(),
                         binWidth_ = new TextBox();
   private final ListBox colour_ = new ListBox(), size_ = new ListBox(), alpha_ = new ListBox(),
                         fill_ = new ListBox(), theme_ = new ListBox(), lineColour_ = new ListBox(),
                         lineWidth_ = new ListBox(), lineType_ = new ListBox(), fitColour_ = new ListBox();
   private final TextArea code_ = new TextArea();
   private final Label status_ = new Label(), model_ = new Label(), orderHint_ = new Label();
   private FormLabel xRowLabel_, yRowLabel_, colourByLabel_, lineColourLabel_;
   private final ThemedButton preview_, export_, refresh_, close_, undo_, reset_;
   private final Map<Widget, Object[]> rows_ = new HashMap<>();
   private final List<Setting> settings_ = new ArrayList<>();
   private final List<String[]> history_ = new ArrayList<>();
   private final String[] defaults_;
   private JsArrayString numericColumns_, discreteColumns_, colourColumns_;
   private String[] current_;
   private boolean restoring_ = false;
   private String revision_ = "";
   private int requestId_ = 0;
   private static ScatterDialog instance_;
   private static final ScatterMessages messages_ = GWT.create(ScatterMessages.class);
}
