// Renkler: Globle tarzı sıcaklık skalası (yakın = koyu kırmızı, uzak = soluk krem) ve tema renkleri.

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

const LIGHT = {
  sea: '#e3edf7', backgroundLand: '#f2f2f2', backgroundBorder: 'rgba(255,255,255,0.7)',
  border: '#ffffff', unguessed: '#d1d1d1', markerStroke: 'rgba(0,0,0,0.35)', text: '#1d1d1f',
  // Küre
  space: '#f4f6fa', seaLight: '#f3f8fd', atmosphere: 'rgba(120, 170, 230, 0.35)',
  globeShade: 'rgba(40, 60, 100, 0.18)', graticule: 'rgba(60, 100, 160, 0.12)',
  // Adlar ve animasyon
  labelText: '#1d1d1f', labelHalo: 'rgba(255,255,255,0.85)', pulse: 'rgba(255,255,255,ALPHA)',
};
const DARK = {
  sea: '#12171f', backgroundLand: '#2b2b2b', backgroundBorder: 'rgba(0,0,0,0.4)',
  border: 'rgba(0,0,0,0.6)', unguessed: '#4d4d4d', markerStroke: 'rgba(255,255,255,0.5)', text: '#f5f5f7',
  space: '#07090d', seaLight: '#1c2533', atmosphere: 'rgba(90, 150, 255, 0.28)',
  globeShade: 'rgba(0, 0, 0, 0.45)', graticule: 'rgba(140, 170, 220, 0.10)',
  labelText: '#f5f5f7', labelHalo: 'rgba(0,0,0,0.75)', pulse: 'rgba(255,255,255,ALPHA)',
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
  document.querySelector('meta[name="theme-color"]')?.setAttribute('content', isDark() ? '#1c1c1e' : '#ffffff');
  listeners.forEach((fn) => fn());
}

export const COLORS = () => ({ ...(isDark() ? DARK : LIGHT), ...SHARED });
export const onThemeChange = (fn) => listeners.add(fn);
darkQuery.addEventListener('change', () => applyTheme());
