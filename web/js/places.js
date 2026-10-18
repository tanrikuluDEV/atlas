// İller, ülkeler, kategoriler ve arama. Mac/iPhone uygulamasındaki Place.swift'in karşılığı.
import { formatKm, language, locale, t } from './i18n.js';
import { VERSION } from './version.js';

/** "İstanbul" → "istanbul", "Bosna-Hersek" → "bosnahersek": Türkçe harfler ASCII'ye, boşluk/noktalama atılır. */
export function normalize(text) {
  return text
    .toLocaleLowerCase('tr')
    .replace(/ı/g, 'i')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^\p{L}\p{N}]/gu, '');
}

export { formatKm };

class Category {
  constructor(id, icon) {
    this.id = id;
    this.icon = icon;
    /** Metin anahtarlarında kullanılır: "province" (il) ya da "country" (ülke). */
    this.kind = id === 'turkey' ? 'province' : 'country';
  }
  get title() { return t(`cat.${this.id}`); }
}

export const CATEGORIES = [
  new Category('turkey', '🇹🇷'),
  new Category('europe', '🌍'),
  new Category('asia', '🌏'),
  new Category('africa', '🌍'),
  new Category('northAmerica', '🌎'),
  new Category('southAmerica', '🌎'),
  new Category('oceania', '🌏'),
  new Category('world', '🌐'),
];

export const categoryIndex = (id) => CATEGORIES.findIndex((c) => c.id === id);
export const categoryById = (id) => CATEGORIES.find((c) => c.id === id);

// Harita görünüm alanları (boylam/enlem) ve antimeridyen kaydırması.
const VIEWS = {
  europe: { bounds: [-25, 34, 70, 38], shift: (x) => x },
  asia: { bounds: [25, -11, 125, 67], shift: (x) => x },
  africa: { bounds: [-26, -36, 90, 74], shift: (x) => x },
  northAmerica: { bounds: [-170, 6, 160, 74], shift: (x) => (x > 100 ? x - 360 : x) },
  southAmerica: { bounds: [-93, -56, 62, 70], shift: (x) => x },
  oceania: { bounds: [110, -48, 125, 70], shift: (x) => (x < 0 ? x + 360 : x) },
  world: { bounds: [-170, -57, 350, 140], shift: (x) => x },
};

const TURKEY_ALIASES = { afyon: 3, maras: 46, urfa: 63, antep: 27, icel: 33, izmit: 41, adapazari: 54 };

const collator = new Intl.Collator('tr');

class Place {
  constructor({ id, code, name, names = {}, aliases = [], rings }) {
    this.id = id;
    this.code = code;
    /** Türkçe ad; sıralama ve kayıtlar bunu kullanır. */
    this.trName = name;
    /** Diğer dillerdeki adlar (yalnızca ülkelerde). */
    this.names = names;
    this.rings = rings;
    // Her dildeki ad aranabilir; öneriler seçili dildeki adla gösterilir.
    this.searchKeys = [...new Set([name, ...Object.values(names), ...aliases].map(normalize))];
  }

  /** Seçili dildeki ad. */
  get name() { return (language() !== 'tr' && this.names[language()]) || this.trName; }

  get primaryKey() {
    if (this._keyLang !== language()) { this._keyLang = language(); this._key = normalize(this.name); }
    return this._key;
  }
}

export class PlaceSet {
  constructor({ category, places, background, view, distance, extraAliases = {} }) {
    this.category = category;
    this.places = places.slice().sort((a, b) => collator.compare(a.trName, b.trName));
    this.byId = new Map(places.map((p) => [p.id, p]));
    this.background = background;
    this.view = view; // { bounds:[minLon,minLat,w,h], shift } ya da null (yerlere sığdır)
    this.distanceLookup = distance;
    this.extraAliases = extraAliases;
    let max = 1;
    for (const a of places) for (const b of places) if (a.id < b.id) max = Math.max(max, distance(a.id, b.id));
    this.maxDistance = max;
  }

  place(id) { return this.byId.get(id); }

  distance(a, b) { return a.id === b.id ? 0 : this.distanceLookup(a.id, b.id); }

  /** id'ye göre sıralı liste (günlük bulmaca bu sırayı kullanır). */
  get placesById() { return [...this.byId.values()].sort((a, b) => a.id - b.id); }

  match(text) {
    const key = normalize(text);
    if (!key) return null;
    const exact = this.places.find((p) => p.searchKeys.includes(key));
    if (exact) return exact;
    if (this.category.id === 'turkey' && /^\d+$/.test(key)) return this.place(Number(key)) ?? null;
    const alias = this.extraAliases[key];
    return alias ? this.place(alias) : null;
  }

  suggestions(text, limit = 6) {
    const key = normalize(text);
    if (!key) return [];
    // Önce seçili dildeki adı yazılanla başlayanlar, sonra diğer ad ve takma adlar, en son adın içinde geçenler.
    const byName = new Intl.Collator(locale());
    const sorted = (list) => list.sort((a, b) => byName.compare(a.name, b.name));
    const primary = sorted(this.places.filter((p) => p.primaryKey.startsWith(key)));
    const alias = sorted(this.places.filter((p) => !primary.includes(p) && p.searchKeys.some((k) => k.startsWith(key))));
    const contains = sorted(this.places.filter((p) => !primary.includes(p) && !alias.includes(p) && p.primaryKey.includes(key)));
    return [...primary, ...alias, ...contains].slice(0, limit);
  }

  subtitle() {
    const n = this.places.length;
    const c = this.category;
    if (c.id === 'turkey' || c.id === 'world') return t(`subtitle.${c.id}`, { n });
    return t('subtitle.continent', { n, continent: c.title });
  }
}

let world = null;
let provinces = null;
let hints = { provinces: {}, countries: {} };
const cache = new Map();

export async function loadData() {
  const [w, p, h] = await Promise.all([
    fetch(`data/world.json?v=${VERSION}`).then((r) => r.json()),
    fetch(`data/provinces.json?v=${VERSION}`).then((r) => r.json()),
    // İpuçları olmadan da oyun oynanabilsin.
    fetch(`data/hints.json?v=${VERSION}`).then((r) => r.json()).catch(() => null),
  ]);
  world = w;
  provinces = p;
  if (h) hints = h;
}

/** Bir il ya da ülke için seçili dildeki 3 genel kültür ipucu (ilki en genel, sonuncusu en belirgin). */
export function hintsFor(categoryId, place) {
  const entry = categoryId === 'turkey' ? hints.provinces[place.id] : hints.countries[place.code];
  return entry?.[language()] ?? entry?.tr ?? [];
}

export function placeSet(categoryId) {
  if (cache.has(categoryId)) return cache.get(categoryId);
  const category = categoryById(categoryId);
  let set;
  if (categoryId === 'turkey') {
    const places = provinces.provinces.map((p) => new Place({ id: p.id, code: String(p.id).padStart(2, '0'), name: p.name, rings: p.rings }));
    // Türkiye dışındaki ülkeler denizleri ve komşuları göstermek için arka planda çizilir.
    const background = [...world.countries.filter((c) => c.code !== 'TUR').map((c) => c.rings), ...world.background];
    const d = provinces.distances;
    set = new PlaceSet({ category, places, background, view: null, distance: (a, b) => d[a - 1][b - 1], extraAliases: TURKEY_ALIASES });
  } else {
    const members = world.countries.filter((c) => categoryId === 'world' || c.continents.includes(categoryId));
    const codes = new Set(members.map((c) => c.code));
    const places = members.map((c) => new Place(c));
    const background = [...world.countries.filter((c) => !codes.has(c.code)).map((c) => c.rings), ...world.background];
    const d = world.distances;
    set = new PlaceSet({ category, places, background, view: VIEWS[categoryId], distance: (a, b) => d[a - 1][b - 1] });
  }
  cache.set(categoryId, set);
  return set;
}
