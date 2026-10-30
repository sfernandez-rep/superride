// SPDX-License-Identifier: AGPL-3.0-only
package org.rstudio.studio.client.workbench.views.superrstudio;

import java.util.ArrayList;
import java.util.List;

import com.google.gwt.aria.client.Roles;
import com.google.gwt.core.client.JsArray;
import com.google.gwt.core.client.JsArrayString;
import com.google.gwt.dom.client.Element;
import com.google.gwt.event.dom.client.KeyCodes;
import com.google.gwt.event.dom.client.KeyDownEvent;
import com.google.gwt.event.shared.HandlerRegistration;
import com.google.gwt.json.client.JSONArray;
import com.google.gwt.json.client.JSONObject;
import com.google.gwt.json.client.JSONString;
import com.google.gwt.json.client.JSONValue;
import com.google.gwt.user.client.ui.*;
import org.rstudio.core.client.ElementIds;
import org.rstudio.core.client.files.FileSystemItem;
import org.rstudio.core.client.widget.FormLabel;
import org.rstudio.core.client.widget.OperationWithInput;
import org.rstudio.core.client.widget.ProgressIndicator;
import org.rstudio.core.client.widget.ProgressOperationWithInput;
import org.rstudio.core.client.widget.ThemedButton;
import org.rstudio.studio.client.RStudioGinjector;
import org.rstudio.studio.client.application.events.EventBus;
import org.rstudio.studio.client.server.ServerError;
import org.rstudio.studio.client.server.ServerRequestCallback;
import org.rstudio.studio.client.workbench.commands.Commands;
import org.rstudio.studio.client.workbench.views.console.events.ConsolePromptEvent;
import org.rstudio.studio.client.workbench.views.console.events.SendToConsoleEvent;
import org.rstudio.studio.client.workbench.views.source.events.NewDocumentWithCodeEvent;
import org.rstudio.studio.client.workbench.views.source.model.SourcePosition;

// Data table window (SessionSuperRStudioSheet.R): values typed or pasted from
// a spreadsheet, a CSV/text/Excel file, or a copy of a data frame of the
// session become a data frame through R code that runs in the console, so
// it is visible, in the history and repeatable. Non-modal like the other
// SuperR windows; the new data frame opens in the plot editor or the
// length-frequency window with one click.
public class SheetDialog extends DialogBox
{
   public static void open(SuperRStudioServerOperations server, EventBus events, Commands commands)
   {
      if (instance_ != null && instance_.isShowing())
      {
         instance_.show();
         instance_.listFrames();
         return;
      }
      instance_ = new SheetDialog(server, events, commands);
      instance_.show();
      instance_.setPopupPosition(32, 56);
      instance_.newTable();
      instance_.listFrames();
   }

   private SheetDialog(SuperRStudioServerOperations server, EventBus events, Commands commands)
   {
      super(false, false);
      setGlassEnabled(false);
      setText(messages_.title());
      addStyleDependentName("ModalDialog");
      Roles.getDialogRole().set(getElement());
      getElement().setAttribute("aria-modal", "false");
      server_ = server;
      events_ = events;
      commands_ = commands;
      SuperRStudioTheme.dialog(this);
      addDomHandler(e -> {
         if (e.getNativeKeyCode() == KeyCodes.KEY_ESCAPE)
         {
            e.preventDefault();
            hide();
         }
      }, KeyDownEvent.getType());
      setWidget(createMainWidget());
   }

   @Override
   public void hide()
   {
      stopWaiting();
      super.hide();
   }

   // Layout -------------------------------------------------------------------

   private Widget createMainWidget()
   {
      VerticalPanel panel = new VerticalPanel();
      panel.setSpacing(4);
      panel.setWidth("820px");
      panel.add(SuperRStudioTheme.hint(new Label(messages_.help())));

      HorizontalPanel sources = new HorizontalPanel();
      sources.setSpacing(4);
      sources.setVerticalAlignment(HasVerticalAlignment.ALIGN_MIDDLE);
      sources.add(button(newTable_, "superrstudio_sheet_new"));
      sources.add(button(openFile_, "superrstudio_sheet_open"));
      // a path can also be typed or pasted (Enter reads it)
      path_.getElement().setId("superrstudio_sheet_path");
      path_.getElement().setAttribute("aria-label", messages_.pathLabel());
      path_.getElement().setAttribute("placeholder", messages_.pathPlaceholder());
      path_.setWidth("420px");
      path_.addKeyDownHandler(e -> {
         if (e.getNativeKeyCode() == KeyCodes.KEY_ENTER)
         {
            e.preventDefault();
            readNewFile();
         }
      });
      sources.add(path_);
      panel.add(sources);
      HorizontalPanel copying = new HorizontalPanel();
      copying.setSpacing(4);
      copying.setVerticalAlignment(HasVerticalAlignment.ALIGN_MIDDLE);
      frames_.getElement().setId("superrstudio_sheet_frames");
      copying.add(new FormLabel(messages_.copyFrom(), frames_));
      copying.add(frames_);
      copying.add(button(copy_, "superrstudio_sheet_copy"));
      panel.add(copying);

      fileInfo_.getElement().setId("superrstudio_sheet_file_info");
      fileInfo_.getElement().getStyle().setProperty("whiteSpace", "pre-line");
      filePanel_.add(fileInfo_);
      textOptions_.setSpacing(4);
      textOptions_.setVerticalAlignment(HasVerticalAlignment.ALIGN_MIDDLE);
      option(sep_, messages_.automatic(), "auto");
      option(sep_, messages_.sepComma(), "comma");
      option(sep_, messages_.sepSemicolon(), "semicolon");
      option(sep_, messages_.sepTab(), "tab");
      option(sep_, messages_.sepPipe(), "pipe");
      option(sep_, messages_.sepSpace(), "space");
      option(dec_, messages_.automatic(), "auto");
      option(dec_, messages_.decPoint(), ".");
      option(dec_, messages_.decComma(), ",");
      option(header_, messages_.automatic(), "auto");
      option(header_, messages_.yes(), "yes");
      option(header_, messages_.no(), "no");
      option(encoding_, messages_.automatic(), "auto");
      option(encoding_, "UTF-8", "UTF-8");
      option(encoding_, messages_.encBom(), "UTF-8-BOM");
      option(encoding_, messages_.encLatin1(), "latin1");
      pair(textOptions_, messages_.separator(), sep_, "superrstudio_sheet_sep");
      pair(textOptions_, messages_.decimal(), dec_, "superrstudio_sheet_dec");
      pair(textOptions_, messages_.header(), header_, "superrstudio_sheet_header");
      pair(textOptions_, messages_.encoding(), encoding_, "superrstudio_sheet_encoding");
      filePanel_.add(textOptions_);
      sheetOptions_.setSpacing(4);
      sheetOptions_.setVerticalAlignment(HasVerticalAlignment.ALIGN_MIDDLE);
      pair(sheetOptions_, messages_.sheet(), sheet_, "superrstudio_sheet_excel_sheet");
      filePanel_.add(sheetOptions_);
      filePanel_.add(button(reread_, "superrstudio_sheet_reread"));
      filePanel_.setVisible(false);
      panel.add(filePanel_);

      table_.getElement().setId("superrstudio_sheet_grid");
      table_.setCellSpacing(0);
      table_.setCellPadding(1);
      scroll_.setSize("812px", "300px");
      panel.add(scroll_);

      hint_.getElement().setId("superrstudio_sheet_hint");
      panel.add(SuperRStudioTheme.hint(hint_));
      editTools_.setSpacing(4);
      editTools_.add(button(addRow_, "superrstudio_sheet_add_row"));
      editTools_.add(button(addColumn_, "superrstudio_sheet_add_column"));
      editTools_.add(button(removeRow_, "superrstudio_sheet_remove_row"));
      editTools_.add(button(removeColumn_, "superrstudio_sheet_remove_column"));
      editTools_.add(button(clear_, "superrstudio_sheet_clear"));
      panel.add(editTools_);

      HorizontalPanel naming = new HorizontalPanel();
      naming.setSpacing(4);
      naming.setVerticalAlignment(HasVerticalAlignment.ALIGN_MIDDLE);
      name_.setValue("datos");
      pair(naming, messages_.objectName(), name_, "superrstudio_sheet_name");
      panel.add(naming);

      status_.getElement().setId("superrstudio_sheet_status");
      status_.addStyleName(SuperRStudioTheme.STATUS);
      status_.getElement().setAttribute("role", "status");
      status_.getElement().setAttribute("aria-live", "polite");
      status_.getElement().getStyle().setProperty("whiteSpace", "pre-line");
      panel.add(status_);

      code_.getElement().setId("superrstudio_sheet_code");
      code_.setReadOnly(true);
      code_.setVisibleLines(5);
      code_.setWidth("806px");
      code_.getElement().setAttribute("aria-label", messages_.openCode());
      code_.getElement().getStyle().setProperty("fontFamily", "monospace");
      panel.add(code_);

      HorizontalPanel actions = new HorizontalPanel();
      actions.setSpacing(4);
      actions.add(button(check_, "superrstudio_sheet_check"));
      actions.add(button(create_, "superrstudio_sheet_create"));
      replace_.setVisible(false);
      actions.add(button(replace_, "superrstudio_sheet_replace"));
      actions.add(button(openCode_, "superrstudio_sheet_code_open"));
      actions.add(button(plot_, "superrstudio_sheet_plot"));
      actions.add(button(lfq_, "superrstudio_sheet_lfq"));
      actions.add(button(close_, "superrstudio_sheet_close"));
      panel.add(actions);
      enable();
      return panel;
   }

   private static ThemedButton button(ThemedButton button, String id)
   {
      ElementIds.assignElementId(button, id);
      return button;
   }

   private static void pair(HorizontalPanel panel, String text, Widget control, String id)
   {
      control.getElement().setId(id);
      panel.add(new FormLabel(text, control));
      panel.add(control);
   }

   private static void option(ListBox list, String label, String value)
   {
      list.addItem(label, value);
   }

   // The editable table ---------------------------------------------------------

   private void newTable()
   {
      file_ = null;
      filePath_ = "";
      resetGrid(3, 10);
      code_.setText("");
      created_ = "";
      status_.setText("");
      enable();
      names_.get(0).setFocus(true);
   }

   private void resetGrid(int columns, int rows)
   {
      table_.removeAllRows();
      names_.clear();
      types_.clear();
      cells_.clear();
      table_.setText(0, 0, "");
      table_.setText(1, 0, "");
      for (int c = 0; c < columns; c++)
         addColumn();
      for (int r = 0; r < rows; r++)
         addRow();
      filePanel_.setVisible(false);
      hint_.setText(messages_.pasteHint());
      editTools_.setVisible(true);
   }

   private boolean addColumn()
   {
      int c = names_.size();
      if (c >= MAX_COLUMNS)
      {
         SuperRStudioTheme.status(status_, messages_.limitColumns(String.valueOf(MAX_COLUMNS)), SuperRStudioTheme.ERROR);
         return false;
      }
      TextBox name = new TextBox();
      name.getElement().setId("superrstudio_sheet_col_" + (c + 1));
      name.getElement().setAttribute("aria-label", messages_.columnName(String.valueOf(c + 1)));
      name.getElement().setAttribute("placeholder", messages_.namePlaceholder());
      name.getElement().getStyle().setProperty("fontWeight", "bold");
      name.setWidth("8em");
      attachPaste(name.getElement(), -1, c);
      name.addKeyDownHandler(e -> {
         if (e.getNativeKeyCode() == KeyCodes.KEY_ENTER || e.getNativeKeyCode() == KeyCodes.KEY_DOWN)
         {
            e.preventDefault();
            move(0, c);
         }
      });
      ListBox type = new ListBox();
      option(type, messages_.typeAuto(), "auto");
      option(type, messages_.typeNumber(), "number");
      option(type, messages_.typeText(), "text");
      option(type, messages_.typeDate(), "date");
      type.getElement().setId("superrstudio_sheet_type_" + (c + 1));
      type.getElement().setAttribute("aria-label", messages_.columnType(String.valueOf(c + 1)));
      type.setWidth("8.6em");
      table_.setWidget(0, c + 1, name);
      table_.setWidget(1, c + 1, type);
      names_.add(name);
      types_.add(type);
      for (int r = 0; r < cells_.size(); r++)
      {
         TextBox cell = cell(r, c);
         cells_.get(r).add(cell);
         table_.setWidget(r + 2, c + 1, cell);
      }
      return true;
   }

   private boolean addRow()
   {
      int r = cells_.size();
      if (r >= MAX_ROWS)
      {
         SuperRStudioTheme.status(status_, messages_.limitRows(String.valueOf(MAX_ROWS)), SuperRStudioTheme.ERROR);
         return false;
      }
      List<TextBox> row = new ArrayList<>();
      table_.setText(r + 2, 0, String.valueOf(r + 1));
      for (int c = 0; c < names_.size(); c++)
      {
         TextBox cell = cell(r, c);
         row.add(cell);
         table_.setWidget(r + 2, c + 1, cell);
      }
      cells_.add(row);
      return true;
   }

   private TextBox cell(int r, int c)
   {
      TextBox cell = new TextBox();
      cell.getElement().setId("superrstudio_sheet_cell_" + (r + 1) + "_" + (c + 1));
      cell.getElement().setAttribute("aria-label", messages_.cell(String.valueOf(r + 1), String.valueOf(c + 1)));
      cell.setWidth("8em");
      attachPaste(cell.getElement(), r, c);
      cell.addKeyDownHandler(e -> {
         int key = e.getNativeKeyCode();
         if (key == KeyCodes.KEY_ENTER || key == KeyCodes.KEY_DOWN)
         {
            e.preventDefault();
            move(r + 1, c);
         }
         else if (key == KeyCodes.KEY_UP)
         {
            e.preventDefault();
            move(r - 1, c);
         }
      });
      return cell;
   }

   private void removeRow()
   {
      if (cells_.size() <= 1)
         return;
      int r = cells_.size() - 1;
      cells_.remove(r);
      table_.removeRow(r + 2);
   }

   private void removeColumn()
   {
      if (names_.size() <= 1)
         return;
      int c = names_.size() - 1;
      names_.remove(c);
      types_.remove(c);
      for (List<TextBox> row : cells_)
         row.remove(c);
      for (int r = table_.getRowCount() - 1; r >= 0; r--)
         if (table_.getCellCount(r) > c + 1)
            table_.removeCell(r, c + 1);
   }

   private void move(int r, int c)
   {
      if (r < 0)
      {
         names_.get(c).setFocus(true);
         return;
      }
      while (r >= cells_.size())
         if (!addRow())
            return;
      TextBox target = cells_.get(r).get(c);
      target.setFocus(true);
      target.selectAll();
   }

   private boolean ensure(int rows, int columns)
   {
      while (names_.size() < columns)
         if (!addColumn())
            return false;
      while (cells_.size() < rows)
         if (!addRow())
            return false;
      return true;
   }

   // Cells copied from a spreadsheet arrive as tab-separated lines. Pasted
   // into a column name, the first line names the columns.
   private void paste(int row, int column, String text)
   {
      String[] lines = text.replace("\r\n", "\n").replace('\r', '\n').split("\n", -1);
      int count = lines.length;
      while (count > 0 && lines[count - 1].isEmpty())
         count--;
      int first = 0;
      if (row < 0 && count > 0)
      {
         String[] fields = lines[0].split("\t", -1);
         if (!ensure(0, column + fields.length))
            return;
         for (int j = 0; j < fields.length; j++)
            names_.get(column + j).setValue(fields[j].trim());
         first = 1;
         row = 0;
      }
      for (int i = first; i < count; i++)
      {
         String[] fields = lines[i].split("\t", -1);
         int r = row + i - first;
         if (!ensure(r + 1, column + fields.length))
            return;
         for (int j = 0; j < fields.length; j++)
            cells_.get(r).get(column + j).setValue(fields[j]);
      }
   }

   private native void attachPaste(Element element, int row, int column) /*-{
      var self = this;
      element.addEventListener('paste', $entry(function(event) {
         var data = event.clipboardData ? event.clipboardData.getData('text/plain') : '';
         if (data && (data.indexOf('\t') >= 0 || data.indexOf('\n') >= 0))
         {
            event.preventDefault();
            self.@org.rstudio.studio.client.workbench.views.superrstudio.SheetDialog::paste(IILjava/lang/String;)(row, column, data);
         }
      }));
   }-*/;

   // The table as sent to the session: names, types and the rows up to the
   // last one with a value
   private JSONObject tableSettings()
   {
      JSONObject json = new JSONObject();
      json.put("name", new JSONString(name_.getValue().trim()));
      JSONArray columns = new JSONArray();
      for (int c = 0; c < names_.size(); c++)
      {
         JSONObject column = new JSONObject();
         column.put("name", new JSONString(names_.get(c).getValue()));
         column.put("type", new JSONString(types_.get(c).getSelectedValue()));
         columns.set(c, column);
      }
      json.put("columns", columns);
      int last = -1;
      for (int r = 0; r < cells_.size(); r++)
         for (TextBox cell : cells_.get(r))
            if (!cell.getValue().trim().isEmpty())
               last = r;
      JSONArray rows = new JSONArray();
      for (int r = 0; r <= last; r++)
      {
         JSONArray row = new JSONArray();
         for (int c = 0; c < names_.size(); c++)
            row.set(c, new JSONString(cells_.get(r).get(c).getValue()));
         rows.set(r, row);
      }
      json.put("rows", rows);
      return json;
   }

   // A data frame of the session copied into the editable table
   private void copyFrame()
   {
      String dataset = frames_.getSelectedIndex() >= 0 ? frames_.getSelectedValue() : "";
      request("sheet_get", dataset, null, result -> {
         file_ = null;
         filePath_ = "";
         JsArrayString columns = result.strings("columns"), types = result.strings("types");
         JsArray<JsArrayString> rows = rowsOf(result);
         resetGrid(columns.length(), Math.max(rows.length() + 1, 2));
         for (int c = 0; c < columns.length(); c++)
         {
            names_.get(c).setValue(columns.get(c));
            select(types_.get(c), types.get(c));
         }
         for (int r = 0; r < rows.length(); r++)
            for (int c = 0; c < columns.length(); c++)
               cells_.get(r).get(c).setValue(rows.get(r).get(c));
         name_.setValue(dataset + "_2");
         created_ = "";
         code_.setText("");
         SuperRStudioTheme.status(status_, messages_.copied(dataset, String.valueOf(rows.length())), "");
      });
   }

   private static native JsArray<JsArrayString> rowsOf(LfqResult result) /*-{
      return result.rows || [];
   }-*/;

   private static void select(ListBox list, String value)
   {
      for (int i = 0; i < list.getItemCount(); i++)
         if (list.getValue(i).equals(value))
            list.setSelectedIndex(i);
   }

   // Files ------------------------------------------------------------------------

   private void openFile()
   {
      RStudioGinjector.INSTANCE.getFileDialogs().openFile(
         messages_.openFileCaption(),
         RStudioGinjector.INSTANCE.getRemoteFileSystemContext(),
         FileSystemItem.createDir("~"),
         new ProgressOperationWithInput<FileSystemItem>()
         {
            @Override public void execute(FileSystemItem input, ProgressIndicator indicator)
            {
               indicator.onCompleted();
               if (input == null)
                  return;
               path_.setValue(input.getPath());
               readNewFile();
            }
         });
   }

   // A file chosen or typed: read with automatic settings
   private void readNewFile()
   {
      if (path_.getValue().trim().isEmpty())
         return;
      name_.setValue(nameFromFile(path_.getValue().trim()));
      for (ListBox list : new ListBox[] {sep_, dec_, header_, encoding_})
         list.setSelectedIndex(0);
      sheet_.clear();
      readFile();
   }

   private JSONObject fileSettings()
   {
      JSONObject json = new JSONObject();
      json.put("path", new JSONString(filePath_));
      json.put("name", new JSONString(name_.getValue().trim()));
      json.put("sep", new JSONString(sep_.getSelectedValue()));
      json.put("dec", new JSONString(dec_.getSelectedValue()));
      json.put("header", new JSONString(header_.getSelectedValue()));
      json.put("encoding", new JSONString(encoding_.getSelectedValue()));
      json.put("sheet", new JSONString(sheet_.getSelectedIndex() >= 0 ? sheet_.getSelectedValue() : ""));
      return json;
   }

   private void readFile()
   {
      filePath_ = path_.getValue().trim();
      request("sheet_file", "", fileSettings(), result -> {
         if (result.has("need"))
         {
            SuperRStudioTheme.status(status_, messages_.needsExcel(), SuperRStudioTheme.ERROR);
            DependencyDialog.ensure(server_, "sheet", true, this::readFile, missing -> {});
            return;
         }
         file_ = result;
         created_ = "";
         showPreview(result);
      });
   }

   // A read-only preview of the file, with how it was read
   private void showPreview(LfqResult result)
   {
      table_.removeAllRows();
      names_.clear();
      types_.clear();
      cells_.clear();
      JsArrayString columns = result.strings("columns"), types = result.strings("types");
      JsArray<JsArrayString> rows = rowsOf(result);
      table_.setText(0, 0, "");
      table_.setText(1, 0, "");
      for (int c = 0; c < columns.length(); c++)
      {
         table_.setText(0, c + 1, columns.get(c));
         table_.setText(1, c + 1, typeLabel(types.get(c)));
         previewCell(0, c + 1).setProperty("fontWeight", "bold");
         previewCell(1, c + 1).setProperty("fontStyle", "italic");
      }
      for (int r = 0; r < rows.length(); r++)
      {
         table_.setText(r + 2, 0, String.valueOf(r + 1));
         previewCell(r + 2, 0).setProperty("opacity", "0.7");
         for (int c = 0; c < columns.length(); c++)
         {
            table_.setText(r + 2, c + 1, rows.get(r).get(c));
            previewCell(r + 2, c + 1);
         }
      }
      boolean excel = "excel".equals(result.str("kind"));
      String file = filePath_.substring(Math.max(filePath_.lastIndexOf('/'), filePath_.lastIndexOf('\\')) + 1);
      String total = String.valueOf((long) result.num("total"));
      String width = String.valueOf(columns.length());
      StringBuilder info = new StringBuilder(result.flag("approximate")
         ? messages_.fileRowsApprox(file, total, width)
         : messages_.fileRows(file, total, width, String.valueOf(rows.length())));
      if (!excel)
         info.append("\n").append(messages_.fileRead(separatorLabel(result.str("sep")),
            decimalLabel(result.str("dec")), encodingLabel(result.str("encoding")),
            result.flag("header") ? messages_.yes() : messages_.no()));
      JsArrayString warnings = result.strings("warnings");
      if (warnings.length() > 0)
         info.append("\n").append(messages_.warnings(warnings.join("; ")));
      fileInfo_.setText(info.toString());
      textOptions_.setVisible(!excel);
      sheetOptions_.setVisible(excel);
      if (excel)
      {
         JsArrayString sheets = result.strings("sheets");
         sheet_.clear();
         for (int i = 0; i < sheets.length(); i++)
            sheet_.addItem(sheets.get(i));
         select(sheet_, result.str("sheet"));
      }
      filePanel_.setVisible(true);
      hint_.setText(messages_.fileReadOnly());
      editTools_.setVisible(false);
      code_.setText(result.str("code"));
      status_.setText("");
      enable();
   }

   // preview cells: padded, with a light rule (readable in light and dark themes)
   private com.google.gwt.dom.client.Style previewCell(int row, int column)
   {
      com.google.gwt.dom.client.Style style = table_.getCellFormatter().getElement(row, column).getStyle();
      style.setProperty("padding", "2px 10px 2px 6px");
      style.setProperty("borderBottom", "1px solid rgba(128, 128, 128, 0.35)");
      style.setProperty("whiteSpace", "nowrap");
      return style;
   }

   private String decimalLabel(String dec)
   {
      return ",".equals(dec) ? messages_.decComma() : messages_.decPoint();
   }

   private String encodingLabel(String encoding)
   {
      return "latin1".equals(encoding) ? messages_.encLatin1()
           : "UTF-8-BOM".equals(encoding) ? messages_.encBom() : encoding;
   }

   // a syntactic R name from a file name: capturas 2024.csv -> capturas_2024
   private static String nameFromFile(String path)
   {
      String file = path.substring(Math.max(path.lastIndexOf('/'), path.lastIndexOf('\\')) + 1);
      int dot = file.lastIndexOf('.');
      String name = (dot > 0 ? file.substring(0, dot) : file).replaceAll("[^A-Za-z0-9_.]", "_");
      if (name.isEmpty() || !name.substring(0, 1).matches("[A-Za-z]"))
         name = "datos_" + name;
      return name.replaceAll("_+", "_").replaceAll("_$", "");
   }

   private String separatorLabel(String sep)
   {
      switch (sep)
      {
         case "semicolon": return messages_.sepSemicolon();
         case "tab": return messages_.sepTab();
         case "pipe": return messages_.sepPipe();
         case "space": return messages_.sepSpace();
         default: return messages_.sepComma();
      }
   }

   private String typeLabel(String type)
   {
      switch (type)
      {
         case "number": return messages_.typeNumber();
         case "date": return messages_.typeDate();
         case "datetime": return messages_.typeDatetime();
         case "logical": return messages_.typeLogical();
         case "factor": return messages_.typeFactor();
         default: return messages_.typeText();
      }
   }

   // Checking and creating ---------------------------------------------------------

   // The current code: from the table, or from the file with its settings
   private void withCode(OperationWithInput<LfqResult> done)
   {
      replace_.setVisible(false);
      if (file_ != null)
         request("sheet_file", "", fileSettings(), result -> {
            file_ = result;
            showPreview(result);
            done.execute(result);
         });
      else
         request("sheet_build", "", tableSettings(), result -> {
            code_.setText(result.str("code"));
            done.execute(result);
         });
   }

   private void check()
   {
      withCode(result -> {
         if (file_ != null)
            return;
         JsArrayString columns = result.strings("columns"), types = result.strings("types");
         StringBuilder summary = new StringBuilder();
         for (int c = 0; c < columns.length(); c++)
            summary.append(c > 0 ? ", " : "").append(columns.get(c)).append(" (")
                   .append(typeLabel(types.get(c)).toLowerCase()).append(")");
         SuperRStudioTheme.status(status_, messages_.checked(String.valueOf((long) result.num("rows")),
            String.valueOf(columns.length()), summary.toString()), "");
      });
   }

   private void create()
   {
      withCode(result -> {
         String name = result.str("name");
         expectedRows_ = (long) (file_ != null ? result.num("total") : result.num("rows"));
         expectedColumns_ = result.strings("columns").length();
         approximate_ = result.flag("approximate");
         String code = result.str("code");
         if (result.flag("exists"))
         {
            // asked in the window (desktop message boxes are native and
            // would leave the window); the Replace button runs the code
            replaceName_ = name;
            replaceCode_ = code;
            replace_.setText(messages_.overwriteTitle(name));
            replace_.setVisible(true);
            SuperRStudioTheme.status(status_, messages_.overwrite(name), "");
            replace_.setFocus(true);
         }
         else
            run(name, code);
      });
   }

   private void replace()
   {
      replace_.setVisible(false);
      run(replaceName_, replaceCode_);
   }

   // Runs the code in the console (visible and in the history); when the
   // console is back at its prompt the new data frame is checked
   private void run(String name, String code)
   {
      stopWaiting();
      created_ = "";
      pending_ = name;
      prompts_ = 0;
      SuperRStudioTheme.status(status_, messages_.running(name), SuperRStudioTheme.BUSY);
      prompt_ = events_.addHandler(ConsolePromptEvent.TYPE, event -> verify());
      events_.fireEvent(new SendToConsoleEvent(code, true));
      enable();
   }

   private void verify()
   {
      if (pending_.isEmpty())
         return;
      prompts_++;
      String name = pending_;
      request("sheet_shape", name, null, result -> {
         boolean ok = result.flag("exists") && (long) result.num("columns") == expectedColumns_ &&
                      (approximate_ || (long) result.num("rows") == expectedRows_);
         if (!ok && prompts_ < 2)
         {
            // an earlier prompt; wait for the one after the code ran
            SuperRStudioTheme.status(status_, messages_.running(name), SuperRStudioTheme.BUSY);
            return;
         }
         stopWaiting();
         if (ok)
         {
            created_ = name;
            SuperRStudioTheme.status(status_, messages_.created(name, String.valueOf((long) result.num("rows")),
               String.valueOf((long) result.num("columns"))), "");
         }
         else
            SuperRStudioTheme.status(status_, messages_.notCreated(name), SuperRStudioTheme.ERROR);
         listFrames();
         enable();
      });
   }

   private void stopWaiting()
   {
      pending_ = "";
      if (prompt_ != null)
      {
         prompt_.removeHandler();
         prompt_ = null;
      }
   }

   private void openCode()
   {
      withCode(result -> events_.fireEvent(new NewDocumentWithCodeEvent(NewDocumentWithCodeEvent.R_SCRIPT,
         result.str("code") + "\n", SourcePosition.create(1, 1), false)));
   }

   // The created data frame, selected in the plot editor or the
   // length-frequency window
   private void openPlot()
   {
      ScatterDialog.openWith(server_, events_, commands_, created_);
   }

   private void openLfq()
   {
      LfqDialog.openWith(server_, events_, created_);
   }

   private void listFrames()
   {
      quietRequest("sheet_list", result -> {
         String selected = frames_.getSelectedIndex() >= 0 ? frames_.getSelectedValue() : "";
         JsArrayString names = result.strings("datasets");
         frames_.clear();
         for (int i = 0; i < names.length(); i++)
            frames_.addItem(names.get(i));
         select(frames_, selected);
         enable();
      });
   }

   private void enable()
   {
      boolean ready = !busy_ && pending_.isEmpty();
      for (ThemedButton button : new ThemedButton[] {newTable_, openFile_, check_, create_, openCode_, reread_})
         button.setEnabled(ready);
      copy_.setEnabled(ready && frames_.getItemCount() > 0);
      plot_.setEnabled(ready && !created_.isEmpty());
      lfq_.setEnabled(ready && !created_.isEmpty());
   }

   // Requests ------------------------------------------------------------------------

   private void request(String operation, String dataset, JSONObject json, OperationWithInput<LfqResult> done)
   {
      busy_ = true;
      enable();
      SuperRStudioTheme.status(status_, messages_.working(), SuperRStudioTheme.BUSY);
      server_.superrstudioData(operation, dataset, "", "", "", json, new ServerRequestCallback<ScatterResult>()
      {
         @Override public void onResponseReceived(ScatterResult response)
         {
            busy_ = false;
            if (!isAttached()) return;
            SuperRStudioTheme.status(status_, "", "");
            done.execute(response.cast());
            enable();
         }

         @Override public void onError(ServerError error)
         {
            busy_ = false;
            if (!isAttached()) return;
            SuperRStudioTheme.status(status_, message(error), SuperRStudioTheme.ERROR);
            enable();
         }
      });
   }

   private void quietRequest(String operation, OperationWithInput<LfqResult> done)
   {
      server_.superrstudioData(operation, "", "", "", "", null, new ServerRequestCallback<ScatterResult>()
      {
         @Override public void onResponseReceived(ScatterResult response)
         {
            if (isAttached())
               done.execute(response.cast());
         }

         @Override public void onError(ServerError error)
         {
         }
      });
   }

   private static String message(ServerError error)
   {
      JSONValue info = error.getClientInfo();
      return info != null && info.isString() != null ? info.isString().stringValue() : error.getUserMessage();
   }

   private final SuperRStudioServerOperations server_;
   private final EventBus events_;
   private final Commands commands_;
   private final FlexTable table_ = new FlexTable();
   private final ScrollPanel scroll_ = new ScrollPanel(table_);
   private final List<TextBox> names_ = new ArrayList<>();
   private final List<ListBox> types_ = new ArrayList<>();
   private final List<List<TextBox>> cells_ = new ArrayList<>();
   private final TextBox name_ = new TextBox(), path_ = new TextBox();
   private final ListBox frames_ = new ListBox();
   private final ListBox sep_ = new ListBox(), dec_ = new ListBox(), header_ = new ListBox(),
      encoding_ = new ListBox(), sheet_ = new ListBox();
   private final VerticalPanel filePanel_ = new VerticalPanel();
   private final HorizontalPanel textOptions_ = new HorizontalPanel(), sheetOptions_ = new HorizontalPanel(),
      editTools_ = new HorizontalPanel();
   private final Label fileInfo_ = new Label(), hint_ = new Label(), status_ = new Label();
   private final TextArea code_ = new TextArea();
   private final ThemedButton newTable_ = new ThemedButton(messages_.newTable(), e -> newTable());
   private final ThemedButton openFile_ = new ThemedButton(messages_.openFile(), e -> openFile());
   private final ThemedButton copy_ = new ThemedButton(messages_.copy(), e -> copyFrame());
   private final ThemedButton reread_ = new ThemedButton(messages_.reread(), e -> readFile());
   private final ThemedButton addRow_ = new ThemedButton(messages_.addRow(), e -> addRow());
   private final ThemedButton addColumn_ = new ThemedButton(messages_.addColumn(), e -> addColumn());
   private final ThemedButton removeRow_ = new ThemedButton(messages_.removeRow(), e -> removeRow());
   private final ThemedButton removeColumn_ = new ThemedButton(messages_.removeColumn(), e -> removeColumn());
   private final ThemedButton clear_ = new ThemedButton(messages_.clear(), e -> {
      file_ = null;
      resetGrid(Math.max(names_.size(), 1), Math.max(cells_.size(), 1));
   });
   private final ThemedButton check_ = new ThemedButton(messages_.check(), e -> check());
   private final ThemedButton create_ = new ThemedButton(messages_.create(), e -> create());
   private final ThemedButton replace_ = new ThemedButton("", e -> replace());
   private final ThemedButton openCode_ = new ThemedButton(messages_.openCode(), e -> openCode());
   private final ThemedButton plot_ = new ThemedButton(messages_.plot(), e -> openPlot());
   private final ThemedButton lfq_ = new ThemedButton(messages_.lfq(), e -> openLfq());
   private final ThemedButton close_ = new ThemedButton(messages_.close(), e -> hide());
   private LfqResult file_;
   private String filePath_ = "", created_ = "", pending_ = "", replaceName_ = "", replaceCode_ = "";
   private long expectedRows_;
   private int expectedColumns_, prompts_;
   private boolean busy_ = false, approximate_ = false;
   private HandlerRegistration prompt_;
   private static SheetDialog instance_;
   private static final SheetMessages messages_ = SuperRStudioLanguage.sheet();
   private static final int MAX_ROWS = 2000, MAX_COLUMNS = 100;
}
