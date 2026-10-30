// SPDX-License-Identifier: AGPL-3.0-only
package org.rstudio.studio.client.workbench.views.superrstudio;

import java.util.HashSet;
import java.util.Set;

import com.google.gwt.aria.client.Roles;
import com.google.gwt.core.client.JsArray;
import com.google.gwt.core.client.JsArrayString;
import com.google.gwt.event.dom.client.KeyCodes;
import com.google.gwt.event.dom.client.KeyDownEvent;
import com.google.gwt.json.client.JSONObject;
import com.google.gwt.json.client.JSONString;
import com.google.gwt.json.client.JSONValue;
import com.google.gwt.user.client.Timer;
import com.google.gwt.user.client.ui.DialogBox;
import com.google.gwt.user.client.ui.HorizontalPanel;
import com.google.gwt.user.client.ui.Label;
import com.google.gwt.user.client.ui.VerticalPanel;
import org.rstudio.core.client.ElementIds;
import org.rstudio.core.client.widget.ThemedButton;
import org.rstudio.studio.client.server.ServerError;
import org.rstudio.studio.client.server.ServerRequestCallback;

// Optional R packages of a SuperR feature (SessionSuperRStudioDeps.R): when a
// package is missing the dialog explains what an installation would do
// (packages, dependencies, repository, target library, renv) and installs
// only when the user chooses Install. The installation runs in a separate R
// process; the IDE stays usable. After a successful installation the
// packages are checked again and the feature continues (onInstalled).
public class DependencyDialog extends DialogBox
{
   // Checks the feature's packages; prompts only if one is missing or too
   // old. onInstalled runs after a successful installation (not when the
   // packages were already there). onMissing receives the missing package
   // names whenever the feature stays without its packages.
   public static void ensure(SuperRStudioServerOperations server, String feature, boolean prompt,
                             Runnable onInstalled, Missing onMissing)
   {
      call(server, "deps_check", feature, null, check -> {
         if (check.flag("ready"))
            return;
         if (onMissing != null)
            onMissing.missing(names(check));
         if (!prompt || (open_ != null && open_.isShowing()))
            return;
         open_ = new DependencyDialog(server, feature, onInstalled, onMissing);
         open_.show();
         open_.center();
         open_.plan();
      }, null);
   }

   public interface Missing
   {
      void missing(String packages);
   }

   public static String featureName(String feature)
   {
      return "lfq".equals(feature) ? messages_.featureLfq()
           : "sheet".equals(feature) ? messages_.featureSheet() : messages_.featurePlot();
   }

   private DependencyDialog(SuperRStudioServerOperations server, String feature, Runnable onInstalled,
                            Missing onMissing)
   {
      super(false, true);
      server_ = server;
      feature_ = feature;
      onInstalled_ = onInstalled;
      onMissing_ = onMissing;
      setText(messages_.title());
      addStyleDependentName("ModalDialog");
      Roles.getDialogRole().set(getElement());
      getElement().setId("superrstudio_deps_dialog");
      SuperRStudioTheme.dialog(this);
      addDomHandler(e -> {
         if (e.getNativeKeyCode() == KeyCodes.KEY_ESCAPE && job_.isEmpty())
         {
            e.preventDefault();
            hide();
         }
      }, KeyDownEvent.getType());

      VerticalPanel panel = new VerticalPanel();
      panel.setSpacing(6);
      panel.setWidth("560px");
      details_.getElement().setId("superrstudio_deps_details");
      details_.getElement().getStyle().setProperty("whiteSpace", "pre-line");
      panel.add(details_);
      panel.add(SuperRStudioTheme.hint(new Label(messages_.consent())));
      status_.getElement().setId("superrstudio_deps_status");
      status_.addStyleName(SuperRStudioTheme.STATUS);
      status_.getElement().setAttribute("role", "status");
      status_.getElement().setAttribute("aria-live", "polite");
      status_.getElement().getStyle().setProperty("whiteSpace", "pre-line");
      panel.add(status_);
      HorizontalPanel buttons = new HorizontalPanel();
      buttons.setSpacing(4);
      ElementIds.assignElementId(install_, "superrstudio_deps_install");
      ElementIds.assignElementId(cancel_, "superrstudio_deps_cancel");
      ElementIds.assignElementId(stop_, "superrstudio_deps_stop");
      buttons.add(install_);
      buttons.add(stop_);
      buttons.add(cancel_);
      panel.add(buttons);
      install_.setEnabled(false);
      stop_.setVisible(false);
      setWidget(panel);
   }

   private void plan()
   {
      SuperRStudioTheme.status(status_, messages_.checking(), SuperRStudioTheme.BUSY);
      call(server_, "deps_plan", feature_, null, plan -> {
         StringBuilder text = new StringBuilder(messages_.intro(featureName(feature_)));
         JsArray<LfqResult> packages = plan.list("packages");
         for (int i = 0; i < packages.length(); i++)
         {
            LfqResult p = packages.get(i);
            if ("ok".equals(p.str("status")))
               continue;
            text.append("\n• ").append("old".equals(p.str("status"))
               ? messages_.packageOld(p.str("name"), p.str("min"), p.str("installed"))
               : messages_.packageMissing(p.str("name"), p.str("min")));
            String why = "TropFishR".equals(p.str("name")) ? messages_.whyTropfishr()
                       : "ggplot2".equals(p.str("name")) ? messages_.whyGgplot2()
                       : "readxl".equals(p.str("name")) ? messages_.whyReadxl() : "";
            if (!why.isEmpty())
               text.append("\n  ").append(why);
            String version = plan.obj("versions").str(p.str("name"));
            if (!version.isEmpty())
               text.append("\n  ").append(messages_.version(version));
         }
         JsArrayString dependencies = plan.strings("dependencies");
         text.append("\n\n").append(dependencies.length() == 0 ? messages_.noDependencies()
            : messages_.dependencies(String.valueOf(dependencies.length()), dependencies.join(", ")));
         text.append("\n").append(messages_.source(plan.strings("repos").join(", ")));
         text.append("\n").append(messages_.target(plan.str("library")));
         if (!plan.str("renv").isEmpty())
            text.append("\n").append(messages_.renv(plan.str("renv")));
         details_.setText(text.toString());
         String problem = plan.str("problem");
         boolean writable = plan.flag("writable");
         if (!problem.isEmpty() || !writable)
         {
            SuperRStudioTheme.status(status_, !writable && problem.isEmpty() ? messages_.notWritable()
               : "repository".equals(problem) ? messages_.problemRepository()
               : "version".equals(problem) ? messages_.problemVersion() : messages_.problemUnavailable(),
               SuperRStudioTheme.ERROR);
            install_.setEnabled(false);
            cancel_.setText(messages_.close());
         }
         else
         {
            SuperRStudioTheme.status(status_, "", "");
            install_.setEnabled(true);
            install_.setFocus(true);
         }
      }, error -> {
         SuperRStudioTheme.status(status_, error, SuperRStudioTheme.ERROR);
         cancel_.setText(messages_.close());
      });
   }

   private void install()
   {
      install_.setEnabled(false);
      cancel_.setVisible(false);
      SuperRStudioTheme.status(status_, messages_.installing(""), SuperRStudioTheme.BUSY);
      call(server_, "deps_install", feature_, null, started -> {
         if ("done".equals(started.str("status")))
         {
            finished();
            return;
         }
         job_ = started.str("job");
         stop_.setVisible(true);
         poll_.schedule(1000);
      }, error -> failed(error, null));
   }

   private void poll()
   {
      call(server_, "deps_poll", feature_, job(), result -> {
         String status = result.str("status");
         if ("running".equals(status))
         {
            SuperRStudioTheme.status(status_, messages_.installing(result.str("progress")), SuperRStudioTheme.BUSY);
            poll_.schedule(1000);
         }
         else if ("done".equals(status))
            finished();
         else if (!"cancelled".equals(status))
            failed(result.str("message"), result.strings("log"));
      }, error -> failed(error, null));
   }

   private void stopInstall()
   {
      poll_.cancel();
      call(server_, "deps_cancel", feature_, job(), result -> {
         job_ = "";
         stop_.setVisible(false);
         cancel_.setText(messages_.close());
         cancel_.setVisible(true);
         JsArrayString locks = result.strings("locks");
         SuperRStudioTheme.status(status_, locks.length() == 0 ? messages_.stopped()
            : messages_.stopped() + "\n" + messages_.locks(result.str("library"), locks.join(", ")), "");
      }, error -> failed(error, null));
   }

   private void finished()
   {
      job_ = "";
      stop_.setVisible(false);
      SuperRStudioTheme.status(status_, messages_.done(), "");
      // the packages were checked again in the session before "done"
      new Timer()
      {
         @Override public void run()
         {
            hide();
            if (onInstalled_ != null)
               onInstalled_.run();
         }
      }.schedule(800);
   }

   private void failed(String message, JsArrayString log)
   {
      job_ = "";
      stop_.setVisible(false);
      cancel_.setText(messages_.close());
      cancel_.setVisible(true);
      install_.setEnabled(true);
      String detail = message == null ? "" : message;
      if (log != null && log.length() > 0)
         detail += "\n" + log.join("\n");
      SuperRStudioTheme.status(status_, messages_.failed() + "\n" + detail.trim(), SuperRStudioTheme.ERROR);
   }

   private JSONObject job()
   {
      JSONObject json = new JSONObject();
      json.put("job", new JSONString(job_));
      return json;
   }

   private static String names(LfqResult check)
   {
      StringBuilder out = new StringBuilder();
      JsArray<LfqResult> packages = check.list("packages");
      for (int i = 0; i < packages.length(); i++)
         if (!"ok".equals(packages.get(i).str("status")))
            out.append(out.length() > 0 ? ", " : "").append(packages.get(i).str("name"));
      return out.toString();
   }

   private interface Done
   {
      void execute(LfqResult result);
   }

   private interface Failed
   {
      void execute(String message);
   }

   private static void call(SuperRStudioServerOperations server, String operation, String feature,
                            JSONObject settings, Done done, Failed failed)
   {
      server.superrstudioData(operation, feature, "", "", "", settings, new ServerRequestCallback<ScatterResult>()
      {
         @Override public void onResponseReceived(ScatterResult response)
         {
            done.execute(response.cast());
         }

         @Override public void onError(ServerError error)
         {
            JSONValue info = error.getClientInfo();
            if (failed != null)
               failed.execute(info != null && info.isString() != null ? info.isString().stringValue()
                                                                       : error.getUserMessage());
         }
      });
   }

   private final SuperRStudioServerOperations server_;
   private final String feature_;
   private final Runnable onInstalled_;
   private final Missing onMissing_;
   private final Label details_ = new Label(), status_ = new Label();
   private final ThemedButton install_ = new ThemedButton(messages_.install(), e -> install()),
      stop_ = new ThemedButton(messages_.stop(), e -> stopInstall()),
      cancel_ = new ThemedButton(messages_.cancel(), e -> hide());
   private final Timer poll_ = new Timer()
   {
      @Override public void run()
      {
         poll();
      }
   };
   private String job_ = "";
   private static DependencyDialog open_;
   private static final DependencyMessages messages_ = SuperRStudioLanguage.deps();
}
