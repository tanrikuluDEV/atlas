// Günlük bulmaca: Mac/iPhone uygulamasıyla birebir aynı seçimi yapar (aynı gün, aynı gizli yer).
// Swift'in SplitMix64 üreteci, `next(upperBound:)` (Lemire yöntemi) ve `shuffled(using:)`
// algoritması 64 bit tam sayılarla (BigInt) kopyalanmıştır.

const MASK = (1n << 64n) - 1n;

export class SeededGenerator {
  constructor(seed) {
    this.state = BigInt.asUintN(64, seed);
  }

  next() {
    this.state = (this.state + 0x9E3779B97F4A7C15n) & MASK;
    let z = this.state;
    z = ((z ^ (z >> 30n)) * 0xBF58476D1CE4E5B9n) & MASK;
    z = ((z ^ (z >> 27n)) * 0x94D049BB133111EBn) & MASK;
    return z ^ (z >> 31n);
  }

  /** Swift RandomNumberGenerator.next(upperBound:) */
  nextBelow(upperBound) {
    const bound = BigInt(upperBound);
    let random = this.next();
    let m = random * bound;
    let low = m & MASK;
    if (low < bound) {
      const t = ((MASK + 1n - bound) & MASK) % bound;
      while (low < t) {
        random = this.next();
        m = random * bound;
        low = m & MASK;
      }
    }
    return Number(m >> 64n);
  }
}

/** Swift MutableCollection.shuffle(using:) */
export function shuffled(array, rng) {
  const a = array.slice();
  let amount = a.length;
  let current = 0;
  while (amount > 1) {
    const r = rng.nextBelow(amount);
    amount -= 1;
    const j = current + r;
    [a[current], a[j]] = [a[j], a[current]];
    current += 1;
  }
  return a;
}

const EPOCH = new Date(2026, 0, 1); // yerel saatle 1 Ocak 2026

export function dayIndex(date = new Date()) {
  const start = new Date(EPOCH.getFullYear(), EPOCH.getMonth(), EPOCH.getDate());
  const today = new Date(date.getFullYear(), date.getMonth(), date.getDate());
  return Math.max(0, Math.round((today - start) / 86_400_000));
}

/** Sıralı (id'ye göre) listede gizli yerin konumu. categoryIndex: GameCategory.allCases sırası. */
export function answerIndex(day, categoryIndex, count) {
  const salt = BigInt.asUintN(64, BigInt(categoryIndex) * 104_729n);
  const cycle = Math.floor(day / count);
  const seed = BigInt.asUintN(64, 0xA71A5n + BigInt(cycle) * 7919n + salt);
  const rng = new SeededGenerator(seed);
  const order = shuffled([...Array(count).keys()], rng);
  return order[day % count];
}
