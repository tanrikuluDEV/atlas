// Zamana karşı ve komşu zinciri: kayıtlar ve komşuluk grafiği. Swift: Atlas/Game/Modes.swift (aynı kurallar).
import { store } from './store.js';

// MARK: - Kayıtlar

export const TimedStats = {
  key: (category) => `atlas.timed.${category}`,
  load(category) { return { best: 0, runs: [], ...store.get(TimedStats.key(category), {}) }; },
  record(category, score, skipped) {
    const s = TimedStats.load(category);
    s.runs.push({ date: Date.now(), score, skipped });
    s.best = Math.max(s.best, score);
    store.set(TimedStats.key(category), s);
    return s;
  },
};

export const ChainStats = {
  key: (category) => `atlas.chain.${category}`,
  load(category) {
    const runs = store.get(ChainStats.key(category), {}).runs ?? [];
    return {
      runs,
      played: runs.length,
      won: runs.filter((r) => r.won).length,
      perfect: runs.filter((r) => r.won && r.guesses === r.optimal).length,
    };
  },
  record(category, run) {
    const runs = ChainStats.load(category).runs;
    runs.push({ date: Date.now(), ...run });
    store.set(ChainStats.key(category), { runs });
  },
};

/** Zincirde bir tahminin durumu: 0 en kısa rotada, 1 rotaya 1–2 adım, 2 uzak. */
export const CHAIN = { onPath: 0, near: 1, far: 2 };

// MARK: - Komşuluk grafiği (kara sınırı = mesafe 0)

const neighborCache = new Map();
const supportCache = new Map();

export function neighbors(set) {
  const id = set.category.id;
  if (neighborCache.has(id)) return neighborCache.get(id);
  const map = new Map();
  for (const a of set.places) map.set(a.id, set.places.filter((b) => b.id !== a.id && set.distance(a, b) === 0));
  neighborCache.set(id, map);
  return map;
}

export function hopDistances(set, start) {
  const graph = neighbors(set);
  const dist = new Map([[start.id, 0]]);
  const queue = [start];
  for (let i = 0; i < queue.length; i++) {
    const p = queue[i];
    for (const n of graph.get(p.id) ?? []) {
      if (!dist.has(n.id)) { dist.set(n.id, dist.get(p.id) + 1); queue.push(n); }
    }
  }
  return dist;
}

/** Yalnızca `allowed` (id kümesi) içinden geçen en kısa rota, uçlar dahil; yoksa null. */
export function shortestPath(set, start, end, allowed = null) {
  const graph = neighbors(set);
  const parent = new Map();
  const seen = new Set([start.id]);
  const queue = [start];
  for (let i = 0; i < queue.length; i++) {
    const p = queue[i];
    if (p.id === end.id) {
      const path = [end];
      while (parent.has(path[0].id)) path.unshift(parent.get(path[0].id));
      return path;
    }
    for (const n of graph.get(p.id) ?? []) {
      if (seen.has(n.id) || (n.id !== end.id && allowed && !allowed.has(n.id))) continue;
      seen.add(n.id);
      parent.set(n.id, p);
      queue.push(n);
    }
  }
  return null;
}

const HOPS = { turkey: [4, 7], southAmerica: [3, 5] };

/** Bu kategoride zincir kurulabilir mi (en az üç adımlık bir rota var mı). */
export function supportsChain(set) {
  const id = set.category.id;
  if (!supportCache.has(id)) {
    supportCache.set(id, set.places.some((p) => [...hopDistances(set, p).values()].some((d) => d >= 3)));
  }
  return supportCache.get(id);
}

const shuffle = (list) => {
  const a = list.slice();
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
};

/** Rastgele başlangıç–bitiş çifti ve aralarındaki en kısa rotalardan biri. */
export function randomChainPair(set) {
  if (!supportsChain(set)) return null;
  const graph = neighbors(set);
  const [lo, hi] = HOPS[set.category.id] ?? [3, 6];
  let fallback = null;
  for (const start of shuffle(set.places.filter((p) => graph.get(p.id).length))) {
    const dist = hopDistances(set, start);
    const candidates = set.places.filter((p) => { const d = dist.get(p.id); return d >= lo && d <= hi; });
    if (candidates.length) {
      const end = candidates[Math.floor(Math.random() * candidates.length)];
      return { start, end, path: shortestPath(set, start, end) };
    }
    for (const [id, d] of dist) {
      if (d >= 3 && d > (fallback?.d ?? 0)) fallback = { start, end: set.place(id), d };
    }
  }
  return fallback ? { start: fallback.start, end: fallback.end, path: shortestPath(set, fallback.start, fallback.end) } : null;
}
