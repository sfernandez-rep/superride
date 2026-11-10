// Creates the R project used by the Chat IA project-context tests.
// SPDX-License-Identifier: AGPL-3.0-only
//
//   node make-chat-project.cjs <parent directory>
//
// Writes <parent>/pesquerias (an RStudio project with related scripts, a large
// CSV, binary R data, a Unicode file name, a .env file and a link that points
// outside the project) and <parent>/fuera.R (outside the project). Prints the
// .Rproj path. An existing project is replaced.
const fs = require('node:fs');
const path = require('node:path');

const parent = path.resolve(process.argv[2]);
const root = path.join(parent, 'pesquerias');
fs.rmSync(root, { recursive: true, force: true });
fs.mkdirSync(path.join(root, 'R'), { recursive: true });
fs.mkdirSync(path.join(root, 'datos'), { recursive: true });
const write = (file, text) => fs.writeFileSync(path.join(root, file), text);
write('pesquerias.Rproj', 'Version: 1.0\n\nRestoreWorkspace: No\nSaveWorkspace: No\n');
write('R/01-cargar.R', [
  '# 01-cargar.R: lee las tallas y prepara la frecuencia de tallas',
  'library(TropFishR)',
  'tallas <- read.csv("datos/tallas.csv")',
  'tallas$talla_cm <- tallas$talla / 10',
  'lfq <- lfqCreate(tallas, Lname = "talla_cm", Dname = "fecha", bin_size = 2)',
  'source("R/02-graficos.R")',
  '',
].join('\n'));
write('R/02-graficos.R', [
  '# 02-graficos.R: histograma de tallas con ggplot2',
  'library(ggplot2)',
  'p <- ggplot(tallas, aes(x = talla_cm)) +',
  '  geom_histogram(binwidth = 2, fill = "steelblue") +',
  '  labs(x = "Talla (cm)", y = "Frecuencia")',
  'print(p)',
  '',
].join('\n'));
// known errors for the edit tests: an unclosed call and a misspelt ggplot2 argument
write('R/03-errores.R', [
  '# 03-errores.R: talla media y gráfico (con errores conocidos)',
  'library(ggplot2)',
  'media <- mean(tallas$talla_cm, na.rm = TRUE',
  'g <- ggplot(tallas, aes(x = talla_cm)) + geom_histogram(binwdth = 2)',
  'print(g)',
  '',
].join('\n'));
write('análisis_ñandú.R', '# análisis_ñandú.R: resumen con acentos\nresumen <- summary(tallas$talla_cm)\nprint(resumen)\n');
write('datos/tallas.csv', 'fecha,talla,peso\n' +
  Array.from({ length: 8000 }, (_, i) => `2024-0${1 + (i % 9)}-15,${100 + (i % 400)},${(i % 50) / 10}`).join('\n') + '\n');
fs.writeFileSync(path.join(root, 'datos', 'modelo.rds'), Buffer.from([0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00]));
write('.env', 'GEMINI_API_KEY=no-debe-salir-del-proyecto\n');
fs.writeFileSync(path.join(parent, 'fuera.R'), 'secreto_fuera <- "no debe leerse"\n');
const link = path.join(root, 'enlace');
try { fs.symlinkSync(parent, link, process.platform === 'win32' ? 'junction' : 'dir'); }
catch (error) { console.error(`link not created: ${error.message}`); }
console.log(path.join(root, 'pesquerias.Rproj'));
