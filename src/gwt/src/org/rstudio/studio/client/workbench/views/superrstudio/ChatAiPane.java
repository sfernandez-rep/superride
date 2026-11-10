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

/** Visual-only chat pane. No provider is connected in this iteration. */
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
      providers.addItem("Gemini");
      providers.addItem("Codex");
      providers.getElement().setId("superr_chat_ai_provider");
      providers.getElement().setAttribute("aria-label", text("Proveedor", "Provider"));
      header.add(providers);
      status_ = new Label();
      status_.getElement().setId("superr_chat_ai_status");
      status_.getElement().setAttribute("role", "status");
      header.add(status_);
      addNorth(header, 115);

      VerticalPanel input = new VerticalPanel();
      input.setWidth("100%");
      input.setSpacing(6);
      TextArea prompt = new TextArea();
      prompt.setWidth("98%");
      prompt.setVisibleLines(3);
      prompt.getElement().setId("superr_chat_ai_prompt");
      prompt.getElement().setAttribute("aria-label", text("Mensaje", "Message"));
      input.add(prompt);
      Button send = new Button(text("Enviar", "Send"), (ClickHandler)e ->
         status_.setText(text("Conexión pendiente", "Connection pending")));
      send.getElement().setId("superr_chat_ai_send");
      input.add(send);
      addSouth(input, 115);
      ScrollPanel conversation = new ScrollPanel();
      conversation.getElement().setId("superr_chat_ai_conversation");
      conversation.getElement().setAttribute("aria-label", text("Conversación", "Conversation"));
      add(conversation);
   }

   private static String text(String es, String en) { return SuperRStudioLanguage.spanish() ? es : en; }
   private final Label status_;
}
