// Harita: Canvas çizimi (düz harita ya da Dünya için 3D küre), kamera uçuşları,
// sürükleme/yakınlaştırma, adlar, renk skalası ve animasyonlar.
// Mac/iPhone uygulamasındaki MapView.swift / GlobeView'in karşılığı.
import { formatKm } from './places.js';
import { t } from './i18n.js';
import { heatColor, COLORS } from './colors.js';

const PADDING = 20;
const MARKER_THRESHOLD = 6; // ekranda bundan küçük kalan yerler noktayla işaretlenir
const MARKER_RADIUS = 4;
const DEG = Math.PI / 180;
const PULSE_MS = 1300;      // yeni tahminin parlaması
const WIN_PULSE_MS = 2600;  // bulunan yerin nabzı
const LABEL_FONT = '600 11px -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif';

// MARK: - Ortak geometri yardımcıları

function union(a, b) {
  if (!a) return b;
  if (!b) return a;
  const x = Math.min(a.x, b.x), y = Math.min(a.y, b.y);
  return { x, y, w: Math.max(a.x + a.w, b.x + b.w) - x, h: Math.max(a.y + a.h, b.y + b.h) - y };
}

const intersects = (a, b) => a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;

/** Ad kutusunu yerin çevresinde çakışmayan ilk adaya koyar; hiçbiri boş değilse en az çakışanı seçer. */
function placeLabel(anchor, w, h, size, placed) {
  const side = w / 2 + 8;
  const offsets = [
    [0, 0], [0, -h * 1.1], [0, h * 1.1], [side, 0], [-side, 0],
    [side, -h * 1.1], [-side, -h * 1.1], [side, h * 1.1], [-side, h * 1.1],
    [0, -h * 2.2], [0, h * 2.2], [0, -h * 3.3], [0, h * 3.3],
    [side * 1.6, 0], [-side * 1.6, 0], [side, -h * 2.2], [-side, h * 2.2],
  ];
  let best = null;
  let bestOverlap = Infinity;
  for (const [dx, dy] of offsets) {
    const x = Math.min(Math.max(anchor.x + dx - w / 2, 2), Math.max(size.w - 2 - w, 2));
    const y = Math.min(Math.max(anchor.y + dy - h / 2, 2), Math.max(size.h - 2 - h, 2));
    const box = { x, y, w, h };
    let overlap = 0;
    for (const r of placed) {
      const ow = Math.min(r.x + r.w, box.x + box.w) - Math.max(r.x, box.x);
      const oh = Math.min(r.y + r.h, box.y + box.h) - Math.max(r.y, box.y);
      if (ow > 0 && oh > 0) overlap += ow * oh;
    }
    if (overlap === 0) return box;
    if (overlap < bestOverlap) {
      bestOverlap = overlap;
      best = box;
    }
  }
  return best;
}

/** En büyük parça ve ona yakın parçalar: Svalbard, Fransız Guyanası, Hawaii kadraja girmez. */
function mainlandRect(rects) {
  if (!rects.length) return null;
  const main = rects.reduce((a, b) => (b.w * b.h > a.w * a.h ? b : a));
  const reach = Math.max(main.w, main.h) * 0.5;
  const near = { x: main.x - reach, y: main.y - reach, w: main.w + reach * 2, h: main.h + reach * 2 };
  return rects.filter((r) => intersects(near, r)).reduce(union, main);
}

/** Halkanın alan ağırlıklı merkezi (düzlemde); ad yazmak için. */
function ringCentroid(pts) {
  let a = 0, cx = 0, cy = 0;
  for (let i = 0, j = pts.length - 1; i < pts.length; j = i++) {
    const f = pts[j][0] * pts[i][1] - pts[i][0] * pts[j][1];
    a += f; cx += (pts[j][0] + pts[i][0]) * f; cy += (pts[j][1] + pts[i][1]) * f;
  }
  if (Math.abs(a) < 1e-9) {
    const n = pts.length;
    return [pts.reduce((s, p) => s + p[0], 0) / n, pts.reduce((s, p) => s + p[1], 0) / n];
  }
  return [cx / (3 * a), cy / (3 * a)];
}

function ringRect(ring) {
  let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
  for (const [x, y] of ring) {
    if (x < minX) minX = x; if (x > maxX) maxX = x;
    if (y < minY) minY = y; if (y > maxY) maxY = y;
  }
  return { x: minX, y: minY, w: maxX - minX, h: maxY - minY };
}

/** En büyük halka (sınır kutusu alanına göre). */
function largestRing(rings) {
  let best = null, bestArea = -1;
  for (const r of rings) {
    const b = ringRect(r);
    if (b.w * b.h > bestArea) { bestArea = b.w * b.h; best = r; }
  }
  return best;
}

// MARK: - Düz harita geometrisi

/** Bir kategorinin düzlem projeksiyonu: x = boylam·cos(φ₀), y = -enlem. Kategori başına bir kez hesaplanır. */
export class FlatGeometry {
  constructor(set) {
    const view = set.view;
    const midLat = view ? view.bounds[1] + view.bounds[3] / 2 : 39;
    const k = Math.cos(Math.min(Math.abs(midLat), 60) * DEG);
    const shift = view ? view.shift : (x) => x;

    const project = (ring) => {
      // Kaydırma halkanın tamamına uygulanır; nokta nokta kaydırmak 0° boylamını kesen şekilleri yırtar.
      const meanLon = ring.reduce((s, p) => s + p[0], 0) / ring.length;
      const dx = shift(meanLon) - meanLon;
      return ring.map(([lon, lat]) => [(lon + dx) * k, -lat]);
    };
    const build = (rings) => {
      const path = new Path2D();
      const projected = rings.filter((r) => r.length).map(project);
      for (const ring of projected) {
        ring.forEach(([x, y], i) => (i === 0 ? path.moveTo(x, y) : path.lineTo(x, y)));
        path.closePath();
      }
      const rects = projected.map(ringRect);
      return { path, rects, rect: rects.reduce(union, null), projected };
    };

    this.places = set.places.map((p) => {
      const g = build(p.rings);
      const main = largestRing(g.projected);
      const [lx, ly] = main ? ringCentroid(main) : [0, 0];
      return { path: g.path, rect: g.rect, focus: mainlandRect(g.rects), label: { x: lx, y: ly } };
    });
    this.background = set.background.map((rings) => { const g = build(rings); return { path: g.path, rect: g.rect }; });
    if (view) {
      const [lon, lat, w, h] = view.bounds;
      this.bounds = { x: lon * k, y: -(lat + h), w: w * k, h };
    } else {
      this.bounds = this.places.map((p) => p.rect).reduce(union, null);
    }
  }
}

// MARK: - Küre geometrisi

/** Her nokta birim küre üzerinde (x, y, z) olarak saklanır; döndürme ve izdüşüm her karede hızlıca yapılır. */
class GlobeGeometry {
  constructor(set) {
    const buildRings = (rings) => rings.filter((r) => r.length > 2).map((ring) => {
      const vec = new Float32Array(ring.length * 3);
      ring.forEach(([lon, lat], i) => {
        const l = lon * DEG, p = lat * DEG;
        vec[i * 3] = Math.cos(p) * Math.cos(l);
        vec[i * 3 + 1] = Math.cos(p) * Math.sin(l);
        vec[i * 3 + 2] = Math.sin(p);
      });
      return { vec, lonlat: ring, rect: ringRect(ring) };
    });

    this.places = set.places.map((p) => {
      const rings = buildRings(p.rings);
      const rect = rings.map((r) => r.rect).reduce(union, null);
      const focus = mainlandRect(rings.map((r) => r.rect));
      const main = largestRing(p.rings);
      const [lon, lat] = main ? ringCentroid(main) : [0, 0];
      // Açısal boyut (derece): ana toprağın boylamı enleme göre daraltılarak.
      const midLat = focus.y + focus.h / 2;
      const size = Math.max(focus.w * Math.cos(midLat * DEG), focus.h);
      return {
        rings, rect,
        label: { lon, lat },
        focus: { lon: focus.x + focus.w / 2, lat: midLat, size },
        angular: Math.max(rect.w * Math.cos((rect.y + rect.h / 2) * DEG), rect.h),
      };
    });
    this.background = set.background.map((rings) => ({ rings: buildRings(rings) }));
  }
}

const flatCache = new WeakMap();
const globeCache = new WeakMap();
export function flatGeometryFor(set) {
  if (!flatCache.has(set)) flatCache.set(set, new FlatGeometry(set));
  return flatCache.get(set);
}
function globeGeometryFor(set) {
  if (!globeCache.has(set)) globeCache.set(set, new GlobeGeometry(set));
  return globeCache.get(set);
}

/** Noktanın halkaların içinde olup olmadığı (boylam/enlem düzleminde, çift-tek kuralı). */
function pointInRings(rings, lon, lat) {
  let inside = false;
  for (const r of rings) {
    const b = r.rect;
    if (lon < b.x || lon > b.x + b.w || lat < b.y || lat > b.y + b.h) continue;
    const pts = r.lonlat;
    for (let i = 0, j = pts.length - 1; i < pts.length; j = i++) {
      const [xi, yi] = pts[i], [xj, yj] = pts[j];
      if ((yi > lat) !== (yj > lat) && lon < ((xj - xi) * (lat - yi)) / (yj - yi) + xi) inside = !inside;
    }
  }
  return inside;
}

// MARK: - Kamera

const SPAN_FRACTIONS = { turkey: [2 / 5, 0.55] };
const spanFractions = (id) => SPAN_FRACTIONS[id] ?? [1 / 3, 0.5];
const maxZoomFor = (id) => (id === 'turkey' ? 8 : 24);
// Küre: odaklanınca görünen açı (derece). İzlanda ekran görüntüsündeki ölçeğe göre.
const GLOBE_SPAN = [48, 62];
const GLOBE_HOME = { lon: 32, lat: 28 }; // açılışta Türkiye tarafı

const easeInOut = (t) => (t < 0.5 ? 2 * t * t : 1 - (-2 * t + 2) ** 2 / 2);
const easeIn = (t) => t * t;
const easeOut = (t) => 1 - (1 - t) * (1 - t);
const wrapLon = (l) => ((((l + 180) % 360) + 360) % 360) - 180;

// MARK: - Harita görünümü

export class MapView {
  constructor(container, game) {
    this.container = container;
    this.game = game;
    this.canvas = container.querySelector('canvas');
    this.ctx = this.canvas.getContext('2d');
    this.hitCtx = document.createElement('canvas').getContext('2d');
    this.tooltip = container.querySelector('.map-tooltip');
    this.pill = container.querySelector('.map-pill');
    this.legend = container.querySelector('.map-legend');

    // Kamera: düz haritada (a, b) = harita merkezi; kürede (a, b) = merkezdeki boylam/enlem.
    this.cam = { zoom: 1, a: 0, b: 0 };
    this.anim = null;
    this.hovered = null;
    this.hoverPoint = { x: 0, y: 0 };
    this.size = { w: 1, h: 1 };
    this.pointers = new Map();
    this.pulses = new Map(); // yer id → { start, duration, win }

    this.setPlaces(game.places);
    new ResizeObserver(() => this.resize()).observe(container);
    this.resize();
    this.bindGestures();
    container.querySelector('[data-zoom="in"]').addEventListener('click', () => this.stepZoom(1.5));
    container.querySelector('[data-zoom="out"]').addEventListener('click', () => this.stepZoom(1 / 1.5));
    container.querySelector('[data-zoom="reset"]').addEventListener('click', () => this.reset());
  }

  get isGlobe() { return this.set.category.id === 'world'; }

  setPlaces(set) {
    this.set = set;
    this.anim = null;
    this.pulses.clear();
    this.hovered = null;
    if (this.isGlobe) {
      this.globe = globeGeometryFor(set);
      this.geo = null;
    } else {
      this.geo = flatGeometryFor(set);
      this.globe = null;
    }
    this.cam = this.homeCamera();
    this.updateLegend();
    this.draw();
  }

  homeCamera() {
    if (this.isGlobe) return { zoom: 1, a: GLOBE_HOME.lon, b: GLOBE_HOME.lat };
    const b = this.geo.bounds;
    return { zoom: 1, a: b.x + b.w / 2, b: b.y + b.h / 2 };
  }

  resize() {
    const r = this.container.getBoundingClientRect();
    this.size = { w: Math.max(1, r.width), h: Math.max(1, r.height) };
    const dpr = window.devicePixelRatio || 1;
    this.canvas.width = Math.round(this.size.w * dpr);
    this.canvas.height = Math.round(this.size.h * dpr);
    this.canvas.style.width = `${this.size.w}px`;
    this.canvas.style.height = `${this.size.h}px`;
    this.draw();
  }

  // MARK: Düz harita dönüşümleri

  get fit() {
    const b = this.geo.bounds;
    return Math.max(Math.min((this.size.w - PADDING * 2) / b.w, (this.size.h - PADDING * 2) / b.h), 0.01);
  }

  get scale() { return this.fit * this.cam.zoom; }

  toScreen(x, y) {
    const s = this.scale;
    return { x: this.size.w / 2 + (x - this.cam.a) * s, y: this.size.h / 2 + (y - this.cam.b) * s };
  }

  toMap(px, py) {
    const s = this.scale;
    return { x: this.cam.a + (px - this.size.w / 2) / s, y: this.cam.b + (py - this.size.h / 2) / s };
  }

  screenRect(r) {
    const a = this.toScreen(r.x, r.y);
    const s = this.scale;
    return { x: a.x, y: a.y, w: r.w * s, h: r.h * s };
  }

  // MARK: Küre dönüşümleri

  /** Kürenin ekrandaki yarıçapı. Yakınlaştırma 1'de küre görünüme sığar. */
  get radius() { return (Math.min(this.size.w, this.size.h) / 2 - PADDING) * this.cam.zoom; }

  /** Döndürme katsayıları: merkezdeki boylam/enlem. */
  rotation() {
    const l = this.cam.a * DEG, p = this.cam.b * DEG;
    return { cl: Math.cos(l), sl: Math.sin(l), cp: Math.cos(p), sp: Math.sin(p) };
  }

  /** Boylam/enlemden ekrana; görünmüyorsa (arka yüz) null. */
  projectLonLat(lon, lat, rot = this.rotation()) {
    const l = lon * DEG, p = lat * DEG;
    const x = Math.cos(p) * Math.cos(l), y = Math.cos(p) * Math.sin(l), z = Math.sin(p);
    const a = x * rot.cl + y * rot.sl, b = y * rot.cl - x * rot.sl;
    const cosc = rot.sp * z + rot.cp * a;
    const R = this.radius;
    return { x: this.size.w / 2 + R * b, y: this.size.h / 2 - R * (rot.cp * z - rot.sp * a), visible: cosc > 0, cosc };
  }

  /** Ekrandan boylam/enleme; küre dışındaysa null. */
  unproject(px, py) {
    const R = this.radius;
    const xp = (px - this.size.w / 2) / R, yp = -(py - this.size.h / 2) / R;
    const d2 = xp * xp + yp * yp;
    if (d2 > 1) return null;
    const cosc = Math.sqrt(1 - d2);
    const { cl, sl, cp, sp } = this.rotation();
    const a = cp * cosc - sp * yp, z = sp * cosc + cp * yp, b = xp;
    const x = a * cl - b * sl, y = a * sl + b * cl;
    return { lon: Math.atan2(y, x) / DEG, lat: Math.asin(Math.max(-1, Math.min(1, z))) / DEG };
  }

  /** Halkaları ekrana çizer; arka yüzdeki noktalar ufuk çemberine yaslanır. */
  traceGlobeRings(ctx, rings, rot) {
    const R = this.radius, cx = this.size.w / 2, cy = this.size.h / 2;
    const { cl, sl, cp, sp } = rot;
    let any = false;
    for (const ring of rings) {
      const v = ring.vec;
      const n = v.length / 3;
      let visible = false;
      for (let i = 0; i < n; i++) {
        const x = v[i * 3], y = v[i * 3 + 1], z = v[i * 3 + 2];
        if (sp * z + cp * (x * cl + y * sl) > 0) { visible = true; break; }
      }
      if (!visible) continue;
      any = true;
      for (let i = 0; i < n; i++) {
        const x = v[i * 3], y = v[i * 3 + 1], z = v[i * 3 + 2];
        const a = x * cl + y * sl;
        let px = y * cl - x * sl, py = cp * z - sp * a;
        if (sp * z + cp * a < 0) {
          const d = Math.hypot(px, py) || 1;
          px /= d; py /= d;
        }
        const sx = cx + R * px, sy = cy - R * py;
        if (i === 0) ctx.moveTo(sx, sy); else ctx.lineTo(sx, sy);
      }
      ctx.closePath();
    }
    return any;
  }

  // MARK: Çizim

  draw() {
    if (this.frame) return;
    this.frame = requestAnimationFrame(() => {
      this.frame = null;
      this.render();
    });
  }

  render() {
    const dpr = window.devicePixelRatio || 1;
    const colors = COLORS();
    const ctx = this.ctx;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.lineJoin = 'round';
    const now = performance.now();
    for (const [id, p] of this.pulses) if (now - p.start > p.duration) this.pulses.delete(id);

    const labels = this.isGlobe ? this.renderGlobe(ctx, colors, now) : this.renderFlat(ctx, colors, now, dpr);
    this.drawLabels(ctx, labels, colors);
    this.updateOverlays();
    // Animasyon sürüyorsa bir sonraki kareyi iste.
    if (this.pulses.size) this.draw();
  }

  renderFlat(ctx, colors, now, dpr) {
    const { geo } = this;
    const s = this.scale;
    const view = { x: -20, y: -20, w: this.size.w + 40, h: this.size.h + 40 };

    ctx.fillStyle = colors.sea;
    ctx.fillRect(0, 0, this.size.w, this.size.h);

    const tx = this.size.w / 2 - this.cam.a * s;
    const ty = this.size.h / 2 - this.cam.b * s;
    ctx.setTransform(dpr * s, 0, 0, dpr * s, dpr * tx, dpr * ty);

    ctx.fillStyle = colors.backgroundLand;
    ctx.strokeStyle = colors.backgroundBorder;
    ctx.lineWidth = 0.4 / s;
    for (const g of geo.background) {
      if (!g.rect || !intersects(this.screenRect(g.rect), view)) continue;
      ctx.fill(g.path);
      ctx.stroke(g.path);
    }

    const markers = [];
    const labels = [];
    geo.places.forEach((g, i) => {
      if (!g.rect) return;
      const sr = this.screenRect(g.rect);
      if (!intersects(sr, view)) return;
      const place = this.set.places[i];
      const color = this.fillFor(place, colors);
      const hovered = this.hovered === place;
      ctx.fillStyle = color;
      ctx.fill(g.path);
      ctx.strokeStyle = hovered ? colors.text : colors.border;
      ctx.lineWidth = (hovered ? 1.6 : 0.6) / s;
      ctx.stroke(g.path);
      const small = sr.w < MARKER_THRESHOLD && sr.h < MARKER_THRESHOLD;
      if (small) markers.push({ sr, color, hovered });
      const pulse = this.pulses.get(place.id);
      if (pulse) this.strokePulse(ctx, g.path, pulse, now, color, colors, 1 / s);
      if (this.labelFor(place)) {
        const p = small ? { x: sr.x + sr.w / 2, y: sr.y + sr.h / 2 - 10 } : this.toScreen(g.label.x, g.label.y);
        labels.push({ place, x: p.x, y: p.y });
      }
    });

    const hi = this.highlightIndex();
    if (hi >= 0) {
      const g = geo.places[hi];
      ctx.strokeStyle = colors.highlightGlow;
      ctx.lineWidth = 7 / s;
      ctx.stroke(g.path);
      ctx.strokeStyle = colors.highlight;
      ctx.lineWidth = 2.5 / s;
      ctx.stroke(g.path);
    }

    // Küçük yer işaretleri ekran koordinatında çizilir.
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    for (const m of markers) this.drawMarker(ctx, m.sr.x + m.sr.w / 2, m.sr.y + m.sr.h / 2, m.color, m.hovered, colors);
    if (hi >= 0) {
      const sr = this.screenRect(geo.places[hi].rect);
      if (sr.w < 24 && sr.h < 24) this.drawRing(ctx, sr.x + sr.w / 2, sr.y + sr.h / 2, colors.highlight);
    }
    return labels;
  }

  renderGlobe(ctx, colors, now) {
    const { globe } = this;
    const R = this.radius, cx = this.size.w / 2, cy = this.size.h / 2;
    const rot = this.rotation();

    // Uzay arka planı ve atmosfer parıltısı
    ctx.fillStyle = colors.space;
    ctx.fillRect(0, 0, this.size.w, this.size.h);
    const glow = ctx.createRadialGradient(cx, cy, R * 0.98, cx, cy, R * 1.08);
    glow.addColorStop(0, colors.atmosphere);
    glow.addColorStop(1, 'rgba(0,0,0,0)');
    ctx.fillStyle = glow;
    ctx.beginPath(); ctx.arc(cx, cy, R * 1.08, 0, Math.PI * 2); ctx.fill();

    // Okyanus: hafif gölgeli küre
    const ocean = ctx.createRadialGradient(cx - R * 0.35, cy - R * 0.35, R * 0.1, cx, cy, R);
    ocean.addColorStop(0, colors.seaLight);
    ocean.addColorStop(1, colors.sea);
    ctx.fillStyle = ocean;
    ctx.beginPath(); ctx.arc(cx, cy, R, 0, Math.PI * 2); ctx.fill();

    ctx.save();
    ctx.beginPath(); ctx.arc(cx, cy, R, 0, Math.PI * 2); ctx.clip();

    this.drawGraticule(ctx, rot, colors);

    ctx.fillStyle = colors.backgroundLand;
    ctx.strokeStyle = colors.backgroundBorder;
    ctx.lineWidth = 0.4;
    for (const g of globe.background) {
      ctx.beginPath();
      if (this.traceGlobeRings(ctx, g.rings, rot)) { ctx.fill(); ctx.stroke(); }
    }

    const markers = [];
    const labels = [];
    const px = (R * Math.PI) / 180; // derece başına piksel (merkezde)
    globe.places.forEach((g, i) => {
      const place = this.set.places[i];
      ctx.beginPath();
      if (!this.traceGlobeRings(ctx, g.rings, rot)) return;
      const color = this.fillFor(place, colors);
      const hovered = this.hovered === place;
      ctx.fillStyle = color;
      ctx.fill();
      ctx.strokeStyle = hovered ? colors.text : colors.border;
      ctx.lineWidth = hovered ? 1.6 : 0.5;
      ctx.stroke();
      const pulse = this.pulses.get(place.id);
      if (pulse) this.strokePulse(ctx, null, pulse, now, color, colors, 1);
      if (place.id === this.game.highlighted?.id) {
        ctx.strokeStyle = colors.highlightGlow; ctx.lineWidth = 7; ctx.stroke();
        ctx.strokeStyle = colors.highlight; ctx.lineWidth = 2.5; ctx.stroke();
      }
      const lp = this.projectLonLat(g.label.lon, g.label.lat, rot);
      const small = g.angular * px < MARKER_THRESHOLD;
      if (small && lp.visible) markers.push({ x: lp.x, y: lp.y, color, hovered, place });
      if (lp.cosc > 0.2 && this.labelFor(place)) labels.push({ place, x: lp.x, y: small ? lp.y - 10 : lp.y });
    });

    for (const m of markers) {
      this.drawMarker(ctx, m.x, m.y, m.color, m.hovered, colors);
      if (m.place.id === this.game.highlighted?.id) this.drawRing(ctx, m.x, m.y, colors.highlight);
    }
    ctx.restore();

    // Kenarda hafif gölge: küreye derinlik verir.
    const shade = ctx.createRadialGradient(cx, cy, R * 0.75, cx, cy, R);
    shade.addColorStop(0, 'rgba(0,0,0,0)');
    shade.addColorStop(1, colors.globeShade);
    ctx.fillStyle = shade;
    ctx.beginPath(); ctx.arc(cx, cy, R, 0, Math.PI * 2); ctx.fill();
    return labels;
  }

  drawGraticule(ctx, rot, colors) {
    ctx.strokeStyle = colors.graticule;
    ctx.lineWidth = 0.6;
    ctx.beginPath();
    const line = (pts) => {
      let pen = false;
      for (const [lon, lat] of pts) {
        const p = this.projectLonLat(lon, lat, rot);
        if (!p.visible) { pen = false; continue; }
        if (pen) ctx.lineTo(p.x, p.y); else { ctx.moveTo(p.x, p.y); pen = true; }
      }
    };
    for (let lon = -180; lon < 180; lon += 30) {
      const pts = [];
      for (let lat = -80; lat <= 80; lat += 4) pts.push([lon, lat]);
      line(pts);
    }
    for (let lat = -60; lat <= 60; lat += 30) {
      const pts = [];
      for (let lon = -180; lon <= 180; lon += 4) pts.push([lon, lat]);
      line(pts);
    }
    ctx.stroke();
  }

  drawMarker(ctx, x, y, color, hovered, colors) {
    ctx.beginPath();
    ctx.arc(x, y, MARKER_RADIUS, 0, Math.PI * 2);
    ctx.fillStyle = color;
    ctx.fill();
    ctx.lineWidth = hovered ? 1.6 : 0.8;
    ctx.strokeStyle = hovered ? colors.text : colors.markerStroke;
    ctx.stroke();
  }

  drawRing(ctx, x, y, color) {
    ctx.beginPath();
    ctx.arc(x, y, 13, 0, Math.PI * 2);
    ctx.lineWidth = 2.5;
    ctx.strokeStyle = color;
    ctx.stroke();
  }

  /** Yeni tahminde kısa parlama; bulunan yerde birkaç kez yeşil nabız. path null ise geçerli yol kullanılır. */
  strokePulse(ctx, path, pulse, now, color, colors, unit) {
    const t = Math.min(1, (now - pulse.start) / pulse.duration);
    const stroke = () => (path ? ctx.stroke(path) : ctx.stroke());
    ctx.save();
    if (pulse.win) {
      const wave = Math.sin(t * Math.PI * 3) ** 2 * (1 - t);
      ctx.strokeStyle = `rgba(46, 158, 79, ${0.85 * wave})`;
      ctx.lineWidth = (4 + 10 * wave) * unit;
      stroke();
    } else {
      const fade = 1 - easeOut(t);
      ctx.strokeStyle = colors.pulse.replace('ALPHA', (0.9 * fade).toFixed(3));
      ctx.lineWidth = (2 + 9 * t) * unit;
      stroke();
    }
    ctx.restore();
  }

  fillFor(place, colors) {
    const game = this.game;
    if (place.id === game.answer.id) {
      if (game.status === 'won') return colors.found;
      if (game.status === 'lost') return colors.answerReveal;
    }
    const g = game.guessFor(place);
    if (!g) return colors.unguessed;
    return heatColor(g.distance, this.set.maxDistance);
  }

  /** Haritada adı yazılacak yerler: tahmin edilenler ve oyun bitince gizli yer. */
  labelFor(place) {
    return !!this.game.guessFor(place) || (this.game.isOver && place.id === this.game.answer.id);
  }

  /**
   * Tahmin edilen her yerin adı mutlaka yazılır. Önce gizli yer, sonra en yakın tahminler yerleşir.
   * Ad sığmıyorsa ya da çakışıyorsa yakındaki boş bir yere (gerekirse komşunun üstüne) kayar ve
   * ince bir çizgiyle yerine bağlanır; ekran kenarında içeri itilir. (Swift'teki LabelLayout ile aynı.)
   */
  drawLabels(ctx, labels, colors) {
    if (!labels.length) return;
    const game = this.game;
    const rank = (p) => (p.id === game.answer.id ? -1 : game.guessFor(p)?.distance ?? 1e9);
    labels.sort((a, b) => rank(a.place) - rank(b.place));
    ctx.font = LABEL_FONT;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.lineJoin = 'round';
    const placed = [];
    for (const l of labels) {
      if (this.hovered?.id === l.place.id || game.highlighted?.id === l.place.id) continue; // etiketleri zaten var
      if (l.x < -40 || l.y < -40 || l.x > this.size.w + 40 || l.y > this.size.h + 40) continue;
      const box = placeLabel(l, ctx.measureText(l.place.name).width + 6, 16, this.size, placed);
      placed.push(box);
      const cx = box.x + box.w / 2;
      const cy = box.y + box.h / 2;
      if (Math.hypot(cx - l.x, cy - l.y) > 10) {
        const ex = Math.min(Math.max(l.x, box.x), box.x + box.w);
        const ey = Math.min(Math.max(l.y, box.y), box.y + box.h);
        ctx.beginPath();
        ctx.moveTo(l.x, l.y);
        ctx.lineTo(ex, ey);
        ctx.strokeStyle = colors.labelHalo;
        ctx.lineWidth = 3;
        ctx.stroke();
        ctx.strokeStyle = colors.labelText;
        ctx.globalAlpha = 0.8;
        ctx.lineWidth = 1;
        ctx.stroke();
        ctx.globalAlpha = 1;
        ctx.beginPath();
        ctx.arc(l.x, l.y, 2, 0, Math.PI * 2);
        ctx.fillStyle = colors.labelText;
        ctx.fill();
      }
      ctx.strokeStyle = colors.labelHalo;
      ctx.lineWidth = 3;
      ctx.strokeText(l.place.name, cx, cy);
      ctx.fillStyle = colors.labelText;
      ctx.fillText(l.place.name, cx, cy);
    }
  }

  highlightIndex() {
    const h = this.game.highlighted;
    return h ? this.set.places.findIndex((p) => p.id === h.id) : -1;
  }

  /** Vurgulanan yerin ekrandaki konumu (etiket için). */
  highlightAnchor() {
    const i = this.highlightIndex();
    if (i < 0) return null;
    if (this.isGlobe) {
      const g = this.globe.places[i];
      const p = this.projectLonLat(g.label.lon, g.label.lat);
      if (!p.visible) return null;
      const half = Math.max(8, (g.angular * this.radius * DEG) / 2);
      return { x: p.x, y: p.y - Math.min(half, 60), small: half < 12 };
    }
    const sr = this.screenRect(this.geo.places[i].rect);
    const small = sr.w < 24 && sr.h < 24;
    return { x: sr.x + sr.w / 2, y: sr.y, small };
  }

  updateOverlays() {
    // Vurgu etiketi
    const anchor = this.game.highlighted && this.hovered?.id !== this.game.highlighted.id ? this.highlightAnchor() : null;
    if (anchor) {
      this.pill.textContent = this.game.highlighted.name;
      this.pill.hidden = false;
      const x = Math.min(Math.max(anchor.x, 70), this.size.w - 70);
      const y = Math.max(anchor.y - (anchor.small ? 26 : 16), 16);
      this.pill.style.transform = `translate(${x}px, ${y}px) translate(-50%, -50%)`;
    } else {
      this.pill.hidden = true;
    }

    // Üzerine gelme / dokunma etiketi
    const label = this.hovered ? this.hoverLabel(this.hovered) : null;
    if (label) {
      this.tooltip.textContent = label;
      this.tooltip.hidden = false;
      const w = this.tooltip.offsetWidth;
      const x = this.hoverPoint.x + 14 + w > this.size.w ? this.hoverPoint.x - w - 10 : this.hoverPoint.x + 14;
      this.tooltip.style.transform = `translate(${Math.max(4, x)}px, ${this.hoverPoint.y + 10}px)`;
    } else {
      this.tooltip.hidden = true;
    }
  }

  hoverLabel(place) {
    const game = this.game;
    const g = game.guessFor(place);
    if (g) {
      if (place.id === game.answer.id) return `${place.name} ✓`;
      if (g.distance === 0) return `${place.name} · ${t('neighbor')}`;
      return game.showDistance ? `${place.name} · ${formatKm(g.distance)}` : place.name;
    }
    return game.isOver ? place.name : null;
  }

  /** Köşedeki renk skalası: kategorinin mesafelerine göre km işaretleri. */
  updateLegend() {
    if (!this.legend) return;
    const max = this.set.maxDistance;
    const stops = [];
    for (let i = 0; i <= 10; i++) {
      const t = i / 10;
      stops.push(`${heatColor(t * t * max, max)} ${t * 100}%`);
    }
    const nice = (v) => {
      const p = 10 ** Math.floor(Math.log10(v));
      return Math.max(p, Math.round(v / p) * p);
    };
    const ticks = this.game.showDistance
      ? [{ t: 0, text: t('neighbor') }, { t: 0.5, text: formatKm(nice(max * 0.25)) }, { t: 1, text: formatKm(nice(max)) }]
      : [{ t: 0, text: t('near') }, { t: 1, text: t('far') }];
    this.legend.innerHTML = `
      <div class="legend-bar" style="background: linear-gradient(90deg, ${stops.join(', ')})"></div>
      <div class="legend-ticks">${ticks.map((k) => `<span style="left:${(k.t * 100).toFixed(1)}%">${k.text}</span>`).join('')}</div>`;
  }

  placeAt(px, py) {
    if (this.isGlobe) return this.placeAtGlobe(px, py);
    const m = this.toMap(px, py);
    for (let i = 0; i < this.geo.places.length; i++) {
      const g = this.geo.places[i];
      const r = g.rect;
      if (!r || m.x < r.x || m.x > r.x + r.w || m.y < r.y || m.y > r.y + r.h) continue;
      if (this.hitCtx.isPointInPath(g.path, m.x, m.y)) return this.set.places[i];
    }
    // Küçük yerlerin işaret noktalarına da isabet edilebilsin (dokunmatikte daha geniş alan).
    const slop = this.lastPointerType === 'touch' ? 12 : 3;
    for (let i = 0; i < this.geo.places.length; i++) {
      const g = this.geo.places[i];
      if (!g.rect) continue;
      const sr = this.screenRect(g.rect);
      if (sr.w < MARKER_THRESHOLD && sr.h < MARKER_THRESHOLD &&
          Math.hypot(px - (sr.x + sr.w / 2), py - (sr.y + sr.h / 2)) <= MARKER_RADIUS + slop) {
        return this.set.places[i];
      }
    }
    return null;
  }

  placeAtGlobe(px, py) {
    const ll = this.unproject(px, py);
    if (!ll) return null;
    for (let i = 0; i < this.globe.places.length; i++) {
      if (pointInRings(this.globe.places[i].rings, ll.lon, ll.lat)) return this.set.places[i];
    }
    const slop = this.lastPointerType === 'touch' ? 12 : 3;
    const pxPerDeg = this.radius * DEG;
    const rot = this.rotation();
    for (let i = 0; i < this.globe.places.length; i++) {
      const g = this.globe.places[i];
      if (g.angular * pxPerDeg >= MARKER_THRESHOLD) continue;
      const p = this.projectLonLat(g.label.lon, g.label.lat, rot);
      if (p.visible && Math.hypot(px - p.x, py - p.y) <= MARKER_RADIUS + slop) return this.set.places[i];
    }
    return null;
  }

  setHovered(place, point) {
    if (point) this.hoverPoint = point;
    if (place === this.hovered && !point) return;
    this.hovered = place;
    this.draw();
  }

  // MARK: Animasyonlar

  /** Yeni tahmin edilen yerde kısa bir parlama. */
  pulse(place) {
    this.pulses.set(place.id, { start: performance.now(), duration: PULSE_MS, win: false });
    this.draw();
  }

  /** Bulunan yerde yeşil nabız. */
  celebrate(place) {
    this.pulses.set(place.id, { start: performance.now(), duration: WIN_PULSE_MS, win: true });
    this.draw();
  }

  // MARK: Kamera uçuşu

  /** Yeri ve çevresini gösterecek kadar yumuşakça yakınlaşır; uzak yerlere geçerken önce hafifçe uzaklaşır. */
  focus(place) {
    const i = this.set.places.findIndex((p) => p.id === place.id);
    if (i < 0) return;
    if (this.isGlobe) return this.focusGlobe(this.globe.places[i].focus);

    const rect = this.geo.places[i].focus;
    const b = this.geo.bounds;
    const fit = this.fit;
    const [minF, maxF] = spanFractions(this.set.category.id);
    const mapSpan = Math.max(b.w, b.h);
    const span = Math.min(Math.max(Math.max(rect.w, rect.h) * 5.2, mapSpan * minF), mapSpan * maxF);
    let z = Math.min((this.size.w - PADDING * 2) / (fit * span), (this.size.h - PADDING * 2) / (fit * span));
    if (z <= 1.05) return this.fly(this.homeCamera());
    z = Math.min(z, maxZoomFor(this.set.category.id) * 0.75);

    // Merkez, görünen alan haritanın dışına fazla taşmayacak şekilde sınırlanır.
    const hw = (this.size.w / 2 / (fit * z)) * 0.8, hh = (this.size.h / 2 / (fit * z)) * 0.8;
    const clamp = (v, lo, hi, mid) => (lo <= hi ? Math.min(Math.max(v, lo), hi) : mid);
    this.fly({
      zoom: z,
      a: clamp(rect.x + rect.w / 2, b.x + hw, b.x + b.w - hw, b.x + b.w / 2),
      b: clamp(rect.y + rect.h / 2, b.y + hh, b.y + b.h - hh, b.y + b.h / 2),
    });
  }

  /** Küre: ülkeyi ortaya getirecek şekilde döndür ve çevresiyle birlikte görünecek kadar yaklaş. */
  focusGlobe(f) {
    const span = Math.min(Math.max(f.size * 5.2, GLOBE_SPAN[0]), GLOBE_SPAN[1]);
    // Yakınlaştırma z'de görünen yarı açı θ için sin θ = 1/z.
    const zoom = Math.max(1, 1 / Math.sin((span / 2) * DEG));
    this.fly({ zoom, a: f.lon, b: Math.max(-70, Math.min(75, f.lat)) });
  }

  fly(target) {
    const from = { ...this.cam };
    const to = { ...target };
    if (this.isGlobe) {
      // Kısa yoldan dön: hedef boylamı mevcut boylama en yakın eşdeğere taşı.
      to.a = from.a + wrapLon(to.a - from.a);
      const dist = Math.acos(Math.max(-1, Math.min(1,
        Math.sin(from.b * DEG) * Math.sin(to.b * DEG) +
        Math.cos(from.b * DEG) * Math.cos(to.b * DEG) * Math.cos((to.a - from.a) * DEG)))) / DEG;
      if (dist < 35) return this.animate([{ ...to, duration: 800, ease: easeInOut }]);
      // Uzak: önce uzaklaşıp küreyi döndür, sonra yaklaş.
      const mid = { zoom: Math.min(from.zoom, to.zoom, 1.15), a: (from.a + to.a) / 2, b: (from.b + to.b) / 2 };
      return this.animate([{ ...mid, duration: 550, ease: easeIn }, { ...to, duration: 650, ease: easeOut }]);
    }

    const screenDistance = Math.hypot(to.a - from.a, to.b - from.b) * this.scale;
    if (screenDistance <= Math.max(this.size.w, this.size.h) * 0.8) {
      this.animate([{ ...to, duration: 750, ease: easeInOut }]);
      return;
    }
    const fit = this.fit;
    const spanX = Math.abs(to.a - from.a) * 1.3 + this.size.w / (fit * to.zoom);
    const spanY = Math.abs(to.b - from.b) * 1.3 + this.size.h / (fit * to.zoom);
    const midZoom = Math.max(1, Math.min(from.zoom, to.zoom, this.size.w / (fit * spanX), this.size.h / (fit * spanY)));
    this.animate([
      { zoom: midZoom, a: (from.a + to.a) / 2, b: (from.b + to.b) / 2, duration: 450, ease: easeIn },
      { ...to, duration: 600, ease: easeOut },
    ]);
  }

  animate(stages) {
    const token = {};
    this.anim = token;
    const run = (index) => {
      if (this.anim !== token || index >= stages.length) return;
      const st = stages[index];
      const c0 = { ...this.cam };
      const t0 = performance.now();
      const step = (now) => {
        if (this.anim !== token) return;
        const t = Math.min(1, (now - t0) / st.duration);
        const e = st.ease(t);
        this.cam = {
          zoom: c0.zoom + (st.zoom - c0.zoom) * e,
          a: c0.a + (st.a - c0.a) * e,
          b: c0.b + (st.b - c0.b) * e,
        };
        this.render();
        if (t < 1) requestAnimationFrame(step); else run(index + 1);
      };
      requestAnimationFrame(step);
    };
    run(0);
  }

  reset() {
    const home = this.homeCamera();
    if (this.isGlobe) home.a = this.cam.a + wrapLon(home.a - this.cam.a);
    this.animate([{ ...home, duration: 600, ease: easeInOut }]);
  }

  stepZoom(factor) {
    this.animate([{ ...this.cam, zoom: this.clampZoom(this.cam.zoom * factor), duration: 300, ease: easeInOut }]);
  }

  clampZoom(z) { return Math.min(Math.max(z, 1), this.isGlobe ? 12 : maxZoomFor(this.set.category.id)); }

  /** Bir ekran noktasını sabit tutarak yakınlaştırır (tekerlek, iki parmak). Kürede merkeze göre. */
  zoomAt(px, py, newZoom) {
    if (this.isGlobe) { this.cam = { ...this.cam, zoom: this.clampZoom(newZoom) }; return; }
    const before = this.toMap(px, py);
    const zoom = this.clampZoom(newZoom);
    const s = this.fit * zoom;
    this.cam = { zoom, a: before.x - (px - this.size.w / 2) / s, b: before.y - (py - this.size.h / 2) / s };
  }

  /** Sürükleme: düz haritada kaydırır, kürede döndürür. */
  dragBy(start, dx, dy) {
    if (this.isGlobe) {
      const k = 1 / (this.radius * DEG);
      this.cam = { ...this.cam, a: start.a - dx * k, b: Math.max(-80, Math.min(80, start.b + dy * k)) };
    } else {
      this.cam = { ...this.cam, a: start.a - dx / this.scale, b: start.b - dy / this.scale };
    }
  }

  // MARK: Hareketler

  bindGestures() {
    const el = this.canvas;
    const local = (e) => {
      const r = el.getBoundingClientRect();
      return { x: e.clientX - r.left, y: e.clientY - r.top };
    };
    let drag = null;
    let pinch = null;
    let lastTap = 0;

    el.addEventListener('pointerdown', (e) => {
      el.setPointerCapture(e.pointerId);
      this.lastPointerType = e.pointerType;
      this.pointers.set(e.pointerId, local(e));
      this.anim = null; // elle müdahale uçuşu durdurur
      if (this.pointers.size === 1) {
        drag = { start: local(e), cam: { ...this.cam }, moved: false };
      } else if (this.pointers.size === 2) {
        const [a, b] = [...this.pointers.values()];
        pinch = { dist: Math.hypot(a.x - b.x, a.y - b.y), zoom: this.cam.zoom };
        drag = null;
      }
    });

    el.addEventListener('pointermove', (e) => {
      const p = local(e);
      if (this.pointers.has(e.pointerId)) this.pointers.set(e.pointerId, p);
      if (pinch && this.pointers.size >= 2) {
        const [a, b] = [...this.pointers.values()];
        const d = Math.hypot(a.x - b.x, a.y - b.y);
        this.zoomAt((a.x + b.x) / 2, (a.y + b.y) / 2, pinch.zoom * (d / pinch.dist));
        this.render();
        return;
      }
      if (drag) {
        const dx = p.x - drag.start.x, dy = p.y - drag.start.y;
        if (!drag.moved && Math.hypot(dx, dy) < 4) return;
        drag.moved = true;
        this.dragBy(drag.cam, dx, dy);
        el.classList.add('dragging');
        this.render();
        return;
      }
      if (e.pointerType === 'mouse') this.setHovered(this.placeAt(p.x, p.y), p);
    });

    const end = (e) => {
      const p = local(e);
      this.pointers.delete(e.pointerId);
      el.classList.remove('dragging');
      if (pinch && this.pointers.size < 2) {
        pinch = null;
        const rest = [...this.pointers.values()][0];
        drag = rest ? { start: rest, cam: { ...this.cam }, moved: true } : null;
        return;
      }
      if (drag && !drag.moved && e.type === 'pointerup') {
        const now = performance.now();
        if (now - lastTap < 300) {
          this.reset();
          lastTap = 0;
        } else {
          lastTap = now;
          // Dokunmatikte üzerine gelme olmadığı için dokunulan yerin adı gösterilir.
          if (e.pointerType !== 'mouse') {
            const tapped = this.placeAt(p.x, p.y);
            this.setHovered(tapped === this.hovered ? null : tapped, p);
          }
        }
      }
      drag = null;
    };
    el.addEventListener('pointerup', end);
    el.addEventListener('pointercancel', end);
    el.addEventListener('pointerleave', (e) => {
      if (e.pointerType === 'mouse' && !drag) this.setHovered(null);
    });

    el.addEventListener('wheel', (e) => {
      e.preventDefault();
      this.anim = null;
      const p = local(e);
      // Trackpad sıkıştırması ctrlKey ile gelir; normal kaydırma da yakınlaştırır.
      const factor = Math.exp(-e.deltaY * (e.ctrlKey ? 0.01 : 0.0025));
      this.zoomAt(p.x, p.y, this.cam.zoom * factor);
      this.render();
    }, { passive: false });
  }
}

// MARK: - Keşif haritası (istatistikler)

/** Bulunan yerleri yeşile boyayan küçük düz harita. */
export function drawDiscoveryMap(canvas, set, foundIds) {
  const geo = flatGeometryFor(set);
  const colors = COLORS();
  const dpr = window.devicePixelRatio || 1;
  const w = canvas.clientWidth, h = canvas.clientHeight;
  canvas.width = Math.round(w * dpr);
  canvas.height = Math.round(h * dpr);
  const ctx = canvas.getContext('2d');
  const b = geo.bounds;
  const s = Math.min((w - 8) / b.w, (h - 8) / b.h);
  const tx = w / 2 - (b.x + b.w / 2) * s, ty = h / 2 - (b.y + b.h / 2) * s;
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.fillStyle = colors.sea;
  ctx.fillRect(0, 0, w, h);
  ctx.setTransform(dpr * s, 0, 0, dpr * s, dpr * tx, dpr * ty);
  ctx.lineJoin = 'round';
  ctx.fillStyle = colors.backgroundLand;
  for (const g of geo.background) ctx.fill(g.path);
  ctx.lineWidth = 0.5 / s;
  ctx.strokeStyle = colors.border;
  const markers = [];
  geo.places.forEach((g, i) => {
    const found = foundIds.has(set.places[i].id);
    ctx.fillStyle = found ? colors.found : colors.unguessed;
    ctx.fill(g.path);
    ctx.stroke(g.path);
    if (found && g.rect && g.rect.w * s < 4 && g.rect.h * s < 4) markers.push(g.rect);
  });
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  for (const r of markers) {
    ctx.beginPath();
    ctx.arc(tx + (r.x + r.w / 2) * s, ty + (r.y + r.h / 2) * s, 3, 0, Math.PI * 2);
    ctx.fillStyle = colors.found;
    ctx.fill();
  }
}
