// Arayüz dilleri. Çeviriler data/strings.json'da (Mac/iPhone uygulamasıyla ortak dosya).
import { store } from './store.js';
import { VERSION } from './version.js';

export const LANGUAGES = [
  { id: 'tr', flag: '🇹🇷', locale: 'tr-TR' },
  { id: 'en', flag: '🇬🇧', locale: 'en-GB' },
  { id: 'de', flag: '🇩🇪', locale: 'de-DE' },
  { id: 'fr', flag: '🇫🇷', locale: 'fr-FR' },
  { id: 'es', flag: '🇪🇸', locale: 'es-ES' },
  { id: 'it', flag: '🇮🇹', locale: 'it-IT' },
];
const IDS = LANGUAGES.map((l) => l.id);

// Ülke kodu (ISO 3166) → dil. Listede olmayan bölgeler tarayıcı diline, o da yoksa İngilizceye düşer.
const REGION_LANG = {
  TR: 'tr',
  DE: 'de', AT: 'de', CH: 'de', LI: 'de',
  FR: 'fr', BE: 'fr', LU: 'fr', MC: 'fr', SN: 'fr', CI: 'fr', ML: 'fr', BF: 'fr', NE: 'fr', TG: 'fr', BJ: 'fr',
  CM: 'fr', GA: 'fr', CG: 'fr', CD: 'fr', MG: 'fr', HT: 'fr', GN: 'fr', TD: 'fr', CF: 'fr', DJ: 'fr', RE: 'fr',
  ES: 'es', MX: 'es', AR: 'es', CO: 'es', CL: 'es', PE: 'es', VE: 'es', EC: 'es', GT: 'es', CU: 'es', BO: 'es',
  DO: 'es', HN: 'es', PY: 'es', SV: 'es', NI: 'es', CR: 'es', PA: 'es', UY: 'es', PR: 'es', GQ: 'es',
  IT: 'it', SM: 'it', VA: 'it',
};

let table = {};
let lang = 'tr';
const listeners = [];

export async function loadStrings() {
  table = await fetch(`data/strings.json?v=${VERSION}`).then((r) => r.json());
}

/** Kullanıcının bağlandığı ülke: Vercel bunu isteğin IP'sinden çıkarır (/api/geo). */
async function fetchRegion() {
  try {
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), 2500);
    const res = await fetch('api/geo', { signal: ctrl.signal, cache: 'no-store' });
    clearTimeout(timer);
    if (!res.ok) return null;
    return (await res.json()).country ?? null;
  } catch { return null; }
}

function browserLanguage() {
  for (const l of navigator.languages ?? [navigator.language]) {
    const id = l?.slice(0, 2).toLowerCase();
    if (IDS.includes(id)) return id;
  }
  return null;
}

/** Elle seçilmiş dil varsa o; yoksa bölgeye, sonra tarayıcı diline göre. */
export async function detectLanguage() {
  const chosen = store.get('atlas.language');
  if (IDS.includes(chosen)) { lang = chosen; applyDocumentLanguage(); return; }
  const region = await fetchRegion();
  lang = REGION_LANG[region] ?? browserLanguage() ?? 'en';
  applyDocumentLanguage();
}

export const language = () => lang;
/** Dilin kendi dilindeki adı ("Deutsch", "Français"…). */
export const nativeName = (id) => table['lang.name']?.[id] ?? id;
export const languageInfo = () => LANGUAGES.find((l) => l.id === lang);
export const locale = () => languageInfo().locale;
export const isAutomaticLanguage = () => !IDS.includes(store.get('atlas.language'));

export function setLanguage(id) {
  if (!IDS.includes(id)) return;
  store.set('atlas.language', id);
  if (id === lang) return;
  lang = id;
  applyDocumentLanguage();
  listeners.forEach((f) => f());
}

export function onLanguageChange(f) { listeners.push(f); }

function applyDocumentLanguage() {
  document.documentElement.lang = lang;
}

/** Çeviri; {ad} yer tutucuları doldurulur. n === 1 ise varsa ".one" biçimi kullanılır. */
export function t(key, vars = {}) {
  const entry = (vars.n === 1 && table[`${key}.one`]) || table[key];
  let s = entry?.[lang] ?? entry?.tr ?? key;
  for (const [k, v] of Object.entries(vars)) s = s.replaceAll(`{${k}}`, v);
  return s;
}

/** Bir ilin ya da ülkenin seçili dildeki adı (iller her dilde aynı). */
export const placeName = (place) => (lang !== 'tr' && place.names?.[lang]) || place.name;

export const formatNumber = (v, opts) => new Intl.NumberFormat(locale(), opts).format(v);
export const formatKm = (km) => `${formatNumber(km)} km`;
