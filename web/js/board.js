// Arkadaş grubu ve günlük skor tablosu (yalnızca web). Sunucu tarafı: api/board.js (Vercel Blob).
// Grup davet bağlantısıyla kurulur (?grup=abcd2345); her tarayıcı rastgele bir oyuncu kimliği ve takma adla katılır.
// Günlük bulmaca bitince sonuç gruba gönderilir; gönderilemeyenler sonraki açılışta yeniden denenir.
import { store } from './store.js';
import { dayIndex } from './daily.js';
import { CATEGORIES } from './places.js';

const GROUP_KEY = 'atlas.group';      // { id, nick }
const PLAYER_KEY = 'atlas.player';    // 10 karakterlik kimlik
const SENT_KEY = 'atlas.board.sent';  // { "<gün>.<kategori>": true } yalnızca son günler

const ALPHABET = 'abcdefghijkmnpqrstuvwxyz23456789';
const randomId = (n) => Array.from(crypto.getRandomValues(new Uint8Array(n)), (b) => ALPHABET[b % ALPHABET.length]).join('');

export const group = () => store.get(GROUP_KEY, null);

export function playerId() {
  let id = store.get(PLAYER_KEY, null);
  if (!/^[a-z0-9]{10}$/.test(id ?? '')) { id = randomId(10); store.set(PLAYER_KEY, id); }
  return id;
}

export const cleanNick = (s) => String(s ?? '').replace(/[\u0000-\u001f<>]/g, '').trim().slice(0, 20);

export function createGroup(nick) {
  store.set(GROUP_KEY, { id: randomId(8), nick: cleanNick(nick) });
  store.set(SENT_KEY, {});
  return group();
}

export function joinGroup(id, nick) {
  store.set(GROUP_KEY, { id, nick: cleanNick(nick) });
  store.set(SENT_KEY, {});
  return group();
}

export function setNick(nick) {
  const g = group();
  if (!g) return;
  store.set(GROUP_KEY, { ...g, nick: cleanNick(nick) });
  store.set(SENT_KEY, {}); // yeni adla yeniden gönderilsin
}

export function leaveGroup() { store.set(GROUP_KEY, null); }

export const inviteLink = () => `${location.origin}${location.pathname}?grup=${group()?.id ?? ''}`;

/** Adres çubuğundaki davet kodu (geçerliyse); okununca adresten silinir. */
export function takeInviteFromURL() {
  const url = new URL(location.href);
  const code = (url.searchParams.get('grup') ?? url.searchParams.get('group') ?? '').toLowerCase();
  if (!url.searchParams.has('grup') && !url.searchParams.has('group')) return null;
  url.searchParams.delete('grup');
  url.searchParams.delete('group');
  history.replaceState(null, '', url.pathname + (url.search || '') + url.hash);
  return /^[a-z0-9]{8}$/.test(code) ? code : null;
}

/** Bugün bitmiş ve henüz gönderilmemiş günlük bulmacaları gruba gönderir. */
export async function syncResults() {
  const g = group();
  if (!g?.nick) return;
  const day = dayIndex();
  const sent = store.get(SENT_KEY, {});
  // Eski günlerin işaretleri temizlenir.
  for (const k of Object.keys(sent)) if (Number(k.split('.')[0]) < day - 3) delete sent[k];
  for (const c of CATEGORIES) {
    const key = `${day}.${c.id}`;
    const saved = store.get(`atlas.daily.${c.id}.${day}`);
    if (sent[key] || !saved || saved.status === 'playing') continue;
    try {
      const res = await fetch('api/board', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          group: g.id, player: playerId(), nick: g.nick, day, category: c.id,
          guesses: saved.guessIDs.length, won: saved.status === 'won', hints: saved.hints ?? 0, expert: !!saved.expert,
        }),
      });
      if (res.ok) sent[key] = true;
    } catch { /* çevrimdışı: sonra yeniden denenir */ }
  }
  store.set(SENT_KEY, sent);
}

/** Grubun bugünkü sonuçları: { turkey: [{ nick, guesses, won, hints, expert, player }], … } ya da hata. */
export async function fetchBoard() {
  const g = group();
  if (!g) return { error: 'nogroup' };
  try {
    const res = await fetch(`api/board?group=${g.id}&day=${dayIndex()}`, { cache: 'no-store' });
    if (!res.ok) return { error: res.status === 503 ? 'storage' : 'server' };
    return await res.json();
  } catch {
    return { error: 'offline' };
  }
}

/** Sıralama: önce bulanlar (az tahmin, az ipucu), sonra pes edenler. */
export function rank(entries) {
  return entries.slice().sort((a, b) => (b.won - a.won) || (a.won ? a.guesses - b.guesses || a.hints - b.hints : 0) || a.at - b.at);
}
