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
import com.google.gwt.json.client.JSONParser;
import com.google.gwt.json.client.JSONString;
import com.google.gwt.json.client.JSONValue;
import com.google.gwt.user.client.Timer;
import com.google.gwt.user.client.ui.*;
import org.rstudio.core.client.ElementIds;
import org.rstudio.core.client.files.FileSystemItem;
import org.rstudio.core.client.widget.ProgressIndicator;
import org.rstudio.core.client.widget.ProgressOperationWithInput;
import org.rstudio.core.client.theme.res.ThemeStyles;
import org.rstudio.core.client.widget.FormLabel;
import org.rstudio.core.client.widget.MiniPopupPanel;
import org.rstudio.core.client.widget.OperationWithInput;
import org.rstudio.core.client.widget.ThemedButton;
import org.rstudio.studio.client.RStudioGinjector;
import org.rstudio.studio.client.application.events.EventBus;
import org.rstudio.studio.client.server.ServerError;
import org.rstudio.studio.client.server.ServerRequestCallback;
import org.rstudio.studio.client.workbench.commands.Commands;
import org.rstudio.studio.client.workbench.views.source.SourceColumn;
import org.rstudio.studio.client.workbench.views.source.editors.EditingTarget;
import org.rstudio.studio.client.workbench.views.source.editors.text.TextEditingTarget;
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
      redo_ = new ThemedButton(messages_.redo(), e -> redo());
      editSelected_ = new ThemedButton(messages_.editSelected(), e -> {
         int[] position = plot_.selectedPagePosition();
         editElement(plot_.selectedRole(), position[0], position[1]);
      });
      reset_ = new ThemedButton(messages_.reset(), e -> reset());
      load_ = new ThemedButton(messages_.loadSpec(), e -> loadFromScript());
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
      kind_.addChangeHandler(e -> { populateColumns(); busy(false); scheduleRender(); });
      datasets_.addChangeHandler(e -> inspect());
      x_.addChangeHandler(e -> { xTypeChanged(); invalidate(); scheduleRender(); });
      y_.addChangeHandler(e -> { invalidate(); scheduleRender(); });
      colourBy_.addChangeHandler(e -> { layoutChanged(); scheduleRender(); });
      groupBy_.addChangeHandler(e -> { invalidate(); scheduleRender(); });
      facetBy_.addChangeHandler(e -> { layoutChanged(); scheduleRender(); });
      facetRows_.addChangeHandler(e -> { layoutChanged(); scheduleRender(); });

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
      option(legendPosition_, messages_.legendRight(), "right");
      option(legendPosition_, messages_.legendBottom(), "bottom");
      option(legendPosition_, messages_.legendTop(), "top");
      option(legendPosition_, messages_.legendLeft(), "left");
      option(legendPosition_, messages_.legendNone(), "none");
      for (ListBox scale : new ListBox[] {xScale_, yScale_})
      {
         option(scale, messages_.scaleLinear(), "linear");
         option(scale, messages_.scaleLog10(), "log10");
      }
      for (ListBox format : new ListBox[] {xFormat_, yFormat_})
      {
         option(format, messages_.formatDefault(), "default");
         option(format, messages_.formatComma(), "comma");
         option(format, messages_.formatScientific(), "scientific");
         option(format, messages_.formatPercent(), "percent");
      }
      option(xDateBreaks_, messages_.formatDefault(), "");
      for (String breaks : new String[] {"1 day", "1 week", "2 weeks", "1 month", "2 months", "3 months",
                                         "6 months", "1 year", "1 hour", "6 hours", "12 hours"})
         option(xDateBreaks_, breaks, breaks);
      option(xDateLabels_, messages_.formatDefault(), "");
      for (String labels : new String[] {"%Y-%m-%d", "%d/%m/%Y", "%m/%d/%Y", "%Y-%m", "%b %Y", "%B %Y", "%Y",
                                         "%d %b", "%H:%M", "%d %b %H:%M", "%Y-%m-%d %H:%M"})
         option(xDateLabels_, labels, labels);
      option(limitsMode_, messages_.limitsZoom(), "zoom");
      option(limitsMode_, messages_.limitsFilter(), "filter");
      option(facetNcol_, messages_.facetAuto(), "0");
      for (String columns : new String[] {"1", "2", "3", "4", "5", "6"})
         option(facetNcol_, columns, columns);
      option(facetScales_, messages_.facetFixed(), "fixed");
      option(facetScales_, messages_.facetFree(), "free");
      option(facetScales_, messages_.facetFreeX(), "free_x");
      option(facetScales_, messages_.facetFreeY(), "free_y");
      gridMajor_.setText(messages_.gridMajor());
      gridMinor_.setText(messages_.gridMinor());
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
      settings_.add(new Setting("legend_position", legendPosition_, TYPE_STRING, "right"));
      settings_.add(new Setting("x_scale", xScale_, TYPE_STRING, "linear"));
      settings_.add(new Setting("x_min", xMin_, TYPE_NUMBER, ""));
      settings_.add(new Setting("x_max", xMax_, TYPE_NUMBER, ""));
      settings_.add(new Setting("x_format", xFormat_, TYPE_STRING, "default"));
      settings_.add(new Setting("x_date_breaks", xDateBreaks_, TYPE_STRING, ""));
      settings_.add(new Setting("x_date_labels", xDateLabels_, TYPE_STRING, ""));
      settings_.add(new Setting("x_timezone", xTimezone_, TYPE_STRING, ""));
      settings_.add(new Setting("y_scale", yScale_, TYPE_STRING, "linear"));
      settings_.add(new Setting("y_min", yMin_, TYPE_NUMBER, ""));
      settings_.add(new Setting("y_max", yMax_, TYPE_NUMBER, ""));
      settings_.add(new Setting("y_format", yFormat_, TYPE_STRING, "default"));
      settings_.add(new Setting("limits_mode", limitsMode_, TYPE_STRING, "zoom"));
      settings_.add(new Setting("grid_major", gridMajor_, TYPE_BOOLEAN, "true"));
      settings_.add(new Setting("grid_minor", gridMinor_, TYPE_BOOLEAN, "true"));
      settings_.add(new Setting("facet_ncol", facetNcol_, TYPE_NUMBER, "0"));
      settings_.add(new Setting("facet_scales", facetScales_, TYPE_STRING, "fixed"));
      defaults_ = new String[settings_.size()];
      for (int i = 0; i < defaults_.length; i++)
         defaults_[i] = settings_.get(i).defaultValue;
      apply(defaults_);
      current_ = defaults_;

      for (TextBox text : new TextBox[] {title_, xLabel_, yLabel_, binWidth_, xMin_, xMax_, yMin_, yMax_})
         text.addValueChangeHandler(e -> settingsChanged());
      for (CheckBox check : new CheckBox[] {fitSe_, showOutliers_, showPoints_, gridMajor_, gridMinor_})
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
      panel.setWidth("560px");
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
      orderHint_.setWidth("260px");
      orderHint_.getElement().getStyle().setProperty("fontSize", "90%");

      Grid look = section(messages_.appearanceHeading(), 13);
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
      row(look, 12, messages_.legendPosition(), legendPosition_, "superrstudio_legend_position");

      undo_.getElement().setId("superrstudio_undo");
      redo_.getElement().setId("superrstudio_redo");
      reset_.getElement().setId("superrstudio_reset");
      load_.getElement().setId("superrstudio_load");
      HorizontalPanel history = new HorizontalPanel();
      history.setSpacing(2);
      history.add(undo_);
      history.add(redo_);
      history.add(reset_);
      history.add(load_);

      Grid xAxis = section(messages_.xAxisHeading(), 7);
      row(xAxis, 0, messages_.scale(), xScale_, "superrstudio_x_scale");
      row(xAxis, 1, messages_.axisMin(), xMin_, "superrstudio_x_min");
      row(xAxis, 2, messages_.axisMax(), xMax_, "superrstudio_x_max");
      row(xAxis, 3, messages_.tickLabels(), xFormat_, "superrstudio_x_format");
      row(xAxis, 4, messages_.dateBreaks(), xDateBreaks_, "superrstudio_x_date_breaks");
      row(xAxis, 5, messages_.dateLabels(), xDateLabels_, "superrstudio_x_date_labels");
      row(xAxis, 6, messages_.timezone(), xTimezone_, "superrstudio_x_timezone");
      Grid yAxis = section(messages_.yAxisHeading(), 4);
      row(yAxis, 0, messages_.scale(), yScale_, "superrstudio_y_scale");
      row(yAxis, 1, messages_.axisMin(), yMin_, "superrstudio_y_min");
      row(yAxis, 2, messages_.axisMax(), yMax_, "superrstudio_y_max");
      row(yAxis, 3, messages_.tickLabels(), yFormat_, "superrstudio_y_format");
      Grid facets = section(messages_.facetsHeading(), 7);
      row(facets, 0, messages_.limitsMode(), limitsMode_, "superrstudio_limits_mode");
      row(facets, 1, messages_.facetBy(), facetBy_, "superrstudio_facet_by");
      row(facets, 2, messages_.facetRows(), facetRows_, "superrstudio_facet_rows");
      row(facets, 3, messages_.facetColumns(), facetNcol_, "superrstudio_facet_ncol");
      row(facets, 4, messages_.facetScales(), facetScales_, "superrstudio_facet_scales");
      row(facets, 5, "", gridMajor_, "superrstudio_grid_major");
      row(facets, 6, "", gridMinor_, "superrstudio_grid_minor");
      Label limitsHint = new Label(messages_.limitsHint());
      limitsHint.setWidth("270px");
      limitsHint.getElement().getStyle().setProperty("fontSize", "90%");

      VerticalPanel dataColumn = column(heading(messages_.dataHeading()), data);
      VerticalPanel layersColumn = column(heading(messages_.layersHeading()), layers, orderHint_);
      addTab(messages_.tabData(), "data", columns(dataColumn, layersColumn));
      addTab(messages_.tabAppearance(), "appearance", column(heading(messages_.appearanceHeading()), look));
      addTab(messages_.tabAxes(), "axes", columns(
         column(heading(messages_.xAxisHeading()), xAxis, heading(messages_.yAxisHeading()), yAxis),
         column(heading(messages_.facetsHeading()), facets, limitsHint)));
      tabBar_.getElement().setAttribute("role", "tablist");
      tabBar_.getElement().setAttribute("aria-label", messages_.settingsTabs());
      panel.add(tabBar_);
      panel.add(tabDeck_);
      showTab(0);
      panel.add(history);

      code_.setReadOnly(true);
      code_.setVisibleLines(6);
      code_.setWidth("550px");
      code_.getElement().setId("superrstudio_code");
      panel.add(new FormLabel(messages_.codeLabel(), code_));
      panel.add(code_);
      model_.getElement().setId("superrstudio_model");
      model_.getElement().setAttribute("role", "status");
      model_.getElement().setAttribute("aria-live", "polite");
      model_.getElement().getStyle().setProperty("whiteSpace", "pre-line");
      model_.setWidth("550px");
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

      // the interactive preview beside the settings
      VerticalPanel preview = new VerticalPanel();
      preview.setSpacing(4);
      preview.add(heading(messages_.interactiveHeading()));
      Label help = new Label(messages_.interactiveHelp());
      help.setWidth("480px");
      help.getElement().getStyle().setProperty("fontSize", "90%");
      preview.add(help);
      plot_.getElement().setAttribute("aria-label", messages_.interactiveHeading());
      preview.add(plot_);
      editSelected_.getElement().setId("superrstudio_edit_selected");
      editSelected_.setEnabled(false);
      preview.add(editSelected_);
      preview.add(heading(messages_.exportHeading()));
      preview.add(createExportPanel());
      HorizontalPanel main = new HorizontalPanel();
      // top-aligned: the preview must not move when the settings column grows
      main.setVerticalAlignment(HasVerticalAlignment.ALIGN_TOP);
      main.add(panel);
      main.add(preview);
      return main;
   }

   // Export -----------------------------------------------------------------

   private Widget createExportPanel()
   {
      option(exportFormat_, messages_.exportPng(), "png");
      option(exportFormat_, messages_.exportSvg(), "svg");
      option(exportFormat_, messages_.exportPdf(), "pdf");
      for (String unit : new String[] {"cm", "mm", "in"})
         option(exportUnits_, unit, unit);
      for (String dpi : new String[] {"150", "300", "600"})
         option(exportDpi_, dpi, dpi);
      select(exportDpi_, "300");
      exportWidth_.setValue("16");
      exportHeight_.setValue("12");
      exportFormat_.addChangeHandler(e -> {
         // keep the file name's extension in step with the format
         String path = exportPath_.getValue().trim();
         int dot = path.lastIndexOf('.');
         if (!path.isEmpty() && dot > path.lastIndexOf('/'))
            exportPath_.setValue(path.substring(0, dot + 1) + exportFormat_.getSelectedValue());
         exportDpi_.setEnabled("png".equals(exportFormat_.getSelectedValue()));
      });
      Grid grid = new Grid(3, 4);
      grid.setCellSpacing(2);
      exportCell(grid, 0, 0, messages_.exportFormat(), exportFormat_, "superrstudio_export_format", "150px");
      exportCell(grid, 0, 2, messages_.exportDpi(), exportDpi_, "superrstudio_export_dpi", "70px");
      exportCell(grid, 1, 0, messages_.exportWidth(), exportWidth_, "superrstudio_export_width", "60px");
      exportCell(grid, 1, 2, messages_.exportHeight(), exportHeight_, "superrstudio_export_height", "60px");
      exportCell(grid, 2, 0, messages_.exportUnits(), exportUnits_, "superrstudio_export_units", "70px");
      exportPath_.getElement().setId("superrstudio_export_path");
      exportPath_.setWidth("300px");
      ThemedButton browse = new ThemedButton(messages_.exportBrowse(), e -> browseExport());
      browse.getElement().setId("superrstudio_export_browse");
      exportImage_.getElement().setId("superrstudio_export_image");
      HorizontalPanel file = new HorizontalPanel();
      file.setSpacing(2);
      file.setVerticalAlignment(HasVerticalAlignment.ALIGN_MIDDLE);
      file.add(new FormLabel(messages_.exportPath(), exportPath_));
      file.add(exportPath_);
      file.add(browse);
      VerticalPanel panel = new VerticalPanel();
      panel.add(grid);
      panel.add(file);
      exportImage_.setEnabled(false);
      panel.add(exportImage_);
      return panel;
   }

   private static void exportCell(Grid grid, int row, int column, String text, Widget control, String id, String width)
   {
      control.getElement().setId(id);
      control.setWidth(width);
      grid.setWidget(row, column, new FormLabel(text, control));
      grid.setWidget(row, column + 1, control);
   }

   private void browseExport()
   {
      String format = exportFormat_.getSelectedValue();
      String name = (value(datasets_).isEmpty() ? "plot" : value(datasets_).replaceAll("[^A-Za-z0-9_.-]", "_"));
      String current = exportPath_.getValue().trim();
      FileSystemItem initial = FileSystemItem.createFile(current.isEmpty()
         ? FileSystemItem.HOME_PREFIX + name + "." + format : current);
      RStudioGinjector.INSTANCE.getFileDialogs().saveFile(
         messages_.exportCaption(),
         RStudioGinjector.INSTANCE.getRemoteFileSystemContext(),
         initial, "." + format, true,
         new ProgressOperationWithInput<FileSystemItem>()
         {
            @Override public void execute(FileSystemItem input, ProgressIndicator indicator)
            {
               indicator.onCompleted();
               if (input != null)
                  exportPath_.setValue(input.getPath());
            }
         });
   }

   private void exportImage()
   {
      status_.setText(messages_.working());
      String kind = kind();
      String y = KIND_SCATTER.equals(kind) || KIND_BOXPLOT.equals(kind) ? value(y_) : "";
      exporting_ = true;
      request("export", value(datasets_), revision_, value(x_), y, result -> {
         showResult(result);
         code_.setText(result.provenance() + result.exportCode());
         status_.setText(messages_.exported(result.savedPath(),
            String.valueOf(Math.max(1, Math.round(result.savedBytes() / 1024)))) +
            (result.warnings().isEmpty() ? "" : "\n" + result.warnings()));
      });
      exporting_ = false;
   }

   private static VerticalPanel column(Widget... widgets)
   {
      VerticalPanel column = new VerticalPanel();
      for (Widget widget : widgets)
         column.add(widget);
      return column;
   }

   private static HorizontalPanel columns(Widget left, Widget right)
   {
      HorizontalPanel columns = new HorizontalPanel();
      columns.setSpacing(4);
      columns.add(left);
      columns.add(right);
      return columns;
   }

   // A WAI-ARIA tab: arrow keys move between tabs, the page is a tabpanel.
   private void addTab(String label, String name, Widget page)
   {
      int index = tabButtons_.size();
      Button tab = new Button(label);
      tab.getElement().setId("superrstudio_tab_" + name);
      tab.getElement().setAttribute("role", "tab");
      tab.getElement().setAttribute("aria-controls", "superrstudio_tabpanel_" + name);
      tab.addClickHandler(e -> showTab(index));
      tab.addKeyDownHandler(e -> {
         int code = e.getNativeKeyCode();
         if (code == KeyCodes.KEY_RIGHT || code == KeyCodes.KEY_LEFT)
         {
            e.preventDefault();
            int next = (index + (code == KeyCodes.KEY_RIGHT ? 1 : -1) + tabButtons_.size()) % tabButtons_.size();
            showTab(next);
            tabButtons_.get(next).setFocus(true);
         }
      });
      page.getElement().setId("superrstudio_tabpanel_" + name);
      page.getElement().setAttribute("role", "tabpanel");
      page.getElement().setAttribute("data-superrstudio-tab", name);
      page.getElement().setAttribute("aria-labelledby", "superrstudio_tab_" + name);
      tabButtons_.add(tab);
      tabBar_.add(tab);
      tabDeck_.add(page);
   }

   private void showTab(int index)
   {
      tabDeck_.showWidget(index);
      for (int i = 0; i < tabButtons_.size(); i++)
      {
         Button tab = tabButtons_.get(i);
         tab.getElement().setAttribute("aria-selected", String.valueOf(i == index));
         tab.getElement().setTabIndex(i == index ? 0 : -1);
         tab.getElement().getStyle().setProperty("fontWeight", i == index ? "bold" : "normal");
      }
   }

   // Interactive preview -----------------------------------------------------

   private String elementName(String role)
   {
      switch (role)
      {
         case "points": return messages_.elementPoints();
         case "lines": return messages_.elementLines();
         case "fit": return messages_.elementFit();
         case "bars": return messages_.elementBars();
         case "boxes": return messages_.elementBoxes();
         case "density": return messages_.elementDensity();
         case "title": return messages_.elementTitle();
         case "x_label": return messages_.elementXLabel();
         case "x_axis": return messages_.elementXAxis();
         case "y_label": return messages_.elementYLabel();
         case "y_axis": return messages_.elementYAxis();
         case "legend": return messages_.elementLegend();
         case "strip": return messages_.elementStrip();
         default: return messages_.elementPanel();
      }
   }

   // The specification settings that a plot element exposes.
   private static String[] elementSettings(String role)
   {
      switch (role)
      {
         case "points": return new String[] {"colour", "size", "alpha"};
         case "lines": return new String[] {"line_colour", "line_width", "line_type", "line_order"};
         case "fit": return new String[] {"fit", "fit_colour", "fit_se", "fit_level", "fit_span"};
         case "bars": return new String[] {"fill", "line_colour", "alpha", "bins", "bin_width", "bar_position"};
         case "boxes": return new String[] {"fill", "line_colour", "alpha", "show_outliers", "show_points"};
         case "density": return new String[] {"fill", "line_colour", "alpha", "adjust"};
         case "title": return new String[] {"title"};
         case "x_label": return new String[] {"x_label"};
         case "x_axis": return new String[] {"x_scale", "x_min", "x_max", "x_format", "x_date_breaks",
                                             "x_date_labels", "x_timezone", "limits_mode", "x_label"};
         case "y_label": return new String[] {"y_label"};
         case "y_axis": return new String[] {"y_scale", "y_min", "y_max", "y_format", "limits_mode", "y_label"};
         case "legend": return new String[] {"legend_position"};
         case "strip": return new String[] {"facet_ncol", "facet_scales"};
         default: return new String[] {"theme", "grid_major", "grid_minor"};
      }
   }

   private Setting setting(String key)
   {
      for (Setting setting : settings_)
         if (setting.key.equals(key))
            return setting;
      return null;
   }

   private boolean rowVisible(Widget control)
   {
      Object[] location = rows_.get(control);
      return location == null ||
         ((Grid) location[0]).getRowFormatter().isVisible((Integer) location[1]);
   }

   // A property popup for one element. Its controls mirror the editor's own
   // settings: a change goes through the same undoable settings table and
   // re-renders the preview, so the plot, the form and the code stay in step.
   private void editElement(String role, int pageX, int pageY)
   {
      if (role == null || role.isEmpty())
         return;
      if (popup_ != null)
         popup_.hide();
      MiniPopupPanel popup = new MiniPopupPanel(true, false);
      popup_ = popup;
      popup.getElement().setId("superrstudio_element_popup");
      Roles.getDialogRole().set(popup.getElement());
      VerticalPanel content = new VerticalPanel();
      content.setSpacing(4);
      Label title = heading(elementName(role));
      content.add(title);
      Grid grid = new Grid(0, 2);
      grid.setCellSpacing(2);
      List<Runnable> refreshers = new ArrayList<>();
      Widget first = null;
      boolean disabled = false;
      for (String key : elementSettings(role))
      {
         Setting setting = setting(key);
         if (setting == null || !rowVisible(setting.widget))
            continue;
         Widget mirror = mirror(setting, refreshers);
         mirror.getElement().setId("superrstudio_popup_" + key);
         int row = grid.insertRow(grid.getRowCount());
         String text = setting.widget instanceof CheckBox ? "" : labels_.get(setting.widget);
         if (text != null && !text.isEmpty())
         {
            FormLabel label = new FormLabel(text, mirror);
            grid.setWidget(row, 0, label);
         }
         grid.setWidget(row, 1, mirror);
         disabled |= !((FocusWidget) setting.widget).isEnabled();
         if (first == null)
            first = mirror;
      }
      content.add(grid);
      if (disabled)
      {
         Label note = new Label(messages_.someDisabled());
         note.setWidth("260px");
         note.getElement().getStyle().setProperty("fontSize", "90%");
         content.add(note);
      }
      popupRefreshers_ = refreshers;
      content.addDomHandler(e -> {
         if (e.getNativeKeyCode() == KeyCodes.KEY_ESCAPE)
         {
            e.preventDefault();
            e.stopPropagation();
            popup.hide();
            plot_.getElement().focus();
         }
      }, KeyDownEvent.getType());
      popup.setWidget(content);
      popup.addCloseHandler(e -> {
         if (popup_ == popup)
         {
            popup_ = null;
            popupRefreshers_ = new ArrayList<>();
         }
      });
      popup.getElement().getStyle().setZIndex(zIndexAbove(getElement()));
      popup.setPopupPosition(pageX + 2, pageY + 2);
      popup.show();
      if (first instanceof FocusWidget)
         ((FocusWidget) first).setFocus(true);
   }

   private Widget mirror(Setting setting, List<Runnable> refreshers)
   {
      Widget original = setting.widget;
      if (original instanceof CheckBox)
      {
         CheckBox source = (CheckBox) original;
         CheckBox copy = new CheckBox(source.getText());
         refreshers.add(() -> {
            copy.setValue(source.getValue());
            copy.setEnabled(source.isEnabled());
         });
         copy.addValueChangeHandler(e -> edit(setting, String.valueOf(copy.getValue())));
         refreshers.get(refreshers.size() - 1).run();
         return copy;
      }
      if (original instanceof TextBox)
      {
         TextBox source = (TextBox) original;
         TextBox copy = new TextBox();
         copy.setWidth("180px");
         refreshers.add(() -> {
            copy.setValue(source.getValue());
            copy.setEnabled(source.isEnabled());
         });
         copy.addValueChangeHandler(e -> edit(setting, copy.getValue()));
         refreshers.get(refreshers.size() - 1).run();
         return copy;
      }
      ListBox source = (ListBox) original;
      ListBox copy = new ListBox();
      copy.setWidth("180px");
      for (int i = 0; i < source.getItemCount(); i++)
         copy.addItem(source.getItemText(i), source.getValue(i));
      refreshers.add(() -> {
         copy.setSelectedIndex(source.getSelectedIndex());
         copy.setEnabled(source.isEnabled());
      });
      copy.addChangeHandler(e -> edit(setting, copy.getSelectedValue()));
      refreshers.get(refreshers.size() - 1).run();
      return copy;
   }

   private void edit(Setting setting, String value)
   {
      setting.set(value);
      settingsChanged();
      refreshPopup();
   }

   private void refreshPopup()
   {
      for (Runnable refresher : popupRefreshers_)
         refresher.run();
   }

   private static native int zIndexAbove(com.google.gwt.dom.client.Element element) /*-{
      var z = parseInt($wnd.getComputedStyle(element).zIndex, 10);
      return isNaN(z) ? 1000 : z + 1;
   }-*/;

   private void scheduleRender()
   {
      plot_.setStale();
      renderTimer_.schedule(250);
   }

   // Re-renders the interactive preview only (no Plots pane entry).
   private void render()
   {
      if (revision_.isEmpty() || !columnsChosen() || !isAttached())
         return;
      if (inFlight_)
      {
         renderTimer_.schedule(250);
         return;
      }
      final int renderId = ++renderId_;
      String kind = kind();
      String y = KIND_SCATTER.equals(kind) || KIND_BOXPLOT.equals(kind) ? value(y_) : "";
      server_.superrstudioData("render", value(datasets_), revision_, value(x_), y, settingsJson(),
         new ServerRequestCallback<ScatterResult>() {
            @Override public void onResponseReceived(ScatterResult result)
            {
               if (!isAttached() || renderId != renderId_) return;
               showResult(result);
               // live updates leave other messages alone, but replace their
               // own earlier error and report warnings
               if (renderError_ || !result.warnings().isEmpty())
                  status_.setText(messages_.rendered() + (result.warnings().isEmpty() ? "" : "\n" + result.warnings()));
               renderError_ = false;
            }
            @Override public void onError(ServerError error)
            {
               if (!isAttached() || renderId != renderId_) return;
               renderError_ = true;
               JSONValue info = error.getClientInfo();
               status_.setText(info != null && info.isString() != null
                  ? info.isString().stringValue()
                  : error.getUserMessage());
            }
         });
   }

   private void showResult(ScatterResult result)
   {
      String code = result.provenance() + result.code() +
         (result.modelCode().isEmpty() ? "" : "\n" + result.modelCode() + "\n");
      code_.setText(code);
      showModel(result);
      if (result.interactive() != null)
         plot_.setPlot(result.interactive());
      refreshPopup();
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
      control.setWidth("150px");
      FormLabel label = null;
      if (!text.isEmpty())
      {
         label = new FormLabel(text, control);
         label.setWidth("120px");
         grid.setWidget(row, 0, label);
         labels_.put(control, text);
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
      String facetBy = value(facetBy_), facetRows = value(facetRows_);
      x_.clear(); y_.clear(); colourBy_.clear(); groupBy_.clear(); facetBy_.clear(); facetRows_.clear();
      colourBy_.addItem(messages_.colourByNone(), "");
      groupBy_.addItem(messages_.colourByNone(), "");
      facetBy_.addItem(messages_.colourByNone(), "");
      facetRows_.addItem(messages_.colourByNone(), "");
      addAll(facetBy_, discreteColumns_);
      addAll(facetRows_, discreteColumns_);
      select(facetBy_, facetBy);
      select(facetRows_, facetRows);
      if (KIND_SCATTER.equals(kind))
      {
         // dates and date-times make a time-series X
         addAll(x_, numericColumns_); addAll(x_, timeColumns_); addAll(y_, numericColumns_);
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
      labels_.put(lineColour_, KIND_SCATTER.equals(kind) ? messages_.lineColour() : messages_.outlineColour());
      xRowLabel_.setText(KIND_SCATTER.equals(kind) ? messages_.xColumn()
         : KIND_BOXPLOT.equals(kind) ? messages_.groupOptional()
         : KIND_BAR.equals(kind) ? messages_.category() : messages_.variable());
      yRowLabel_.setText(KIND_BOXPLOT.equals(kind) ? messages_.response() : messages_.yColumn());
      colourByLabel_.setText(KIND_SCATTER.equals(kind) ? messages_.colourBy() : messages_.fillBy());
      xType_ = xType();
   }

   // The selected X column's kind: "" (numeric), "date" or "datetime".
   private String xType()
   {
      if (!KIND_SCATTER.equals(kind()))
         return "";
      String x = value(x_);
      return contains(datetimeColumns_, x) ? "datetime" : contains(timeColumns_, x) ? "date" : "";
   }

   private static boolean contains(JsArrayString values, String value)
   {
      for (int i = 0; values != null && i < values.length(); i++)
         if (values.get(i).equals(value))
            return true;
      return false;
   }

   // Switching between a numeric and a date X: limits, scales and labels of
   // one kind mean nothing for the other, so they return to their defaults.
   private void xTypeChanged()
   {
      String type = xType();
      if (type.equals(xType_))
         return;
      xType_ = type;
      xMin_.setValue("");
      xMax_.setValue("");
      select(xScale_, "linear");
      select(xFormat_, "default");
      select(xDateBreaks_, "");
      select(xDateLabels_, "");
      xTimezone_.setValue("");
      layoutChanged();
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
      // axis settings a kind cannot use are reset rather than sent
      boolean continuousX = scatter || histogram || density, rawY = scatter || boxplot;
      if (!continuousX && (!"linear".equals(xScale_.getSelectedValue()) || !"default".equals(xFormat_.getSelectedValue()) ||
                           !xMin_.getValue().trim().isEmpty() || !xMax_.getValue().trim().isEmpty()))
      {
         select(xScale_, "linear");
         select(xFormat_, "default");
         xMin_.setValue("");
         xMax_.setValue("");
         dirty = true;
      }
      if (!rawY && !"linear".equals(yScale_.getSelectedValue()))
      {
         select(yScale_, "linear");
         dirty = true;
      }
      // filtering needs a measured axis (bars count categories)
      if (!continuousX && !rawY && "filter".equals(limitsMode_.getSelectedValue()))
      {
         select(limitsMode_, "zoom");
         dirty = true;
      }
      String time = xType();
      xType_ = time;
      for (Widget axis : new Widget[] {xMin_, xMax_})
         showRow(axis, continuousX);
      for (Widget axis : new Widget[] {xScale_, xFormat_})
         showRow(axis, continuousX && time.isEmpty());
      showRow(xDateBreaks_, !time.isEmpty());
      showRow(xDateLabels_, !time.isEmpty());
      showRow(xTimezone_, "datetime".equals(time));
      String placeholder = "date".equals(time) ? "YYYY-MM-DD" : "datetime".equals(time) ? "YYYY-MM-DD HH:MM" : "";
      for (TextBox limit : new TextBox[] {xMin_, xMax_})
         limit.getElement().setAttribute("placeholder", placeholder);
      showRow(yScale_, rawY);
      limitsMode_.setEnabled(continuousX || rawY);
      facetNcol_.setEnabled(has(facetBy_) && !has(facetRows_));
      facetScales_.setEnabled(has(facetBy_) || has(facetRows_));

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
      plot_.setStale();
   }

   // Loading a specification ------------------------------------------------

   // Restores the editor from the "# Specification: {...}" header of code it
   // generated (schema versions 1 to 3) in the active script. The dataset is
   // selected first; the rest is applied once its columns are known.
   private void loadFromScript()
   {
      JSONObject spec = activeScriptSpec();
      if (spec == null)
      {
         status_.setText(messages_.loadNone());
         return;
      }
      double version = number(spec, "schema_version", 0);
      if (version < 1 || version > 5)
      {
         status_.setText(messages_.loadUnsupported(String.valueOf(version)));
         return;
      }
      String dataset = string(spec, "dataset");
      boolean found = false;
      for (int i = 0; i < datasets_.getItemCount(); i++)
         found |= datasets_.getValue(i).equals(dataset);
      if (!found)
      {
         status_.setText(messages_.loadMissing(dataset));
         return;
      }
      pendingSpec_ = spec;
      select(datasets_, dataset);
      inspect();
   }

   private JSONObject activeScriptSpec()
   {
      SourceColumn column = RStudioGinjector.INSTANCE.getSourceColumnManager().getActive();
      EditingTarget target = column == null ? null : column.getActiveEditor();
      if (!(target instanceof TextEditingTarget))
         return null;
      String code = ((TextEditingTarget) target).getDocDisplay().getCode();
      for (String line : code.split("\n"))
      {
         String prefix = "# Specification: ";
         if (!line.startsWith(prefix))
            continue;
         try
         {
            JSONValue value = JSONParser.parseStrict(line.substring(prefix.length()).trim());
            return value.isObject();
         }
         catch (Exception e)
         {
            return null;
         }
      }
      return null;
   }

   private void applySpec(JSONObject spec)
   {
      String kind = string(spec, "kind");
      select(kind_, kind.isEmpty() ? KIND_SCATTER : kind);
      populateColumns();
      select(x_, string(spec, "x"));
      select(y_, string(spec, "y"));
      String mapped = string(spec, "colour_by");
      select(colourBy_, mapped.isEmpty() ? string(spec, "fill_by") : mapped);
      select(groupBy_, string(spec, "group_by"));
      select(facetBy_, string(spec, "facet_by"));
      select(facetRows_, string(spec, "facet_rows"));

      // settings missing from older schemas keep their defaults
      String[] values = Arrays.copyOf(defaults_, defaults_.length);   // GWT has no array clone()
      JSONObject layers = spec.get("layers") == null ? null : spec.get("layers").isObject();
      JSONObject appearance = spec.get("appearance") == null ? null : spec.get("appearance").isObject();
      JSONObject axes = spec.get("axes") == null ? null : spec.get("axes").isObject();
      for (int i = 0; i < settings_.size(); i++)
      {
         String key = settings_.get(i).key;
         JSONValue value = layers != null && layers.get(key) != null ? layers.get(key)
            : appearance != null && appearance.get(key) != null ? appearance.get(key)
            : axes != null ? axes.get(key) : null;
         if (value != null)
            values[i] = text(value);
      }
      apply(values);
      settingsChanged();   // one undoable step
      busy(false);
      status_.setText(messages_.loaded());
   }

   private static String string(JSONObject object, String key)
   {
      JSONValue value = object.get(key);
      return value != null && value.isString() != null ? value.isString().stringValue() : "";
   }

   private static double number(JSONObject object, String key, double fallback)
   {
      JSONValue value = object.get(key);
      return value != null && value.isNumber() != null ? value.isNumber().doubleValue() : fallback;
   }

   // JSON value as the string form used by the settings table (30, not 30.0)
   private static String text(JSONValue value)
   {
      if (value.isString() != null) return value.isString().stringValue();
      if (value.isBoolean() != null) return String.valueOf(value.isBoolean().booleanValue());
      if (value.isNumber() != null)
      {
         double number = value.isNumber().doubleValue();
         return number == Math.rint(number) ? String.valueOf((long) number) : String.valueOf(number);
      }
      return "";
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
      future_.clear();
      current_ = next;
      layoutChanged();
      updateUndo();
      scheduleRender();
   }

   private void undo()
   {
      if (history_.isEmpty())
         return;
      future_.add(current_);
      current_ = history_.remove(history_.size() - 1);
      restore();
   }

   private void redo()
   {
      if (future_.isEmpty())
         return;
      history_.add(current_);
      current_ = future_.remove(future_.size() - 1);
      restore();
   }

   private void restore()
   {
      apply(current_);
      // a restored fixed colour cannot coexist with an active colour column;
      // layoutChanged() may adjust it, which must not be recorded as an edit
      restoring_ = true;
      layoutChanged();
      restoring_ = false;
      current_ = read();
      updateUndo();
      refreshPopup();
      scheduleRender();
   }

   private void reset()
   {
      apply(defaults_);
      settingsChanged();
   }

   private void updateUndo()
   {
      undo_.setEnabled(!history_.isEmpty());
      redo_.setEnabled(!future_.isEmpty());
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
      json.put("facet_by", new JSONString(value(facetBy_)));
      json.put("facet_rows", new JSONString(value(facetRows_)));
      if (exporting_)
      {
         json.put("export_path", new JSONString(exportPath_.getValue().trim()));
         json.put("export_format", new JSONString(exportFormat_.getSelectedValue()));
         json.put("export_units", new JSONString(exportUnits_.getSelectedValue()));
         json.put("export_dpi", new JSONNumber(Double.parseDouble(exportDpi_.getSelectedValue())));
         for (String[] side : new String[][] {{"export_width", exportWidth_.getValue()},
                                              {"export_height", exportHeight_.getValue()}})
         {
            try
            {
               json.put(side[0], new JSONNumber(Double.parseDouble(side[1].trim())));
            }
            catch (NumberFormatException e)
            {
               json.put(side[0], new JSONString(side[1]));   // rejected by the session
            }
         }
      }
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
      if (!result.notes().isEmpty())
         text.append(text.length() == 0 || text.charAt(text.length() - 1) == '\n' ? "" : "\n")
             .append(messages_.notesHeading()).append(":\n").append(result.notes()).append("\n");
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
      facetBy_.setEnabled(!busy && facetBy_.getItemCount() > 1);
      facetRows_.setEnabled(!busy && facetRows_.getItemCount() > 1);
      refresh_.setEnabled(!busy);
      preview_.setEnabled(!busy && !revision_.isEmpty() && columnsChosen());
      export_.setEnabled(!busy && !revision_.isEmpty() && columnsChosen());
      exportImage_.setEnabled(!busy && !revision_.isEmpty() && columnsChosen());
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
      numericColumns_ = discreteColumns_ = colourColumns_ = timeColumns_ = datetimeColumns_ = null;
      x_.clear(); y_.clear(); colourBy_.clear(); groupBy_.clear(); facetBy_.clear(); facetRows_.clear();
      invalidate();
      plot_.clear();
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
         timeColumns_ = result.timeColumns();
         datetimeColumns_ = result.datetimeColumns();
         populateColumns();
         status_.setText(numericColumns_.length() > 0 ? messages_.ready() : messages_.noColumns());
         busy(false);
         if (pendingSpec_ != null)
         {
            JSONObject spec = pendingSpec_;
            pendingSpec_ = null;
            applySpec(spec);
         }
         scheduleRender();
      });
   }
   private void generate(boolean export)
   {
      status_.setText(messages_.working());
      String kind = kind();
      String y = KIND_SCATTER.equals(kind) || KIND_BOXPLOT.equals(kind) ? value(y_) : "";
      request(export ? "code" : "preview", value(datasets_), revision_, value(x_), y, result -> {
         showResult(result);
         String code = code_.getText();
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
      inFlight_ = true;
      final int requestId = ++requestId_;
      server_.superrstudioData(operation, dataset, revision, x, y, settingsJson(),
         new ServerRequestCallback<ScatterResult>() {
            @Override public void onResponseReceived(ScatterResult result)
            {
               if (!isAttached() || requestId != requestId_) return;
               inFlight_ = false;
               busy(false);
               done.execute(result);
            }
            @Override public void onError(ServerError error)
            {
               if (!isAttached() || requestId != requestId_) return;
               inFlight_ = false;
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
      ++renderId_;
      inFlight_ = false;
      renderTimer_.cancel();
      if (popup_ != null)
         popup_.hide();
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
   private final ThemedButton preview_, export_, refresh_, close_, undo_, redo_, reset_, load_,
                              editSelected_;
   private final ListBox exportFormat_ = new ListBox(), exportUnits_ = new ListBox(), exportDpi_ = new ListBox();
   private final TextBox exportWidth_ = new TextBox(), exportHeight_ = new TextBox(), exportPath_ = new TextBox();
   private final ThemedButton exportImage_ = new ThemedButton(messages_.exportImage(), e -> exportImage());
   private boolean exporting_ = false;
   private final ListBox legendPosition_ = new ListBox(), xScale_ = new ListBox(), yScale_ = new ListBox(),
                         xFormat_ = new ListBox(), yFormat_ = new ListBox(), limitsMode_ = new ListBox(),
                         facetBy_ = new ListBox(), facetRows_ = new ListBox(), facetNcol_ = new ListBox(),
                         facetScales_ = new ListBox();
   private final TextBox xMin_ = new TextBox(), xMax_ = new TextBox(), yMin_ = new TextBox(), yMax_ = new TextBox();
   private final CheckBox gridMajor_ = new CheckBox(), gridMinor_ = new CheckBox();
   private final HorizontalPanel tabBar_ = new HorizontalPanel();
   private final DeckPanel tabDeck_ = new DeckPanel();
   private final List<Button> tabButtons_ = new ArrayList<>();
   private final InteractivePreview plot_ = new InteractivePreview(new InteractivePreview.Listener()
   {
      @Override public void onSelect(String role)
      {
         editSelected_.setEnabled(!role.isEmpty());
         if (!role.isEmpty())
            status_.setText(messages_.selected(elementName(role)));
      }

      @Override public void onEdit(String role, int pageX, int pageY)
      {
         editElement(role, pageX, pageY);
      }
   });
   private final Timer renderTimer_ = new Timer()
   {
      @Override public void run()
      {
         render();
      }
   };
   private MiniPopupPanel popup_;
   private List<Runnable> popupRefreshers_ = new ArrayList<>();
   private final Map<Widget, String> labels_ = new HashMap<>();
   private final List<String[]> future_ = new ArrayList<>();
   private boolean inFlight_ = false, renderError_ = false;
   private int renderId_ = 0;
   private JSONObject pendingSpec_;
   private final Map<Widget, Object[]> rows_ = new HashMap<>();
   private final List<Setting> settings_ = new ArrayList<>();
   private final List<String[]> history_ = new ArrayList<>();
   private final String[] defaults_;
   private JsArrayString numericColumns_, discreteColumns_, colourColumns_, timeColumns_, datetimeColumns_;
   private String xType_ = "";
   private final ListBox xDateBreaks_ = new ListBox(), xDateLabels_ = new ListBox();
   private final TextBox xTimezone_ = new TextBox();
   private String[] current_;
   private boolean restoring_ = false;
   private String revision_ = "";
   private int requestId_ = 0;
   private static ScatterDialog instance_;
   private static final ScatterMessages messages_ = SuperRStudioLanguage.scatter();
}
