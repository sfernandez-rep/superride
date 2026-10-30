# Generates DependencyMessages.java and DependencyMessages_es.properties (the
# optional-package dialog) from one English/Spanish table, then the Spanish
# Java implementations. Run from anywhere:
#   python tools/superrstudio/i18n/deps_messages.py
# Messages use java.text.MessageFormat: {0} are parameters and a single quote
# is written once here (the generator doubles it).
import os
import re
import runpy

base = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..',
                    'src/gwt/src/org/rstudio/studio/client/workbench/views/superrstudio/')
M = [
    ('title', 'R packages for SuperR', 'Paquetes de R para SuperR'),
    ('featurePlot', 'The plot editor', 'El editor de gráficos'),
    ('featureLfq', 'Length-frequency analysis', 'El análisis de frecuencias de tallas'),
    ('featureSheet', 'Reading Excel files', 'La lectura de archivos Excel'),
    ('intro', '{0} needs R packages that are not available in this R session:', '{0} necesita paquetes de R que no están disponibles en esta sesión de R:'),
    ('packageMissing', '{0} {1} or newer: not installed', '{0} {1} o más reciente: no instalado'),
    ('packageOld', '{0} {1} or newer: version {2} is installed', '{0} {1} o más reciente: está instalada la versión {2}'),
    ('whyGgplot2', 'ggplot2 draws the preview and is used by the generated plotting code.', 'ggplot2 dibuja la vista previa y lo usa el código de gráficos generado.'),
    ('whyReadxl', 'readxl reads .xlsx and .xls files; CSV and text files need no package.', 'readxl lee archivos .xlsx y .xls; los archivos CSV y de texto no necesitan ningún paquete.'),
    ('whyTropfishr', 'TropFishR performs the analyses (length-frequency data, ELEFAN growth, mortality, yield per recruit).', 'TropFishR realiza los análisis (datos de frecuencias de tallas, crecimiento ELEFAN, mortalidad, rendimiento por recluta).'),
    ('checking', 'Checking the package repository…', 'Consultando el repositorio de paquetes…'),
    ('version', 'Version to install: {0}.', 'Versión a instalar: {0}.'),
    ('dependencies', 'It also installs {0} package(s) it depends on: {1}.', 'También instala {0} paquete(s) de los que depende: {1}.'),
    ('noDependencies', 'No other packages are needed.', 'No se necesitan otros paquetes.'),
    ('source', 'Source: {0} (installed with install.packages(); binary packages where available).', 'Origen: {0} (se instala con install.packages(); paquetes binarios cuando están disponibles).'),
    ('target', 'Library: {0}', 'Biblioteca: {0}'),
    ('renv', 'This project uses renv ({0}): the packages go into the project library only. renv.lock is not changed; run renv::snapshot() to record them.', 'Este proyecto usa renv ({0}): los paquetes van solo a la biblioteca del proyecto. renv.lock no se modifica; ejecuta renv::snapshot() para registrarlos.'),
    ('notWritable', 'This library is not writable, so SuperR cannot install here. Install the packages into a library you can write to (for example with install.packages() in the console), then try again.', 'Esta biblioteca no admite escritura, así que SuperR no puede instalar aquí. Instala los paquetes en una biblioteca con permiso de escritura (por ejemplo con install.packages() en la consola) y vuelve a intentarlo.'),
    ('problemRepository', 'The package repository could not be read. Check the network connection or the repos option (options("repos")).', 'No se pudo leer el repositorio de paquetes. Revisa la conexión de red o la opción repos (options("repos")).'),
    ('problemUnavailable', 'The package is not available from the configured repository.', 'El paquete no está disponible en el repositorio configurado.'),
    ('problemVersion', 'The repository does not offer a recent enough version.', 'El repositorio no ofrece una versión suficientemente reciente.'),
    ('consent', 'Nothing is installed unless you choose Install. The rest of SuperR stays usable while packages install.', 'No se instala nada salvo que elijas Instalar. El resto de SuperR sigue disponible mientras se instalan los paquetes.'),
    ('install', 'Install', 'Instalar'),
    ('cancel', 'Cancel', 'Cancelar'),
    ('stop', 'Stop installation', 'Detener la instalación'),
    ('close', 'Close', 'Cerrar'),
    ('installing', 'Installing… {0}', 'Instalando… {0}'),
    ('done', 'Installed and checked. Continuing.', 'Instalado y verificado. Continuando.'),
    ('failed', 'The installation failed:', 'La instalación falló:'),
    ('stopped', 'Installation stopped.', 'Instalación detenida.'),
    ('locks', 'The interrupted installation left these folders in {0}: {1}. R removes them at the next installation, or you can delete them.', 'La instalación interrumpida dejó estas carpetas en {0}: {1}. R las elimina en la próxima instalación, o puedes borrarlas.'),
    ('missingHint', '{0} needs {1}, which is not installed.', '{0} necesita {1}, que no está instalado.'),
    ('installButton', 'Install {0}…', 'Instalar {0}…'),
]
java = ['// SPDX-License-Identifier: AGPL-3.0-only',
        'package org.rstudio.studio.client.workbench.views.superrstudio;',
        'import com.google.gwt.i18n.client.Messages;',
        '// Generated by tools/superrstudio/i18n/deps_messages.py; keep both files in step.',
        'public interface DependencyMessages extends Messages',
        '{']


def arity(text):
    found = [int(m) for m in re.findall(r'\{(\d+)\}', text)]
    return max(found) + 1 if found else 0


for key, en, es in M:
    params = ', '.join('String p%d' % i for i in range(arity(en)))
    escaped = en.replace('\\', '\\\\').replace('"', '\\"').replace("'", "''")
    java.append('   @DefaultMessage("%s") String %s(%s);' % (escaped, key, params))
java.append('}')
open(base + 'DependencyMessages.java', 'w', encoding='utf-8', newline='\n').write('\n'.join(java) + '\n')
props = ['# Spanish messages for DependencyMessages (generated alongside the Java interface)']
for key, en, es in M:
    props.append('%s=%s' % (key, es.replace("'", "''")))
open(base + 'DependencyMessages_es.properties', 'w', encoding='utf-8', newline='\n').write('\n'.join(props) + '\n')
keys = [key for key, en, es in M]
assert len(keys) == len(set(keys)), 'duplicate message keys'
for key, en, es in M:
    assert arity(en) == arity(es), key
print('ok', len(M))
runpy.run_path(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'spanish_messages.py'))
