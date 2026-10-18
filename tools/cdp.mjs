// Web sürümünü headless Chrome'da sürmek için küçük DevTools Protocol aracı (bağımlılıksız).
// Sayfayı açar, konsol hatalarını toplar, adımları (JS değerlendirme / bekleme / ekran görüntüsü) çalıştırır.
//
// Kullanım: node tools/cdp.mjs <url> <genişlik> <yükseklik> <ölçek> <adımlar.json> <çıktı-klasörü>
// adımlar.json: [{ "eval": "js ifadesi", "wait": ms, "shot": "dosya.png" }, ...]
// Genişlik 800'den küçükse dokunmatik telefon taklit edilir.
import { spawn } from 'node:child_process';
import { writeFileSync, readFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const [url, w, h, scale, stepsFile, outDir] = process.argv.slice(2);
const steps = JSON.parse(readFileSync(stepsFile, 'utf8'));
const port = 9300 + Math.floor(Math.random() * 500);
const chrome = spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', [
  '--headless=new', `--remote-debugging-port=${port}`, '--disable-gpu', '--hide-scrollbars',
  `--user-data-dir=${mkdtempSync(join(tmpdir(), 'cdp-'))}`, 'about:blank',
], { stdio: 'ignore' });

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let target;
for (let i = 0; i < 50 && !target; i++) {
  await sleep(200);
  try {
    const list = await (await fetch(`http://127.0.0.1:${port}/json`)).json();
    target = list.find((t) => t.type === 'page');
  } catch {}
}
const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((r) => ws.addEventListener('open', r));
let id = 0;
const pending = new Map();
const logs = [];
ws.addEventListener('message', (ev) => {
  const msg = JSON.parse(ev.data);
  if (msg.id && pending.has(msg.id)) { pending.get(msg.id)(msg); pending.delete(msg.id); }
  if (msg.method === 'Runtime.consoleAPICalled') logs.push(`[${msg.params.type}] ${msg.params.args.map((a) => a.value ?? a.description).join(' ')}`);
  if (msg.method === 'Runtime.exceptionThrown') logs.push(`[exception] ${msg.params.exceptionDetails.exception?.description ?? msg.params.exceptionDetails.text}`);
  if (msg.method === 'Log.entryAdded' && msg.params.entry.level !== 'verbose') logs.push(`[log:${msg.params.entry.level}] ${msg.params.entry.text}`);
});
const send = (method, params = {}) => new Promise((resolve) => { const i = ++id; pending.set(i, resolve); ws.send(JSON.stringify({ id: i, method, params })); });

await send('Runtime.enable');
await send('Log.enable');
await send('Page.enable');
const mobile = Number(w) < 800;
await send('Emulation.setDeviceMetricsOverride', { width: Number(w), height: Number(h), deviceScaleFactor: Number(scale), mobile });
if (mobile) await send('Emulation.setTouchEmulationEnabled', { enabled: true, maxTouchPoints: 5 });
await send('Page.navigate', { url });
await sleep(2500);

for (const step of steps) {
  if (step.eval) {
    const r = await send('Runtime.evaluate', { expression: step.eval, awaitPromise: true, returnByValue: true });
    const v = r.result?.result?.value;
    if (r.result?.exceptionDetails) logs.push(`[eval-error] ${r.result.exceptionDetails.exception?.description}`);
    else if (v !== undefined) logs.push(`[eval] ${typeof v === 'string' ? v : JSON.stringify(v)}`);
  }
  if (step.wait) await sleep(step.wait);
  if (step.shot) {
    const r = await send('Page.captureScreenshot', { format: 'png' });
    writeFileSync(join(outDir, step.shot), Buffer.from(r.result.data, 'base64'));
  }
}
console.log(logs.join('\n') || '(konsol temiz)');
ws.close();
chrome.kill();
process.exit(0);
