// Rozetler. Mac/iPhone/Apple TV'deki Badges.swift'in karşılığı (aynı rozetler, aynı koşullar).
// Ayrıca saklanmaz; tüm kategorilerin istatistiklerinden hesaplanır.
import { CATEGORIES, placeSet } from './places.js';
import { t } from './i18n.js';

/** Swift'teki SF Symbol'lerin web karşılığı. */
const ICONS = {
  firstWin: '🏁', sharp: '👁️', ace: '🎯', streak3: '🔥', streak7: '🔥', streak30: '☀️',
  wins10: '🥾', wins50: '✈️', wins100: '👑', allCategories: '🌍', explorer: '🗺️',
  expert: '🙈', expert10: '🎓',
};

/** `loadStats(category, mode)` bir Stats nesnesi döndürür (döngüsel içe aktarmayı önlemek için dışarıdan verilir). */
export function allBadges(loadStats) {
  let wins = 0, best = Infinity, maxStreak = 0, categoriesWon = 0, expertWins = 0;
  const explorers = [];
  for (const c of CATEGORIES) {
    const daily = loadStats(c.id, 'daily');
    const practice = loadStats(c.id, 'practice');
    const won = daily.won + practice.won;
    wins += won;
    if (won > 0) categoriesWon += 1;
    for (const r of [...daily.history, ...practice.history]) if (r.won) best = Math.min(best, r.guesses);
    maxStreak = Math.max(maxStreak, daily.maxStreak);
    expertWins += [...daily.history, ...practice.history].filter((r) => r.won && r.expert).length;
    const set = placeSet(c.id);
    const found = new Set([...daily.history, ...practice.history].filter((r) => r.won && set.place(r.answerID)).map((r) => r.answerID));
    const total = set.places.length;
    explorers.push({
      id: `explorer.${c.id}`, icon: ICONS.explorer,
      name: t('badge.explorer.name', { cat: c.title }), detail: t(`badge.explorer.desc.${c.kind}`, { n: total }),
      current: found.size, target: total, earned: found.size >= total,
    });
  }
  const badge = (id, current, target) => ({
    id, icon: ICONS[id], name: t(`badge.${id}.name`), detail: t(`badge.${id}.desc`),
    current: Math.min(current, target), target, earned: current >= target,
  });
  return [
    badge('firstWin', wins, 1),
    badge('sharp', best <= 3 ? 1 : 0, 1),
    badge('ace', best === 1 ? 1 : 0, 1),
    badge('streak3', maxStreak, 3),
    badge('streak7', maxStreak, 7),
    badge('streak30', maxStreak, 30),
    badge('wins10', wins, 10),
    badge('wins50', wins, 50),
    badge('wins100', wins, 100),
    badge('allCategories', categoriesWon, CATEGORIES.length),
    badge('expert', expertWins, 1),
    badge('expert10', expertWins, 10),
    ...explorers,
  ];
}

export function earnedBadgeIds(loadStats) {
  return new Set(allBadges(loadStats).filter((b) => b.earned).map((b) => b.id));
}
