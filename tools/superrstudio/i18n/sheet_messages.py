# Generates SheetMessages.java and SheetMessages_es.properties (the data table
# window) from one English/Spanish table, then the Spanish Java
# implementations. Run from anywhere:
#   python tools/superrstudio/i18n/sheet_messages.py
# Messages use java.text.MessageFormat: {0} are parameters and a single quote
# is written once here (the generator doubles it).
import os
import re
import runpy

base = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..',
                    'src/gwt/src/org/rstudio/studio/client/workbench/views/superrstudio/')
M = [
    ('title', 'Data table', 'Tabla de datos'),
    ('toolbarLabel', 'Data table', 'Tabla de datos'),
    ('toolbarTitle', 'Type, paste or load data into a data frame', 'Escribir, pegar o cargar datos en un data frame'),
    ('help', 'Type values or paste cells from Excel or LibreOffice, open a CSV, text or Excel file, or copy a data frame of this session. SuperR writes the R code that creates the data frame and runs it in the console, so it stays in the history and can be repeated.',
     'Escribe valores o pega celdas desde Excel o LibreOffice, abre un archivo CSV, de texto o Excel, o copia un data frame de esta sesión. SuperR escribe el código R que crea el data frame y lo ejecuta en la consola, así queda en el historial y se puede repetir.'),
    ('newTable', 'New table', 'Nueva tabla'),
    ('openFile', 'Open file…', 'Abrir archivo…'),
    ('pathLabel', 'File path', 'Ruta del archivo'),
    ('pathPlaceholder', 'or paste the path of a CSV, text or Excel file and press Enter', 'o pega la ruta de un archivo CSV, de texto o Excel y pulsa Enter'),
    ('openFileCaption', 'Open a data file (CSV, text or Excel)', 'Abrir un archivo de datos (CSV, texto o Excel)'),
    ('copyFrom', 'Copy a data frame of this session', 'Copiar un data frame de esta sesión'),
    ('copy', 'Copy into the table', 'Copiar a la tabla'),
    ('pasteHint', 'Paste from Excel or LibreOffice: select the cells, copy them and paste (Ctrl+V) into a cell. Pasted into a column name, the first row becomes the column names. Numbers may use a decimal point or comma (12.5 or 12,5); dates 2024-03-15 or 15/03/2024 (day first). Empty cells are missing values. Enter moves down.',
     'Pegar desde Excel o LibreOffice: selecciona las celdas, cópialas y pégalas (Ctrl+V) en una celda. Pegadas en un nombre de columna, la primera fila pasa a ser los nombres de columna. Los números pueden llevar punto o coma decimal (12.5 o 12,5); las fechas 2024-03-15 o 15/03/2024 (día primero). Las celdas vacías son valores faltantes. Enter baja a la fila siguiente.'),
    ('columnName', 'Name of column {0}', 'Nombre de la columna {0}'),
    ('columnType', 'Type of column {0}', 'Tipo de la columna {0}'),
    ('cell', 'Row {0}, column {1}', 'Fila {0}, columna {1}'),
    ('namePlaceholder', 'name', 'nombre'),
    ('typeAuto', 'Automatic', 'Automático'),
    ('typeNumber', 'Number', 'Número'),
    ('typeText', 'Text', 'Texto'),
    ('typeDate', 'Date', 'Fecha'),
    ('typeDatetime', 'Date-time', 'Fecha y hora'),
    ('typeLogical', 'Logical', 'Lógico'),
    ('typeFactor', 'Factor', 'Factor'),
    ('addRow', 'Add row', 'Añadir fila'),
    ('addColumn', 'Add column', 'Añadir columna'),
    ('removeRow', 'Remove last row', 'Quitar última fila'),
    ('removeColumn', 'Remove last column', 'Quitar última columna'),
    ('clear', 'Clear', 'Vaciar'),
    ('limitRows', 'The table holds at most {0} rows; load larger data from a file.', 'La tabla admite como máximo {0} filas; carga datos más grandes desde un archivo.'),
    ('limitColumns', 'The table holds at most {0} columns.', 'La tabla admite como máximo {0} columnas.'),
    ('objectName', 'Name of the data frame', 'Nombre del data frame'),
    ('separator', 'Separator', 'Separador'),
    ('sepComma', 'Comma', 'Coma'),
    ('sepSemicolon', 'Semicolon', 'Punto y coma'),
    ('sepTab', 'Tab', 'Tabulador'),
    ('sepPipe', 'Vertical bar (|)', 'Barra vertical (|)'),
    ('sepSpace', 'Spaces', 'Espacios'),
    ('decimal', 'Decimal mark', 'Separador decimal'),
    ('decPoint', 'Point (12.5)', 'Punto (12.5)'),
    ('decComma', 'Comma (12,5)', 'Coma (12,5)'),
    ('header', 'Column names in the first row', 'Nombres de columna en la primera fila'),
    ('yes', 'Yes', 'Sí'),
    ('no', 'No', 'No'),
    ('encoding', 'Encoding', 'Codificación'),
    ('encBom', 'UTF-8 with BOM', 'UTF-8 con BOM'),
    ('encLatin1', 'Latin-1 (Windows)', 'Latin-1 (Windows)'),
    ('automatic', 'Automatic', 'Automático'),
    ('sheet', 'Sheet', 'Hoja'),
    ('reread', 'Read again', 'Volver a leer'),
    ('fileRows', '{0}: {1} rows and {2} columns. The preview shows the first {3} rows; the code reads the whole file.',
     '{0}: {1} filas y {2} columnas. La vista previa muestra las primeras {3} filas; el código lee el archivo completo.'),
    ('fileRowsApprox', '{0}: about {1} rows (a large file: the preview reads the first ones) and {2} columns. The code reads the whole file.',
     '{0}: unas {1} filas (archivo grande: la vista previa lee las primeras) y {2} columnas. El código lee el archivo completo.'),
    ('fileRead', 'Read with: separator {0}, decimal mark {1}, encoding {2}, column names in the first row: {3}.',
     'Leído con: separador {0}, separador decimal {1}, codificación {2}, nombres de columna en la primera fila: {3}.'),
    ('fileReadOnly', 'This is a preview of the file and cannot be edited here. New table starts an empty table.',
     'Esta es una vista previa del archivo y no se edita aquí. Nueva tabla empieza una tabla vacía.'),
    ('warnings', 'Warnings while reading: {0}', 'Advertencias al leer: {0}'),
    ('copied', 'Copied {0} ({1} rows). Edit it and create it under a new name, or replace the original.',
     'Copiado {0} ({1} filas). Edítalo y créalo con otro nombre, o reemplaza el original.'),
    ('check', 'Check', 'Revisar'),
    ('checked', '{0} rows and {1} columns: {2}.', '{0} filas y {1} columnas: {2}.'),
    ('create', 'Create in the session', 'Crear en la sesión'),
    ('overwriteTitle', 'Replace {0}', 'Reemplazar {0}'),
    ('overwrite', 'An object named {0} already exists in this session. Replace it with the new data frame?',
     'Ya existe un objeto llamado {0} en esta sesión. ¿Reemplazarlo por el nuevo data frame?'),
    ('running', 'Creating {0} in the console…', 'Creando {0} en la consola…'),
    ('created', '{0} is ready in the session: {1} rows and {2} columns. Open it in the plot editor or the length-frequency window.',
     '{0} está listo en la sesión: {1} filas y {2} columnas. Ábrelo en el editor de gráficos o en la ventana de frecuencia de tallas.'),
    ('notCreated', '{0} was not created as expected; see the message in the console.', '{0} no se creó como se esperaba; mira el mensaje en la consola.'),
    ('openCode', 'Open R code', 'Abrir código R'),
    ('plot', 'Plot editor', 'Editor de gráficos'),
    ('lfq', 'Length frequency', 'Frecuencia de tallas'),
    ('close', 'Close', 'Cerrar'),
    ('working', 'Working…', 'Trabajando…'),
    ('needsExcel', 'Reading Excel files needs the readxl package.', 'Leer archivos Excel necesita el paquete readxl.'),
]
java = ['// SPDX-License-Identifier: AGPL-3.0-only',
        'package org.rstudio.studio.client.workbench.views.superrstudio;',
        'import com.google.gwt.i18n.client.Messages;',
        '// Generated by tools/superrstudio/i18n/sheet_messages.py; keep both files in step.',
        'public interface SheetMessages extends Messages',
        '{']


def arity(text):
    found = [int(m) for m in re.findall(r'\{(\d+)\}', text)]
    return max(found) + 1 if found else 0


for key, en, es in M:
    params = ', '.join('String p%d' % i for i in range(arity(en)))
    escaped = en.replace('\\', '\\\\').replace('"', '\\"').replace("'", "''")
    java.append('   @DefaultMessage("%s") String %s(%s);' % (escaped, key, params))
java.append('}')
open(base + 'SheetMessages.java', 'w', encoding='utf-8', newline='\n').write('\n'.join(java) + '\n')
props = ['# Spanish messages for SheetMessages (generated alongside the Java interface)']
for key, en, es in M:
    props.append('%s=%s' % (key, es.replace("'", "''")))
open(base + 'SheetMessages_es.properties', 'w', encoding='utf-8', newline='\n').write('\n'.join(props) + '\n')
keys = [key for key, en, es in M]
assert len(keys) == len(set(keys)), 'duplicate message keys'
for key, en, es in M:
    assert arity(en) == arity(es), key
print('ok', len(M))
runpy.run_path(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'spanish_messages.py'))
