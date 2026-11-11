// Copyright (C) 2026 SuperR contributors. SPDX-License-Identifier: AGPL-3.0-only
package org.rstudio.studio.client.workbench.views.superrstudio;

import java.util.ArrayList;
import java.util.List;

import com.google.gwt.core.client.JavaScriptObject;
import com.google.gwt.dom.client.Document;
import com.google.gwt.dom.client.Element;
import com.google.gwt.event.dom.client.ClickHandler;
import com.google.gwt.user.client.ui.Button;
import com.google.gwt.user.client.ui.FlowPanel;
import com.google.gwt.user.client.ui.HTMLPanel;
import com.google.gwt.user.client.ui.Label;

import org.rstudio.core.client.CommandWithArg;
import org.rstudio.core.client.files.FileSystemItem;
import org.rstudio.studio.client.RStudioGinjector;
import org.rstudio.studio.client.workbench.views.source.SourceColumnManager;
import org.rstudio.studio.client.workbench.views.source.editors.text.DocDisplay;
import org.rstudio.studio.client.workbench.views.source.editors.text.TextEditingTarget;
import org.rstudio.studio.client.workbench.views.source.editors.text.ace.Position;
import org.rstudio.studio.client.workbench.views.source.editors.text.ace.Range;

/**
 * Review of edit proposals from Chat IA (phase 3). Each proposal is shown as a
 * card with its diff and Accept / Reject buttons. Accepting opens the file in
 * the editor, checks that it still equals the text the proposal was computed
 * from (unsaved changes included), and replaces it through the editor, so the
 * change is undoable and stays unsaved until the user saves. Several proposals
 * are applied all or nothing. Revert restores the original text while the
 * document still equals the applied version.
 */
public class ChatEditReview
{
   public interface Host { void notice(String text); }

   /** The proposal object sent by the desktop (see edit-proposal.ts). */
   public static class Proposal extends JavaScriptObject
   {
      protected Proposal() {}
      public final native String getId() /*-{ return this.id; }-*/;
      public final native String getPath() /*-{ return this.path; }-*/;
      public final native String getIdePath() /*-{ return this.idePath || ''; }-*/;
      public final native String getSummary() /*-{ return this.summary || ''; }-*/;
      public final native String getOriginal() /*-{ return this.original; }-*/;
      public final native String getProposed() /*-{ return this.proposed; }-*/;
      public final native int getAdded() /*-{ return this.added; }-*/;
      public final native int getRemoved() /*-{ return this.removed; }-*/;
      public final native int getHunkCount() /*-{ return this.hunks.length; }-*/;
      public final native String getHunkHeader(int i) /*-{
         var h = this.hunks[i];
         return '@@ -' + h.oldStart + ',' + h.oldLines + ' +' + h.newStart + ',' + h.newLines + ' @@';
      }-*/;
      public final native int getHunkNewStart(int i) /*-{ return this.hunks[i].newStart; }-*/;
      public final native int getLineCount(int i) /*-{ return this.hunks[i].lines.length; }-*/;
      public final native String getLineType(int i, int j) /*-{ return this.hunks[i].lines[j].type; }-*/;
      public final native String getLineText(int i, int j) /*-{ return this.hunks[i].lines[j].text; }-*/;
   }

   public ChatEditReview(Host host)
   {
      host_ = host;
   }

   /**
    * A card for the proposal, or null if it is already shown (a proposal arrives
    * both as an event and in the turn's final result). It is remembered for
    * "Accept all" of its turn.
    */
   public FlowPanel card(Proposal proposal)
   {
      if (!shown_.add(proposal.getId())) return null;
      Entry entry = new Entry(proposal);
      FlowPanel card = new FlowPanel();
      card.addStyleName("superr-edit-card");
      card.getElement().setAttribute("data-proposal", proposal.getId());
      Label title = new Label(text("Cambio propuesto: ", "Proposed change: ") + proposal.getPath() +
            "  (+" + proposal.getAdded() + " −" + proposal.getRemoved() + ")");
      title.addStyleName("superr-edit-title");
      card.add(title);
      if (!proposal.getSummary().isEmpty())
      {
         Label summary = new Label(proposal.getSummary());
         summary.addStyleName("superr-edit-summary");
         card.add(summary);
      }
      HTMLPanel diff = new HTMLPanel("");
      diff.addStyleName("superr-edit-diff");
      diff.getElement().appendChild(diffElement(proposal));
      card.add(diff);
      FlowPanel buttons = new FlowPanel();
      buttons.addStyleName("superr-chat-row");
      entry.accept = button(text("Aceptar", "Accept"), "superr-edit-accept", () -> apply(list(entry)));
      entry.reject = button(text("Rechazar", "Reject"), "superr-edit-reject", () -> {
         entry.state = State.REJECTED;
         refresh(entry);
         host_.notice(text("Cambio rechazado: ", "Change rejected: ") + proposal.getPath());
      });
      entry.revert = button(text("Revertir", "Revert"), "superr-edit-revert", () -> revert(entry));
      buttons.add(entry.accept);
      buttons.add(entry.reject);
      buttons.add(entry.revert);
      card.add(buttons);
      entry.status = new Label();
      entry.status.addStyleName("superr-edit-status");
      card.add(entry.status);
      entry.card = card;
      turn_.add(entry);
      refresh(entry);
      return card;
   }

   /** Ends the turn: with two or more pending proposals, returns an "Accept all" button (else null). */
   public Button finishTurn()
   {
      List<Entry> entries = new ArrayList<>(turn_);
      turn_.clear();
      if (entries.size() < 2) return null;
      Button all = button(text("Aceptar todos (", "Accept all (") + entries.size() + ")", "superr-edit-accept-all", null);
      all.addClickHandler(e -> {
         List<Entry> pending = new ArrayList<>();
         for (Entry entry : entries)
            if (entry.state == State.PENDING) pending.add(entry);
         if (pending.isEmpty()) { host_.notice(text("No quedan cambios pendientes.", "No pending changes left.")); return; }
         apply(pending);
      });
      return all;
   }

   public void clear() { turn_.clear(); }

   private final java.util.Set<String> shown_ = new java.util.HashSet<>();

   // ---- applying -----------------------------------------------------------

   private void apply(List<Entry> entries)
   {
      for (Entry entry : entries)
         if (entry.state != State.PENDING) { host_.notice(text("Ese cambio ya no está pendiente.", "That change is no longer pending.")); return; }
      openAll(entries, 0, new ArrayList<>(), targets -> {
         // all or nothing: every document must still equal the text the proposal was made from
         for (int i = 0; i < entries.size(); i++)
         {
            if (!normalize(targets.get(i).getDocDisplay().getCode()).equals(normalize(entries.get(i).proposal.getOriginal())))
            {
               entries.get(i).state = State.STALE;
               refresh(entries.get(i));
               host_.notice(entries.get(i).proposal.getPath() + text(" cambió después de la propuesta; no se aplicó ningún cambio. " +
                     "Pídele a Gemini una propuesta nueva.", " changed after the proposal; no change was applied. Ask Gemini for a new proposal."));
               return;
            }
         }
         List<Integer> applied = new ArrayList<>();
         try
         {
            for (int i = 0; i < entries.size(); i++)
            {
               Entry entry = entries.get(i);
               replaceAll(targets.get(i).getDocDisplay(), normalize(entry.proposal.getProposed()),
                     entry.proposal.getHunkCount() > 0 ? entry.proposal.getHunkNewStart(0) - 1 : 0);
               entry.target = targets.get(i);
               applied.add(i);
            }
         }
         catch (RuntimeException e)
         {
            for (int i : applied)
               replaceAll(targets.get(i).getDocDisplay(), normalize(entries.get(i).proposal.getOriginal()), 0);
            host_.notice(text("No se pudieron aplicar los cambios; se restauraron los documentos.",
                  "The changes could not be applied; the documents were restored."));
            return;
         }
         StringBuilder names = new StringBuilder();
         for (Entry entry : entries)
         {
            entry.state = State.APPLIED;
            refresh(entry);
            if (names.length() > 0) names.append(", ");
            names.append(entry.proposal.getPath());
         }
         host_.notice(text("Aplicado en el editor, sin guardar: ", "Applied in the editor, unsaved: ") + names +
               text(". Revísalo y guarda (Ctrl+S); Ctrl+Z o Revertir lo deshacen.", ". Review and save (Ctrl+S); Ctrl+Z or Revert undoes it."));
      });
   }

   private void revert(Entry entry)
   {
      if (entry.state != State.APPLIED || entry.target == null) return;
      DocDisplay display = entry.target.getDocDisplay();
      if (!normalize(display.getCode()).equals(normalize(entry.proposal.getProposed())))
      {
         host_.notice(text("El documento cambió después de aplicar el cambio; usa Ctrl+Z en el editor para deshacerlo.",
               "The document changed after the change was applied; use Ctrl+Z in the editor to undo it."));
         return;
      }
      replaceAll(display, normalize(entry.proposal.getOriginal()), entry.proposal.getHunkCount() > 0 ?
            entry.proposal.getHunkNewStart(0) - 1 : 0);
      entry.state = State.REVERTED;
      refresh(entry);
      host_.notice(text("Cambio revertido: ", "Change reverted: ") + entry.proposal.getPath());
   }

   /** Opens (or finds) each target document in order. */
   private void openAll(List<Entry> entries, int index, List<TextEditingTarget> targets,
                        CommandWithArg<List<TextEditingTarget>> done)
   {
      if (index == entries.size()) { done.execute(targets); return; }
      Proposal proposal = entries.get(index).proposal;
      SourceColumnManager columns = RStudioGinjector.INSTANCE.getSourceColumnManager();
      CommandWithArg<TextEditingTarget> next = target -> {
         targets.add(target);
         openAll(entries, index + 1, targets, done);
      };
      if (proposal.getIdePath().isEmpty())
      {
         // an untitled document: only the active one, with the same name
         columns.withTarget("", target -> {
            if (proposal.getPath().equals(target.getName().getValue())) next.execute(target);
            else host_.notice(text("Activa el documento ", "Activate the document ") + proposal.getPath() +
                  text(" en el editor para aplicar el cambio.", " in the editor to apply the change."));
         }, () -> host_.notice(text("No hay un documento activo para aplicar el cambio.", "No active document to apply the change to.")));
         return;
      }
      FileSystemItem file = FileSystemItem.createFile(proposal.getIdePath());
      columns.openFile(file, RStudioGinjector.INSTANCE.getFileTypeRegistry().getTextTypeForFile(file), target -> {
         if (target instanceof TextEditingTarget)
            ((TextEditingTarget) target).ensureTextEditorActive(() -> next.execute((TextEditingTarget) target));
         else
            host_.notice(proposal.getPath() + text(" no se puede editar como texto.", " cannot be edited as text."));
      });
   }

   /** One undoable replacement of the whole document; the cursor row is kept. */
   private static void replaceAll(DocDisplay display, String text, int scrollRow)
   {
      int last = Math.max(0, display.getRowCount() - 1);
      Position cursor = display.getCursorPosition();
      display.replaceRange(Range.fromPoints(Position.create(0, 0), Position.create(last, display.getLine(last).length())), text);
      int rows = Math.max(1, display.getRowCount());
      display.setCursorPosition(Position.create(Math.min(cursor.getRow(), rows - 1), 0));
      display.scrollToLine(Math.max(0, Math.min(scrollRow, rows - 1)), true);
   }

   private static String normalize(String text)
   {
      return text == null ? "" : text.replace("\r\n", "\n");
   }

   // ---- view ---------------------------------------------------------------

   private enum State { PENDING, APPLIED, REJECTED, REVERTED, STALE }

   private static class Entry
   {
      Entry(Proposal proposal) { this.proposal = proposal; }
      final Proposal proposal;
      State state = State.PENDING;
      TextEditingTarget target;
      FlowPanel card;
      Button accept, reject, revert;
      Label status;
   }

   private static List<Entry> list(Entry entry)
   {
      List<Entry> result = new ArrayList<>();
      result.add(entry);
      return result;
   }

   private static void refresh(Entry entry)
   {
      entry.accept.setVisible(entry.state == State.PENDING);
      entry.reject.setVisible(entry.state == State.PENDING);
      entry.revert.setVisible(entry.state == State.APPLIED);
      String status;
      switch (entry.state)
      {
         case APPLIED: status = text("Aplicado en el editor (sin guardar).", "Applied in the editor (unsaved)."); break;
         case REJECTED: status = text("Rechazado.", "Rejected."); break;
         case REVERTED: status = text("Revertido.", "Reverted."); break;
         case STALE: status = text("Obsoleto: el archivo cambió después de la propuesta.", "Stale: the file changed after the proposal."); break;
         default: status = text("Pendiente de revisión. Nada se modificó todavía.", "Waiting for review. Nothing has changed yet.");
      }
      entry.status.setText(status);
      entry.card.getElement().setAttribute("data-state", entry.state.name().toLowerCase());
   }

   private static Element diffElement(Proposal proposal)
   {
      Element pre = Document.get().createPreElement();
      for (int i = 0; i < proposal.getHunkCount(); i++)
      {
         Element header = Document.get().createDivElement();
         header.setClassName("superr-diff-hunk");
         header.appendChild(Document.get().createTextNode(proposal.getHunkHeader(i)));
         pre.appendChild(header);
         for (int j = 0; j < proposal.getLineCount(i); j++)
         {
            String type = proposal.getLineType(i, j);
            Element line = Document.get().createDivElement();
            line.setClassName("+".equals(type) ? "superr-diff-add" : "-".equals(type) ? "superr-diff-del" : "superr-diff-ctx");
            line.appendChild(Document.get().createTextNode(type + " " + proposal.getLineText(i, j)));
            pre.appendChild(line);
         }
      }
      return pre;
   }

   private static Button button(String label, String className, Runnable action)
   {
      Button button = action == null ? new Button(label) : new Button(label, (ClickHandler)e -> action.run());
      button.addStyleName("superr-chat-button " + className);
      return button;
   }

   private static String text(String es, String en) { return SuperRStudioLanguage.spanish() ? es : en; }

   private final Host host_;
   private final List<Entry> turn_ = new ArrayList<>();
}
