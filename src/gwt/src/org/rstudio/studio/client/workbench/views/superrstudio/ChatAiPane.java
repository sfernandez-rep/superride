// Copyright (C) 2026 SuperR contributors. SPDX-License-Identifier: AGPL-3.0-only
package org.rstudio.studio.client.workbench.views.superrstudio;

import com.google.gwt.core.client.Scheduler;
import com.google.gwt.dom.client.Element;
import com.google.gwt.dom.client.Style.Unit;
import com.google.gwt.dom.client.StyleInjector;
import com.google.gwt.event.dom.client.ClickHandler;
import com.google.gwt.event.dom.client.KeyCodes;
import com.google.gwt.user.client.Timer;
import com.google.gwt.user.client.ui.Button;
import com.google.gwt.user.client.ui.DockLayoutPanel;
import com.google.gwt.user.client.ui.FlowPanel;
import com.google.gwt.user.client.ui.HTMLPanel;
import com.google.gwt.user.client.ui.Label;
import com.google.gwt.user.client.ui.ListBox;
import com.google.gwt.user.client.ui.PasswordTextBox;
import com.google.gwt.user.client.ui.ScrollPanel;
import com.google.gwt.user.client.ui.TextArea;

import org.rstudio.studio.client.RStudioGinjector;
import org.rstudio.studio.client.application.Desktop;
import org.rstudio.studio.client.workbench.views.source.editors.text.DocDisplay;

/**
 * Chat IA sidebar. The Gemini API mode chats with the user's own Google AI
 * Studio key (text only: no project files, commands or edits); the agent
 * providers (Antigravity, Codex) fail closed until their isolation is verified.
 * The state shown comes from the provider's real responses: a saved key is
 * checked with Google before "connected" is shown, and quota or connection
 * failures are reported as such.
 */
public class ChatAiPane extends DockLayoutPanel
{
   private enum State { NOT_CONFIGURED, VERIFYING, CONNECTED, GENERATING, ERROR, QUOTA, DISCONNECTED, UNAVAILABLE }

   public ChatAiPane(Runnable close)
   {
      super(Unit.PX);
      setSize("100%", "100%");
      getElement().setId("superr_chat_ai_panel");
      injectStyles();

      // header: title, state and actions; provider and model; connection panel; notice
      header_ = new FlowPanel();
      header_.addStyleName("superr-chat-header");
      FlowPanel row1 = new FlowPanel();
      row1.addStyleName("superr-chat-row superr-chat-nowrap");
      Label title = new Label("Chat IA");
      title.addStyleName("superr-chat-title");
      row1.add(title);
      state_ = new Label();
      state_.addStyleName("superr-chat-state");
      state_.getElement().setId("superr_chat_ai_state");
      row1.add(state_);
      Label spacer = new Label();
      spacer.addStyleName("superr-chat-spacer");
      row1.add(spacer);
      newChat_ = iconButton("+", text("Nueva conversación", "New conversation"), "superr_chat_ai_new", () -> newConversation());
      row1.add(newChat_);
      manage_ = iconButton("⚙", text("Gestionar conexión", "Manage connection"), "superr_chat_ai_manage", () -> toggleManage());
      row1.add(manage_);
      row1.add(iconButton("✕", text("Cerrar", "Close"), "superr_chat_ai_close", close));
      header_.add(row1);

      FlowPanel row2 = new FlowPanel();
      row2.addStyleName("superr-chat-row superr-chat-nowrap");
      providers_ = new ListBox();
      providers_.addItem(text("Gemini API (gratis)", "Gemini API (free)"), GEMINI_API);
      providers_.addItem("Gemini (Antigravity)", "gemini");
      providers_.addItem("Codex", "codex");
      providers_.addStyleName("superr-chat-select");
      providers_.getElement().setId("superr_chat_ai_provider");
      providers_.getElement().setAttribute("aria-label", text("Proveedor", "Provider"));
      providers_.setTitle(text("Proveedor", "Provider"));
      row2.add(providers_);
      models_ = new ListBox();
      models_.addStyleName("superr-chat-select");
      models_.getElement().setId("superr_chat_ai_model");
      models_.getElement().setAttribute("aria-label", text("Modelo de Gemini", "Gemini model"));
      models_.setTitle(text("Modelo de Gemini (con nivel gratuito según Google)", "Gemini model (free tier according to Google)"));
      models_.addChangeHandler(e -> store(MODEL_KEY, models_.getSelectedValue()));
      row2.add(models_);
      header_.add(row2);

      setup_ = new FlowPanel();
      setup_.addStyleName("superr-chat-setup");
      setup_.getElement().setId("superr_chat_ai_gemini_setup");
      header_.add(setup_);
      buildGeminiSetup();
      agentSetup_ = new FlowPanel();
      agentSetup_.addStyleName("superr-chat-setup");
      agentSetup_.getElement().setId("superr_chat_ai_agent_setup");
      header_.add(agentSetup_);
      buildAgentSetup();

      status_ = new Label();
      status_.addStyleName("superr-chat-notice");
      status_.getElement().setId("superr_chat_ai_status");
      status_.getElement().setAttribute("role", "status");
      header_.add(status_);
      headerScroll_ = new ScrollPanel(header_);
      addNorth(headerScroll_, 64);

      // composer
      FlowPanel composer = new FlowPanel();
      composer.addStyleName("superr-chat-composer");
      prompt_ = new TextArea();
      prompt_.addStyleName("superr-chat-prompt");
      prompt_.setVisibleLines(2);
      prompt_.getElement().setId("superr_chat_ai_prompt");
      prompt_.getElement().setAttribute("aria-label", text("Mensaje", "Message"));
      prompt_.getElement().setAttribute("placeholder", text("Escribe un mensaje… (Enter envía, Shift+Enter nueva línea)",
            "Write a message… (Enter sends, Shift+Enter new line)"));
      prompt_.addKeyDownHandler(e -> {
         if (e.getNativeKeyCode() == KeyCodes.KEY_ENTER && !e.isShiftKeyDown() && !isComposing(e.getNativeEvent()))
         {
            e.preventDefault();
            sendMessage();
         }
      });
      prompt_.addKeyUpHandler(e -> composerChanged());
      prompt_.addChangeHandler(e -> composerChanged());
      composer.add(prompt_);
      FlowPanel actions = new FlowPanel();
      actions.addStyleName("superr-chat-row superr-chat-nowrap");
      hint_ = new Label(text("Solo texto: no lee el proyecto ni ejecuta comandos.", "Text only: no project access or commands."));
      hint_.addStyleName("superr-chat-hint");
      actions.add(hint_);
      cancel_ = new Button(text("Detener", "Stop"), (ClickHandler)e -> cancel(provider()));
      cancel_.addStyleName("superr-chat-button");
      cancel_.getElement().setId("superr_chat_ai_cancel");
      actions.add(cancel_);
      send_ = new Button(text("Enviar", "Send"), (ClickHandler)e -> sendMessage());
      send_.addStyleName("superr-chat-button superr-chat-primary");
      send_.getElement().setId("superr_chat_ai_send");
      actions.add(send_);
      composer.add(actions);
      actions_ = actions;
      composer_ = composer;
      addSouth(composer_, 96);

      // conversation
      conversation_ = new FlowPanel();
      conversation_.addStyleName("superr-chat-messages");
      conversation_.getElement().setId("superr_chat_ai_messages");
      scroll_ = new ScrollPanel(conversation_);
      scroll_.getElement().setId("superr_chat_ai_conversation");
      scroll_.getElement().setAttribute("aria-label", text("Conversación", "Conversation"));
      add(scroll_);
      showWelcome();

      markdown_ = new ChatMarkdown(new ChatMarkdown.Actions()
      {
         @Override public void copy(String code) { copyToClipboard(code); }
         @Override public void insert(String code) { insertInEditor(code); }
         @Override public void openLink(String url) { openUrl(url); }
      }, SuperRStudioLanguage.spanish());
      renderTimer_ = new Timer()
      {
         @Override public void run() { renderAnswer(); }
      };
      String savedProvider = load(PROVIDER_KEY);
      for (int i = 0; i < providers_.getItemCount(); i++)
         if (providers_.getValue(i).equals(savedProvider)) providers_.setSelectedIndex(i);
      previousModel_ = load(MODEL_KEY);
      providers_.addChangeHandler(e -> providerChanged());
      listen();
      providerChanged();
   }

   // ---- construction -------------------------------------------------------

   private void buildGeminiSetup()
   {
      Label privacy = new Label(text(
            "Privacidad: en el nivel gratuito, Google puede usar tus mensajes y las respuestas para mejorar sus productos, " +
            "y revisores humanos pueden leerlos. No envíes datos personales, confidenciales ni sensibles.",
            "Privacy: on the free tier, Google may use your messages and the responses to improve its products, " +
            "and human reviewers may read them. Do not send personal, confidential or sensitive information."));
      privacy.getElement().setId("superr_chat_ai_privacy");
      privacy.addStyleName("superr-chat-note");
      setup_.add(privacy);
      Label steps = new Label(text(
            "Crea una clave de API en Google AI Studio, en un proyecto sin facturación (SuperR no pide tarjeta ni activa " +
            "facturación), y pégala aquí. Se guarda cifrada con el almacén de credenciales del sistema y no se vuelve a mostrar.",
            "Create an API key in Google AI Studio, in a project without billing (SuperR asks for no card and never enables " +
            "billing), and paste it here. It is stored encrypted with the system's credential storage and never shown again."));
      steps.addStyleName("superr-chat-note");
      setup_.add(steps);
      FlowPanel links = new FlowPanel();
      links.addStyleName("superr-chat-row");
      links.add(smallButton(text("Abrir Google AI Studio", "Open Google AI Studio"), "superr_chat_ai_open_key_page",
            () -> openPage(GEMINI_API, "key")));
      links.add(smallButton(text("Ver límites de mi proyecto", "View my project's limits"), "superr_chat_ai_open_limits",
            () -> openPage(GEMINI_API, "limits")));
      setup_.add(links);
      keyBox_ = new PasswordTextBox();
      keyBox_.addStyleName("superr-chat-key");
      keyBox_.getElement().setId("superr_chat_ai_key");
      keyBox_.getElement().setAttribute("placeholder", text("Pega tu clave de API", "Paste your API key"));
      keyBox_.getElement().setAttribute("aria-label", text("Clave de API de Google AI Studio", "Google AI Studio API key"));
      keyBox_.getElement().setAttribute("autocomplete", "off");
      keyBox_.getElement().setAttribute("spellcheck", "false");
      keyBox_.addKeyDownHandler(e -> { if (e.getNativeKeyCode() == KeyCodes.KEY_ENTER) { e.preventDefault(); saveKey(); } });
      setup_.add(keyBox_);
      FlowPanel keyButtons = new FlowPanel();
      keyButtons.addStyleName("superr-chat-row");
      saveKey_ = smallButton(text("Guardar clave", "Save key"), "superr_chat_ai_save_key", () -> saveKey());
      keyButtons.add(saveKey_);
      forgetKey_ = smallButton(text("Quitar clave", "Remove key"), "superr_chat_ai_forget_key", () -> {
         notice(text("Quitando la clave…", "Removing the key…"));
         forgetKey(GEMINI_API);
      });
      keyButtons.add(forgetKey_);
      setup_.add(keyButtons);
   }

   private void buildAgentSetup()
   {
      agentNote_ = new Label();
      agentNote_.addStyleName("superr-chat-note");
      agentSetup_.add(agentNote_);
      signIn_ = smallButton(text("Iniciar sesión con ChatGPT", "Sign in with ChatGPT"), "superr_chat_ai_sign_in", () -> {
         if ("gemini".equals(provider())) { onGoogleNotOffered(); return; }
         notice(text("Esperando el inicio de sesión en el navegador…", "Waiting for sign-in in the browser…"));
         signIn(provider());
      });
      agentSetup_.add(signIn_);
   }

   private Button iconButton(String icon, String title, String id, Runnable action)
   {
      Button button = new Button(icon, (ClickHandler)e -> action.run());
      button.addStyleName("superr-chat-icon");
      button.setTitle(title);
      button.getElement().setAttribute("aria-label", title);
      button.getElement().setId(id);
      return button;
   }

   private Button smallButton(String label, String id, Runnable action)
   {
      Button button = new Button(label, (ClickHandler)e -> action.run());
      button.addStyleName("superr-chat-button");
      button.getElement().setId(id);
      return button;
   }

   // ---- state --------------------------------------------------------------

   private String provider() { return providers_.getValue(providers_.getSelectedIndex()); }
   private boolean geminiApi() { return GEMINI_API.equals(provider()); }

   private void providerChanged()
   {
      store(PROVIDER_KEY, provider());
      manageOpen_ = false;
      boolean api = geminiApi();
      models_.setVisible(api);
      newChat_.setVisible(api);
      hint_.setVisible(api);
      if (api)
      {
         setState(State.VERIFYING, "");
         refresh(GEMINI_API);
      }
      else
      {
         agentNote_.setText("gemini".equals(provider()) ? googleNotOfferedText() :
               text("Codex usa tu cuenta de ChatGPT. El chat sigue deshabilitado hasta verificar el aislamiento de solo lectura del agente.",
                    "Codex uses your ChatGPT account. Chat stays disabled until the agent's read-only isolation is verified."));
         signIn_.setVisible("codex".equals(provider()));
         setState(State.UNAVAILABLE, text("Comprobando…", "Checking…"));
         refresh(provider());
      }
   }

   private void setState(State state, String detail)
   {
      currentState_ = state;
      String label;
      String css;
      switch (state)
      {
         case NOT_CONFIGURED: label = text("Sin configurar", "Not configured"); css = "idle"; break;
         case VERIFYING: label = text("Verificando…", "Checking…"); css = "busy"; break;
         case CONNECTED: label = text("Gemini conectado", "Gemini connected"); css = "ok"; break;
         case GENERATING: label = text("Generando…", "Generating…"); css = "busy"; break;
         case QUOTA: label = text("Cuota agotada", "Quota exhausted"); css = "warn"; break;
         case DISCONNECTED: label = text("Sin conexión", "Offline"); css = "warn"; break;
         case UNAVAILABLE: label = text("No disponible", "Unavailable"); css = "idle"; break;
         default: label = "Error"; css = "error"; break;
      }
      state_.setText(label);
      state_.getElement().setAttribute("data-state", css);
      state_.setTitle(detail);
      notice(detail);
      boolean api = geminiApi();
      boolean generating = state == State.GENERATING;
      cancel_.setVisible(generating);
      send_.setVisible(!generating);
      models_.setEnabled(!generating);
      providers_.setEnabled(!generating);
      setup_.setVisible(api && (state == State.NOT_CONFIGURED || manageOpen_));
      agentSetup_.setVisible(!api && manageOpen_);
      saveKey_.setText(state == State.NOT_CONFIGURED ? text("Guardar clave", "Save key") : text("Cambiar clave", "Change key"));
      forgetKey_.setVisible(state != State.NOT_CONFIGURED);
      manage_.getElement().setAttribute("aria-expanded", manageOpen_ ? "true" : "false");
      composerChanged();
      relayout();
   }

   private boolean canSend()
   {
      if (!geminiApi() || busy_ || models_.getItemCount() == 0) return false;
      return currentState_ == State.CONNECTED || currentState_ == State.QUOTA || currentState_ == State.DISCONNECTED ||
             currentState_ == State.ERROR;
   }

   private void notice(String detail)
   {
      status_.setText(detail == null ? "" : detail);
      status_.setVisible(detail != null && !detail.isEmpty());
      relayout();
   }

   private void toggleManage()
   {
      manageOpen_ = !manageOpen_;
      setState(currentState_, status_.getText());
      if (manageOpen_ && geminiApi()) keyBox_.setFocus(true);
   }

   private void relayout()
   {
      Scheduler.get().scheduleDeferred(() -> {
         int available = Math.max(getOffsetHeight(), 300);
         int header = Math.min(header_.getOffsetHeight() + 2, available / 2);
         setWidgetSize(headerScroll_, Math.max(header, 40));
      });
   }

   private void composerChanged()
   {
      boolean empty = prompt_.getText().trim().isEmpty();
      send_.setEnabled(!empty && canSend());
      Element area = prompt_.getElement();
      area.getStyle().setProperty("height", "auto");
      int height = Math.max(40, Math.min(area.getScrollHeight() + 2, 170));
      area.getStyle().setHeight(height, Unit.PX);
      int total = height + Math.max(actions_.getOffsetHeight(), 26) + 18;
      if (total != composerHeight_)
      {
         composerHeight_ = total;
         setWidgetSize(composer_, total);
      }
   }

   @Override
   public void onResize()
   {
      super.onResize();
      relayout();
      composerChanged();
   }

   // ---- Gemini API ---------------------------------------------------------

   private void saveKey()
   {
      if (keyBox_.getText().trim().isEmpty())
      {
         notice(text("Pega primero tu clave de API.", "Paste your API key first."));
         return;
      }
      setState(State.VERIFYING, text("Comprobando la clave con Google…", "Checking the key with Google…"));
      setKey(GEMINI_API, keyBox_.getText());
   }

   private void onKeySaved(boolean ok, String kind)
   {
      if (!ok)
      {
         // the earlier saved key, if any, is untouched
         refresh(GEMINI_API);
         pendingNotice_ = errorText(kind, "", "", 0);
         return;
      }
      keyBox_.setText("");
      manageOpen_ = false;
      refresh(GEMINI_API);
   }

   /** A saved key is only "connected" after Google accepted it again (models.list costs no generation quota). */
   private void onStatus(String provider, boolean installed, String authentication)
   {
      if (!provider.equals(provider())) return;
      if (GEMINI_API.equals(provider))
      {
         if ("connected".equals(authentication))
         {
            setState(State.VERIFYING, text("Comprobando la conexión con Google…", "Checking the connection with Google…"));
            loadModels(GEMINI_API);
         }
         else
         {
            models_.clear();
            setState(State.NOT_CONFIGURED, takeNotice(text("Conecta Gemini con tu propia clave gratuita de Google AI Studio.",
                  "Connect Gemini with your own free Google AI Studio key.")));
         }
         return;
      }
      String install = installed ? text("instalado", "installed") : text("no detectado en PATH", "not found on PATH");
      String auth = "connected".equals(authentication) ? text("cuenta conectada", "account connected") :
            "signed_out".equals(authentication) ? text("sin iniciar sesión", "signed out") : text("autenticación desconocida", "authentication unknown");
      String name = "codex".equals(provider) ? "Codex" : "Antigravity";
      setState(State.UNAVAILABLE, name + ": " + install + " · " + auth + " · " +
            text("chat deshabilitado: aislamiento de solo lectura sin verificar", "chat disabled: read-only isolation not verified"));
   }

   private void clearModels()
   {
      if (models_.getItemCount() > 0) previousModel_ = models_.getSelectedValue();
      models_.clear();
   }

   private void addModel(String id, String label)
   {
      models_.addItem(label, id);
      if (id.equals(previousModel_)) models_.setSelectedIndex(models_.getItemCount() - 1);
   }

   private void onModels(boolean ok, String kind)
   {
      if (!geminiApi()) return;
      if (ok && models_.getItemCount() > 0)
      {
         String selected = models_.getSelectedValue();
         String message = takeNotice(text("Listo. Tus mensajes van a Google con tu clave; los límites dependen de tu proyecto.",
               "Ready. Your messages go to Google with your key; limits depend on your project."));
         if (!previousModel_.isEmpty() && !previousModel_.equals(selected))
            message = text("El modelo elegido antes (", "The previously chosen model (") + previousModel_ +
                  text(") ya no está disponible para tu clave; se seleccionó ", ") is no longer available for your key; selected ") +
                  models_.getSelectedItemText() + ".";
         store(MODEL_KEY, selected);
         setState(State.CONNECTED, message);
      }
      else if (ok)
         setState(State.ERROR, text("Tu clave no tiene acceso a ningún modelo de texto con nivel gratuito.",
               "Your key has no access to any free-tier text model."));
      else if ("connection".equals(kind))
         setState(State.DISCONNECTED, text("Clave guardada, pero no se pudo contactar a Google. Revisa la conexión o el proxy.",
               "Key saved, but Google could not be reached. Check the connection or proxy."));
      else if ("unavailable".equals(kind))
         setState(State.DISCONNECTED, errorText(kind, "", "", 0));
      else if ("no_key".equals(kind))
         setState(State.NOT_CONFIGURED, "");
      else
      {
         manageOpen_ = "invalid_key".equals(kind);
         setState(State.ERROR, errorText(kind, "", "", 0));
      }
   }

   private void newConversation()
   {
      boolean wasBusy = busy_;
      busy_ = false;
      turn_ = "";
      answer_ = null;
      renderTimer_.cancel();
      conversation_.clear();
      showWelcome();
      newChat(GEMINI_API);
      if (currentState_ == State.GENERATING || wasBusy)
         setState(State.CONNECTED, text("Respuesta cancelada. Nueva conversación.", "Response cancelled. New conversation."));
      else
         notice(text("Nueva conversación.", "New conversation."));
      composerChanged();
   }

   private void sendMessage()
   {
      String message = prompt_.getText().trim();
      if (message.isEmpty() || !canSend())
      {
         if (busy_) notice(errorText("busy", "", "", 0));
         return;
      }
      busy_ = true;
      if (welcome_ != null) { welcome_.removeFromParent(); welcome_ = null; }
      turn_ = "t" + (++turnCount_);
      addUserMessage(message);
      answerText_ = new StringBuilder();
      answer_ = addModelMessage();
      prompt_.setText("");
      setState(State.GENERATING, text("Gemini está respondiendo con ", "Gemini is answering with ") + models_.getSelectedItemText() + "…");
      send(GEMINI_API, message, models_.getSelectedValue(), turn_);
   }

   private void addUserMessage(String message)
   {
      FlowPanel item = new FlowPanel();
      item.addStyleName("superr-chat-msg superr-chat-user");
      Label who = new Label(text("Tú", "You"));
      who.addStyleName("superr-chat-who");
      item.add(who);
      Label body = new Label(message);
      body.addStyleName("superr-chat-user-text");
      item.add(body);
      conversation_.add(item);
      scroll_.scrollToBottom();
   }

   private HTMLPanel addModelMessage()
   {
      FlowPanel item = new FlowPanel();
      item.addStyleName("superr-chat-msg superr-chat-model");
      Label who = new Label("Gemini · " + models_.getSelectedItemText());
      who.addStyleName("superr-chat-who");
      item.add(who);
      HTMLPanel body = new HTMLPanel("");
      body.addStyleName("superr-chat-answer");
      body.getElement().setId("superr_chat_ai_answer_" + turnCount_);
      Label typing = new Label("…");
      typing.addStyleName("superr-chat-typing");
      body.add(typing);
      item.add(body);
      conversation_.add(item);
      scroll_.scrollToBottom();
      return body;
   }

   private void showWelcome()
   {
      welcome_ = new Label(text(
            "Pregúntale a Gemini sobre R, ggplot2 o TropFishR. Las respuestas con código traen botones para copiarlo o " +
            "insertarlo en el script abierto.",
            "Ask Gemini about R, ggplot2 or TropFishR. Answers with code have buttons to copy it or insert it into the open script."));
      welcome_.addStyleName("superr-chat-welcome");
      conversation_.add(welcome_);
   }

   private void onDelta(String turn, String delta)
   {
      if (answer_ == null || !turn.equals(turn_)) return;
      answerText_.append(delta);
      // render at most every 60 ms; only the current answer is rebuilt
      if (!renderTimer_.isRunning()) renderTimer_.schedule(60);
   }

   private void renderAnswer()
   {
      if (answer_ == null) return;
      boolean atBottom = scroll_.getVerticalScrollPosition() + scroll_.getOffsetHeight() >=
            scroll_.getMaximumVerticalScrollPosition() + scroll_.getOffsetHeight() - 40;
      Element body = answer_.getElement();
      while (body.getFirstChild() != null) body.removeChild(body.getFirstChild());
      body.appendChild(markdown_.render(answerText_.toString()));
      if (atBottom) scroll_.scrollToBottom();
   }

   private void onSendResult(String turn, String status, String kind, String finishReason,
                             String quotaScope, String quotaLimit, int retryAfter)
   {
      if (!turn.equals(turn_)) return;
      busy_ = false;
      renderTimer_.cancel();
      renderAnswer();
      boolean empty = answerText_ == null || answerText_.length() == 0;
      if ("completed".equals(status))
      {
         if (empty) setAnswerNote(text("(Gemini no devolvió texto)", "(Gemini returned no text)"));
         setState(State.CONNECTED, text("Respuesta recibida.", "Response received."));
      }
      else if ("cancelled".equals(status))
      {
         appendAnswerNote(text("Respuesta detenida.", "Response stopped."));
         setState(State.CONNECTED, text("Respuesta detenida.", "Response stopped."));
      }
      else if ("incomplete".equals(status))
      {
         appendAnswerNote(text("Respuesta incompleta (", "Incomplete response (") + finishReason + ").");
         setState(State.CONNECTED, text("Respuesta incompleta (", "Incomplete response (") + finishReason + ").");
      }
      else
      {
         String message = errorText(kind, quotaScope, quotaLimit, retryAfter);
         if (empty) setAnswerNote(message); else appendAnswerNote(message);
         if ("quota".equals(kind)) setState(State.QUOTA, message);
         else if ("connection".equals(kind) || "unavailable".equals(kind)) setState(State.DISCONNECTED, message);
         else if ("invalid_key".equals(kind) || "no_key".equals(kind)) { manageOpen_ = true; setState(State.ERROR, message); }
         else if ("model".equals(kind)) { setState(State.ERROR, message); loadModels(GEMINI_API); }
         else setState(State.ERROR, message);
      }
      answer_ = null;
      composerChanged();
   }

   private void setAnswerNote(String note)
   {
      if (answer_ == null) return;
      Element body = answer_.getElement();
      while (body.getFirstChild() != null) body.removeChild(body.getFirstChild());
      appendAnswerNote(note);
   }

   private void appendAnswerNote(String note)
   {
      if (answer_ == null) return;
      Label label = new Label(note);
      label.addStyleName("superr-chat-answer-note");
      answer_.add(label);
   }

   private void onSendFailed(String provider)
   {
      busy_ = false;
      answer_ = null;
      setState(State.ERROR, text("No se pudo enviar el mensaje (puente del escritorio no disponible).",
            "The message could not be sent (desktop bridge unavailable)."));
   }

   private void onError(String provider)
   {
      if (!provider.equals(provider())) return;
      if (geminiApi())
         setState(State.ERROR, text("No disponible. Comprueba el almacenamiento seguro de credenciales del sistema.",
               "Unavailable. Check the system's secure credential storage."));
      else
         setState(State.UNAVAILABLE, text("No disponible. Comprueba la instalación y el almacenamiento seguro de credenciales.",
               "Unavailable. Check installation and secure credential storage."));
   }

   // Antigravity's terms and FAQ do not support its consumer (personal Google
   // account) login inside third-party applications; see chat-ia.md.
   private void onGoogleNotOffered() { notice(googleNotOfferedText()); }
   private static String googleNotOfferedText()
   {
      return text("Inicio de sesión con una cuenta personal de Google no disponible: los términos de Antigravity " +
            "no admiten su uso desde aplicaciones de terceros con planes de consumo. Usa «Gemini API (gratis)».",
            "Personal Google account sign-in is not available: Antigravity's terms do not support it in " +
            "third-party applications on consumer plans. Use \"Gemini API (free)\".");
   }
   private void onNoTurn(String provider)
   {
      if (provider.equals(provider()))
         notice(text("No hay ninguna respuesta en curso.", "No response is in progress."));
   }

   private String takeNotice(String fallback)
   {
      String result = pendingNotice_ != null ? pendingNotice_ : fallback;
      pendingNotice_ = null;
      return result;
   }

   private static String errorText(String kind, String quotaScope, String quotaLimit, int retryAfter)
   {
      switch (kind == null ? "" : kind)
      {
         case "invalid_key": return text("La clave de API no es válida. Comprueba que la copiaste completa o crea otra en Google AI Studio.",
               "The API key is not valid. Check that you copied all of it, or create another in Google AI Studio.");
         case "quota":
         {
            String scope = "day".equals(quotaScope) ?
                  text("Se alcanzó el límite diario de solicitudes de tu proyecto para este modelo", "Your project's daily request limit for this model was reached") :
                  "minute".equals(quotaScope) ?
                  text("Se alcanzó el límite por minuto de tu proyecto para este modelo", "Your project's per-minute limit for this model was reached") :
                  text("Cuota agotada o demasiadas solicitudes", "Quota exhausted or too many requests");
            if (quotaLimit != null && !quotaLimit.isEmpty())
               scope += text(" (límite informado por Google: ", " (limit reported by Google: ") + quotaLimit + ")";
            scope += ".";
            if (retryAfter > 0)
               scope += text(" Google indica reintentar en ", " Google says to retry in ") + retryAfter + " s.";
            return scope + text(" Puedes elegir otro modelo o ver los límites de tu proyecto en Google AI Studio.",
                  " You can choose another model or view your project's limits in Google AI Studio.");
         }
         case "verification": return text("Google pide verificar tu proyecto antes de usar el nivel gratuito. Hazlo en Google AI Studio.",
               "Google asks you to verify your project before using the free tier. Do it in Google AI Studio.");
         case "permission": return text("Google denegó el acceso para esta clave o su proyecto.", "Google denied access for this key or its project.");
         case "billing": return text("El proyecto de esta clave usa facturación prepaga sin saldo. Para no pagar, usa una clave de un proyecto sin facturación.",
               "This key's project uses prepaid billing with no balance. To stay free, use a key from a project without billing.");
         case "region": return text("La API de Gemini no está disponible en tu región.", "The Gemini API is not available in your region.");
         case "model": return text("Ese modelo ya no está disponible para tu clave. Elige otro en la lista.",
               "That model is no longer available for your key. Choose another in the list.");
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

   // ---- code actions -------------------------------------------------------

   private void copyToClipboard(String code)
   {
      if (Desktop.hasDesktopFrame()) Desktop.getFrame().setClipboardText(code);
      else copyInBrowser(code);
      notice(text("Código copiado al portapapeles.", "Code copied to the clipboard."));
   }

   /** Inserts at the cursor of the active script through the editor, so Ctrl+Z undoes it. */
   private void insertInEditor(String code)
   {
      RStudioGinjector.INSTANCE.getSourceColumnManager().withTarget("", target -> target.ensureTextEditorActive(() -> {
         DocDisplay display = target.getDocDisplay();
         display.insertCode(code);
         display.focus();
         notice(text("Código insertado en ", "Code inserted into ") + target.getName().getValue() +
               text(" (Ctrl+Z lo deshace).", " (Ctrl+Z undoes it)."));
      }), () -> notice(text("Abre un script o documento de texto en el editor para insertar el código.",
            "Open a script or text document in the editor to insert the code.")));
   }

   private void openUrl(String url)
   {
      if (!ChatMarkdown.safeUrl(url)) return;
      if (Desktop.hasDesktopFrame()) Desktop.getFrame().browseUrl(url);
      else RStudioGinjector.INSTANCE.getGlobalDisplay().openWindow(url);
   }

   // ---- styles -------------------------------------------------------------

   private static void injectStyles()
   {
      if (stylesInjected_) return;
      stylesInjected_ = true;
      StyleInjector.inject(
         "#superr_chat_ai_panel { font-size: 13px; background: #ffffff; color: #1f2328; }" +
         "#superr_chat_ai_panel .superr-chat-header { padding: 6px 8px 4px 8px; border-bottom: 1px solid rgba(128,128,128,0.25); }" +
         "#superr_chat_ai_panel .superr-chat-row { display: flex; align-items: center; gap: 6px; flex-wrap: wrap; margin: 2px 0; }" +
         "#superr_chat_ai_panel .superr-chat-row.superr-chat-nowrap { flex-wrap: nowrap; }" +
         "#superr_chat_ai_panel .superr-chat-title { font-weight: 600; white-space: nowrap; }" +
         "#superr_chat_ai_panel .superr-chat-icon, #superr_chat_ai_panel .superr-chat-button { flex: 0 0 auto; }" +
         "#superr_chat_ai_panel .superr-chat-spacer { flex: 1 1 auto; }" +
         "#superr_chat_ai_panel .superr-chat-state { font-size: 11px; padding: 1px 8px; border-radius: 10px; background: rgba(128,128,128,0.15); white-space: nowrap; min-width: 0; overflow: hidden; text-overflow: ellipsis; }" +
         "#superr_chat_ai_panel .superr-chat-state::before { content: '● '; }" +
         "#superr_chat_ai_panel .superr-chat-state[data-state=ok]::before { color: #2da44e; }" +
         "#superr_chat_ai_panel .superr-chat-state[data-state=busy]::before { color: #3b82f6; }" +
         "#superr_chat_ai_panel .superr-chat-state[data-state=warn]::before { color: #d97706; }" +
         "#superr_chat_ai_panel .superr-chat-state[data-state=error]::before { color: #d1242f; }" +
         "#superr_chat_ai_panel .superr-chat-state[data-state=idle]::before { color: #8c959f; }" +
         "#superr_chat_ai_panel .superr-chat-icon { min-width: 26px; height: 24px; padding: 0 6px; border: 1px solid transparent; background: transparent; color: inherit; border-radius: 4px; cursor: pointer; font-size: 14px; line-height: 20px; }" +
         "#superr_chat_ai_panel .superr-chat-icon:hover { background: rgba(128,128,128,0.18); }" +
         "#superr_chat_ai_panel .superr-chat-select { flex: 1 1 90px; min-width: 0; width: 0; height: 24px; }" +
         "#superr_chat_ai_panel .superr-chat-setup { margin-top: 6px; padding: 6px; border: 1px solid rgba(128,128,128,0.3); border-radius: 6px; }" +
         "#superr_chat_ai_panel .superr-chat-note { font-size: 12px; opacity: 0.85; margin-bottom: 6px; }" +
         "#superr_chat_ai_panel .superr-chat-key { width: 100%; box-sizing: border-box; margin: 4px 0; }" +
         "#superr_chat_ai_panel .superr-chat-notice { font-size: 12px; margin-top: 4px; opacity: 0.9; }" +
         "#superr_chat_ai_panel .superr-chat-button { height: 24px; padding: 0 10px; border-radius: 4px; border: 1px solid rgba(128,128,128,0.5); background: transparent; color: inherit; cursor: pointer; }" +
         "#superr_chat_ai_panel .superr-chat-button:disabled { opacity: 0.45; cursor: default; }" +
         "#superr_chat_ai_panel .superr-chat-primary { background: #2f6fd6; border-color: #2f6fd6; color: #fff; }" +
         "#superr_chat_ai_panel .superr-chat-composer { padding: 6px 8px; border-top: 1px solid rgba(128,128,128,0.25); }" +
         "#superr_chat_ai_panel .superr-chat-prompt { width: 100%; box-sizing: border-box; resize: none; border-radius: 6px; padding: 6px; font: inherit; overflow-y: auto; }" +
         "#superr_chat_ai_panel .superr-chat-hint { font-size: 11px; opacity: 0.7; flex: 1 1 auto; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }" +
         "#superr_chat_ai_panel .superr-chat-messages { padding: 8px; }" +
         "#superr_chat_ai_panel .superr-chat-welcome { opacity: 0.7; margin: 16px 8px; text-align: center; }" +
         "#superr_chat_ai_panel .superr-chat-msg { margin: 0 0 12px 0; }" +
         "#superr_chat_ai_panel .superr-chat-who { font-size: 11px; font-weight: 600; opacity: 0.7; margin-bottom: 2px; }" +
         "#superr_chat_ai_panel .superr-chat-user-text { white-space: pre-wrap; background: rgba(47,111,214,0.10); border-radius: 8px; padding: 6px 8px; }" +
         "#superr_chat_ai_panel .superr-chat-answer { line-height: 1.45; overflow-wrap: anywhere; }" +
         "#superr_chat_ai_panel .superr-chat-answer-note { font-size: 12px; font-style: italic; opacity: 0.8; margin-top: 4px; }" +
         "#superr_chat_ai_panel .superr-chat-typing { opacity: 0.6; }" +
         "#superr_chat_ai_panel .superr-md p { margin: 0 0 8px 0; }" +
         "#superr_chat_ai_panel .superr-md h3, #superr_chat_ai_panel .superr-md h4, #superr_chat_ai_panel .superr-md h5, #superr_chat_ai_panel .superr-md h6 { margin: 10px 0 6px 0; font-size: 13px; font-weight: 700; }" +
         "#superr_chat_ai_panel .superr-md h3 { font-size: 15px; } #superr_chat_ai_panel .superr-md h4 { font-size: 14px; }" +
         "#superr_chat_ai_panel .superr-md ul, #superr_chat_ai_panel .superr-md ol { margin: 0 0 8px 0; padding-left: 20px; }" +
         "#superr_chat_ai_panel .superr-md li { margin: 2px 0; }" +
         "#superr_chat_ai_panel .superr-md code { font-family: 'Lucida Console', Consolas, monospace; font-size: 12px; background: rgba(128,128,128,0.15); border-radius: 3px; padding: 0 3px; }" +
         "#superr_chat_ai_panel .superr-md-code { margin: 6px 0 10px 0; border: 1px solid rgba(128,128,128,0.3); border-radius: 6px; overflow: hidden; }" +
         "#superr_chat_ai_panel .superr-md-code-bar { display: flex; align-items: center; gap: 6px; padding: 2px 6px; background: rgba(128,128,128,0.12); font-size: 11px; }" +
         "#superr_chat_ai_panel .superr-md-code-lang { flex: 1 1 auto; opacity: 0.8; }" +
         "#superr_chat_ai_panel .superr-md-button { font-size: 11px; border: 1px solid rgba(128,128,128,0.45); border-radius: 3px; background: transparent; color: inherit; padding: 0 6px; cursor: pointer; }" +
         "#superr_chat_ai_panel .superr-md-code pre { margin: 0; padding: 8px; overflow-x: auto; background: rgba(128,128,128,0.06); }" +
         "#superr_chat_ai_panel .superr-md-code pre code { background: transparent; padding: 0; white-space: pre; }" +
         "#superr_chat_ai_panel .superr-md-table { overflow-x: auto; margin: 6px 0 10px 0; }" +
         "#superr_chat_ai_panel .superr-md table { border-collapse: collapse; font-size: 12px; }" +
         "#superr_chat_ai_panel .superr-md th, #superr_chat_ai_panel .superr-md td { border: 1px solid rgba(128,128,128,0.4); padding: 3px 6px; text-align: left; }" +
         "#superr_chat_ai_panel .superr-md th { background: rgba(128,128,128,0.12); }" +
         "#superr_chat_ai_panel .superr-md blockquote { margin: 4px 0 8px 0; padding-left: 8px; border-left: 3px solid rgba(128,128,128,0.5); opacity: 0.9; }" +
         "#superr_chat_ai_panel .superr-md hr { border: 0; border-top: 1px solid rgba(128,128,128,0.35); margin: 8px 0; }" +
         "#superr_chat_ai_panel .superr-md-link { color: #2f6fd6; text-decoration: underline; cursor: pointer; }" +
         "#superr_chat_ai_panel .superr-tok-comment { color: #6a737d; font-style: italic; }" +
         "#superr_chat_ai_panel .superr-tok-string { color: #0a7d32; }" +
         "#superr_chat_ai_panel .superr-tok-number { color: #b35900; }" +
         "#superr_chat_ai_panel .superr-tok-keyword { color: #8a3ffc; font-weight: 600; }" +
         "#superr_chat_ai_panel .superr-tok-function { color: #1f5fbf; }" +
         "#superr_chat_ai_panel .superr-tok-operator { color: #c2185b; }" +
         ".rstudio-themes-dark #superr_chat_ai_panel { background: #1c1d20; color: #e6e6e6; }" +
         ".rstudio-themes-dark #superr_chat_ai_panel textarea, .rstudio-themes-dark #superr_chat_ai_panel input," +
         ".rstudio-themes-dark #superr_chat_ai_panel select { background: #292b30; color: #f0f0f0; border: 1px solid #5a5d63; }" +
         ".rstudio-themes-dark #superr_chat_ai_panel .superr-md-link { color: #79b0ff; }" +
         ".rstudio-themes-dark #superr_chat_ai_panel .superr-tok-comment { color: #8b949e; }" +
         ".rstudio-themes-dark #superr_chat_ai_panel .superr-tok-string { color: #7ee787; }" +
         ".rstudio-themes-dark #superr_chat_ai_panel .superr-tok-number { color: #ffa657; }" +
         ".rstudio-themes-dark #superr_chat_ai_panel .superr-tok-keyword { color: #d2a8ff; }" +
         ".rstudio-themes-dark #superr_chat_ai_panel .superr-tok-function { color: #79c0ff; }" +
         ".rstudio-themes-dark #superr_chat_ai_panel .superr-tok-operator { color: #ff7b72; }");
   }

   // ---- desktop bridge (JSNI) ----------------------------------------------

   private static native boolean isComposing(com.google.gwt.dom.client.NativeEvent event) /*-{
      return !!event.isComposing;
   }-*/;
   private static native void copyInBrowser(String text) /*-{
      if ($wnd.navigator.clipboard) $wnd.navigator.clipboard.writeText(text);
   }-*/;
   private static native String load(String key) /*-{
      try { return $wnd.localStorage.getItem(key) || ""; } catch (e) { return ""; }
   }-*/;
   private static native void store(String key, String value) /*-{
      try { $wnd.localStorage.setItem(key, value || ""); } catch (e) {}
   }-*/;
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
   private native void openPage(String provider, String page) /*-{
      var self = this, bridge = $wnd.desktop;
      if (!bridge || !bridge.superrChatOpenKeyPage) { self.@org.rstudio.studio.client.workbench.views.superrstudio.ChatAiPane::onError(Ljava/lang/String;)(provider); return; }
      bridge.superrChatOpenKeyPage(provider, page).then(function(){}, function() {
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
         if (r && r.ok) {
            self.@org.rstudio.studio.client.workbench.views.superrstudio.ChatAiPane::clearModels()();
            for (var i = 0; i < r.models.length; i++)
               self.@org.rstudio.studio.client.workbench.views.superrstudio.ChatAiPane::addModel(Ljava/lang/String;Ljava/lang/String;)(r.models[i].id, r.models[i].label);
         }
         self.@org.rstudio.studio.client.workbench.views.superrstudio.ChatAiPane::onModels(ZLjava/lang/String;)(!!(r && r.ok), (r && r.kind) || '');
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
         if (r && typeof r.status === 'string') {
            var q = r.quota || {};
            self.@org.rstudio.studio.client.workbench.views.superrstudio.ChatAiPane::onSendResult(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;I)(
               turn, r.status, r.kind || '', r.finishReason || '', q.scope || '', q.limit || '', q.retryAfterSeconds || 0);
         }
      }, function() { self.@org.rstudio.studio.client.workbench.views.superrstudio.ChatAiPane::onSendFailed(Ljava/lang/String;)(provider); });
   }-*/;
   private native void cancel(String provider) /*-{
      var self = this, bridge = $wnd.desktop;
      if (!bridge || !bridge.superrChatCancel) { self.@org.rstudio.studio.client.workbench.views.superrstudio.ChatAiPane::onError(Ljava/lang/String;)(provider); return; }
      bridge.superrChatCancel(provider).then(function(){}, function(){ self.@org.rstudio.studio.client.workbench.views.superrstudio.ChatAiPane::onNoTurn(Ljava/lang/String;)(provider); });
   }-*/;
   private static String text(String es, String en) { return SuperRStudioLanguage.spanish() ? es : en; }

   private static final String GEMINI_API = "gemini-api";
   private static final String PROVIDER_KEY = "superr.chatIa.provider";
   private static final String MODEL_KEY = "superr.chatIa.geminiModel";
   private static boolean stylesInjected_;
   private final FlowPanel header_;
   private final ScrollPanel headerScroll_;
   private final Label state_;
   private final Label status_;
   private final ListBox providers_;
   private final ListBox models_;
   private final Button newChat_;
   private final Button manage_;
   private final FlowPanel setup_;
   private final FlowPanel agentSetup_;
   private PasswordTextBox keyBox_;
   private Button saveKey_;
   private Button forgetKey_;
   private Label agentNote_;
   private Button signIn_;
   private final TextArea prompt_;
   private final Label hint_;
   private final Button send_;
   private final Button cancel_;
   private final FlowPanel composer_;
   private final FlowPanel actions_;
   private final FlowPanel conversation_;
   private final ScrollPanel scroll_;
   private final ChatMarkdown markdown_;
   private final Timer renderTimer_;
   private Label welcome_;
   private HTMLPanel answer_;
   private StringBuilder answerText_;
   private State currentState_ = State.VERIFYING;
   private String turn_ = "";
   private String previousModel_ = "";
   private String pendingNotice_;
   private int turnCount_;
   private int composerHeight_;
   private boolean busy_;
   private boolean manageOpen_;
}
