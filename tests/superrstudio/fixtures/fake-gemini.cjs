// Simulated Gemini API for the Chat IA GUI tests (no Google service, no quota).
// SPDX-License-Identifier: AGPL-3.0-only
//
//   node fake-gemini.cjs <port>
//
// Listens on 127.0.0.1 only. SuperR uses it when the desktop is started with
// SUPER_RSTUDIO_GEMINI_TEST_BASE=http://127.0.0.1:<port>/v1beta (accepted for
// the loopback address only). The key "AIzaFakeSuperRGuiTestKey000000000000" is
// valid; any other key is rejected like Google does. The answer depends on the
// last user message: "markdown" streams formatted text (with HTML and a
// javascript: link that must stay inert), "lento"/"slow" streams slowly until
// cancelled, "cuota"/"quota" returns Google's 429 body, "retirado"/"retired"
// returns 404; anything else gets a short answer.
//
// Project context (function calling): when the request offers functions and
// the message asks to analyse ("analiz"), the fake model calls
// read_project_files for the scripts in SuperR's index, with a thought
// signature; given the function results (and only if the signature came back,
// as Gemini 3 requires) it lists each file with its first line. With "cuota"
// the second request gets a 429. A message carrying SuperR's attached document
// is answered with the document name, whether it had unsaved changes and its
// first line.
const http = require('node:http');

const port = Number(process.argv[2] || 19395);
const KEY = 'AIzaFakeSuperRGuiTestKey000000000000';
const MARKDOWN = [
  '### Resumen de `mean()`\n\n',
  '`mean()` calcula la **media aritmética** de un vector numérico. Con *na.rm = TRUE* ',
  'ignora los valores faltantes.\n\n',
  '- Argumento `x`: el vector\n- `trim`: fracción recortada\n  - entre 0 y 0.5\n- `na.rm`: lógico\n\n',
  '1. Primero\n2. Segundo\n\n',
  '| Función | Uso |\n|---|---|\n| `mean()` | media |\n| `median()` | mediana |\n\n',
  'Más en [la documentación](https://stat.ethz.ch/R-manual/R-devel/library/base/html/mean.html) ',
  'y [esto no](javascript:alert(1)). <script>window.superrInjected = true</script> <b>no negrita</b>\n\n',
  '```r\n# media sin faltantes\nx <- c(1, 2, NA, 4)\nmean(x, na.rm = TRUE)\n',
  'library(ggplot2)\nggplot(df, aes(x = talla)) + geom_histogram(bins = 20)\n```\n\n',
  '> Nota: devuelve `NA` si hay faltantes y `na.rm = FALSE`.\n',
];

function json(res, status, body) {
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(body));
}
function chunk(text, finish) {
  return `data: ${JSON.stringify({ candidates: [{ content: { role: 'model', parts: [{ text }] },
    ...(finish ? { finishReason: 'STOP' } : {}) }] })}\r\n\r\n`;
}

http.createServer((req, res) => {
  if (req.headers['x-goog-api-key'] !== KEY)
    return json(res, 400, { error: { code: 400, status: 'INVALID_ARGUMENT', message: 'API key not valid. Please pass a valid API key.',
      details: [{ '@type': 'type.googleapis.com/google.rpc.ErrorInfo', reason: 'API_KEY_INVALID' }] } });
  if (req.method === 'GET' && req.url.startsWith('/v1beta/models'))
    return json(res, 200, { models: ['gemini-3.6-flash', 'gemini-3.5-flash-lite'].map(id =>
      ({ name: `models/${id}`, supportedGenerationMethods: ['generateContent'] })) });
  const match = /^\/v1beta\/models\/([^:]+):streamGenerateContent\?alt=sse$/.exec(req.url);
  if (req.method !== 'POST' || !match) return json(res, 404, { error: { code: 404, status: 'NOT_FOUND', message: 'Not found' } });
  let body = '';
  req.on('data', d => { body += d; });
  req.on('end', async () => {
    const request = JSON.parse(body);
    const contents = request.contents;
    const lastParts = contents[contents.length - 1].parts;
    if (lastParts[0].functionResponse) {
      const asked = contents[contents.length - 3]?.parts[0]?.text?.toLowerCase() ?? '';
      const previous = contents[contents.length - 2];
      if (!previous.parts.some(part => part.thoughtSignature === 'fake-signature'))
        return json(res, 400, { error: { code: 400, status: 'INVALID_ARGUMENT', message: 'Function call is missing a thought_signature' } });
      if (/cuota|quota/.test(asked))
        return json(res, 429, { error: { code: 429, status: 'RESOURCE_EXHAUSTED', message: 'quota', details: [
          { '@type': 'type.googleapis.com/google.rpc.QuotaFailure', violations: [{ quotaId: 'GenerateRequestsPerDayPerProjectPerModel-FreeTier', quotaValue: '20' }] }] } });
      const files = lastParts.flatMap(part => part.functionResponse.response.files ?? []);
      const lines = files.map(f => f.content !== undefined ? `- **${f.path}**: ${f.content.split(/\r?\n/)[0]}` :
        `- ${f.path}: ${f.error ? 'no legible' : 'sin contenido'}`);
      res.writeHead(200, { 'Content-Type': 'text/event-stream' });
      res.end(chunk(`Leí ${files.length} archivos del proyecto:\n\n${lines.join('\n')}\n`, true));
      return;
    }
    const last = lastParts[0].text.toLowerCase();
    if (request.tools && /analiz/.test(last)) {
      const index = request.systemInstruction?.parts[0]?.text ?? '';
      const scripts = [...index.matchAll(/^(\S+\.R) \(/gm)].map(m => m[1]).slice(0, 4);
      res.writeHead(200, { 'Content-Type': 'text/event-stream' });
      res.end(`data: ${JSON.stringify({ candidates: [{ content: { role: 'model', parts: [
        { text: 'Voy a leer los scripts. ' },
        { functionCall: { name: 'read_project_files', args: { paths: scripts } }, thoughtSignature: 'fake-signature' }] },
        finishReason: 'STOP' }] })}\r\n\r\n`);
      return;
    }
    const attached = /^\[superr attached the active editor document "([^"]+)"( \(with unsaved changes\))?/i.exec(lastParts[0].text);
    if (attached) {
      const code = lastParts[0].text.split('\n')[2] ?? '';
      res.writeHead(200, { 'Content-Type': 'text/event-stream' });
      res.end(chunk(`Recibí el documento "${attached[1]}" (sin guardar: ${attached[2] ? 'sí' : 'no'}). Primera línea: ${code}`, true));
      return;
    }
    if (/cuota|quota/.test(last))
      return json(res, 429, { error: { code: 429, status: 'RESOURCE_EXHAUSTED', message: 'You exceeded your current quota.', details: [
        { '@type': 'type.googleapis.com/google.rpc.QuotaFailure', violations: [{ quotaId: 'GenerateRequestsPerMinutePerProjectPerModel-FreeTier', quotaValue: '5' }] },
        { '@type': 'type.googleapis.com/google.rpc.RetryInfo', retryDelay: '17s' }] } });
    if (/retirado|retired/.test(last))
      return json(res, 404, { error: { code: 404, status: 'NOT_FOUND', message: `models/${match[1]} is not found` } });
    res.writeHead(200, { 'Content-Type': 'text/event-stream' });
    let closed = false;
    res.on('close', () => { closed = true; });
    const parts = /markdown/.test(last) ? MARKDOWN : /lent[oa]|slow/.test(last) ?
      Array.from({ length: 200 }, (_, i) => `palabra ${i} `) : [`Respuesta simulada a: ${last.slice(0, 40)} (turnos: ${contents.length})`];
    const delay = /lent[oa]|slow/.test(last) ? 150 : 40;
    for (let i = 0; i < parts.length && !closed; i++) {
      res.write(chunk(parts[i], i === parts.length - 1));
      await new Promise(r => setTimeout(r, delay));
    }
    res.end();
  });
}).listen(port, '127.0.0.1', () => console.log(`fake Gemini on http://127.0.0.1:${port}/v1beta`));
