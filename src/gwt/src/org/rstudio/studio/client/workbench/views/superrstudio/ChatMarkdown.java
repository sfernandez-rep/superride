// Copyright (C) 2026 SuperR contributors. SPDX-License-Identifier: AGPL-3.0-only
package org.rstudio.studio.client.workbench.views.superrstudio;

import java.util.ArrayList;
import java.util.List;

import com.google.gwt.dom.client.Document;
import com.google.gwt.dom.client.Element;
import com.google.gwt.user.client.DOM;
import com.google.gwt.user.client.Event;

/**
 * Renders a model's Markdown answer as DOM nodes. Every piece of text becomes a
 * text node (never innerHTML), so HTML or script in an answer is shown as text.
 * Links open externally and only for http, https and mailto. Supports headings,
 * paragraphs and line breaks, bold, italic, inline code, fenced code blocks
 * (with copy/insert actions and R highlighting), lists, tables, block quotes
 * and rules. An unterminated fence renders as code, so partial (streamed)
 * answers look right.
 */
public class ChatMarkdown
{
   public interface Actions
   {
      void copy(String code);
      void insert(String code);
      void openLink(String url);
   }

   public ChatMarkdown(Actions actions, boolean spanish)
   {
      actions_ = actions;
      spanish_ = spanish;
   }

   public Element render(String markdown)
   {
      Element root = div("superr-md");
      String[] lines = markdown.replace("\r\n", "\n").replace('\r', '\n').split("\n", -1);
      int i = 0;
      List<String> paragraph = new ArrayList<>();
      while (i < lines.length)
      {
         String line = lines[i];
         String trimmed = line.trim();
         if (trimmed.startsWith("```") || trimmed.startsWith("~~~"))
         {
            flushParagraph(root, paragraph);
            String fence = trimmed.substring(0, 3);
            String language = trimmed.substring(3).trim();
            StringBuilder code = new StringBuilder();
            i++;
            boolean first = true;
            while (i < lines.length && !lines[i].trim().startsWith(fence))
            {
               if (!first) code.append('\n');
               code.append(lines[i]);
               first = false;
               i++;
            }
            i++; // closing fence, if any
            root.appendChild(codeBlock(language, code.toString()));
            continue;
         }
         if (trimmed.isEmpty())
         {
            flushParagraph(root, paragraph);
            i++;
            continue;
         }
         int level = headingLevel(trimmed);
         if (level > 0)
         {
            flushParagraph(root, paragraph);
            Element heading = Document.get().createElement("h" + Math.min(level + 2, 6));
            heading.setClassName("superr-md-h");
            inline(heading, trimmed.substring(level).trim());
            root.appendChild(heading);
            i++;
            continue;
         }
         if (isRule(trimmed))
         {
            flushParagraph(root, paragraph);
            root.appendChild(Document.get().createHRElement());
            i++;
            continue;
         }
         if (trimmed.startsWith(">"))
         {
            flushParagraph(root, paragraph);
            StringBuilder quote = new StringBuilder();
            while (i < lines.length && lines[i].trim().startsWith(">"))
            {
               String text = lines[i].trim().substring(1);
               if (text.startsWith(" ")) text = text.substring(1);
               if (quote.length() > 0) quote.append('\n');
               quote.append(text);
               i++;
            }
            Element block = Document.get().createElement("blockquote");
            block.appendChild(new ChatMarkdown(actions_, spanish_).render(quote.toString()));
            root.appendChild(block);
            continue;
         }
         if (line.contains("|") && i + 1 < lines.length && isTableSeparator(lines[i + 1]))
         {
            flushParagraph(root, paragraph);
            List<String> rows = new ArrayList<>();
            rows.add(line);
            i += 2;
            while (i < lines.length && lines[i].contains("|") && !lines[i].trim().isEmpty())
               rows.add(lines[i++]);
            root.appendChild(table(rows));
            continue;
         }
         if (listMarker(line) != null)
         {
            flushParagraph(root, paragraph);
            i = list(root, lines, i);
            continue;
         }
         paragraph.add(line);
         i++;
      }
      flushParagraph(root, paragraph);
      return root;
   }

   // ---- blocks -------------------------------------------------------------

   private void flushParagraph(Element root, List<String> lines)
   {
      if (lines.isEmpty()) return;
      Element p = Document.get().createPElement();
      StringBuilder text = new StringBuilder();
      for (int i = 0; i < lines.size(); i++)
      {
         if (i > 0) text.append('\n');
         text.append(lines.get(i).trim());
      }
      inline(p, text.toString());
      root.appendChild(p);
      lines.clear();
   }

   private static int headingLevel(String trimmed)
   {
      int n = 0;
      while (n < trimmed.length() && n < 7 && trimmed.charAt(n) == '#') n++;
      return n >= 1 && n <= 6 && n < trimmed.length() && trimmed.charAt(n) == ' ' ? n : 0;
   }

   private static boolean isRule(String trimmed)
   {
      String compact = trimmed.replace(" ", "");
      if (compact.length() < 3) return false;
      char c = compact.charAt(0);
      if (c != '-' && c != '*' && c != '_') return false;
      for (int i = 0; i < compact.length(); i++)
         if (compact.charAt(i) != c) return false;
      return true;
   }

   private static boolean isTableSeparator(String line)
   {
      String t = line.trim();
      if (!t.contains("-")) return false;
      for (int i = 0; i < t.length(); i++)
      {
         char c = t.charAt(i);
         if (c != '|' && c != '-' && c != ':' && c != ' ') return false;
      }
      return t.contains("|") || t.startsWith("-");
   }

   private static List<String> cells(String row)
   {
      String t = row.trim();
      if (t.startsWith("|")) t = t.substring(1);
      if (t.endsWith("|") && !t.endsWith("\\|")) t = t.substring(0, t.length() - 1);
      List<String> result = new ArrayList<>();
      StringBuilder cell = new StringBuilder();
      boolean code = false;
      for (int i = 0; i < t.length(); i++)
      {
         char c = t.charAt(i);
         if (c == '\\' && i + 1 < t.length() && t.charAt(i + 1) == '|') { cell.append('|'); i++; continue; }
         if (c == '`') code = !code;
         if (c == '|' && !code) { result.add(cell.toString().trim()); cell.setLength(0); continue; }
         cell.append(c);
      }
      result.add(cell.toString().trim());
      return result;
   }

   private Element table(List<String> rows)
   {
      Element wrapper = div("superr-md-table");
      Element table = Document.get().createTableElement();
      for (int r = 0; r < rows.size(); r++)
      {
         Element tr = Document.get().createTRElement();
         for (String cell : cells(rows.get(r)))
         {
            Element td = Document.get().createElement(r == 0 ? "th" : "td");
            inline(td, cell);
            tr.appendChild(td);
         }
         table.appendChild(tr);
      }
      wrapper.appendChild(table);
      return wrapper;
   }

   /** Returns {indent, ordered (0/1), content start} or null. */
   private static int[] listMarker(String line)
   {
      int indent = 0;
      while (indent < line.length() && line.charAt(indent) == ' ') indent++;
      if (indent >= line.length()) return null;
      char c = line.charAt(indent);
      if ((c == '-' || c == '*' || c == '+') && indent + 1 < line.length() && line.charAt(indent + 1) == ' ')
         return new int[] { indent, 0, indent + 2 };
      int j = indent;
      while (j < line.length() && j - indent < 9 && Character.isDigit(line.charAt(j))) j++;
      if (j > indent && j + 1 < line.length() && (line.charAt(j) == '.' || line.charAt(j) == ')') && line.charAt(j + 1) == ' ')
         return new int[] { indent, 1, j + 2 };
      return null;
   }

   private int list(Element root, String[] lines, int i)
   {
      List<Element> lists = new ArrayList<>();
      List<Integer> indents = new ArrayList<>();
      Element lastItem = null;
      while (i < lines.length)
      {
         String line = lines[i];
         int[] marker = listMarker(line);
         if (marker == null)
         {
            // an indented continuation line belongs to the last item
            if (lastItem != null && !line.trim().isEmpty() && line.startsWith("  "))
            {
               lastItem.appendChild(Document.get().createBRElement());
               inline(lastItem, line.trim());
               i++;
               continue;
            }
            break;
         }
         int indent = marker[0];
         while (!indents.isEmpty() && indent < indents.get(indents.size() - 1))
         {
            lists.remove(lists.size() - 1);
            indents.remove(indents.size() - 1);
         }
         if (indents.isEmpty() || indent > indents.get(indents.size() - 1))
         {
            Element list = Document.get().createElement(marker[1] == 1 ? "ol" : "ul");
            if (lists.isEmpty() || lastItem == null) root.appendChild(list);
            else lastItem.appendChild(list);
            lists.add(list);
            indents.add(indent);
         }
         Element item = Document.get().createLIElement();
         inline(item, line.substring(marker[2]).trim());
         lists.get(lists.size() - 1).appendChild(item);
         lastItem = item;
         i++;
      }
      return i;
   }

   private Element codeBlock(String language, String code)
   {
      Element block = div("superr-md-code");
      Element bar = div("superr-md-code-bar");
      String name = language.replace("{", "").replace("}", "").trim();
      int space = name.indexOf(' ');
      if (space > 0) name = name.substring(0, space);
      Element label = Document.get().createSpanElement();
      label.setClassName("superr-md-code-lang");
      label.appendChild(text(name.isEmpty() ? (spanish_ ? "código" : "code") : name));
      bar.appendChild(label);
      bar.appendChild(button(spanish_ ? "Copiar" : "Copy", "superr-md-copy", () -> actions_.copy(code)));
      bar.appendChild(button(spanish_ ? "Insertar en editor" : "Insert in editor", "superr-md-insert", () -> actions_.insert(code)));
      block.appendChild(bar);
      Element pre = Document.get().createPreElement();
      Element codeElement = Document.get().createElement("code");
      String lower = name.toLowerCase();
      if (lower.equals("r") || lower.equals("rscript") || lower.equals("splus") || lower.equals("rmd"))
         highlightR(codeElement, code);
      else
         codeElement.appendChild(text(code));
      pre.appendChild(codeElement);
      block.appendChild(pre);
      return block;
   }

   // ---- inline -------------------------------------------------------------

   private void inline(Element parent, String s)
   {
      StringBuilder plain = new StringBuilder();
      int i = 0;
      while (i < s.length())
      {
         char c = s.charAt(i);
         if (c == '\\' && i + 1 < s.length() && "\\`*_[]()#+-.!|<>~".indexOf(s.charAt(i + 1)) >= 0)
         {
            plain.append(s.charAt(i + 1));
            i += 2;
            continue;
         }
         if (c == '\n')
         {
            flush(parent, plain);
            parent.appendChild(Document.get().createBRElement());
            i++;
            continue;
         }
         if (c == '`')
         {
            int ticks = run(s, i, '`');
            int close = s.indexOf(repeat('`', ticks), i + ticks);
            if (close > 0)
            {
               flush(parent, plain);
               Element code = Document.get().createElement("code");
               code.appendChild(text(s.substring(i + ticks, close).trim()));
               parent.appendChild(code);
               i = close + ticks;
               continue;
            }
         }
         if ((c == '*' || c == '_') && i + 1 < s.length() && s.charAt(i + 1) == c)
         {
            String marker = repeat(c, 2);
            int close = s.indexOf(marker, i + 2);
            if (close > i + 2 && s.charAt(i + 2) != ' ')
            {
               flush(parent, plain);
               Element strong = Document.get().createElement("strong");
               inline(strong, s.substring(i + 2, close));
               parent.appendChild(strong);
               i = close + 2;
               continue;
            }
         }
         if ((c == '*' || c == '_') && i + 1 < s.length() && s.charAt(i + 1) != ' ' &&
             (c == '*' || i == 0 || !Character.isLetterOrDigit(s.charAt(i - 1))))
         {
            int close = findSingle(s, i + 1, c);
            if (close > i + 1)
            {
               flush(parent, plain);
               Element em = Document.get().createElement("em");
               inline(em, s.substring(i + 1, close));
               parent.appendChild(em);
               i = close + 1;
               continue;
            }
         }
         if (c == '[')
         {
            int end = s.indexOf("](", i);
            int close = end > 0 ? s.indexOf(')', end + 2) : -1;
            int newline = s.indexOf('\n', i);
            if (end > i && close > end && (newline < 0 || newline > close))
            {
               flush(parent, plain);
               link(parent, s.substring(i + 1, end), s.substring(end + 2, close).trim());
               i = close + 1;
               continue;
            }
         }
         if ((s.startsWith("https://", i) || s.startsWith("http://", i)) &&
             (i == 0 || !Character.isLetterOrDigit(s.charAt(i - 1))))
         {
            int end = i;
            while (end < s.length() && !Character.isWhitespace(s.charAt(end)) && s.charAt(end) != '<' && s.charAt(end) != '>') end++;
            while (end > i && ".,;:!?)\"'".indexOf(s.charAt(end - 1)) >= 0) end--;
            flush(parent, plain);
            String url = s.substring(i, end);
            link(parent, url, url);
            i = end;
            continue;
         }
         plain.append(c);
         i++;
      }
      flush(parent, plain);
   }

   private static int findSingle(String s, int from, char c)
   {
      for (int i = from; i < s.length(); i++)
      {
         if (s.charAt(i) == '\n') return -1;
         if (s.charAt(i) == c && s.charAt(i - 1) != ' ' && (i + 1 >= s.length() || s.charAt(i + 1) != c))
         {
            if (c == '_' && i + 1 < s.length() && Character.isLetterOrDigit(s.charAt(i + 1))) continue;
            return i;
         }
      }
      return -1;
   }

   private void link(Element parent, String label, String url)
   {
      if (!safeUrl(url))
      {
         parent.appendChild(text(label));
         return;
      }
      Element a = Document.get().createSpanElement();
      a.setClassName("superr-md-link");
      a.setTitle(url);
      a.setAttribute("role", "link");
      a.setTabIndex(0);
      inline(a, label);
      listen(a, () -> actions_.openLink(url));
      parent.appendChild(a);
   }

   public static boolean safeUrl(String url)
   {
      String lower = url.toLowerCase();
      if (!(lower.startsWith("https://") || lower.startsWith("http://") || lower.startsWith("mailto:"))) return false;
      for (int i = 0; i < url.length(); i++)
         if (url.charAt(i) < 0x20 || url.charAt(i) == ' ') return false;
      return true;
   }

   // ---- R highlighting -----------------------------------------------------

   private static final String[] R_KEYWORDS = { "if", "else", "repeat", "while", "function", "for", "in", "next",
         "break", "return", "TRUE", "FALSE", "NULL", "Inf", "NaN", "NA", "NA_integer_", "NA_real_",
         "NA_character_", "NA_complex_", "library", "require", "T", "F" };

   private static void highlightR(Element parent, String code)
   {
      int i = 0;
      StringBuilder plain = new StringBuilder();
      while (i < code.length())
      {
         char c = code.charAt(i);
         int start = i;
         String cls = null;
         if (c == '#')
         {
            while (i < code.length() && code.charAt(i) != '\n') i++;
            cls = "superr-tok-comment";
         }
         else if (c == '"' || c == '\'' || c == '`')
         {
            i++;
            while (i < code.length() && code.charAt(i) != c && code.charAt(i) != '\n')
               i += code.charAt(i) == '\\' ? 2 : 1;
            i = Math.min(i + 1, code.length());
            cls = c == '`' ? null : "superr-tok-string";
         }
         else if (Character.isDigit(c) || (c == '.' && i + 1 < code.length() && Character.isDigit(code.charAt(i + 1))))
         {
            while (i < code.length() && (Character.isLetterOrDigit(code.charAt(i)) || code.charAt(i) == '.')) i++;
            cls = "superr-tok-number";
         }
         else if (Character.isLetter(c) || c == '.' || c == '_')
         {
            while (i < code.length() && (Character.isLetterOrDigit(code.charAt(i)) || code.charAt(i) == '.' || code.charAt(i) == '_')) i++;
            String word = code.substring(start, i);
            int next = i;
            while (next < code.length() && code.charAt(next) == ' ') next++;
            if (isKeyword(word)) cls = "superr-tok-keyword";
            else if (next < code.length() && code.charAt(next) == '(') cls = "superr-tok-function";
         }
         else if (c == '%')
         {
            int close = code.indexOf('%', i + 1);
            int line = code.indexOf('\n', i + 1);
            i = close > 0 && (line < 0 || close < line) ? close + 1 : i + 1;
            cls = "superr-tok-operator";
         }
         else if ("<-=>|&!+*/^~$@:".indexOf(c) >= 0)
         {
            while (i < code.length() && "<-=>|&!:".indexOf(code.charAt(i)) >= 0 && i - start < 3) i++;
            if (i == start) i++;
            cls = "superr-tok-operator";
         }
         else
            i++;
         if (cls == null)
            plain.append(code, start, i);
         else
         {
            flush(parent, plain);
            Element span = Document.get().createSpanElement();
            span.setClassName(cls);
            span.appendChild(text(code.substring(start, i)));
            parent.appendChild(span);
         }
      }
      flush(parent, plain);
   }

   private static boolean isKeyword(String word)
   {
      for (String keyword : R_KEYWORDS)
         if (keyword.equals(word)) return true;
      return false;
   }

   // ---- DOM helpers --------------------------------------------------------

   private static Element div(String className)
   {
      Element div = Document.get().createDivElement();
      div.setClassName(className);
      return div;
   }

   private static com.google.gwt.dom.client.Text text(String s)
   {
      return Document.get().createTextNode(s);
   }

   private static void flush(Element parent, StringBuilder plain)
   {
      if (plain.length() == 0) return;
      parent.appendChild(text(plain.toString()));
      plain.setLength(0);
   }

   private static int run(String s, int i, char c)
   {
      int n = 0;
      while (i + n < s.length() && s.charAt(i + n) == c) n++;
      return n;
   }

   private static String repeat(char c, int n)
   {
      StringBuilder b = new StringBuilder();
      for (int i = 0; i < n; i++) b.append(c);
      return b.toString();
   }

   private static Element button(String label, String className, Runnable action)
   {
      Element button = Document.get().createElement("button");
      button.setClassName("superr-md-button " + className);
      button.setAttribute("type", "button");
      button.appendChild(text(label));
      listen(button, action);
      return button;
   }

   private static void listen(Element element, Runnable action)
   {
      DOM.sinkEvents(element, Event.ONCLICK | Event.ONKEYDOWN);
      DOM.setEventListener(element, event -> {
         if (event.getTypeInt() == Event.ONCLICK ||
             (event.getTypeInt() == Event.ONKEYDOWN && event.getKeyCode() == 13))
         {
            event.preventDefault();
            event.stopPropagation();
            action.run();
         }
      });
   }

   private final Actions actions_;
   private final boolean spanish_;
}
