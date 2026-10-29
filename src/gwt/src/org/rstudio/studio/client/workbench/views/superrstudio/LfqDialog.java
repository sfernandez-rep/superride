// SPDX-License-Identifier: AGPL-3.0-only
package org.rstudio.studio.client.workbench.views.superrstudio;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

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
import org.rstudio.core.client.files.FileSystemItem;
import org.rstudio.core.client.theme.res.ThemeStyles;
import org.rstudio.core.client.widget.FormLabel;
import org.rstudio.core.client.widget.OperationWithInput;
import org.rstudio.core.client.widget.ProgressIndicator;
import org.rstudio.core.client.widget.ProgressOperationWithInput;
import org.rstudio.core.client.widget.ThemedButton;
import org.rstudio.studio.client.RStudioGinjector;
import org.rstudio.studio.client.application.events.EventBus;
import org.rstudio.studio.client.server.ServerError;
import org.rstudio.studio.client.server.ServerRequestCallback;
import org.rstudio.studio.client.workbench.views.source.events.NewDocumentWithCodeEvent;
import org.rstudio.studio.client.workbench.views.source.model.SourcePosition;

// Guided length-frequency workflow over TropFishR (SessionSuperRStudioLfq*.R):
// data mapping and checks, LFQ creation and restructuring, ELEFAN runs in a
// separate R process, a comparison of every recorded run, catch-curve
// mortality and saved analyses. Like the plot editor it is a non-modal
// window; the IDE stays usable while analyses run.
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
      SuperRStudioTheme.dialog(this);
      addDomHandler(e -> {
         if (e.getNativeKeyCode() == KeyCodes.KEY_ESCAPE)
         {
            e.preventDefault();
            hide();
         }
      }, KeyDownEvent.getType());
      register();
      setWidget(createMainWidget());
   }

   // Every setting sent to (and restored from) the session, by its key
   private void register()
   {
      Object[][] lists = {{"length", length_}, {"date", date_}, {"date_format", dateFormat_}, {"freq", freq_},
         {"species_column", speciesColumn_}, {"species", species_}, {"unit", unit_}, {"aggregate", aggregate_},
         {"ma", ma_}, {"method", method_}, {"sa_stop", saStop_}, {"cc_year", ccYear_}, {"cc_plus", ccPlus_},
         {"cc_method", ccMethod_}, {"m_method", mMethod_}};
      for (Object[] entry : lists)
         lists_.put((String) entry[0], (ListBox) entry[1]);
      Object[][] texts = {{"period_start", periodStart_}, {"period_end", periodEnd_}, {"bin_size", binSize_},
         {"lmin", lmin_}, {"plus_group", plusGroup_}, {"linf_min", linfMin_}, {"linf_max", linfMax_},
         {"k_min", kMin_}, {"k_max", kMax_}, {"t_min", tMin_}, {"t_max", tMax_}, {"c_min", cMin_},
         {"c_max", cMax_}, {"ts_min", tsMin_}, {"ts_max", tsMax_}, {"seeds", seeds_}, {"pop_size", popSize_},
         {"max_iter", maxIter_}, {"run", run_}, {"pmutation", pmutation_}, {"pcrossover", pcrossover_},
         {"elitism", elitism_}, {"sa_maxit", saMaxit_}, {"sa_time", saTime_}, {"linf_init", linfInit_},
         {"k_init", kInit_}, {"t_init", tInit_}, {"linf_steps", linfSteps_}, {"k_steps", kSteps_},
         {"label", label_}, {"cc_linf", ccLinf_}, {"cc_k", ccK_}, {"cc_c", ccC_}, {"cc_ts", ccTs_},
         {"cc_plus_value", ccPlusValue_}, {"cc_first", ccFirst_}, {"cc_last", ccLast_}, {"m_temp", mTemp_},
         {"m_tmax", mTmax_}, {"m_value", mValue_}};
      for (Object[] entry : texts)
         texts_.put((String) entry[0], (TextBox) entry[1]);
      Object[][] checks = {{"addl_sqrt", addlSqrt_}, {"seasonalised", seasonalised_}, {"cc_ogive", ccOgive_},
         {"m_schooling", mSchooling_}};
      for (Object[] entry : checks)
         checks_.put((String) entry[0], (CheckBox) entry[1]);
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
      status_.addStyleName(SuperRStudioTheme.STATUS);
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
      option(aggregate_, messages_.aggregateNone(), "none");
      option(aggregate_, messages_.aggregateMonth(), "month");
      option(aggregate_, messages_.aggregateQuarter(), "quarter");
      for (String ma : new String[] {"3", "5", "7", "9", "11", "13", "15"})
         option(ma_, ma, ma);
      select(ma_, "5");
      option(method_, messages_.methodGa(), "ga");
      option(method_, messages_.methodSa(), "sa");
      option(method_, messages_.methodElefan(), "elefan");
      option(saStop_, messages_.saIterations(), "iterations");
      option(saStop_, messages_.saTime(), "time");
      option(ccYear_, messages_.allDates(), "");
      option(ccPlus_, messages_.plusLinf(), "linf");
      option(ccPlus_, messages_.plusNone(), "none");
      option(ccPlus_, messages_.plusValue(), "value");
      option(ccMethod_, messages_.ccPauly(), "pauly");
      option(ccMethod_, messages_.ccCumulative(), "cumulative");
      option(mMethod_, messages_.mNone(), "none");
      option(mMethod_, messages_.mThenGrowth(), "then_growth");
      option(mMethod_, messages_.mPauly(), "pauly_linf");
      option(mMethod_, messages_.mThenTmax(), "then_tmax");
      option(mMethod_, messages_.mManual(), "manual");
      option(saveSource_, messages_.sourceCurrent(), "");
      binSize_.setValue("1");
      lmin_.setValue("0");
      plusGroup_.setValue("0");
      addlSqrt_.setText(messages_.addlSqrt());
      seasonalised_.setText(messages_.seasonalised());
      ccOgive_.setText(messages_.ccOgive());
      mSchooling_.setText(messages_.mSchooling());
      periodStart_.getElement().setAttribute("placeholder", "YYYY-MM-DD");
      periodEnd_.getElement().setAttribute("placeholder", "YYYY-MM-DD");

      datasets_.addChangeHandler(e -> columns(null));
      speciesColumn_.addChangeHandler(e -> { species_.clear(); species_.addItem(messages_.none(), ""); });
      method_.addChangeHandler(e -> methodChanged());
      seasonalised_.addValueChangeHandler(e -> methodChanged());
      saStop_.addChangeHandler(e -> methodChanged());
      runs_.addChangeHandler(e -> showRun());
      ccPlus_.addChangeHandler(e -> mortalityChanged());
      ccMethod_.addChangeHandler(e -> mortalityChanged());
      mMethod_.addChangeHandler(e -> mortalityChanged());
      analyses_.addChangeHandler(e -> enableSteps());

      // 1. data
      Grid data = new Grid(10, 2);
      row(data, 0, messages_.dataset(), datasets_, "superrstudio_lfq_dataset");
      row(data, 1, messages_.lengthColumn(), length_, "superrstudio_lfq_length");
      row(data, 2, messages_.unit(), unit_, "superrstudio_lfq_unit");
      row(data, 3, messages_.dateColumn(), date_, "superrstudio_lfq_date");
      row(data, 4, messages_.dateFormat(), dateFormat_, "superrstudio_lfq_date_format");
      row(data, 5, messages_.freqColumn(), freq_, "superrstudio_lfq_freq");
      row(data, 6, messages_.speciesColumn(), speciesColumn_, "superrstudio_lfq_species_column");
      row(data, 7, messages_.species(), species_, "superrstudio_lfq_species");
      row(data, 8, messages_.periodStart(), periodStart_, "superrstudio_lfq_period_start");
      row(data, 9, messages_.periodEnd(), periodEnd_, "superrstudio_lfq_period_end");
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
      row(classes, 2, messages_.aggregate(), aggregate_, "superrstudio_lfq_aggregate");
      row(classes, 3, messages_.plusGroup(), plusGroup_, "superrstudio_lfq_plus_group");
      row(classes, 4, messages_.ma(), ma_, "superrstudio_lfq_ma");
      row(classes, 5, "", addlSqrt_, "superrstudio_lfq_addl_sqrt");
      VerticalPanel classesPage = new VerticalPanel();
      classesPage.setSpacing(4);
      classesPage.add(classes);
      classesPage.add(small(messages_.classesHint()));
      classesPage.add(small(messages_.aggregateHint()));
      classesPage.add(button(create_, "superrstudio_lfq_create"));
      created_.getElement().setId("superrstudio_lfq_created");
      created_.getElement().getStyle().setProperty("whiteSpace", "pre-line");
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
      growthGrid_ = growth;
      kMin_.setValue("0.05"); kMax_.setValue("1"); tMin_.setValue("0"); tMax_.setValue("1");
      cMin_.setValue("0"); cMax_.setValue("1"); tsMin_.setValue("0"); tsMax_.setValue("1");
      seeds_.setValue("1-5"); popSize_.setValue("50"); maxIter_.setValue("100"); run_.setValue("100");
      pmutation_.setValue("0.1"); pcrossover_.setValue("0.8"); elitism_.setValue("3");
      saMaxit_.setValue("300"); saTime_.setValue("60"); kInit_.setValue("0.3"); tInit_.setValue("0.5");
      linfSteps_.setValue("20"); kSteps_.setValue("30");
      VerticalPanel growthPage = new VerticalPanel();
      growthPage.setSpacing(4);
      methodHint_.setWidth("740px");
      SuperRStudioTheme.hint(methodHint_);
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
      varies_.getElement().setId("superrstudio_lfq_varies");
      varies_.getElement().getStyle().setProperty("fontWeight", "bold");
      comparePage.add(varies_);
      comparePage.add(heading(messages_.groupsHeading()));
      groups_.getElement().setId("superrstudio_lfq_groups");
      groups_.getElement().getStyle().setProperty("whiteSpace", "pre-line");
      comparePage.add(groups_);
      notes_.getElement().getStyle().setProperty("whiteSpace", "pre-line");
      SuperRStudioTheme.hint(notes_);
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
      addTab(messages_.tabMortality(), "mortality", createMortalityPage());
      addTab(messages_.tabSaved(), "saved", createSavedPage());
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
      mortalityChanged();
      enableSteps();
      return panel;
   }

   // 5. mortality: catch curve, natural mortality, diagnostics
   private Widget createMortalityPage()
   {
      VerticalPanel page = new VerticalPanel();
      page.setSpacing(4);
      page.add(small(messages_.mortalityHelp()));
      Grid grid = new Grid(0, 4);
      grid.setCellSpacing(2);
      int row = growthRow(grid, messages_.growthFrom(), ccRun_, "superrstudio_lfq_cc_run", null, null);
      ccRun_.setWidth("220px");
      grid.setWidget(row, 2, button(useRun_, "superrstudio_lfq_cc_use_run"));
      growthRow(grid, messages_.ccLinf(), ccLinf_, "superrstudio_lfq_cc_linf", null, null);
      growthRow(grid, messages_.ccK(), ccK_, "superrstudio_lfq_cc_k", null, null);
      growthRow(grid, messages_.ccC(), ccC_, "superrstudio_lfq_cc_c", ccTs_, "superrstudio_lfq_cc_ts");
      growthRow(grid, messages_.ccYear(), ccYear_, "superrstudio_lfq_cc_year", null, null);
      growthRow(grid, messages_.ccPlus(), ccPlus_, "superrstudio_lfq_cc_plus", ccPlusValue_, "superrstudio_lfq_cc_plus_value");
      ccPlus_.setWidth("260px");
      growthRow(grid, messages_.ccMethod(), ccMethod_, "superrstudio_lfq_cc_method", null, null);
      growthRow(grid, messages_.ccPoints(), ccFirst_, "superrstudio_lfq_cc_first", ccLast_, "superrstudio_lfq_cc_last");
      growthRow(grid, "", ccOgive_, "superrstudio_lfq_cc_ogive", null, null);
      growthRow(grid, messages_.mMethod(), mMethod_, "superrstudio_lfq_m_method", null, null);
      mTempRow_ = growthRow(grid, messages_.mTemp(), mTemp_, "superrstudio_lfq_m_temp", null, null);
      mSchoolingRow_ = growthRow(grid, "", mSchooling_, "superrstudio_lfq_m_schooling", null, null);
      mTmaxRow_ = growthRow(grid, messages_.mTmax(), mTmax_, "superrstudio_lfq_m_tmax", null, null);
      mValueRow_ = growthRow(grid, messages_.mValue(), mValue_, "superrstudio_lfq_m_value", null, null);
      mortalityGrid_ = grid;
      page.add(grid);
      page.add(small(messages_.ccPointsHint()));
      page.add(button(computeZ_, "superrstudio_lfq_compute_z"));
      mortality_.getElement().setId("superrstudio_lfq_mortality");
      mortality_.getElement().setAttribute("role", "status");
      mortality_.getElement().getStyle().setProperty("whiteSpace", "pre-line");
      page.add(mortality_);
      page.add(small(messages_.mortalityCaveat()));
      HorizontalPanel output = new HorizontalPanel();
      output.setSpacing(4);
      ccImage_.getElement().setId("superrstudio_lfq_cc_image");
      ccImage_.getElement().setAttribute("alt", messages_.ccMethod());
      ccImage_.setPixelSize(400, 262);
      ccImage_.setVisible(false);
      output.add(ccImage_);
      VerticalPanel points = new VerticalPanel();
      points.add(heading(messages_.pointsHeading()));
      points_.getElement().setId("superrstudio_lfq_cc_points");
      points_.setCellSpacing(0);
      points_.setCellPadding(2);
      points_.setBorderWidth(1);
      ScrollPanel scroll = new ScrollPanel(points_);
      scroll.setSize("300px", "250px");
      points.add(scroll);
      output.add(points);
      page.add(output);
      return page;
   }

   // 6. saved analyses
   private Widget createSavedPage()
   {
      VerticalPanel page = new VerticalPanel();
      page.setSpacing(4);
      page.add(small(messages_.savedHelp()));
      HorizontalPanel file = new HorizontalPanel();
      file.setSpacing(4);
      file.setVerticalAlignment(HasVerticalAlignment.ALIGN_MIDDLE);
      libraryPath_.getElement().setId("superrstudio_lfq_lib_path");
      libraryPath_.setWidth("380px");
      libraryPath_.getElement().setAttribute("placeholder", "lfq-analyses.json");
      file.add(new FormLabel(messages_.fileLabel(), libraryPath_));
      file.add(libraryPath_);
      file.add(button(browseLibrary_, "superrstudio_lfq_lib_browse"));
      file.add(button(openLibrary_, "superrstudio_lfq_lib_open"));
      file.add(button(saveLibrary_, "superrstudio_lfq_lib_save_as"));
      page.add(file);
      libraryFile_.getElement().setId("superrstudio_lfq_lib_file");
      page.add(libraryFile_);
      HorizontalPanel save = new HorizontalPanel();
      save.setSpacing(4);
      save.setVerticalAlignment(HasVerticalAlignment.ALIGN_MIDDLE);
      saveSource_.getElement().setId("superrstudio_lfq_lib_source");
      save.add(new FormLabel(messages_.saveFrom(), saveSource_));
      save.add(saveSource_);
      analysisName_.getElement().setId("superrstudio_lfq_lib_name");
      analysisName_.setWidth("220px");
      save.add(new FormLabel(messages_.analysisName(), analysisName_));
      save.add(analysisName_);
      save.add(button(saveAnalysis_, "superrstudio_lfq_lib_add"));
      page.add(save);
      page.add(heading(messages_.analyses()));
      analyses_.getElement().setId("superrstudio_lfq_lib_list");
      analyses_.setVisibleItemCount(6);
      analyses_.setWidth("740px");
      Roles.getListboxRole().setAriaLabelProperty(analyses_.getElement(), messages_.analyses());
      page.add(analyses_);
      HorizontalPanel actions = new HorizontalPanel();
      actions.setSpacing(4);
      actions.setVerticalAlignment(HasVerticalAlignment.ALIGN_MIDDLE);
      actions.add(button(restore_, "superrstudio_lfq_lib_restore"));
      actions.add(button(rerun_, "superrstudio_lfq_lib_rerun"));
      actions.add(button(rename_, "superrstudio_lfq_lib_rename"));
      actions.add(button(duplicate_, "superrstudio_lfq_lib_duplicate"));
      actions.add(button(delete_, "superrstudio_lfq_lib_delete"));
      compareWith_.getElement().setId("superrstudio_lfq_lib_other");
      compareWith_.setWidth("160px");
      actions.add(new FormLabel(messages_.compareWith(), compareWith_));
      actions.add(compareWith_);
      actions.add(button(compareAnalyses_, "superrstudio_lfq_lib_compare"));
      page.add(actions);
      savedStatus_.getElement().setId("superrstudio_lfq_lib_status");
      savedStatus_.getElement().setAttribute("role", "status");
      savedStatus_.getElement().setAttribute("aria-live", "polite");
      savedStatus_.getElement().getStyle().setProperty("whiteSpace", "pre-line");
      page.add(savedStatus_);
      return page;
   }

   private static Label small(String text)
   {
      Label label = SuperRStudioTheme.hint(new Label(text));
      label.setWidth("740px");
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

   private void mortalityChanged()
   {
      ccPlusValue_.setEnabled("value".equals(value(ccPlus_)));
      boolean cumulative = "cumulative".equals(value(ccMethod_));
      if (cumulative)
         ccOgive_.setValue(false);
      ccOgive_.setEnabled(!cumulative);
      String m = value(mMethod_);
      mortalityGrid_.getRowFormatter().setVisible(mTempRow_, "pauly_linf".equals(m));
      mortalityGrid_.getRowFormatter().setVisible(mSchoolingRow_, "pauly_linf".equals(m));
      mortalityGrid_.getRowFormatter().setVisible(mTmaxRow_, "then_tmax".equals(m));
      mortalityGrid_.getRowFormatter().setVisible(mValueRow_, "manual".equals(m));
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
      computeZ_.setEnabled(!busy_ && createdOk_ && installed_);
      useRun_.setEnabled(ccRun_.getItemCount() > 0);
      boolean selected = !value(analyses_).isEmpty();
      saveAnalysis_.setEnabled(!busy_ && (ready || !value(saveSource_).isEmpty()));
      for (ThemedButton action : new ThemedButton[] {restore_, rename_, duplicate_, delete_})
         action.setEnabled(!busy_ && selected);
      rerun_.setEnabled(!busy_ && selected && installed_ && job_.isEmpty());
      compareAnalyses_.setEnabled(!busy_ && selected && compareWith_.getItemCount() > 1);
      openLibrary_.setEnabled(!busy_);
      saveLibrary_.setEnabled(!busy_);
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
               columns(null);
            refreshRuns();
            request("lfq_lib", "", null, this::showLibrary);
         });
      });
   }

   private void columns(Runnable after)
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
         if (after != null)
            after.run();
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

   private void create(Runnable after)
   {
      request("lfq_create", value(datasets_), settings(), result -> {
         createdOk_ = true;
         showReport(result.obj("report"));
         StringBuilder text = new StringBuilder(messages_.created(result.str("dates"), result.str("classes"),
            result.str("total"), ScatterResult.format(result.num("asp")), result.str("ma")));
         text.append("\n").append(messages_.transformations());
         JsArrayString steps = result.strings("transformations");
         for (int i = 0; i < steps.length(); i++)
            text.append("\n").append(i + 1).append(". ").append(steps.get(i));
         if (result.strings("warnings").length() > 0)
            text.append("\n").append(result.strings("warnings").join("\n"));
         created_.setText(text.toString());
         rawImage_.setUrl("data:image/png;base64," + result.str("raw_image"));
         restructuredImage_.setUrl("data:image/png;base64," + result.str("restructured_image"));
         rawImage_.setVisible(true);
         restructuredImage_.setVisible(true);
         code_.setText(result.str("code"));
         // TropFishR derives its default Linf search range from the data; show it
         if (linfMin_.getValue().trim().isEmpty()) linfMin_.setValue(result.str("linf_suggest_min"));
         if (linfMax_.getValue().trim().isEmpty()) linfMax_.setValue(result.str("linf_suggest_max"));
         // the sampling years available to the catch curve
         String year = value(ccYear_);
         ccYear_.clear();
         option(ccYear_, messages_.allDates(), "");
         JsArrayString years = result.strings("years");
         for (int i = 0; i < years.length(); i++)
            option(ccYear_, years.get(i), years.get(i));
         select(ccYear_, year);
         enableSteps();
         if (after != null)
            after.run();
      });
   }

   private void startAnalysis()
   {
      request("lfq_start", value(datasets_), settings(), result -> {
         job_ = result.str("job");
         SuperRStudioTheme.status(progress_, messages_.running("…", "0"), SuperRStudioTheme.BUSY);
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
               SuperRStudioTheme.status(progress_, messages_.running(result.str("progress"), result.str("elapsed")),
                                        SuperRStudioTheme.BUSY);
               return;
            }
            finishJob();
            if ("done".equals(status))
            {
               SuperRStudioTheme.status(progress_, messages_.done(), "");
               showRuns(result);
               showTab(3);
            }
            else if ("failed".equals(status))
               SuperRStudioTheme.status(progress_, messages_.failed(result.str("message")), SuperRStudioTheme.ERROR);
            else
               SuperRStudioTheme.status(progress_, messages_.cancelled(), "");
         }

         @Override public void onError(ServerError error)
         {
            polling_ = false;
            finishJob();
            SuperRStudioTheme.status(progress_, message(error), SuperRStudioTheme.ERROR);
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
         SuperRStudioTheme.status(progress_, messages_.cancelled(), "");
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
      String selected = value(runs_), growthRun = value(ccRun_), source = value(saveSource_);
      runs_.clear();
      ccRun_.clear();
      saveSource_.clear();
      option(saveSource_, messages_.sourceCurrent(), "");
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
         String item = run.str("id").replace("run", "#") + " " + run.str("method") +
                       (run.has("seed") ? " seed " + run.str("seed") : "") +
                       (run.str("label").isEmpty() ? "" : " (" + run.str("label") + ")");
         runs_.addItem(item, run.str("id"));
         saveSource_.addItem(item, run.str("id"));
         if (run.has("linf") && run.has("k"))
            ccRun_.addItem(item + ": Linf " + number(run, "linf") + ", K " + number(run, "k"), run.str("id"));
      }
      select(runs_, selected);
      select(ccRun_, growthRun);
      select(saveSource_, source);
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
            number(k, "mean"), number(k, "sd"), number(k, "min"), number(k, "max")));
         JsArrayString differs = group.strings("differs");
         if (i > 0 && differs.length() > 0)
            groups.append("; ").append(messages_.differs(categories(differs)));
         groups.append("\n");
      }
      groups_.setText(runsData_.length() == 0 ? messages_.noRuns() : groups.toString());
      JsArrayString varies = result.strings("varies");
      varies_.setText(runsData_.length() < 2 ? "" : varies.length() == 0 ? messages_.variesNone()
                                                   : messages_.varies(categories(varies)));
      String notes = result.strings("notes").join("\n");
      notes_.setText((notes.isEmpty() ? "" : notes + "\n") + messages_.comparisonCaveat());
      enableSteps();
   }

   private String categories(JsArrayString codes)
   {
      StringBuilder labels = new StringBuilder();
      for (int i = 0; i < codes.length(); i++)
         labels.append(i == 0 ? "" : ", ").append(category(codes.get(i)));
      return labels.toString();
   }

   private static String category(String code)
   {
      switch (code)
      {
         case "data": return messages_.catData();
         case "classes": return messages_.catClasses();
         case "aggregation": return messages_.catAggregation();
         case "restructuring": return messages_.catRestructuring();
         case "ranges": return messages_.catRanges();
         case "method": return messages_.catMethod();
         case "optimiser": return messages_.catOptimiser();
         case "seed": return messages_.catSeed();
         case "versions": return messages_.catVersions();
         default: return code;
      }
   }

   private static String number(LfqResult object, String key)
   {
      return object.has(key) && !Double.isNaN(object.num(key)) ? ScatterResult.format(object.num(key)) : "";
   }

   private LfqResult run(String id)
   {
      for (int i = 0; runsData_ != null && i < runsData_.length(); i++)
         if (runsData_.get(i).str("id").equals(id))
            return runsData_.get(i);
      return null;
   }

   private void showRun()
   {
      fitImage_.setVisible(false);
      LfqResult run = run(value(runs_));
      if (run != null)
         code_.setText(run.str("code"));
   }

   private void showFit()
   {
      JSONObject json = new JSONObject();
      json.put("run_id", new JSONString(value(runs_)));
      request("lfq_run_plot", "", json, result -> {
         fitImage_.setUrl("data:image/png;base64," + result.str("image"));
         showRun();
         fitImage_.setVisible(true);
      });
   }

   private void openCode()
   {
      LfqResult run = run(value(runs_));
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

   // Mortality ------------------------------------------------------------------

   // growth parameters of a recorded run (the values, not a reference)
   private void useRun()
   {
      LfqResult run = run(value(ccRun_));
      if (run == null)
         return;
      ccLinf_.setValue(run.str("linf"));
      ccK_.setValue(run.str("k"));
      ccC_.setValue(run.has("c") ? run.str("c") : "");
      ccTs_.setValue(run.has("ts") ? run.str("ts") : "");
   }

   private void computeMortality()
   {
      request("lfq_mortality", value(datasets_), settings(), this::showMortality);
   }

   private void showMortality(LfqResult result)
   {
      StringBuilder text = new StringBuilder(messages_.zResult(number(result, "z"), number(result, "se"),
         number(result, "ci_low"), number(result, "ci_high"), number(result, "r2"), result.str("n"),
         result.str("first"), result.str("last")));
      if (result.has("m"))
         text.append("\n").append(messages_.mResult(number(result, "m"), number(result, "f"), number(result, "e")));
      if (result.has("l50"))
         text.append("\n").append(messages_.ogiveResult(number(result, "l50"), number(result, "l75")));
      JsArray<LfqResult> diagnostics = result.list("diagnostics");
      if (diagnostics.length() > 0)
         text.append("\n").append(messages_.diagnostics());
      for (int i = 0; i < diagnostics.length(); i++)
         text.append("\n• ").append(diagnostic(diagnostics.get(i)));
      if (result.strings("warnings").length() > 0)
         text.append("\n").append(result.strings("warnings").join("\n"));
      mortality_.setText(text.toString());
      // the points used are shown so that they can be checked and adjusted
      ccFirst_.setValue(result.str("first"));
      ccLast_.setValue(result.str("last"));
      ccImage_.setUrl("data:image/png;base64," + result.str("image"));
      ccImage_.setVisible(true);
      boolean cumulative = "cumulative".equals(result.str("method"));
      String[] headers = {"#", messages_.colLength(), cumulative ? messages_.colLnLinf() : messages_.colAge(),
                          cumulative ? "ln C" : "ln(C/dt)", messages_.colUsed()};
      JsArray<LfqResult> points = result.list("points");
      points_.resize(points.length() + 1, headers.length);
      for (int c = 0; c < headers.length; c++)
      {
         points_.setText(0, c, headers[c]);
         points_.getCellFormatter().getElement(0, c).getStyle().setProperty("fontWeight", "bold");
      }
      for (int i = 0; i < points.length(); i++)
      {
         LfqResult point = points.get(i);
         String[] cells = {point.str("index"), number(point, "length"), number(point, "x"), number(point, "y"),
                           point.flag("used") ? messages_.yes() : ""};
         for (int c = 0; c < cells.length; c++)
            points_.setText(i + 1, c, cells[c]);
         points_.getRowFormatter().getElement(i + 1).getStyle().setProperty("fontWeight",
                                                                            point.flag("used") ? "bold" : "normal");
      }
      code_.setText(result.str("code"));
   }

   private static String diagnostic(LfqResult item)
   {
      JsArrayString v = item.strings("values");
      String a = v.length() > 0 ? v.get(0) : "", b = v.length() > 1 ? v.get(1) : "";
      switch (item.str("code"))
      {
         case "automatic": return messages_.dAutomatic(a, b);
         case "before_peak": return messages_.dBeforePeak();
         case "few_points": return messages_.dFewPoints(a);
         case "low_r2": return messages_.dLowR2(a);
         case "wide_ci": return messages_.dWideCi(a);
         case "near_linf": return messages_.dNearLinf();
         case "no_age": return messages_.dNoAge(a);
         case "negative_f": return messages_.dNegativeF();
         case "ogive": return messages_.dOgive();
         default: return item.str("text");
      }
   }

   // Saved analyses -------------------------------------------------------------

   private JSONObject libraryRequest(String... pairs)
   {
      JSONObject json = new JSONObject();
      for (int i = 0; i + 1 < pairs.length; i += 2)
         json.put(pairs[i], new JSONString(pairs[i + 1]));
      return json;
   }

   private void showLibrary(LfqResult result)
   {
      String path = result.str("path");
      libraryFile_.setText(path.isEmpty() ? messages_.savedNoFile() : messages_.savedFile(path));
      String selected = value(analyses_), other = value(compareWith_);
      analyses_.clear();
      compareWith_.clear();
      JsArray<LfqResult> list = result.list("analyses");
      for (int i = 0; i < list.length(); i++)
      {
         LfqResult analysis = list.get(i);
         String method = analysis.str("method") +
            (analysis.str("seeds").isEmpty() ? "" : " (" + messages_.catSeed() + " " + analysis.str("seeds") + ")");
         String item = messages_.analysisItem(analysis.str("name"), method, analysis.str("dataset"),
            analysis.str("created").replace("T", " ")) +
            (analysis.num("results") > 0 && analysis.has("linf")
               ? "; " + messages_.withResults(number(analysis, "linf"), number(analysis, "k")) : "");
         analyses_.addItem(item, analysis.str("id"));
         compareWith_.addItem(analysis.str("name"), analysis.str("id"));
      }
      select(analyses_, selected);
      select(compareWith_, other);
      if (analyses_.getSelectedIndex() < 0 && analyses_.getItemCount() > 0)
         analyses_.setSelectedIndex(analyses_.getItemCount() - 1);
      enableSteps();
   }

   private void browseLibrary()
   {
      String current = libraryPath_.getValue().trim();
      RStudioGinjector.INSTANCE.getFileDialogs().saveFile(
         messages_.fileCaption(),
         RStudioGinjector.INSTANCE.getRemoteFileSystemContext(),
         FileSystemItem.createFile(current.isEmpty() ? FileSystemItem.HOME_PREFIX + "lfq-analyses.json" : current),
         ".json", true,
         new ProgressOperationWithInput<FileSystemItem>()
         {
            @Override public void execute(FileSystemItem input, ProgressIndicator indicator)
            {
               indicator.onCompleted();
               if (input != null)
                  libraryPath_.setValue(input.getPath());
            }
         });
   }

   private void libraryFile(String operation)
   {
      request(operation, "", libraryRequest("path", libraryPath_.getValue().trim()), result -> {
         savedStatus_.setText("");
         showLibrary(result);
      });
   }

   private void saveAnalysis()
   {
      String source = value(saveSource_);
      JSONObject json = source.isEmpty() ? settings() : new JSONObject();
      json.put("name", new JSONString(analysisName_.getValue().trim()));
      if (!source.isEmpty())
         json.put("run_id", new JSONString(source));
      request("lfq_lib_add", value(datasets_), json, result -> {
         savedStatus_.setText("");
         showLibrary(result);
         analyses_.setSelectedIndex(analyses_.getItemCount() - 1);
         enableSteps();
      });
   }

   private void libraryAction(String operation, boolean named)
   {
      String id = value(analyses_);
      if (id.isEmpty())
      {
         savedStatus_.setText(messages_.selectAnalysis());
         return;
      }
      JSONObject json = named ? libraryRequest("analysis", id, "name", analysisName_.getValue().trim())
                              : libraryRequest("analysis", id);
      request(operation, "", json, result -> {
         savedStatus_.setText("");
         showLibrary(result);
      });
   }

   // Restores every setting; the saved dataset is selected only if it exists.
   // With run, the data are created and the analysis started afterwards.
   private void restore(boolean run)
   {
      String id = value(analyses_);
      if (id.isEmpty())
      {
         savedStatus_.setText(messages_.selectAnalysis());
         return;
      }
      request("lfq_lib_restore", value(datasets_), libraryRequest("analysis", id), result -> {
         StringBuilder text = new StringBuilder(messages_.restored(result.str("name")));
         JsArray<LfqResult> warnings = result.list("warnings");
         if (warnings.length() > 0)
            text.append("\n").append(messages_.checkBefore());
         for (int i = 0; i < warnings.length(); i++)
            text.append("\n• ").append(warning(warnings.get(i)));
         boolean found = result.flag("dataset_found");
         if (run && !found)
            text.append("\n").append(messages_.rerunNeedsDataset());
         savedStatus_.setText(text.toString());
         LfqResult settings = result.obj("settings");
         if (!found)
         {
            apply(settings);
            createdOk_ = false;
            enableSteps();
            return;
         }
         select(datasets_, result.str("dataset"));
         columns(() -> {
            apply(settings);
            if (run)
               create(() -> startAnalysis());
         });
      });
   }

   private static String warning(LfqResult item)
   {
      JsArrayString v = item.strings("values");
      String a = v.length() > 0 ? v.get(0) : "", b = v.length() > 1 ? v.get(1) : "",
             c = v.length() > 2 ? v.get(2) : "";
      switch (item.str("code"))
      {
         case "dataset_missing": return messages_.wDatasetMissing(a);
         case "columns_missing": return messages_.wColumnsMissing(a, b);
         case "data_changed": return messages_.wDataChanged(a, b, c);
         case "no_tropfishr": return messages_.wNoTropfishr();
         case "tropfishr_version": return messages_.wTropfishrVersion(a, b);
         case "r_version": return messages_.wRVersion(a, b);
         default: return item.str("text");
      }
   }

   private void apply(LfqResult settings)
   {
      for (Map.Entry<String, ListBox> entry : lists_.entrySet())
      {
         if (!settings.has(entry.getKey()))
            continue;
         String value = settings.str(entry.getKey());
         ListBox list = entry.getValue();
         // saved choices that the current lists do not offer yet (species, years)
         if (!value.isEmpty() && !contains(list, value) && (list == species_ || list == ccYear_))
            list.addItem(value, value);
         select(list, value);
      }
      for (Map.Entry<String, TextBox> entry : texts_.entrySet())
         if (settings.has(entry.getKey()))
            entry.getValue().setValue(settings.str(entry.getKey()));
      for (Map.Entry<String, CheckBox> entry : checks_.entrySet())
         if (settings.has(entry.getKey()))
            entry.getValue().setValue(settings.flag(entry.getKey()));
      methodChanged();
      mortalityChanged();
   }

   private void compareAnalyses()
   {
      request("lfq_lib_compare", "", libraryRequest("analysis", value(analyses_), "other", value(compareWith_)), result -> {
         JsArray<LfqResult> rows = result.list("rows");
         if (rows.length() == 0)
         {
            savedStatus_.setText(messages_.compareSame());
            return;
         }
         StringBuilder text = new StringBuilder(messages_.compareResult(result.str("a"), result.str("b"),
                                                                        categories(result.strings("categories"))));
         for (int i = 0; i < rows.length(); i++)
            text.append("\n").append(rows.get(i).str("setting")).append(": ")
                .append(rows.get(i).str("a")).append(" → ").append(rows.get(i).str("b"));
         savedStatus_.setText(text.toString());
      });
   }

   // Settings -------------------------------------------------------------------

   private JSONObject settings()
   {
      JSONObject json = new JSONObject();
      for (Map.Entry<String, ListBox> entry : lists_.entrySet())
      {
         String value = value(entry.getValue());
         if ("ma".equals(entry.getKey()))
            json.put("ma", new JSONNumber(Double.parseDouble(value)));
         else
            text(json, entry.getKey(), value);
      }
      for (Map.Entry<String, TextBox> entry : texts_.entrySet())
      {
         if (TEXT_KEYS.contains(entry.getKey()))
            text(json, entry.getKey(), entry.getValue().getValue().trim());
         else
            numberSetting(json, entry.getKey(), entry.getValue());
      }
      for (Map.Entry<String, CheckBox> entry : checks_.entrySet())
         json.put(entry.getKey(), JSONBoolean.getInstance(entry.getValue().getValue()));
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
      SuperRStudioTheme.status(status_, messages_.working(), SuperRStudioTheme.BUSY);
      server_.superrstudioData(operation, dataset, "", "", "", json, new ServerRequestCallback<ScatterResult>()
      {
         @Override public void onResponseReceived(ScatterResult response)
         {
            if (!isAttached()) return;
            busy_ = false;
            SuperRStudioTheme.status(status_, installed_ ? version_ : messages_.missingPackage(), "");
            done.execute(response.cast());
            enableSteps();
         }

         @Override public void onError(ServerError error)
         {
            if (!isAttached()) return;
            busy_ = false;
            SuperRStudioTheme.status(status_, message(error), SuperRStudioTheme.ERROR);
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

   private static boolean contains(ListBox list, String value)
   {
      for (int i = 0; i < list.getItemCount(); i++)
         if (list.getValue(i).equals(value))
            return true;
      return false;
   }

   private static void select(ListBox list, String value)
   {
      for (int i = 0; i < list.getItemCount(); i++)
         if (list.getValue(i).equals(value))
            list.setSelectedIndex(i);
   }

   private static String value(ListBox list)
   {
      return list.getItemCount() > 0 && list.getSelectedIndex() >= 0 && list.getSelectedValue() != null
         ? list.getSelectedValue() : "";
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
                       methodHint_ = new Label(), progress_ = new Label(), groups_ = new Label(), notes_ = new Label(),
                       varies_ = new Label(), mortality_ = new Label(), libraryFile_ = new Label(),
                       savedStatus_ = new Label();
   private final ListBox datasets_ = new ListBox(), length_ = new ListBox(), unit_ = new ListBox(),
                         date_ = new ListBox(), dateFormat_ = new ListBox(), freq_ = new ListBox(),
                         speciesColumn_ = new ListBox(), species_ = new ListBox(), aggregate_ = new ListBox(),
                         ma_ = new ListBox(), method_ = new ListBox(), saStop_ = new ListBox(), runs_ = new ListBox(),
                         ccRun_ = new ListBox(), ccYear_ = new ListBox(), ccPlus_ = new ListBox(),
                         ccMethod_ = new ListBox(), mMethod_ = new ListBox(), saveSource_ = new ListBox(),
                         analyses_ = new ListBox(), compareWith_ = new ListBox();
   private final TextBox periodStart_ = new TextBox(), periodEnd_ = new TextBox(),
                         binSize_ = new TextBox(), lmin_ = new TextBox(), plusGroup_ = new TextBox(),
                         linfMin_ = new TextBox(), linfMax_ = new TextBox(), kMin_ = new TextBox(),
                         kMax_ = new TextBox(), tMin_ = new TextBox(), tMax_ = new TextBox(),
                         cMin_ = new TextBox(), cMax_ = new TextBox(), tsMin_ = new TextBox(), tsMax_ = new TextBox(),
                         seeds_ = new TextBox(), popSize_ = new TextBox(), maxIter_ = new TextBox(),
                         run_ = new TextBox(), pmutation_ = new TextBox(), pcrossover_ = new TextBox(),
                         elitism_ = new TextBox(), saMaxit_ = new TextBox(), saTime_ = new TextBox(),
                         linfInit_ = new TextBox(), kInit_ = new TextBox(), tInit_ = new TextBox(),
                         linfSteps_ = new TextBox(), kSteps_ = new TextBox(), label_ = new TextBox(),
                         ccLinf_ = new TextBox(), ccK_ = new TextBox(), ccC_ = new TextBox(), ccTs_ = new TextBox(),
                         ccPlusValue_ = new TextBox(), ccFirst_ = new TextBox(), ccLast_ = new TextBox(),
                         mTemp_ = new TextBox(), mTmax_ = new TextBox(), mValue_ = new TextBox(),
                         libraryPath_ = new TextBox(), analysisName_ = new TextBox();
   private final CheckBox addlSqrt_ = new CheckBox(), seasonalised_ = new CheckBox(),
                          ccOgive_ = new CheckBox(), mSchooling_ = new CheckBox();
   private final ThemedButton check_ = new ThemedButton(messages_.check(), e -> check()),
      create_ = new ThemedButton(messages_.create(), e -> create(null)),
      start_ = new ThemedButton(messages_.start(), e -> startAnalysis()),
      cancel_ = new ThemedButton(messages_.cancel(), e -> cancelAnalysis()),
      showFit_ = new ThemedButton(messages_.showFit(), e -> showFit()),
      openCode_ = new ThemedButton(messages_.openCode(), e -> openCode()),
      clear_ = new ThemedButton(messages_.clearRuns(), e -> clearRuns()),
      useRun_ = new ThemedButton(messages_.useRun(), e -> useRun()),
      computeZ_ = new ThemedButton(messages_.computeZ(), e -> computeMortality()),
      browseLibrary_ = new ThemedButton("…", e -> browseLibrary()),
      openLibrary_ = new ThemedButton(messages_.openFile(), e -> libraryFile("lfq_lib_open")),
      saveLibrary_ = new ThemedButton(messages_.saveAs(), e -> libraryFile("lfq_lib_save_as")),
      saveAnalysis_ = new ThemedButton(messages_.saveAnalysis(), e -> saveAnalysis()),
      restore_ = new ThemedButton(messages_.restore(), e -> restore(false)),
      rerun_ = new ThemedButton(messages_.rerun(), e -> restore(true)),
      rename_ = new ThemedButton(messages_.rename(), e -> libraryAction("lfq_lib_rename", true)),
      duplicate_ = new ThemedButton(messages_.duplicate(), e -> libraryAction("lfq_lib_duplicate", false)),
      delete_ = new ThemedButton(messages_.delete(), e -> libraryAction("lfq_lib_delete", false)),
      compareAnalyses_ = new ThemedButton(messages_.compare(), e -> compareAnalyses()),
      close_ = new ThemedButton(messages_.close(), e -> hide());
   private final Image rawImage_ = new Image(), restructuredImage_ = new Image(), fitImage_ = new Image(),
                       ccImage_ = new Image();
   private final Grid table_ = new Grid(1, 1), points_ = new Grid(1, 1);
   private final TextArea code_ = new TextArea();
   private final HorizontalPanel tabBar_ = new HorizontalPanel();
   private final DeckPanel tabDeck_ = new DeckPanel();
   private final List<Button> tabButtons_ = new ArrayList<>();
   private final List<Integer> gaRows_ = new ArrayList<>(), saRows_ = new ArrayList<>(), elefanRows_ = new ArrayList<>();
   private final Map<String, ListBox> lists_ = new LinkedHashMap<>();
   private final Map<String, TextBox> texts_ = new LinkedHashMap<>();
   private final Map<String, CheckBox> checks_ = new LinkedHashMap<>();
   private Grid growthGrid_, mortalityGrid_;
   private int cRow_, tsRow_, mTempRow_, mSchoolingRow_, mTmaxRow_, mValueRow_;
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
   private static final LfqMessages messages_ = SuperRStudioLanguage.lfq();
   // settings typed as text; every other text box holds a number
   private static final List<String> TEXT_KEYS = Arrays.asList("seeds", "label", "period_start", "period_end");
}
