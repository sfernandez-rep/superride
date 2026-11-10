// Copyright (C) 2026 SuperR contributors. SPDX-License-Identifier: AGPL-3.0-only
package org.rstudio.studio.client.workbench.views.superrstudio;

import com.google.gwt.dom.client.Style.Unit;
import com.google.gwt.dom.client.StyleInjector;
import com.google.gwt.event.dom.client.ClickHandler;
import com.google.gwt.event.dom.client.KeyCodes;
import com.google.gwt.user.client.ui.Button;
import com.google.gwt.user.client.ui.DockLayoutPanel;
import com.google.gwt.user.client.ui.FlowPanel;
import com.google.gwt.user.client.ui.HorizontalPanel;
import com.google.gwt.user.client.ui.Label;
import com.google.gwt.user.client.ui.ListBox;
import com.google.gwt.user.client.ui.PasswordTextBox;
import com.google.gwt.user.client.ui.ScrollPanel;
import com.google.gwt.user.client.ui.TextArea;
import com.google.gwt.user.client.ui.VerticalPanel;

/**
 * Chat IA desktop bridge. The Gemini API mode chats with the user's own Google
 * AI Studio key (text only: no project files, commands or edits); the agent
 * providers fail closed until their isolation is verified.
 */
public class ChatAiPane extends DockLayoutPanel
{
   public ChatAiPane(Runnable close)
   {
      super(Unit.PX);
      setSize("100%", "100%");
      getElement().setId("superr_chat_ai_panel");
      StyleInjector.inject(
            "#superr_chat_ai_panel .superr-chat-message { white-space: pre-wrap; margin: 4px 6px 10px 6px; padding: 6px 8px; border-radius: 6px; }" +
            "#superr_chat_ai_panel .superr-chat-user { background: rgba(66, 133, 244, 0.12); }" +
            "#superr_chat_ai_panel .superr-chat-model { background: rgba(128, 128, 128, 0.10); }" +
            "#superr_chat_ai_panel .superr-chat-who { font-weight: bold; margin: 6px 6px 0 6px; }" +
            "#superr_chat_ai_panel .superr-chat-note { font-size: 90%; opacity: 0.85; }" +
            ".rstudio-themes-dark #superr_chat_ai_panel { background: #1c1d20; color: #f0f0f0; }" +
            ".rstudio-themes-dark #superr_chat_ai_panel textarea, .rstudio-themes-dark #superr_chat_ai_panel input," +
            ".rstudio-themes-dark #superr_chat_ai_panel select { background: #292b30; color: #f0f0f0; border: 1px solid #888; }");

      VerticalPanel header = new VerticalPanel();
      header.setWidth("100%");
      header.setSpacing(4);
      HorizontalPanel title = new HorizontalPanel();
      title.setWidth("100%");
      title.add(new Label("Chat IA"));
      Button closeButton = new Button(text("Cerrar", "Close"), (ClickHandler)e -> close.run());
      closeButton.getElement().setId("superr_chat_ai_close");
      title.add(closeButton);
      header.add(title);
      providers_ = new ListBox();
      providers_.addItem(text("Gemini API (gratis)", "Gemini API (free)"), GEMINI_API);
      providers_.addItem("Gemini (Antigravity)", "gemini");
      providers_.addItem("Codex", "codex");
      providers_.getElement().setId("superr_chat_ai_provider");
      providers_.getElement().setAttribute("aria-label", text("Proveedor", "Provider"));
      header.add(providers_);
      status_ = new Label();
      status_.getElement().setId("superr_chat_ai_status");
      status_.getElement().setAttribute("role", "status");
      header.add(status_);

      connect_ = new Button(text("Conectar Gemini (gratis)", "Connect Gemini (free)"), (ClickHandler)e -> toggleSetup());
      connect_.getElement().setId("superr_chat_ai_connect");
      header.add(connect_);
      signIn_ = new Button(text("Iniciar sesión", "Sign in"), (ClickHandler)e -> {
         if ("gemini".equals(provider())) { onGoogleNotOffered(); return; }
         status_.setText(text("Esperando el inicio de sesión en el navegador…", "Waiting for sign-in in the browser…"));
         signIn(provider());
      });
      signIn_.getElement().setId("superr_chat_ai_sign_in");
      header.add(signIn_);

      setup_ = new VerticalPanel();
      setup_.setWidth("100%");
      setup_.setSpacing(4);
      setup_.getElement().setId("superr_chat_ai_gemini_setup");
      Label privacy = new Label(text(
            "Privacidad: en el nivel gratuito, Google puede usar tus mensajes y las respuestas para mejorar sus productos, " +
            "y revisores humanos pueden leerlos. No envíes datos personales, confidenciales ni sensibles.",
            "Privacy: on the free tier, Google may use your messages and the responses to improve its products, " +
            "and human reviewers may read them. Do not send personal, confidential or sensitive information."));
      privacy.getElement().setId("superr_chat_ai_privacy");
      privacy.addStyleName("superr-chat-note");
      setup_.add(privacy);
      Label steps = new Label(text(
            "1. Abre Google AI Studio e inicia sesión con tu cuenta de Google. 2. Crea una clave de API en un proyecto sin " +
            "facturación (así no hay cargos; SuperR no pide tarjeta ni activa facturación). 3. Pégala aquí y guárdala: " +
            "se cifra con el almacén de credenciales de Windows y no se muestra de nuevo.",
            "1. Open Google AI Studio and sign in with your Google account. 2. Create an API key in a project without " +
            "billing (no charges; SuperR asks for no card and never enables billing). 3. Paste it here and save it: " +
            "it is encrypted with Windows' credential storage and never shown again."));
      steps.addStyleName("superr-chat-note");
      setup_.add(steps);
      Button openKeyPage = new Button(text("Abrir Google AI Studio", "Open Google AI Studio"),
            (ClickHandler)e -> openKeyPage(GEMINI_API));
      openKeyPage.getElement().setId("superr_chat_ai_open_key_page");
      setup_.add(openKeyPage);
      keyBox_ = new PasswordTextBox();
      keyBox_.setWidth("95%");
      keyBox_.getElement().setId("superr_chat_ai_key");
      keyBox_.getElement().setAttribute("placeholder", text("Pega tu clave de API", "Paste your API key"));
      keyBox_.getElement().setAttribute("aria-label", text("Clave de API de Google AI Studio", "Google AI Studio API key"));
      keyBox_.getElement().setAttribute("autocomplete", "off");
      keyBox_.getElement().setAttribute("spellcheck", "false");
      setup_.add(keyBox_);
      HorizontalPanel keyButtons = new HorizontalPanel();
      keyButtons.setSpacing(2);
      Button saveKey = new Button(text("Guardar clave", "Save key"), (ClickHandler)e -> saveKey());
      saveKey.getElement().setId("superr_chat_ai_save_key");
      keyButtons.add(saveKey);
      Button forgetKey = new Button(text("Quitar clave", "Remove key"), (ClickHandler)e -> {
         status_.setText(text("Quitando la clave…", "Removing the key…"));
         forgetKey(GEMINI_API);
      });
      forgetKey.getElement().setId("superr_chat_ai_forget_key");
      keyButtons.add(forgetKey);
      setup_.add(keyButtons);
      setup_.setVisible(false);
      header.add(setup_);

      modelRow_ = new HorizontalPanel();
      modelRow_.setSpacing(2);
      modelRow_.add(new Label(text("Modelo:", "Model:")));
      models_ = new ListBox();
      models_.getElement().setId("superr_chat_ai_model");
      models_.getElement().setAttribute("aria-label", text("Modelo de Gemini", "Gemini model"));
      modelRow_.add(models_);
      Button newChat = new Button(text("Nueva conversación", "New conversation"), (ClickHandler)e -> newConversation());
      newChat.getElement().setId("superr_chat_ai_new");
      modelRow_.add(newChat);
      header.add(modelRow_);
      providers_.addChangeHandler(e -> providerChanged());
      header_ = new ScrollPanel(header);
      addNorth(header_, HEADER_SMALL);

      VerticalPanel input = new VerticalPanel();
      input.setWidth("100%");
      input.setSpacing(6);
      prompt_ = new TextArea();
      prompt_.setWidth("98%");
      prompt_.setVisibleLines(3);
      prompt_.getElement().setId("superr_chat_ai_prompt");
      prompt_.getElement().setAttribute("aria-label", text("Mensaje (Ctrl+Enter envía)", "Message (Ctrl+Enter sends)"));
      prompt_.addKeyDownHandler(e -> {
         if (e.getNativeKeyCode() == KeyCodes.KEY_ENTER && e.isControlKeyDown()) { e.preventDefault(); sendMessage(); }
      });
      input.add(prompt_);
      HorizontalPanel buttons = new HorizontalPanel();
      buttons.setSpacing(2);
      Button send = new Button(text("Enviar", "Send"), (ClickHandler)e -> sendMessage());
      send.getElement().setId("superr_chat_ai_send");
      buttons.add(send);
      Button cancel = new Button(text("Detener", "Stop"), (ClickHandler)e -> cancel(provider()));
      cancel.getElement().setId("superr_chat_ai_cancel");
      buttons.add(cancel);
      input.add(buttons);
      addSouth(input, 115);
      conversation_ = new FlowPanel();
      conversation_.getElement().setId("superr_chat_ai_messages");
      scroll_ = new ScrollPanel(conversation_);
      scroll_.getElement().setId("superr_chat_ai_conversation");
      scroll_.getElement().setAttribute("aria-label", text("Conversación", "Conversation"));
      scroll_.getElement().setAttribute("aria-live", "polite");
      add(scroll_);
      listen();
      providerChanged();
   }

   private String provider() { return providers_.getValue(providers_.getSelectedIndex()); }
   private boolean geminiApi() { return GEMINI_API.equals(provider()); }

   private void providerChanged()
   {
      boolean api = geminiApi();
      connect_.setVisible(api);
      signIn_.setVisible(!api);
      modelRow_.setVisible(api);
      if (!api) showSetup(false);
      refresh(provider());
   }

   private void toggleSetup() { showSetup(!setup_.isVisible()); }

   private void showSetup(boolean visible)
   {
      setup_.setVisible(visible);
      setWidgetSize(header_, visible ? HEADER_LARGE : HEADER_SMALL);
      if (visible) keyBox_.setFocus(true);
   }

   private void saveKey()
   {
      if (keyBox_.getText().trim().isEmpty())
      {
         status_.setText(text("Pega primero tu clave de API.", "Paste your API key first."));
         return;
      }
      status_.setText(text("Comprobando la clave con Google…", "Checking the key with Google…"));
      setKey(GEMINI_API, keyBox_.getText());
   }

   private void onKeySaved(boolean ok, String kind)
   {
      if (!ok) { status_.setText(errorText(kind)); return; }
      keyBox_.setText("");
      showSetup(false);
      refresh(GEMINI_API);
   }

   private void newConversation()
   {
      if (busy_) { status_.setText(errorText("busy")); return; }
      conversation_.clear();
      newChat(GEMINI_API);
      status_.setText(text("Nueva conversación.", "New conversation."));
   }

   private void sendMessage()
   {
      String message = prompt_.getText().trim();
      if (message.isEmpty()) { status_.setText(text("Escribe un mensaje.", "Write a message.")); return; }
      if (!geminiApi()) { send(provider(), message, "", ""); return; }
      if (busy_) { status_.setText(errorText("busy")); return; }
      if (models_.getItemCount() == 0) { status_.setText(errorText("no_key")); showSetup(true); return; }
      busy_ = true;
      turn_ = "t" + (++turnCount_);
      addMessage(text("Tú", "You"), message, "superr-chat-user");
      answer_ = addMessage("Gemini", "", "superr-chat-model");
      answer_.getElement().setId("superr_chat_ai_answer_" + turnCount_);
      prompt_.setText("");
      status_.setText(text("Gemini está respondiendo…", "Gemini is answering…"));
      send(GEMINI_API, message, models_.getSelectedValue(), turn_);
   }

   private Label addMessage(String who, String body, String style)
   {
      Label name = new Label(who);
      name.addStyleName("superr-chat-who");
      conversation_.add(name);
      Label message = new Label(body);
      message.addStyleName("superr-chat-message");
      message.addStyleName(style);
      conversation_.add(message);
      scroll_.scrollToBottom();
      return message;
   }

   private void onDelta(String turn, String delta)
   {
      if (answer_ == null || !turn.equals(turn_)) return;
      answer_.setText(answer_.getText() + delta);
      scroll_.scrollToBottom();
   }

   private void onSendResult(String turn, String status, String kind, String finishReason)
   {
      if (!turn.equals(turn_)) return;
      busy_ = false;
      boolean empty = answer_ == null || answer_.getText().isEmpty();
      if ("completed".equals(status))
      {
         if (empty) answer_.setText(text("(Gemini no devolvió texto)", "(Gemini returned no text)"));
         status_.setText(text("Respuesta recibida de Gemini.", "Response received from Gemini."));
      }
      else if ("cancelled".equals(status))
      {
         answer_.setText(answer_.getText() + text(" [detenido]", " [stopped]"));
         status_.setText(text("Respuesta detenida.", "Response stopped."));
      }
      else if ("incomplete".equals(status))
         status_.setText(text("Respuesta incompleta (", "Incomplete response (") + finishReason + ").");
      else
      {
         if (empty && answer_ != null) answer_.setText(text("(sin respuesta)", "(no response)"));
         status_.setText(errorText(kind));
         if ("invalid_key".equals(kind) || "no_key".equals(kind)) refresh(GEMINI_API);
      }
      answer_ = null;
   }

   private void onSendFailed(String provider)
   {
      if (GEMINI_API.equals(provider))
      {
         busy_ = false;
         answer_ = null;
         onError(provider);
      }
      else
         onBlocked(provider);
   }

   private void onStatus(String provider, boolean installed, String authentication)
   {
      if (!provider.equals(provider())) return;
      if (GEMINI_API.equals(provider))
      {
         if ("connected".equals(authentication))
         {
            status_.setText(text("Gemini conectado con tu clave (nivel gratuito). Solo texto: Chat IA no lee tu proyecto, " +
                  "no ejecuta comandos ni modifica archivos.",
                  "Gemini connected with your key (free tier). Text only: Chat IA does not read your project, " +
                  "run commands or change files."));
            loadModels(GEMINI_API);
         }
         else
         {
            models_.clear();
            status_.setText(text("Gemini no está conectado. Pulsa «Conectar Gemini (gratis)».",
                  "Gemini is not connected. Press \"Connect Gemini (free)\"."));
            showSetup(true);
         }
         return;
      }
      String install = installed ? text("Instalado", "Installed") : text("No detectado en PATH", "Not found on PATH");
      String auth = "connected".equals(authentication) ? text("Cuenta conectada", "Account connected") :
            "signed_out".equals(authentication) ? text("Sin iniciar sesión", "Signed out") : text("Autenticación desconocida", "Authentication unknown");
      status_.setText(install + " · " + auth + " · " + text("Chat deshabilitado: aislamiento de solo lectura sin verificar", "Chat disabled: read-only isolation not verified"));
   }

   private void clearModels() { previousModel_ = models_.getItemCount() > 0 ? models_.getSelectedValue() : previousModel_; models_.clear(); }
   private void addModel(String id, String label)
   {
      models_.addItem(label, id);
      if (id.equals(previousModel_)) models_.setSelectedIndex(models_.getItemCount() - 1);
   }
   private void onModelsFailed(String kind)
   {
      status_.setText("ok".equals(kind) ?
            text("Tu clave no tiene acceso a ningún modelo de texto con nivel gratuito.", "Your key has no access to any free-tier text model.") :
            errorText(kind));
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
            "no admiten su uso desde aplicaciones de terceros con planes de consumo. Usa «Gemini API (gratis)».",
            "Personal Google account sign-in is not available: Antigravity's terms do not support it in " +
            "third-party applications on consumer plans. Use \"Gemini API (free)\"."));
   }
   private void onNoTurn(String provider)
   {
      if (provider.equals(provider()))
         status_.setText(text("No hay ninguna respuesta en curso.", "No response is in progress."));
   }

   private static String errorText(String kind)
   {
      switch (kind == null ? "" : kind)
      {
         case "invalid_key": return text("La clave de API no es válida. Comprueba que la copiaste completa o crea otra en Google AI Studio.",
               "The API key is not valid. Check that you copied all of it, or create another in Google AI Studio.");
         case "quota": return text("Cuota gratuita agotada o demasiadas solicitudes por minuto. Espera un momento o elige otro modelo; " +
               "el límite diario se renueva cada día.",
               "Free quota used up or too many requests per minute. Wait a moment or choose another model; the daily limit renews every day.");
         case "verification": return text("Google pide verificar tu proyecto antes de usar el nivel gratuito. Hazlo en Google AI Studio.",
               "Google asks you to verify your project before using the free tier. Do it in Google AI Studio.");
         case "permission": return text("Google denegó el acceso para esta clave o su proyecto.", "Google denied access for this key or its project.");
         case "billing": return text("El proyecto de esta clave usa facturación prepaga sin saldo. Para no pagar, usa una clave de un proyecto sin facturación.",
               "This key's project uses prepaid billing with no balance. To stay free, use a key from a project without billing.");
         case "region": return text("La API de Gemini no está disponible en tu región.", "The Gemini API is not available in your region.");
         case "model": return text("Ese modelo no está disponible para tu clave. Elige otro.", "That model is not available for your key. Choose another.");
         case "blocked": return text("Gemini bloqueó la solicitud o la respuesta por sus filtros de seguridad.",
               "Gemini blocked the request or the response with its safety filters.");
         case "unavailable": return text("El servicio de Gemini no está disponible o está saturado. Inténtalo de nuevo en unos minutos.",
               "The Gemini service is unavailable or overloaded. Try again in a few minutes.");
         case "connection": return text("No se pudo conectar con Gemini. Revisa tu conexión a internet o el proxy.",
               "Could not connect to Gemini. Check your internet connection or proxy.");
         case "busy": return text("Ya hay una respuesta en curso.", "A response is already in progress.");
         case "no_key": return text("Primero conecta Gemini con tu clave de API.", "Connect Gemini with your API key first.");
         case "storage": return text("No se pudo usar el almacenamiento cifrado de credenciales del sistema.",
               "Could not use the system's encrypted credential storage.");
         default: return text("Gemini rechazó la solicitud.", "Gemini rejected the request.");
      }
   }

   private native void listen() /*-{
      var self = this, bridge = $wnd.desktop;
      if (!bridge || !bridge.superrChatOnEvent) return;
      bridge.superrChatOnEvent(function(e) {
         if (e && typeof e.turn === 'string' && typeof e.text === 'string')
            self.@org.rstudio.studio.client.workbench.views.superrstudio.ChatAiPane::onDelta(Ljava/lang/String;Ljava/lang/String;)(e.turn, e.text);
      });
   }-*/;
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
   private native void openKeyPage(String provider) /*-{
      var self = this, bridge = $wnd.desktop;
      if (!bridge || !bridge.superrChatOpenKeyPage) { self.@org.rstudio.studio.client.workbench.views.superrstudio.ChatAiPane::onError(Ljava/lang/String;)(provider); return; }
      bridge.superrChatOpenKeyPage(provider).then(function(){}, function() {
         self.@org.rstudio.studio.client.workbench.views.superrstudio.ChatAiPane::onError(Ljava/lang/String;)(provider); });
   }-*/;
   private native void setKey(String provider, String key) /*-{
      var self = this, bridge = $wnd.desktop;
      if (!bridge || !bridge.superrChatSetKey) { self.@org.rstudio.studio.client.workbench.views.superrstudio.ChatAiPane::onError(Ljava/lang/String;)(provider); return; }
      bridge.superrChatSetKey(provider, key).then(function(r) {
         self.@org.rstudio.studio.client.workbench.views.superrstudio.ChatAiPane::onKeySaved(ZLjava/lang/String;)(!!(r && r.ok), (r && r.kind) || '');
      }, function() { self.@org.rstudio.studio.client.workbench.views.superrstudio.ChatAiPane::onError(Ljava/lang/String;)(provider); });
   }-*/;
   private native void forgetKey(String provider) /*-{
      var self = this, bridge = $wnd.desktop;
      if (!bridge || !bridge.superrChatForgetKey) { self.@org.rstudio.studio.client.workbench.views.superrstudio.ChatAiPane::onError(Ljava/lang/String;)(provider); return; }
      bridge.superrChatForgetKey(provider).then(function(s) {
         self.@org.rstudio.studio.client.workbench.views.superrstudio.ChatAiPane::onStatus(Ljava/lang/String;ZLjava/lang/String;)(provider, !!s.installed, s.authentication);
      }, function() { self.@org.rstudio.studio.client.workbench.views.superrstudio.ChatAiPane::onError(Ljava/lang/String;)(provider); });
   }-*/;
   private native void loadModels(String provider) /*-{
      var self = this, bridge = $wnd.desktop;
      if (!bridge || !bridge.superrChatModels) { self.@org.rstudio.studio.client.workbench.views.superrstudio.ChatAiPane::onError(Ljava/lang/String;)(provider); return; }
      bridge.superrChatModels(provider).then(function(r) {
         if (!r || !r.ok) { self.@org.rstudio.studio.client.workbench.views.superrstudio.ChatAiPane::onModelsFailed(Ljava/lang/String;)((r && r.kind) || ''); return; }
         self.@org.rstudio.studio.client.workbench.views.superrstudio.ChatAiPane::clearModels()();
         for (var i = 0; i < r.models.length; i++)
            self.@org.rstudio.studio.client.workbench.views.superrstudio.ChatAiPane::addModel(Ljava/lang/String;Ljava/lang/String;)(r.models[i].id, r.models[i].label);
         if (!r.models.length) self.@org.rstudio.studio.client.workbench.views.superrstudio.ChatAiPane::onModelsFailed(Ljava/lang/String;)('ok');
      }, function() { self.@org.rstudio.studio.client.workbench.views.superrstudio.ChatAiPane::onError(Ljava/lang/String;)(provider); });
   }-*/;
   private native void newChat(String provider) /*-{
      var bridge = $wnd.desktop;
      if (bridge && bridge.superrChatNew) bridge.superrChatNew(provider).then(function(){}, function(){});
   }-*/;
   private native void send(String provider, String message, String model, String turn) /*-{
      var self = this, bridge = $wnd.desktop;
      if (!bridge || !bridge.superrChatSend) { self.@org.rstudio.studio.client.workbench.views.superrstudio.ChatAiPane::onSendFailed(Ljava/lang/String;)(provider); return; }
      bridge.superrChatSend(provider, message, model, turn).then(function(r) {
         if (r && typeof r.status === 'string')
            self.@org.rstudio.studio.client.workbench.views.superrstudio.ChatAiPane::onSendResult(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)(turn, r.status, r.kind || '', r.finishReason || '');
      }, function() { self.@org.rstudio.studio.client.workbench.views.superrstudio.ChatAiPane::onSendFailed(Ljava/lang/String;)(provider); });
   }-*/;
   private native void cancel(String provider) /*-{
      var self = this, bridge = $wnd.desktop;
      if (!bridge || !bridge.superrChatCancel) { self.@org.rstudio.studio.client.workbench.views.superrstudio.ChatAiPane::onError(Ljava/lang/String;)(provider); return; }
      bridge.superrChatCancel(provider).then(function(){}, function(){ self.@org.rstudio.studio.client.workbench.views.superrstudio.ChatAiPane::onNoTurn(Ljava/lang/String;)(provider); });
   }-*/;
   private static String text(String es, String en) { return SuperRStudioLanguage.spanish() ? es : en; }

   private static final String GEMINI_API = "gemini-api";
   private static final int HEADER_SMALL = 190;
   private static final int HEADER_LARGE = 470;
   private final Label status_;
   private final ListBox providers_;
   private final ListBox models_;
   private final TextArea prompt_;
   private final Button connect_;
   private final Button signIn_;
   private final VerticalPanel setup_;
   private final PasswordTextBox keyBox_;
   private final HorizontalPanel modelRow_;
   private final ScrollPanel header_;
   private final FlowPanel conversation_;
   private final ScrollPanel scroll_;
   private Label answer_;
   private String turn_ = "";
   private String previousModel_ = "";
   private int turnCount_;
   private boolean busy_;
}
