// Arkadaş grubunun günlük skor tablosu. Veriler Vercel Blob'da (özel depo) saklanır:
// board/<grup>/<gün>/<kategori>/<oyuncu>.json → { nick, guesses, won, hints, expert, at }
// GET  /api/board?group=abcd2345&day=312  → { day, results: { turkey: [ ... ], europe: [ ... ] } }
// POST /api/board { group, day, category, player, nick, guesses, won, hints, expert }
// Hesap yok: gruba davet bağlantısıyla girilir, takma ad yeter (arkadaşlar arası, güven esaslı).
const { get, list, put } = require('@vercel/blob');

const CATEGORIES = ['turkey', 'europe', 'world', 'asia', 'africa', 'northAmerica', 'southAmerica', 'oceania'];
const GROUP = /^[a-z0-9]{8}$/;
const PLAYER = /^[a-z0-9]{10}$/;
const EPOCH = Date.UTC(2026, 0, 1);
const today = () => Math.floor((Date.now() - EPOCH) / 86_400_000);

function send(res, status, body) {
  res.statusCode = status;
  res.setHeader('Content-Type', 'application/json');
  res.setHeader('Cache-Control', 'no-store');
  res.end(JSON.stringify(body));
}

async function readBody(req) {
  if (req.body && typeof req.body === 'object') return req.body;
  const chunks = [];
  for await (const c of req) chunks.push(c);
  try { return JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}'); } catch { return {}; }
}

/** Gün, sunucunun gününden en çok 2 gün sapabilir (saat dilimleri). */
const validDay = (d) => Number.isInteger(d) && Math.abs(d - today()) <= 2;

module.exports = async (req, res) => {
  if (!process.env.BLOB_READ_WRITE_TOKEN && !process.env.BLOB_STORE_ID) return send(res, 503, { error: 'storage' });
  try {
    if (req.method === 'GET') {
      const url = new URL(req.url, 'http://x');
      const group = url.searchParams.get('group') ?? '';
      const day = Number(url.searchParams.get('day'));
      if (!GROUP.test(group) || !validDay(day)) return send(res, 400, { error: 'params' });
      const { blobs } = await list({ prefix: `board/${group}/${day}/`, limit: 1000 });
      const results = {};
      await Promise.all(blobs.map(async (b) => {
        const category = b.pathname.split('/')[3];
        const player = b.pathname.split('/')[4]?.replace('.json', '');
        const r = await get(b.pathname, { access: 'private', useCache: false });
        if (!r?.stream) return;
        try {
          const entry = JSON.parse(await new Response(r.stream).text());
          (results[category] ??= []).push({ ...entry, player });
        } catch { /* bozuk kayıt atlanır */ }
      }));
      return send(res, 200, { day, results });
    }
    if (req.method === 'POST') {
      const b = await readBody(req);
      const nick = String(b.nick ?? '').replace(/[\u0000-\u001f<>]/g, '').trim().slice(0, 20);
      const guesses = Number(b.guesses);
      if (!GROUP.test(b.group ?? '') || !PLAYER.test(b.player ?? '') || !validDay(b.day) || !CATEGORIES.includes(b.category)
        || !nick || !Number.isInteger(guesses) || guesses < 0 || guesses > 400) return send(res, 400, { error: 'params' });
      const entry = {
        nick, guesses, won: !!b.won, hints: Math.max(0, Math.min(3, Number(b.hints) || 0)), expert: !!b.expert, at: Date.now(),
      };
      await put(`board/${b.group}/${b.day}/${b.category}/${b.player}.json`, JSON.stringify(entry), {
        access: 'private', addRandomSuffix: false, allowOverwrite: true, contentType: 'application/json',
      });
      return send(res, 200, { ok: true });
    }
    return send(res, 405, { error: 'method' });
  } catch (err) {
    console.error(err);
    return send(res, 500, { error: 'server' });
  }
};
