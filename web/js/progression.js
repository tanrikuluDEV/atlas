// Puan (XP) ve seviyeler. Mac/iPhone/Apple TV'deki Progression.swift'in karşılığı; formüller birebir aynı.
//
// Yalnızca kazanılan oyun puan getirir:
// - Taban puan tahmin sayısına göre: 1 → 200, 2 → 150, 3 → 120, sonra her tahminde 10 eksik (en az 20).
// - Günlük bulmaca ×1,5; kategori zorluğu ×0,6–1,5; her ipucu −%15. Sonuç 5'in katına yuvarlanır.
// Seviye L'ye ulaşmak için toplam 125·L·(L−1) XP gerekir. Toplam XP oyun geçmişinden hesaplanır.
import { CATEGORIES } from './places.js';

const CATEGORY_FACTOR = {
  world: 1.5, turkey: 1.2, europe: 1, asia: 1, africa: 1, northAmerica: 0.8, southAmerica: 0.6, oceania: 0.6,
};

export function basePoints(guesses) {
  if (guesses === 1) return 200;
  if (guesses === 2) return 150;
  if (guesses === 3) return 120;
  return Math.max(20, 150 - 10 * guesses);
}

export function points(guesses, hints, category, mode) {
  const hintFactor = 1 - 0.15 * Math.min(Math.max(hints ?? 0, 0), 3);
  const modeFactor = mode === 'daily' ? 1.5 : 1;
  const raw = basePoints(guesses) * hintFactor * CATEGORY_FACTOR[category] * modeFactor;
  // Swift'teki .rounded() ile aynı (pozitif sayılarda yarımlar yukarı); işlem sırası da aynı.
  return Math.round(raw / 5) * 5;
}

export const threshold = (level) => 125 * level * (level - 1);

export function levelFor(xp) {
  let level = Math.floor((125 + Math.sqrt(15625 + 500 * xp)) / 250);
  while (threshold(level + 1) <= xp) level += 1;
  while (level > 1 && threshold(level) > xp) level -= 1;
  return Math.max(level, 1);
}

export function progress(xp) {
  const level = levelFor(xp);
  const start = threshold(level);
  const next = threshold(level + 1);
  return { xp, level, start, next, fraction: (xp - start) / (next - start) };
}

/// `loadStats(category, mode)` bir Stats nesnesi döndürür (döngüsel içe aktarmayı önlemek için dışarıdan verilir).
export function totalXP(loadStats) {
  let total = 0;
  for (const c of CATEGORIES) {
    for (const mode of ['daily', 'practice']) {
      for (const r of loadStats(c.id, mode).history) {
        if (r.won) total += points(r.guesses, r.hints ?? 0, c.id, mode);
      }
    }
  }
  return total;
}
