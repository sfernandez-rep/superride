// SPDX-License-Identifier: AGPL-3.0-only
package org.rstudio.studio.client.workbench.views.superrstudio;

import java.util.ArrayList;
import java.util.List;

import com.google.gwt.aria.client.Roles;
import com.google.gwt.core.client.GWT;
import com.google.gwt.core.client.JsArray;
import com.google.gwt.core.client.JsArrayNumber;
import com.google.gwt.core.client.JsArrayString;
import com.google.gwt.event.dom.client.KeyCodes;
import com.google.gwt.event.dom.client.KeyDownEvent;
import com.google.gwt.json.client.JSONBoolean;
import com.google.gwt.json.client.JSONNumber;
import com.google.gwt.json.client.JSONObject;
import com.google.gwt.json.client.JSONString;
import com.google.gwt.json.client.JSONValue;
import com.google.gwt.user.client.Timer;
import com.google.gwt.user.client.ui.*;
import org.rstudio.core.client.ElementIds;
import org.rstudio.core.client.theme.res.ThemeStyles;
import org.rstudio.core.client.widget.FormLabel;
import org.rstudio.core.client.widget.OperationWithInput;
import org.rstudio.core.client.widget.ThemedButton;
import org.rstudio.studio.client.application.events.EventBus;
import org.rstudio.studio.client.server.ServerError;
import org.rstudio.studio.client.server.ServerRequestCallback;
import org.rstudio.studio.client.workbench.views.source.events.NewDocumentWithCodeEvent;
import org.rstudio.studio.client.workbench.views.source.model.SourcePosition;

// Guided length-frequency workflow over TropFishR (SessionSuperRStudioLfq.R):
// data mapping and checks, LFQ creation and restructuring, ELEFAN runs in a
// separate R process, and a comparison of every recorded run. Like the plot
// editor it is a non-modal window; the IDE stays usable while analyses run.
public class LfqDialog extends DialogBox
{
   public static void open(SuperRStudioServerOperations server, EventBus events)
   {
      if (instance_ != null && instance_.isShowing())
      {
         instance_.show();
         return;
      }
      instance_ = new LfqDialog(server, events);
      instance_.show();
      instance_.setPopupPosition(24, 48);
      instance_.datasets_.setFocus(true);
      instance_.start();
   }

   private LfqDialog(SuperRStudioServerOperations server, EventBus events)
   {
      super(false, false);
      setGlassEnabled(false);
      setText(messages_.title());
      addStyleDependentName("ModalDialog");
      Roles.getDialogRole().set(getElement());
      getElement().setAttribute("aria-modal", "false");
      server_ = server;
      events_ = events;
      addDomHandler(e -> {
         if (e.getNativeKeyCode() == KeyCodes.KEY_ESCAPE)
         {
            e.preventDefault();
            hide();
         }
      }, KeyDownEvent.getType());
      setWidget(createMainWidget());
   }

   // Layout -------------------------------------------------------------------

   private Widget createMainWidget()
   {
      VerticalPanel panel = new VerticalPanel();
      panel.setSpacing(4);
      panel.setWidth("760px");
      Label help = new Label(messages_.help());
      panel.add(help);
      status_.getElement().setId("superrstudio_lfq_status");
      status_.getElement().setAttribute("role", "status");
      status_.getElement().setAttribute("aria-live", "polite");
      status_.getElement().getStyle().setProperty("whiteSpace", "pre-line");
      panel.add(status_);

      option(unit_, "cm", "cm");
      option(unit_, "mm", "mm");
      option(unit_, "m", "m");
      option(dateFormat_, messages_.dateFormatNative(), "");
      option(dateFormat_, "YYYY-MM-DD", "%Y-%m-%d");
      option(dateFormat_, "DD/MM/YYYY", "%d/%m/%Y");
      option(dateFormat_, "MM/DD/YYYY", "%m/%d/%Y");
      option(dateFormat_, "DD-MM-YYYY", "%d-%m-%Y");
      option(dateFormat_, "DD.MM.YYYY", "%d.%m.%Y");
      for (String ma : new String[] {"3", "5", "7", "9", "11", "13", "15"})
         option(ma_, ma, ma);
      select(ma_, "5");
      option(method_, messages_.methodGa(), "ga");
      option(method_, messages_.methodSa(), "sa");
      option(method_, messages_.methodElefan(), "elefan");
      option(saStop_, messages_.saIterations(), "iterations");
      option(saStop_, messages_.saTime(), "time");
      binSize_.setValue("1");
      lmin_.setValue("0");
      plusGroup_.setValue("0");
      aggregate_.setText(messages_.aggregate());
      addlSqrt_.setText(messages_.addlSqrt());
      seasonalised_.setText(messages_.seasonalised());

      datasets_.addChangeHandler(e -> columns());
      speciesColumn_.addChangeHandler(e -> { species_.clear(); species_.addItem(messages_.none(), ""); });
      method_.addChangeHandler(e -> methodChanged());
      seasonalised_.addValueChangeHandler(e -> methodChanged());
      saStop_.addChangeHandler(e -> methodChanged());
      runs_.addChangeHandler(e -> showRun());

      // 1. data
      Grid data = new Grid(8, 2);
      row(data, 0, messages_.dataset(), datasets_, "superrstudio_lfq_dataset");
      row(data, 1, messages_.lengthColumn(), length_, "superrstudio_lfq_length");
      row(data, 2, messages_.unit(), unit_, "superrstudio_lfq_unit");
      row(data, 3, messages_.dateColumn(), date_, "superrstudio_lfq_date");
      row(data, 4, messages_.dateFormat(), dateFormat_, "superrstudio_lfq_date_format");
      row(data, 5, messages_.freqColumn(), freq_, "superrstudio_lfq_freq");
      row(data, 6, messages_.speciesColumn(), speciesColumn_, "superrstudio_lfq_species_column");
      row(data, 7, messages_.species(), species_, "superrstudio_lfq_species");
      VerticalPanel dataPage = new VerticalPanel();
      dataPage.setSpacing(4);
      dataPage.add(data);
      dataPage.add(small(messages_.freqHint()));
      dataPage.add(button(check_, "superrstudio_lfq_check"));
      report_.getElement().setId("superrstudio_lfq_report");
      report_.getElement().getStyle().setProperty("whiteSpace", "pre-line");
      dataPage.add(report_);

      // 2. length classes
      Grid classes = new Grid(6, 2);
      row(classes, 0, messages_.binSize(), binSize_, "superrstudio_lfq_bin_size");
      row(classes, 1, messages_.lmin(), lmin_, "superrstudio_lfq_lmin");
      row(classes, 2, "", aggregate_, "superrstudio_lfq_aggregate");
      row(classes, 3, messages_.plusGroup(), plusGroup_, "superrstudio_lfq_plus_group");
      row(classes, 4, messages_.ma(), ma_, "superrstudio_lfq_ma");
      row(classes, 5, "", addlSqrt_, "superrstudio_lfq_addl_sqrt");
      VerticalPanel classesPage = new VerticalPanel();
      classesPage.setSpacing(4);
      classesPage.add(classes);
      classesPage.add(small(messages_.classesHint()));
      classesPage.add(button(create_, "superrstudio_lfq_create"));
      created_.getElement().setId("superrstudio_lfq_created");
      classesPage.add(created_);
      HorizontalPanel images = new HorizontalPanel();
      images.setSpacing(4);
      images.add(imageColumn(messages_.rawHeading(), rawImage_, "superrstudio_lfq_raw_image"));
      images.add(imageColumn(messages_.restructuredHeading(), restructuredImage_, "superrstudio_lfq_restructured_image"));
      classesPage.add(images);

      // 3. growth
      Grid growth = new Grid(0, 4);
      growth.setCellSpacing(2);
      growthRow(growth, messages_.method(), method_, "superrstudio_lfq_method", null, null);
      growthRow(growth, "", seasonalised_, "superrstudio_lfq_seasonalised", null, null);
      growthRow(growth, messages_.range("Linf (cm)"), linfMin_, "superrstudio_lfq_linf_min", linfMax_, "superrstudio_lfq_linf_max");
      growthRow(growth, messages_.range("K (1/year)"), kMin_, "superrstudio_lfq_k_min", kMax_, "superrstudio_lfq_k_max");
      growthRow(growth, messages_.range("t_anchor"), tMin_, "superrstudio_lfq_t_min", tMax_, "superrstudio_lfq_t_max");
      cRow_ = growthRow(growth, messages_.range("C"), cMin_, "superrstudio_lfq_c_min", cMax_, "superrstudio_lfq_c_max");
      tsRow_ = growthRow(growth, messages_.range("ts"), tsMin_, "superrstudio_lfq_ts_min", tsMax_, "superrstudio_lfq_ts_max");
      gaRows_.add(growthRow(growth, messages_.seeds(), seeds_, "superrstudio_lfq_seeds", null, null));
      gaRows_.add(growthRow(growth, messages_.popSize(), popSize_, "superrstudio_lfq_pop_size", null, null));
      gaRows_.add(growthRow(growth, messages_.maxIter(), maxIter_, "superrstudio_lfq_max_iter", null, null));
      gaRows_.add(growthRow(growth, messages_.run(), run_, "superrstudio_lfq_run", null, null));
      gaRows_.add(growthRow(growth, messages_.pmutation(), pmutation_, "superrstudio_lfq_pmutation", null, null));
      gaRows_.add(growthRow(growth, messages_.pcrossover(), pcrossover_, "superrstudio_lfq_pcrossover", null, null));
      gaRows_.add(growthRow(growth, messages_.elitism(), elitism_, "superrstudio_lfq_elitism", null, null));
      saRows_.add(growthRow(growth, messages_.saStop(), saStop_, "superrstudio_lfq_sa_stop", null, null));
      saRows_.add(growthRow(growth, messages_.saMaxit(), saMaxit_, "superrstudio_lfq_sa_maxit", saTime_, "superrstudio_lfq_sa_time"));
      saRows_.add(growthRow(growth, messages_.linfInit(), linfInit_, "superrstudio_lfq_linf_init", null, null));
      saRows_.add(growthRow(growth, messages_.kInit(), kInit_, "superrstudio_lfq_k_init", tInit_, "superrstudio_lfq_t_init"));
      elefanRows_.add(growthRow(growth, messages_.linfSteps(), linfSteps_, "superrstudio_lfq_linf_steps", null, null));
      elefanRows_.add(growthRow(growth, messages_.kSteps(), kSteps_, "superrstudio_lfq_k_steps", null, null));
      growthRow(growth, messages_.label(), label_, "superrstudio_lfq_label", null, null);
      kMin_.setValue("0.05"); kMax_.setValue("1"); tMin_.setValue("0"); tMax_.setValue("1");
      cMin_.setValue("0"); cMax_.setValue("1"); tsMin_.setValue("0"); tsMax_.setValue("1");
      seeds_.setValue("1-5"); popSize_.setValue("50"); maxIter_.setValue("100"); run_.setValue("100");
      pmutation_.setValue("0.1"); pcrossover_.setValue("0.8"); elitism_.setValue("3");
      saMaxit_.setValue("300"); saTime_.setValue("60"); kInit_.setValue("0.3"); tInit_.setValue("0.5");
      linfSteps_.setValue("20"); kSteps_.setValue("30");
      VerticalPanel growthPage = new VerticalPanel();
      growthPage.setSpacing(4);
      methodHint_.setWidth("740px");
      methodHint_.getElement().getStyle().setProperty("fontSize", "90%");
      growthPage.add(methodHint_);
      growthPage.add(growth);
      HorizontalPanel run = new HorizontalPanel();
      run.setSpacing(4);
      run.add(button(start_, "superrstudio_lfq_start"));
      run.add(button(cancel_, "superrstudio_lfq_cancel"));
      progress_.getElement().setId("superrstudio_lfq_progress");
      progress_.getElement().setAttribute("role", "status");
      progress_.getElement().setAttribute("aria-live", "polite");
      run.add(progress_);
      growthPage.add(run);
      cancel_.setEnabled(false);

      // 4. compare
      VerticalPanel comparePage = new VerticalPanel();
      comparePage.setSpacing(4);
      comparePage.add(heading(messages_.runsHeading()));
      table_.getElement().setId("superrstudio_lfq_runs");
      table_.setCellSpacing(0);
      table_.setCellPadding(3);
      table_.setBorderWidth(1);
      ScrollPanel tableScroll = new ScrollPanel(table_);
      tableScroll.setSize("760px", "180px");
      comparePage.add(tableScroll);
      comparePage.add(heading(messages_.groupsHeading()));
      groups_.getElement().setId("superrstudio_lfq_groups");
      groups_.getElement().getStyle().setProperty("whiteSpace", "pre-line");
      comparePage.add(groups_);
      notes_.getElement().getStyle().setProperty("whiteSpace", "pre-line");
      notes_.getElement().getStyle().setProperty("fontSize", "90%");
      comparePage.add(notes_);
      HorizontalPanel selection = new HorizontalPanel();
      selection.setSpacing(4);
      selection.setVerticalAlignment(HasVerticalAlignment.ALIGN_MIDDLE);
      runs_.getElement().setId("superrstudio_lfq_run_select");
      selection.add(new FormLabel(messages_.selectRun(), runs_));
      selection.add(runs_);
      selection.add(button(showFit_, "superrstudio_lfq_show_fit"));
      selection.add(button(openCode_, "superrstudio_lfq_open_code"));
      selection.add(button(clear_, "superrstudio_lfq_clear"));
      comparePage.add(selection);
      fitImage_.getElement().setId("superrstudio_lfq_fit_image");
      fitImage_.getElement().setAttribute("alt", "");
      fitImage_.setPixelSize(528, 346);
      fitImage_.setVisible(false);
      comparePage.add(fitImage_);

      addTab(messages_.tabData(), "data", dataPage);
      addTab(messages_.tabClasses(), "classes", classesPage);
      addTab(messages_.tabGrowth(), "growth", growthPage);
      addTab(messages_.tabCompare(), "compare", comparePage);
      tabBar_.getElement().setAttribute("role", "tablist");
      tabBar_.getElement().setAttribute("aria-label", messages_.steps());
      panel.add(tabBar_);
      ScrollPanel deck = new ScrollPanel(tabDeck_);
      deck.setSize("770px", "520px");
      panel.add(deck);
      showTab(0);

      code_.setReadOnly(true);
      code_.setVisibleLines(4);
      code_.setWidth("750px");
      code_.getElement().setId("superrstudio_lfq_code");
      panel.add(code_);

      HorizontalPanel buttons = new HorizontalPanel();
      buttons.setStyleName(ThemeStyles.INSTANCE.dialogBottomPanel());
      buttons.setWidth("100%");
      HorizontalPanel right = new HorizontalPanel();
      right.add(button(close_, "superrstudio_lfq_close"));
      buttons.add(right);
      buttons.setCellHorizontalAlignment(right, HasHorizontalAlignment.ALIGN_RIGHT);
      panel.add(buttons);
      methodChanged();
      enableSteps();
      return panel;
   }

   private static Label small(String text)
   {
      Label label = new Label(text);
      label.setWidth("740px");
      label.getElement().getStyle().setProperty("fontSize", "90%");
      return label;
   }

   private Label heading(String text)
   {
      Label label = new Label(text);
      label.getElement().getStyle().setProperty("fontWeight", "bold");
      Roles.getHeadingRole().set(label.getElement());
      Roles.getHeadingRole().setAriaLevelProperty(label.getElement(), 3);
      return label;
   }

   private VerticalPanel imageColumn(String title, Image image, String id)
   {
      VerticalPanel column = new VerticalPanel();
      column.add(heading(title));
      image.getElement().setId(id);
      image.getElement().setAttribute("alt", title);
      image.setPixelSize(368, 241);
      image.setVisible(false);
      column.add(image);
      return column;
   }

   private static ThemedButton button(ThemedButton button, String id)
   {
      ElementIds.assignElementId(button, id);
      return button;
   }

   private void row(Grid grid, int row, String text, Widget control, String id)
   {
      control.getElement().setId(id);
      control.setWidth("220px");
      if (!text.isEmpty())
      {
         FormLabel label = new FormLabel(text, control);
         label.setWidth("230px");
         grid.setWidget(row, 0, label);
      }
      grid.setWidget(row, 1, control);
   }

   private int growthRow(Grid grid, String text, Widget control, String id, Widget second, String secondId)
   {
      int row = grid.insertRow(grid.getRowCount());
      control.getElement().setId(id);
      control.setWidth(second == null ? "260px" : "100px");
      if (!text.isEmpty())
      {
         FormLabel label = new FormLabel(text, control);
         label.setWidth("280px");
         grid.setWidget(row, 0, label);
      }
      grid.setWidget(row, 1, control);
      if (second != null)
      {
         second.getElement().setId(secondId);
         second.setWidth("100px");
         grid.setWidget(row, 2, new FormLabel(messages_.to(), second));
         grid.setWidget(row, 3, second);
      }
      growthGrid_ = grid;
      return row;
   }

   private void addTab(String label, String name, Widget page)
   {
      int index = tabButtons_.size();
      Button tab = new Button(label);
      tab.getElement().setId("superrstudio_lfq_tab_" + name);
      tab.getElement().setAttribute("role", "tab");
      tab.getElement().setAttribute("aria-controls", "superrstudio_lfq_tabpanel_" + name);
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
      page.getElement().setId("superrstudio_lfq_tabpanel_" + name);
      page.getElement().setAttribute("role", "tabpanel");
      page.getElement().setAttribute("aria-labelledby", "superrstudio_lfq_tab_" + name);
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

   private void methodChanged()
   {
      String method = method_.getSelectedValue();
      boolean ga = "ga".equals(method), sa = "sa".equals(method), elefan = "elefan".equals(method);
      for (int row : gaRows_) growthGrid_.getRowFormatter().setVisible(row, ga);
      for (int row : saRows_) growthGrid_.getRowFormatter().setVisible(row, sa);
      for (int row : elefanRows_) growthGrid_.getRowFormatter().setVisible(row, elefan);
      seasonalised_.setEnabled(!elefan);
      boolean seasonal = seasonalised_.getValue() && !elefan;
      growthGrid_.getRowFormatter().setVisible(cRow_, seasonal);
      growthGrid_.getRowFormatter().setVisible(tsRow_, seasonal);
      boolean byTime = "time".equals(saStop_.getSelectedValue());
      saMaxit_.setEnabled(!byTime);
      saTime_.setEnabled(byTime);
      methodHint_.setText(ga ? messages_.methodHintGa() : sa ? messages_.methodHintSa() : messages_.methodHintElefan());
   }

   private void enableSteps()
   {
      boolean ready = datasets_.getItemCount() > 0 && length_.getItemCount() > 0 && date_.getItemCount() > 0;
      check_.setEnabled(!busy_ && ready);
      create_.setEnabled(!busy_ && ready && installed_);
      start_.setEnabled(!busy_ && createdOk_ && installed_ && job_.isEmpty());
      cancel_.setEnabled(!job_.isEmpty());
      boolean runs = runs_.getItemCount() > 0;
      showFit_.setEnabled(!busy_ && runs);
      openCode_.setEnabled(runs);
      clear_.setEnabled(!busy_ && runs && job_.isEmpty());
   }

   // Requests -------------------------------------------------------------------

   private void start()
   {
      request("lfq_status", "", null, result -> {
         installed_ = result.flag("tropfishr");
         version_ = installed_ ? messages_.packageVersion(result.str("version"), result.str("r_version")) : "";
         status_.setText(installed_ ? version_ : messages_.missingPackage());
         request("lfq_list", "", null, list -> {
            JsArrayString names = list.strings("datasets");
            datasets_.clear();
            for (int i = 0; i < names.length(); i++)
               datasets_.addItem(names.get(i));
            if (names.length() > 0)
               columns();
            refreshRuns();
         });
      });
   }

   private void columns()
   {
      request("lfq_columns", value(datasets_), null, result -> {
         fill(length_, result.strings("numeric"), false);
         fill(date_, result.strings("dates"), false);
         fill(freq_, result.strings("numeric"), true);
         fill(speciesColumn_, result.strings("categories"), true);
         species_.clear();
         species_.addItem(messages_.none(), "");
         createdOk_ = false;
         enableSteps();
      });
   }

   private void check()
   {
      request("lfq_check", value(datasets_), settings(), result -> {
         showReport(result);
         // offer the species found, most frequent first
         String chosen = value(species_);
         species_.clear();
         species_.addItem(messages_.none(), "");
         JsArray<LfqResult> species = result.list("species");
         for (int i = 0; i < species.length(); i++)
            species_.addItem(species.get(i).str("species") + " (" + species.get(i).str("rows") + ")",
                             species.get(i).str("species"));
         select(species_, chosen);
      });
   }

   private void showReport(LfqResult report)
   {
      StringBuilder text = new StringBuilder();
      text.append(messages_.checkSummary(report.str("rows"), report.str("kept"),
         report.str("individuals"), report.str("first_date"), report.str("last_date"),
         ScatterResult.format(report.num("length_min")), ScatterResult.format(report.num("length_max")), "cm"));
      JsArray<LfqResult> steps = report.list("steps");
      for (int i = 0; i < steps.length(); i++)
         if (steps.get(i).num("removed") > 0)
            text.append("\n").append(messages_.removedRule(steps.get(i).str("removed"), steps.get(i).str("rule")));
      JsArrayString dates = report.strings("dates");
      JsArrayNumber counts = report.numbers("date_counts");
      text.append("\n").append(messages_.perDate());
      for (int i = 0; i < dates.length(); i++)
         text.append(i % 4 == 0 ? "\n" : ";   ").append(dates.get(i)).append(": ")
             .append(String.valueOf((long) counts.get(i)));
      if (dates.length() < 2)
         text.append("\n").append(messages_.fewDates());
      report_.setText(text.toString());
      code_.setText(report.str("code"));
   }

   private void create()
   {
      request("lfq_create", value(datasets_), settings(), result -> {
         createdOk_ = true;
         showReport(result.obj("report"));
         created_.setText(messages_.created(result.str("dates"), result.str("classes"),
            result.str("total"), ScatterResult.format(result.num("asp")), result.str("ma")) +
            (result.strings("warnings").length() > 0 ? "\n" + result.strings("warnings").join("\n") : ""));
         rawImage_.setUrl("data:image/png;base64," + result.str("raw_image"));
         restructuredImage_.setUrl("data:image/png;base64," + result.str("restructured_image"));
         rawImage_.setVisible(true);
         restructuredImage_.setVisible(true);
         code_.setText(result.str("code"));
         // TropFishR derives its default Linf search range from the data; show it
         if (linfMin_.getValue().trim().isEmpty()) linfMin_.setValue(result.str("linf_suggest_min"));
         if (linfMax_.getValue().trim().isEmpty()) linfMax_.setValue(result.str("linf_suggest_max"));
         enableSteps();
      });
   }

   private void startAnalysis()
   {
      request("lfq_start", value(datasets_), settings(), result -> {
         job_ = result.str("job");
         progress_.setText(messages_.running("…", "0"));
         enableSteps();
         poll_.scheduleRepeating(1000);
      });
   }

   private void poll()
   {
      if (job_.isEmpty() || polling_)
         return;
      polling_ = true;
      JSONObject json = new JSONObject();
      json.put("job", new JSONString(job_));
      server_.superrstudioData("lfq_poll", "", "", "", "", json, new ServerRequestCallback<ScatterResult>()
      {
         @Override public void onResponseReceived(ScatterResult response)
         {
            polling_ = false;
            if (!isAttached()) return;
            LfqResult result = response.cast();
            String status = result.str("status");
            if ("running".equals(status))
            {
               progress_.setText(messages_.running(result.str("progress"), result.str("elapsed")));
               return;
            }
            finishJob();
            if ("done".equals(status))
            {
               progress_.setText(messages_.done());
               showRuns(result);
               showTab(3);
            }
            else if ("failed".equals(status))
               progress_.setText(messages_.failed(result.str("message")));
            else
               progress_.setText(messages_.cancelled());
         }

         @Override public void onError(ServerError error)
         {
            polling_ = false;
            finishJob();
            progress_.setText(message(error));
         }
      });
   }

   private void finishJob()
   {
      poll_.cancel();
      job_ = "";
      enableSteps();
   }

   private void cancelAnalysis()
   {
      JSONObject json = new JSONObject();
      json.put("job", new JSONString(job_));
      request("lfq_cancel", "", json, result -> {
         finishJob();
         progress_.setText(messages_.cancelled());
      });
   }

   private void refreshRuns()
   {
      request("lfq_runs", "", null, this::showRuns);
   }

   private void showRuns(LfqResult result)
   {
      runsData_ = result.list("runs");
      String[] headers = {"#", "Label", "Method", "Seed", "Species", "Dates", "Class (cm)", "MA",
                          "Linf", "K", "t_anchor", "C", "ts", "phiL", "Score", "s", "Notes"};
      table_.resize(runsData_.length() + 1, headers.length);
      for (int c = 0; c < headers.length; c++)
      {
         table_.setText(0, c, headers[c]);
         table_.getCellFormatter().getElement(0, c).getStyle().setProperty("fontWeight", "bold");
      }
      String selected = value(runs_);
      runs_.clear();
      for (int i = 0; i < runsData_.length(); i++)
      {
         LfqResult run = runsData_.get(i);
         String[] cells = {run.str("id").replace("run", ""), run.str("label"), run.str("method"),
            run.has("seed") ? run.str("seed") : "", run.str("species"),
            run.str("first_date") + " – " + run.str("last_date"), run.str("bin_size"), run.str("ma"),
            number(run, "linf"), number(run, "k"), number(run, "t_anchor"), number(run, "c"), number(run, "ts"),
            number(run, "phil"), number(run, "score"), run.str("seconds"),
            run.str("error").isEmpty() ? run.strings("warnings").join("; ") : run.str("error")};
         for (int c = 0; c < cells.length; c++)
            table_.setText(i + 1, c, cells[c]);
         runs_.addItem(run.str("id").replace("run", "#") + " " + run.str("method") +
                       (run.has("seed") ? " seed " + run.str("seed") : "") +
                       (run.str("label").isEmpty() ? "" : " (" + run.str("label") + ")"), run.str("id"));
      }
      select(runs_, selected);
      StringBuilder groups = new StringBuilder();
      JsArray<LfqResult> list = result.list("groups");
      for (int i = 0; i < list.length(); i++)
      {
         LfqResult group = list.get(i);
         LfqResult linf = group.obj("linf"), k = group.obj("k");
         if (!linf.has("mean"))
            continue;
         groups.append(messages_.group(group.str("method"), group.str("runs"),
            number(linf, "mean"), number(linf, "sd"), number(linf, "min"), number(linf, "max"),
            number(k, "mean"), number(k, "sd"), number(k, "min"), number(k, "max"))).append("\n");
      }
      groups_.setText(runsData_.length() == 0 ? messages_.noRuns() : groups.toString());
      String notes = result.strings("notes").join("\n");
      notes_.setText((notes.isEmpty() ? "" : notes + "\n") + messages_.comparisonCaveat());
      enableSteps();
   }

   private static String number(LfqResult object, String key)
   {
      return object.has(key) && !Double.isNaN(object.num(key)) ? ScatterResult.format(object.num(key)) : "";
   }

   private LfqResult selectedRun()
   {
      String id = value(runs_);
      for (int i = 0; runsData_ != null && i < runsData_.length(); i++)
         if (runsData_.get(i).str("id").equals(id))
            return runsData_.get(i);
      return null;
   }

   private void showRun()
   {
      fitImage_.setVisible(false);
      LfqResult run = selectedRun();
      if (run != null)
         code_.setText(run.str("code"));
   }

   private void showFit()
   {
      JSONObject json = new JSONObject();
      json.put("run_id", new JSONString(value(runs_)));
      request("lfq_run_plot", "", json, result -> {
         fitImage_.setUrl("data:image/png;base64," + result.str("image"));
         fitImage_.setVisible(true);
         showRun();
         fitImage_.setVisible(true);
      });
   }

   private void openCode()
   {
      LfqResult run = selectedRun();
      if (run != null)
         events_.fireEvent(new NewDocumentWithCodeEvent(NewDocumentWithCodeEvent.R_SCRIPT, run.str("code"),
                                                        SourcePosition.create(1, 1), false));
   }

   private void clearRuns()
   {
      request("lfq_clear", "", null, result -> {
         fitImage_.setVisible(false);
         showRuns(result);
      });
   }

   private JSONObject settings()
   {
      JSONObject json = new JSONObject();
      text(json, "length", value(length_));
      text(json, "date", value(date_));
      text(json, "date_format", value(dateFormat_));
      text(json, "freq", value(freq_));
      text(json, "species_column", value(speciesColumn_));
      text(json, "species", value(species_));
      text(json, "unit", value(unit_));
      numberSetting(json, "bin_size", binSize_);
      numberSetting(json, "lmin", lmin_);
      json.put("aggregate_dates", JSONBoolean.getInstance(aggregate_.getValue()));
      numberSetting(json, "plus_group", plusGroup_);
      json.put("ma", new JSONNumber(Double.parseDouble(value(ma_))));
      json.put("addl_sqrt", JSONBoolean.getInstance(addlSqrt_.getValue()));
      text(json, "method", value(method_));
      json.put("seasonalised", JSONBoolean.getInstance(seasonalised_.getValue()));
      for (Object[] entry : new Object[][] {{"linf_min", linfMin_}, {"linf_max", linfMax_}, {"k_min", kMin_},
            {"k_max", kMax_}, {"t_min", tMin_}, {"t_max", tMax_}, {"c_min", cMin_}, {"c_max", cMax_},
            {"ts_min", tsMin_}, {"ts_max", tsMax_}, {"pop_size", popSize_}, {"max_iter", maxIter_},
            {"run", run_}, {"pmutation", pmutation_}, {"pcrossover", pcrossover_}, {"elitism", elitism_},
            {"sa_maxit", saMaxit_}, {"sa_time", saTime_}, {"linf_init", linfInit_}, {"k_init", kInit_},
            {"t_init", tInit_}, {"linf_steps", linfSteps_}, {"k_steps", kSteps_}})
         numberSetting(json, (String) entry[0], (TextBox) entry[1]);
      text(json, "seeds", seeds_.getValue());
      text(json, "sa_stop", value(saStop_));
      text(json, "label", label_.getValue().trim());
      return json;
   }

   private static void text(JSONObject json, String key, String value)
   {
      json.put(key, new JSONString(value == null ? "" : value));
   }

   // numbers are sent as numbers; anything else as text for the session to reject
   private static void numberSetting(JSONObject json, String key, TextBox box)
   {
      String value = box.getValue().trim();
      try
      {
         json.put(key, value.isEmpty() ? new JSONString("") : new JSONNumber(Double.parseDouble(value)));
      }
      catch (NumberFormatException e)
      {
         json.put(key, new JSONString(value));
      }
   }

   private void request(String operation, String dataset, JSONObject json, OperationWithInput<LfqResult> done)
   {
      busy_ = true;
      enableSteps();
      status_.setText(messages_.working());
      server_.superrstudioData(operation, dataset, "", "", "", json, new ServerRequestCallback<ScatterResult>()
      {
         @Override public void onResponseReceived(ScatterResult response)
         {
            if (!isAttached()) return;
            busy_ = false;
            status_.setText(installed_ ? version_ : messages_.missingPackage());
            done.execute(response.cast());
            enableSteps();
         }

         @Override public void onError(ServerError error)
         {
            if (!isAttached()) return;
            busy_ = false;
            status_.setText(message(error));
            enableSteps();
         }
      });
   }

   private static String message(ServerError error)
   {
      JSONValue info = error.getClientInfo();
      return info != null && info.isString() != null ? info.isString().stringValue() : error.getUserMessage();
   }

   private static void option(ListBox list, String label, String value)
   {
      list.addItem(label, value);
   }

   private static void select(ListBox list, String value)
   {
      for (int i = 0; i < list.getItemCount(); i++)
         if (list.getValue(i).equals(value))
            list.setSelectedIndex(i);
   }

   private static String value(ListBox list)
   {
      return list.getItemCount() > 0 && list.getSelectedValue() != null ? list.getSelectedValue() : "";
   }

   private void fill(ListBox list, JsArrayString values, boolean optional)
   {
      String previous = value(list);
      list.clear();
      if (optional)
         list.addItem(messages_.none(), "");
      for (int i = 0; i < values.length(); i++)
         list.addItem(values.get(i));
      select(list, previous);
   }

   @Override protected void onUnload()
   {
      poll_.cancel();
      // a running analysis is cancelled with its window
      if (!job_.isEmpty())
      {
         JSONObject json = new JSONObject();
         json.put("job", new JSONString(job_));
         server_.superrstudioData("lfq_cancel", "", "", "", "", json, new ServerRequestCallback<ScatterResult>()
         {
            @Override public void onResponseReceived(ScatterResult result) {}
            @Override public void onError(ServerError error) {}
         });
         job_ = "";
      }
      super.onUnload();
   }

   private final SuperRStudioServerOperations server_;
   private final EventBus events_;
   private final Label status_ = new Label(), report_ = new Label(), created_ = new Label(),
                       methodHint_ = new Label(), progress_ = new Label(), groups_ = new Label(), notes_ = new Label();
   private final ListBox datasets_ = new ListBox(), length_ = new ListBox(), unit_ = new ListBox(),
                         date_ = new ListBox(), dateFormat_ = new ListBox(), freq_ = new ListBox(),
                         speciesColumn_ = new ListBox(), species_ = new ListBox(), ma_ = new ListBox(),
                         method_ = new ListBox(), saStop_ = new ListBox(), runs_ = new ListBox();
   private final TextBox binSize_ = new TextBox(), lmin_ = new TextBox(), plusGroup_ = new TextBox(),
                         linfMin_ = new TextBox(), linfMax_ = new TextBox(), kMin_ = new TextBox(),
                         kMax_ = new TextBox(), tMin_ = new TextBox(), tMax_ = new TextBox(),
                         cMin_ = new TextBox(), cMax_ = new TextBox(), tsMin_ = new TextBox(), tsMax_ = new TextBox(),
                         seeds_ = new TextBox(), popSize_ = new TextBox(), maxIter_ = new TextBox(),
                         run_ = new TextBox(), pmutation_ = new TextBox(), pcrossover_ = new TextBox(),
                         elitism_ = new TextBox(), saMaxit_ = new TextBox(), saTime_ = new TextBox(),
                         linfInit_ = new TextBox(), kInit_ = new TextBox(), tInit_ = new TextBox(),
                         linfSteps_ = new TextBox(), kSteps_ = new TextBox(), label_ = new TextBox();
   private final CheckBox aggregate_ = new CheckBox(), addlSqrt_ = new CheckBox(), seasonalised_ = new CheckBox();
   private final ThemedButton check_ = new ThemedButton(messages_.check(), e -> check()),
      create_ = new ThemedButton(messages_.create(), e -> create()),
      start_ = new ThemedButton(messages_.start(), e -> startAnalysis()),
      cancel_ = new ThemedButton(messages_.cancel(), e -> cancelAnalysis()),
      showFit_ = new ThemedButton(messages_.showFit(), e -> showFit()),
      openCode_ = new ThemedButton(messages_.openCode(), e -> openCode()),
      clear_ = new ThemedButton(messages_.clearRuns(), e -> clearRuns()),
      close_ = new ThemedButton(messages_.close(), e -> hide());
   private final Image rawImage_ = new Image(), restructuredImage_ = new Image(), fitImage_ = new Image();
   private final Grid table_ = new Grid(1, 1);
   private final TextArea code_ = new TextArea();
   private final HorizontalPanel tabBar_ = new HorizontalPanel();
   private final DeckPanel tabDeck_ = new DeckPanel();
   private final List<Button> tabButtons_ = new ArrayList<>();
   private final List<Integer> gaRows_ = new ArrayList<>(), saRows_ = new ArrayList<>(), elefanRows_ = new ArrayList<>();
   private Grid growthGrid_;
   private int cRow_, tsRow_;
   private JsArray<LfqResult> runsData_;
   private final Timer poll_ = new Timer()
   {
      @Override public void run()
      {
         poll();
      }
   };
   private String job_ = "", version_ = "";
   private boolean busy_ = false, installed_ = false, createdOk_ = false, polling_ = false;
   private static LfqDialog instance_;
   private static final LfqMessages messages_ = GWT.create(LfqMessages.class);
}
