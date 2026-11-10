// Copyright (C) 2026 SuperR contributors. SPDX-License-Identifier: AGPL-3.0-only
package org.rstudio.studio.client.workbench.views.superrstudio;

import com.google.gwt.dom.client.Style.Unit;
import com.google.gwt.dom.client.StyleInjector;
import com.google.gwt.event.dom.client.ClickHandler;
import com.google.gwt.user.client.ui.Button;
import com.google.gwt.user.client.ui.DockLayoutPanel;
import com.google.gwt.user.client.ui.HorizontalPanel;
import com.google.gwt.user.client.ui.Label;
import com.google.gwt.user.client.ui.ListBox;
import com.google.gwt.user.client.ui.ScrollPanel;
import com.google.gwt.user.client.ui.TextArea;
import com.google.gwt.user.client.ui.VerticalPanel;

/** Chat IA desktop bridge; unavailable providers fail closed. */
public class ChatAiPane extends DockLayoutPanel
{
   public ChatAiPane(Runnable close)
   {
      super(Unit.PX);
      setSize("100%", "100%");
      getElement().setId("superr_chat_ai_panel");
      StyleInjector.inject(".rstudio-themes-dark #superr_chat_ai_panel { background: #1c1d20; color: #f0f0f0; }" +
            ".rstudio-themes-dark #superr_chat_ai_panel textarea { background: #292b30; color: #f0f0f0; border: 1px solid #888; }");

      VerticalPanel header = new VerticalPanel();
      header.setWidth("100%");
      header.setSpacing(6);
      HorizontalPanel title = new HorizontalPanel();
      title.setWidth("100%");
      title.add(new Label("Chat IA"));
      Button closeButton = new Button(text("Cerrar", "Close"), (ClickHandler)e -> close.run());
      closeButton.getElement().setId("superr_chat_ai_close");
      title.add(closeButton);
      header.add(title);
      ListBox providers = new ListBox();
      providers.addItem("Gemini", "gemini");
      providers.addItem("Codex", "codex");
      providers_ = providers;
      providers.getElement().setId("superr_chat_ai_provider");
      providers.getElement().setAttribute("aria-label", text("Proveedor", "Provider"));
      header.add(providers);
      status_ = new Label();
      status_.getElement().setId("superr_chat_ai_status");
      status_.getElement().setAttribute("role", "status");
      header.add(status_);
      Button signIn = new Button(text("Iniciar sesión", "Sign in"), (ClickHandler)e -> {
         if ("gemini".equals(provider())) { onGoogleNotOffered(); return; }
         status_.setText(text("Esperando el inicio de sesión en el navegador…", "Waiting for sign-in in the browser…"));
         signIn(provider());
      });
      signIn.getElement().setId("superr_chat_ai_sign_in");
      header.add(signIn);
      providers.addChangeHandler(e -> refresh(provider()));
      addNorth(header, 150);

      VerticalPanel input = new VerticalPanel();
      input.setWidth("100%");
      input.setSpacing(6);
      TextArea prompt = new TextArea();
      prompt_ = prompt;
      prompt.setWidth("98%");
      prompt.setVisibleLines(3);
      prompt.getElement().setId("superr_chat_ai_prompt");
      prompt.getElement().setAttribute("aria-label", text("Mensaje", "Message"));
      input.add(prompt);
      Button send = new Button(text("Enviar", "Send"), (ClickHandler)e -> {
         if (prompt_.getText().trim().isEmpty())
            status_.setText(text("Escribe un mensaje.", "Write a message."));
         else
            send(provider(), prompt_.getText());
      });
      send.getElement().setId("superr_chat_ai_send");
      input.add(send);
      Button cancel = new Button(text("Detener", "Stop"), (ClickHandler)e -> cancel(provider()));
      cancel.getElement().setId("superr_chat_ai_cancel");
      input.add(cancel);
      addSouth(input, 145);
      ScrollPanel conversation = new ScrollPanel();
      conversation.getElement().setId("superr_chat_ai_conversation");
      conversation.getElement().setAttribute("aria-label", text("Conversación", "Conversation"));
      add(conversation);
      refresh(provider());
   }

   private String provider() { return providers_.getValue(providers_.getSelectedIndex()); }
   private void onStatus(String provider, boolean installed, String authentication)
   {
      if (!provider.equals(provider())) return;
      String install = installed ? text("Instalado", "Installed") : text("No detectado en PATH", "Not found on PATH");
      String auth = "connected".equals(authentication) ? text("Cuenta conectada", "Account connected") :
            "signed_out".equals(authentication) ? text("Sin iniciar sesión", "Signed out") : text("Autenticación desconocida", "Authentication unknown");
      status_.setText(install + " · " + auth + " · " + text("Chat deshabilitado: aislamiento de solo lectura sin verificar", "Chat disabled: read-only isolation not verified"));
   }
   private void onError(String provider)
   {
      if (provider.equals(provider()))
         status_.setText(text("No disponible. Comprueba la instalación y el almacenamiento seguro de credenciales.",
               "Unavailable. Check installation and secure credential storage."));
   }
   private void onBlocked(String provider)
   {
      if (provider.equals(provider()))
         status_.setText(text("Chat deshabilitado: aislamiento de solo lectura sin verificar.",
               "Chat disabled: read-only isolation not verified."));
   }
   // Antigravity's terms and FAQ do not support its consumer (personal Google
   // account) login inside third-party applications; see chat-ia.md.
   private void onGoogleNotOffered()
   {
      status_.setText(text("Inicio de sesión con una cuenta personal de Google no disponible: los términos de Antigravity " +
            "no admiten su uso desde aplicaciones de terceros con planes de consumo.",
            "Personal Google account sign-in is not available: Antigravity's terms do not support it in " +
            "third-party applications on consumer plans."));
   }
   private void onNoTurn(String provider)
   {
      if (provider.equals(provider()))
         status_.setText(text("No hay ninguna respuesta en curso.", "No response is in progress."));
   }
   private native void refresh(String provider) /*-{
      var self = this, bridge = $wnd.desktop;
      if (!bridge || !bridge.superrChatStatus) { self.@org.rstudio.studio.client.workbench.views.superrstudio.ChatAiPane::onError(Ljava/lang/String;)(provider); return; }
      bridge.superrChatStatus(provider).then(function(s) {
         self.@org.rstudio.studio.client.workbench.views.superrstudio.ChatAiPane::onStatus(Ljava/lang/String;ZLjava/lang/String;)(provider, !!s.installed, s.authentication);
      }, function() { self.@org.rstudio.studio.client.workbench.views.superrstudio.ChatAiPane::onError(Ljava/lang/String;)(provider); });
   }-*/;
   private native void signIn(String provider) /*-{
      var self = this, bridge = $wnd.desktop;
      if (!bridge || !bridge.superrChatSignIn) { self.@org.rstudio.studio.client.workbench.views.superrstudio.ChatAiPane::onError(Ljava/lang/String;)(provider); return; }
      bridge.superrChatSignIn(provider).then(function(s) {
         self.@org.rstudio.studio.client.workbench.views.superrstudio.ChatAiPane::onStatus(Ljava/lang/String;ZLjava/lang/String;)(provider, !!s.installed, s.authentication);
      }, function() { self.@org.rstudio.studio.client.workbench.views.superrstudio.ChatAiPane::onError(Ljava/lang/String;)(provider); });
   }-*/;
   private native void send(String provider, String message) /*-{
      var self = this, bridge = $wnd.desktop;
      if (!bridge || !bridge.superrChatSend) { self.@org.rstudio.studio.client.workbench.views.superrstudio.ChatAiPane::onError(Ljava/lang/String;)(provider); return; }
      bridge.superrChatSend(provider, message).then(function(){}, function(){ self.@org.rstudio.studio.client.workbench.views.superrstudio.ChatAiPane::onBlocked(Ljava/lang/String;)(provider); });
   }-*/;
   private native void cancel(String provider) /*-{
      var self = this, bridge = $wnd.desktop;
      if (!bridge || !bridge.superrChatCancel) { self.@org.rstudio.studio.client.workbench.views.superrstudio.ChatAiPane::onError(Ljava/lang/String;)(provider); return; }
      bridge.superrChatCancel(provider).then(function(){}, function(){ self.@org.rstudio.studio.client.workbench.views.superrstudio.ChatAiPane::onNoTurn(Ljava/lang/String;)(provider); });
   }-*/;
   private static String text(String es, String en) { return SuperRStudioLanguage.spanish() ? es : en; }
   private final Label status_;
   private final ListBox providers_;
   private final TextArea prompt_;
}
