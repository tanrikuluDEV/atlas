// Renkler: sıcaklık skalası (yakın = koyu kırmızı, uzak = soluk krem) ve tema renkleri.

const STOPS = [
  [0.45, 0.00, 0.06], // komşu
  [0.72, 0.07, 0.12],
  [0.93, 0.30, 0.14],
  [0.99, 0.55, 0.24],
  [1.00, 0.76, 0.45],
  [1.00, 0.90, 0.72],
  [1.00, 0.96, 0.89], // en uzak
];

export function heatColor(km, maxKm) {
  // Karekök ile yakın mesafelerdeki farklar daha belirgin olur.
  const t = Math.min(1, Math.max(0, Math.sqrt(km / Math.max(maxKm, 1))));
  const scaled = t * (STOPS.length - 1);
  const i = Math.min(Math.floor(scaled), STOPS.length - 2);
  const f = scaled - i;
  const [a, b] = [STOPS[i], STOPS[i + 1]];
  const c = (j) => Math.round((a[j] + (b[j] - a[j]) * f) * 255);
  return `rgb(${c(0)}, ${c(1)}, ${c(2)})`;
}

// Kara sıcak gri/krem, deniz soğuk gri-mavi; koyu temada her şey lacivert tonunda (Swift: MapLayer.palette).
const LIGHT = {
  sea: '#dbe5ec', backgroundLand: '#efece6', backgroundBorder: 'rgba(255,255,255,0.75)',
  border: '#fbf9f5', unguessed: '#dcd6cc', markerStroke: 'rgba(20,32,48,0.35)', text: '#142030',
  // Küre
  space: '#f3f1ec', seaLight: '#eef4f8', atmosphere: 'rgba(120, 170, 230, 0.35)',
  globeShade: 'rgba(20, 32, 48, 0.18)', graticule: 'rgba(20, 60, 110, 0.10)',
  vignette: 'rgba(20, 40, 70, 0.10)',
  // Adlar ve animasyon
  labelText: '#142030', labelHalo: 'rgba(251,249,245,0.88)', pulse: 'rgba(255,255,255,ALPHA)',
  thumbPlace: '#f26644', thumbLand: '#e6e1d8', thumbSea: '#eef2f4',
};
const DARK = {
  sea: '#0c141e', backgroundLand: '#1b2633', backgroundBorder: 'rgba(0,0,0,0.4)',
  border: 'rgba(6,11,18,0.75)', unguessed: '#2f3c4c', markerStroke: 'rgba(249,246,241,0.5)', text: '#f9f6f1',
  space: '#060b12', seaLight: '#17263a', atmosphere: 'rgba(90, 150, 255, 0.26)',
  globeShade: 'rgba(0, 0, 0, 0.45)', graticule: 'rgba(150, 180, 220, 0.08)',
  vignette: 'rgba(0, 0, 0, 0.35)',
  labelText: '#f9f6f1', labelHalo: 'rgba(8,14,22,0.8)', pulse: 'rgba(255,255,255,ALPHA)',
  thumbPlace: '#f26644', thumbLand: '#253244', thumbSea: '#131e2c',
};
const SHARED = {
  found: 'rgb(46, 158, 79)', answerReveal: 'rgb(41, 115, 217)',
  highlight: 'rgb(148, 61, 245)', highlightGlow: 'rgba(148, 61, 245, 0.35)',
};

// Tema tercihi: 'system' (cihazı izle), 'light' ya da 'dark'. index.html'deki küçük betik
// sayfa çizilmeden önce aynı tercihi uygular; böylece açılışta renk sıçraması olmaz.
const darkQuery = window.matchMedia('(prefers-color-scheme: dark)');
const listeners = new Set();
const THEME_KEY = 'atlas.theme';

export function themePreference() {
  try { return JSON.parse(localStorage.getItem(THEME_KEY)) ?? 'system'; } catch { return 'system'; }
}

export const isDark = () => {
  const pref = themePreference();
  return pref === 'dark' || (pref === 'system' && darkQuery.matches);
};

export function setThemePreference(pref) {
  try { localStorage.setItem(THEME_KEY, JSON.stringify(pref)); } catch { /* gizli sekme vb. */ }
  applyTheme();
}

export function applyTheme() {
  const pref = themePreference();
  const root = document.documentElement;
  if (pref === 'system') delete root.dataset.theme; else root.dataset.theme = pref;
  document.querySelector('meta[name="theme-color"]')?.setAttribute('content', isDark() ? '#121c29' : '#fbf9f5');
  listeners.forEach((fn) => fn());
}

export const COLORS = () => ({ ...(isDark() ? DARK : LIGHT), ...SHARED });
export const onThemeChange = (fn) => listeners.add(fn);
darkQuery.addEventListener('change', () => applyTheme());
