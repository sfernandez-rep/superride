// Copyright (C) 2026 SuperR contributors. SPDX-License-Identifier: AGPL-3.0-only
package org.rstudio.studio.client.workbench.views.superrstudio;

import com.google.gwt.event.dom.client.ClickHandler;
import com.google.gwt.user.client.ui.Button;
import com.google.gwt.user.client.ui.DialogBox;
import com.google.gwt.user.client.ui.Label;
import com.google.gwt.user.client.ui.VerticalPanel;

/** Download progress. A verified download is never executed by this dialog. */
public class SuperRUpdateDownload extends DialogBox
{
   public SuperRUpdateDownload(String version, String channel)
   {
      setText("SuperR Updater");
      setGlassEnabled(true);
      SuperRStudioTheme.dialog(this);
      VerticalPanel body = new VerticalPanel();
      body.setSpacing(10);
      body.add(new Label(text("Actualización: ", "Update: ") + version));
      status_ = new Label(text("Verificando la firma…", "Verifying signature…"));
      status_.getElement().setId("superr_update_download_status");
      status_.getElement().setAttribute("role", "status");
      body.add(status_);
      cancel_ = new Button(text("Cancelar", "Cancel"));
      cancel_.addClickHandler((ClickHandler)e -> {
         if (finished_) { cleanup(); hide(); }
         else { cancel_.setEnabled(false); cancelDownload(); }
      });
      cancel_.getElement().setId("superr_update_download_cancel");
      body.add(cancel_);
      setWidget(body);
      center();
      start(version, channel);
   }

   private void progress(String stage, double received, double total)
   {
      if ("downloading".equals(stage) && total > 0)
         status_.setText(text("Descargando: ", "Downloading: ") + (int)(100 * received / total) + "%");
   }
   private void complete(boolean ok, String reason)
   {
      finished_ = true;
      cancel_.setEnabled(true);
      cancel_.setText(text("Cerrar", "Close"));
      if (ok)
         status_.setText(text("Descarga verificada. La instalación automática aún no está habilitada.",
               "Download verified. Automatic installation is not enabled yet."));
      else if ("untrusted".equals(reason))
         status_.setText(text("No hay una clave de firma confiable configurada. No se descargó ningún instalador.",
               "No trusted signing key is configured. No installer was downloaded."));
      else if ("cancelled".equals(reason))
         status_.setText(text("Descarga cancelada.", "Download cancelled."));
      else if ("verification".equals(reason))
         status_.setText(text("La actualización no superó la verificación de seguridad.", "The update failed security verification."));
      else if ("busy".equals(reason))
         status_.setText(text("Ya hay una descarga en curso.", "A download is already in progress."));
      else
         status_.setText(text("No se pudo descargar la actualización. Comprueba la conexión.",
               "The update could not be downloaded. Check your connection."));
      cleanup();
   }
   private native void start(String version, String channel) /*-{
      var self=this, desktop=$wnd.desktop;
      if (!desktop || !desktop.superrDownloadUpdate || !desktop.superrOnUpdateProgress) {
         self.@org.rstudio.studio.client.workbench.views.superrstudio.SuperRUpdateDownload::complete(ZLjava/lang/String;)(false, "network"); return;
      }
      self.__superrUnsubscribe = desktop.superrOnUpdateProgress(function(p) {
         self.@org.rstudio.studio.client.workbench.views.superrstudio.SuperRUpdateDownload::progress(Ljava/lang/String;DD)(p.stage, p.received, p.total);
      });
      desktop.superrDownloadUpdate(version, channel).then(function(result) {
         self.@org.rstudio.studio.client.workbench.views.superrstudio.SuperRUpdateDownload::complete(ZLjava/lang/String;)(!!result.ok, result.reason || "");
      }, function() { self.@org.rstudio.studio.client.workbench.views.superrstudio.SuperRUpdateDownload::complete(ZLjava/lang/String;)(false, "network"); });
   }-*/;
   private native void cancelDownload() /*-{
      if ($wnd.desktop && $wnd.desktop.superrCancelDownload) $wnd.desktop.superrCancelDownload().then(function() {}, function() {});
   }-*/;
   private native void cleanup() /*-{
      if (this.__superrUnsubscribe) { this.__superrUnsubscribe(); this.__superrUnsubscribe = null; }
   }-*/;
   private static String text(String es, String en) { return SuperRStudioLanguage.spanish() ? es : en; }
   private final Label status_;
   private final Button cancel_;
   private boolean finished_ = false;
}
