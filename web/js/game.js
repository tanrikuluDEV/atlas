// Oyun durumu ve istatistikler. Mac/iPhone uygulamasındaki GameModel.swift ve Stats.swift'in karşılığı.
import { answerIndex, dayIndex } from './daily.js';
import { categoryById, categoryIndex, hintsFor, placeSet } from './places.js';
import { formatKm, t } from './i18n.js';
import { store } from './store.js';
import { progress, totalXP } from './progression.js';
import { earnedBadgeIds, allBadges } from './badges.js';
import { CHAIN, ChainStats, TimedStats, hopDistances, randomChainPair, shortestPath, supportsChain } from './modes.js';
import { flaggedName } from './flags.js';

/** Gizli yeri bulma modları (istatistikleri Stats'ta). */
export const isClassic = (mode) => mode === 'daily' || mode === 'practice';
export const MODES = ['daily', 'practice', 'timed', 'chain'];
export const TIMED_DURATION = 180_000;
const SKIP_PENALTY = 10_000;

export { store };

// MARK: - İstatistikler

export class Stats {
  constructor(data = {}) {
    this.played = data.played ?? 0;
    this.won = data.won ?? 0;
    this.currentStreak = data.currentStreak ?? 0;
    this.maxStreak = data.maxStreak ?? 0;
    this.lastWonDay = data.lastWonDay ?? null;
    this.lastPlayedDay = data.lastPlayedDay ?? null;
    this.history = data.history ?? []; // { date, guesses, won, answerID, hints }
  }

  static key(category, mode) {
    return `atlas.stats.${mode}.${category}`;
  }

  static load(category, mode) {
    const s = new Stats(store.get(Stats.key(category, mode), {}));
    if (mode === 'daily') s.refreshStreak(dayIndex());
    return s;
  }

  save(category, mode) { store.set(Stats.key(category, mode), this); }

  get winRate() { return this.played ? Math.round((this.won / this.played) * 100) : 0; }

  get winningCounts() { return this.history.filter((r) => r.won).map((r) => r.guesses); }

  get averageGuesses() {
    const w = this.winningCounts;
    return w.length ? w.reduce((a, b) => a + b, 0) / w.length : null;
  }

  recentAverage(n) {
    const w = this.winningCounts.slice(-n);
    return w.length ? w.reduce((a, b) => a + b, 0) / w.length : null;
  }

  get distribution() {
    const buckets = [['1–3', 1, 3], ['4–6', 4, 6], ['7–10', 7, 10], ['11–15', 11, 15], ['16+', 16, Infinity]];
    const w = this.winningCounts;
    return buckets.map(([label, lo, hi]) => ({ label, count: w.filter((g) => g >= lo && g <= hi).length }));
  }

  recordDaily(won, guesses, hints, answerID, day, expert = false) {
    if (this.lastPlayedDay === day) return;
    this.lastPlayedDay = day;
    this.played += 1;
    this.history.push({ date: Date.now(), guesses, won, answerID, hints, ...(expert ? { expert: true } : {}) });
    if (won) {
      this.won += 1;
      this.currentStreak = this.lastWonDay === day - 1 ? this.currentStreak + 1 : 1;
      this.maxStreak = Math.max(this.maxStreak, this.currentStreak);
      this.lastWonDay = day;
    } else {
      this.currentStreak = 0;
    }
  }

  recordPractice(won, guesses, hints, answerID, expert = false) {
    this.played += 1;
    this.history.push({ date: Date.now(), guesses, won, answerID, hints, ...(expert ? { expert: true } : {}) });
    if (won) {
      this.won += 1;
      this.currentStreak += 1;
      this.maxStreak = Math.max(this.maxStreak, this.currentStreak);
    } else {
      this.currentStreak = 0;
    }
  }

  refreshStreak(today) {
    if (this.lastWonDay != null && this.lastWonDay < today - 1) this.currentStreak = 0;
  }
}

// MARK: - Oyun

export class Game {
  constructor(onChange) {
    this.onChange = onChange;
    this.category = store.get('atlas.category', 'turkey');
    if (categoryIndex(this.category) < 0) this.category = 'turkey';
    this.places = placeSet(this.category);
    this.mode = 'daily';
    this.message = null;
    this.lastGuess = null;
    this.highlighted = null;
    this.roundID = 0;
    this.timedFound = [];
    this.timedSkipped = [];
    this.timedStart = null;
    this.timedEnd = null;
    this.chainShortest = [];
    this.loadStats();
    this.startDaily();
  }

  // Türetilmiş değerler
  get isOver() { return this.status !== 'playing'; }
  get puzzleNumber() { return this.day + 1; }
  get currentStats() { return this.mode === 'daily' ? this.dailyStats : this.practiceStats; }
  get sortedGuesses() { return this.guesses.slice().sort((a, b) => a.distance - b.distance || a.order - b.order); }
  get closest() { return this.sortedGuesses[0] ?? null; }
  guessFor(place) { return this.guesses.find((g) => g.place.id === place.id) ?? null; }

  /** Rota tekrarının adım sayısı: tahminler, pes edildiyse bir de gizli yer. */
  get replayLength() { return this.guesses.length + (this.status === 'lost' ? 1 : 0); }
  /** Haritada görünen tahmin (rota tekrarında sırası gelmemiş tahminler gizlenir). */
  mapGuessFor(place) {
    const g = this.guessFor(place);
    if (g && this.replayStep != null && g.order >= this.replayStep) return null;
    return g;
  }
  /** Haritada gizli yer açık mı (oyun bittiyse ve rota tekrarı sona geldiyse). */
  get mapRevealsAnswer() { return this.isOver && (this.replayStep == null || this.replayStep >= this.replayLength); }
  /** Rota tekrarında o adımda gösterilen yer. */
  replayPlace(step) {
    if (step < 1) return null;
    const ordered = this.guesses.slice().sort((a, b) => a.order - b.order);
    return step <= ordered.length ? ordered[step - 1].place : this.answer;
  }
  /** Uzman modu: haritada adlar ve mesafeler gizli, yalnızca renk. İlk tahminde ayardan alınıp tur boyunca sabit kalır. */
  get expert() { return isClassic(this.mode) && (this.roundExpert ?? store.get('atlas.expert', false)); }
  /** Mesafe kilometre olarak gösterilsin mi (ayar açık ve uzman modu kapalı). */
  get showsKm() { return this.showDistance && !this.expert; }
  /** Haritada tahmin edilen yerlerin adları yazılsın mı (uzman modunda oyun bitene kadar yazılmaz). */
  get showsGuessNames() { return !this.expert || this.isOver; }

  /** Gizli yer hakkındaki ipuçları (seçili dilde). */
  get hints() { return hintsFor(this.category, this.answer); }

  /** Mesaj, dil değişince yeniden çevrilebilsin diye metin değil işlev olarak saklanır. */
  get message() { return this.messageFn?.() ?? null; }
  set message(fn) { this.messageFn = fn; }

  emit() { this.onChange?.(this); }

  // Eylemler
  submitText(text) {
    if (this.isOver) return false;
    const place = this.places.match(text);
    if (!place) {
      this.message = () => t(`msg.notFound.${this.places.category.kind}`, { text: text.trim() });
      this.emit();
      return false;
    }
    return this.submit(place);
  }

  submit(place) {
    if (this.isOver) return false;
    if (this.mode === 'chain') return this.submitChain(place);
    if (this.guessFor(place)) {
      this.message = () => t('msg.already', { name: place.name });
      this.emit();
      return false;
    }
    if (this.mode === 'timed' && !this.timedStart) this.startTimer(false);
    if (this.roundExpert == null) this.roundExpert = store.get('atlas.expert', false);
    const g = { place, distance: this.places.distance(place, this.answer), order: this.guesses.length };
    this.lastImproved = !this.guesses.length || g.distance < this.closest.distance;
    this.guesses.push(g);
    this.lastGuess = g;
    this.message = null;
    if (place.id === this.answer.id) {
      if (this.mode === 'timed') {
        this.timedFound.push(place);
        this.nextTimedTarget();
        this.message = () => t('timed.found', { name: place.name });
        this.emit();
        return true;
      }
      this.status = 'won';
      this.finish();
    }
    this.persistDaily();
    this.emit();
    return true;
  }

  useHint() {
    if (this.isOver || this.hintsUsed >= this.hints.length) return;
    this.hintsUsed += 1;
    this.persistDaily();
    this.emit();
  }

  giveUp() {
    if (this.isOver) return;
    if (this.mode === 'timed') { this.finishTimed(); return; }
    if (this.mode === 'chain') {
      this.status = 'lost';
      this.message = null;
      this.finishChain();
      this.emit();
      return;
    }
    if (this.roundExpert == null) this.roundExpert = store.get('atlas.expert', false);
    this.status = 'lost';
    this.message = null;
    this.finish();
    this.persistDaily();
    this.emit();
  }

  switchMode(mode) {
    if (mode === this.mode) return;
    this.mode = mode;
    this.startMode();
    this.emit();
  }

  startMode() {
    if (this.mode === 'daily') this.startDaily();
    else if (this.mode === 'timed') this.newTimed(false);
    else if (this.mode === 'chain') this.newChain(false);
    else this.newPractice(false);
  }

  /** "Yeni oyun": süreli ve zincirde aynı modda yeni tur; günlük ve alıştırmada yeni alıştırma. */
  newRound() {
    if (this.mode === 'timed') this.newTimed();
    else if (this.mode === 'chain') this.newChain();
    else this.newPractice();
  }

  switchCategory(id) {
    if (id === this.category) return;
    this.category = id;
    this.places = placeSet(id);
    store.set('atlas.category', id);
    this.loadStats();
    this.startMode();
    this.emit();
  }

  newPractice(emit = true) {
    this.mode = 'practice';
    this.stopTimer();
    const list = this.places.places;
    let next;
    do { next = list[Math.floor(Math.random() * list.length)]; } while (this.answer && next.id === this.answer.id);
    this.answer = next;
    this.resetRound();
    if (emit) this.emit();
  }

  refreshDayIfNeeded() {
    const today = dayIndex();
    if (today === this.day) return;
    this.dailyStats.refreshStreak(today);
    this.dailyStats.save(this.category, 'daily');
    if (this.mode === 'daily') { this.startDaily(); this.emit(); }
  }

  /** Tahminleri sırasıyla haritada yeniden oynatır; harita her adımda o yere uçar ve parlar. */
  startReplay() {
    if (!isClassic(this.mode) || !this.isOver || !this.replayLength) return;
    this.stopReplay(false);
    const total = this.replayLength;
    // Uzun oyunlarda adımlar kısalır; tekrar en fazla ~12 sn sürer.
    const interval = Math.max(450, Math.min(1100, 12000 / total));
    const token = (this.replayToken = (this.replayToken ?? 0) + 1);
    this.replayStep = 0;
    this.emit();
    const step = (n) => {
      if (token !== this.replayToken) return;
      if (n > total) { this.replayStep = null; this.emit(); return; }
      this.replayStep = n;
      this.emit();
      setTimeout(() => step(n + 1), n === total ? 2600 : interval);
    };
    setTimeout(() => step(1), 700);
  }

  stopReplay(emit = true) {
    this.replayToken = (this.replayToken ?? 0) + 1;
    if (this.replayStep == null) return;
    this.replayStep = null;
    if (emit) this.emit();
  }

  setHighlighted(place) {
    this.highlighted = place;
    this.emit();
  }

  // İç işler
  startDaily() {
    this.stopTimer();
    this.day = dayIndex();
    const byId = this.places.placesById;
    this.answer = byId[answerIndex(this.day, categoryById(this.category).seed, byId.length)];
    this.restoreDaily();
  }

  resetRound() {
    this.stopReplay(false);
    this.newBadges = [];
    this.lastImproved = false;
    this.guesses = [];
    this.status = 'playing';
    this.message = null;
    this.lastGuess = null;
    this.highlighted = null;
    this.hintsUsed = 0;
    this.reward = null;
    this.showResult = false;
    this.roundExpert = null;
    this.roundID += 1;
  }

  loadStats() {
    this.dailyStats = Stats.load(this.category, 'daily');
    this.practiceStats = Stats.load(this.category, 'practice');
  }

  finish() {
    const won = this.status === 'won';
    const before = totalXP(Stats.load);
    const badgesBefore = earnedBadgeIds(Stats.load);
    if (this.mode === 'daily') {
      this.dailyStats.recordDaily(won, this.guesses.length, this.hintsUsed, this.answer.id, this.day, this.expert);
      this.dailyStats.save(this.category, 'daily');
    } else {
      this.practiceStats.recordPractice(won, this.guesses.length, this.hintsUsed, this.answer.id, this.expert);
      this.practiceStats.save(this.category, 'practice');
    }
    this.rewardAndBadges(before, badgesBefore);
  }

  rewardAndBadges(before, badgesBefore) {
    // Bu oyunun kazandırdığı puan; sonuç penceresinde canlandırılır.
    this.reward = { before: progress(before), after: progress(totalXP(Stats.load)) };
    this.newBadges = allBadges(Stats.load).filter((b) => b.earned && !badgesBefore.has(b.id));
    this.showResult = true;
  }

  get dailyKey() { return `atlas.daily.${this.category}.${this.day}`; }

  persistDaily() {
    if (this.mode !== 'daily') return;
    store.set(this.dailyKey, { guessIDs: this.guesses.map((g) => g.place.id), status: this.status, hints: this.hintsUsed, ...(this.roundExpert != null ? { expert: this.roundExpert } : {}) });
  }

  restoreDaily() {
    this.resetRound();
    const saved = store.get(this.dailyKey);
    if (!saved) return;
    for (const id of saved.guessIDs) {
      const p = this.places.place(id);
      if (p) this.guesses.push({ place: p, distance: this.places.distance(p, this.answer), order: this.guesses.length });
    }
    this.status = saved.status;
    this.hintsUsed = saved.hints ?? 0;
    // Başlamış bir turun uzman modu kayıttan gelir (eski kayıtlar normal mod).
    if (this.guesses.length || this.status !== 'playing') this.roundExpert = saved.expert ?? false;
  }

  // MARK: Zamana karşı

  newTimed(emit = true) {
    this.mode = 'timed';
    this.stopTimer();
    this.timedStart = null;
    this.timedEnd = null;
    this.timedFound = [];
    this.timedSkipped = [];
    this.timedResult = null;
    this.answer = this.randomTimedTarget();
    this.resetRound();
    if (emit) this.emit();
  }

  startTimer(emit = true) {
    if (this.mode !== 'timed' || this.timedStart || this.isOver) return;
    this.timedStart = Date.now();
    this.timedEnd = this.timedStart + TIMED_DURATION;
    this.scheduleTimedEnd();
    if (emit) this.emit();
  }

  /** Kalan süre (ms; başlamadıysa tam süre). */
  timedRemaining(now = Date.now()) {
    return this.timedEnd ? Math.max(0, this.timedEnd - now) : TIMED_DURATION;
  }

  skipTimed() {
    if (this.mode !== 'timed' || this.isOver) return;
    if (!this.timedStart) this.startTimer(false);
    const skipped = this.answer;
    this.timedSkipped.push(skipped);
    this.timedEnd -= SKIP_PENALTY;
    if (this.timedRemaining() <= 0) { this.finishTimed(); return; }
    this.scheduleTimedEnd();
    this.nextTimedTarget();
    this.message = () => t('timed.skipped', { name: skipped.name });
    this.emit();
  }

  scheduleTimedEnd() {
    clearTimeout(this.timer);
    this.timer = setTimeout(() => this.finishTimed(), this.timedRemaining() + 20);
  }

  stopTimer() { clearTimeout(this.timer); this.timer = null; }

  randomTimedTarget() {
    const used = new Set([...this.timedFound, ...this.timedSkipped, this.answer].filter(Boolean).map((p) => p.id));
    const open = this.places.places.filter((p) => !used.has(p.id));
    const list = open.length ? open : this.places.places;
    return list[Math.floor(Math.random() * list.length)];
  }

  nextTimedTarget() {
    this.answer = this.randomTimedTarget();
    this.guesses = [];
    this.lastGuess = null;
    this.lastImproved = false;
    this.highlighted = null;
    this.message = null;
    this.roundID += 1;
  }

  finishTimed() {
    if (this.mode !== 'timed' || this.status !== 'playing' || !this.timedStart) return;
    this.stopTimer();
    const before = totalXP(Stats.load);
    const badgesBefore = earnedBadgeIds(Stats.load);
    const previousBest = TimedStats.load(this.category).best;
    const s = TimedStats.record(this.category, this.timedFound.length, this.timedSkipped.length);
    const score = this.timedFound.length;
    this.timedResult = { score, best: s.best, isRecord: score > previousBest && score > 0 };
    this.status = 'lost';
    this.message = null;
    this.rewardAndBadges(before, badgesBefore);
    this.emit();
  }

  // MARK: Komşu zinciri

  get chainAvailable() { return supportsChain(this.places); }
  get chainOptimal() { return Math.max(0, this.chainShortest.length - 2); }
  get chainLimit() { return this.chainOptimal + 4; }
  get chainGuessesLeft() { return Math.max(0, this.chainLimit - this.guesses.length); }

  newChain(emit = true) {
    this.mode = 'chain';
    this.stopTimer();
    this.resetRound();
    this.chainPath = null;
    const pair = randomChainPair(this.places);
    this.chainStart = pair?.start ?? null;
    this.chainEnd = pair?.end ?? null;
    this.chainShortest = pair?.path ?? [];
    this.chainFromStart = pair ? hopDistances(this.places, pair.start) : new Map();
    this.chainFromEnd = pair ? hopDistances(this.places, pair.end) : new Map();
    if (pair) this.answer = pair.end;
    if (emit) this.emit();
  }

  chainClass(place) {
    const a = this.chainFromStart?.get(place.id), b = this.chainFromEnd?.get(place.id);
    if (a == null || b == null) return CHAIN.far;
    const extra = a + b - (this.chainShortest.length - 1);
    return extra === 0 ? CHAIN.onPath : extra <= 2 ? CHAIN.near : CHAIN.far;
  }

  isChainEnd(place) { return place.id === this.chainStart?.id || place.id === this.chainEnd?.id; }

  submitChain(place) {
    if (!this.chainStart) return false;
    if (this.isChainEnd(place)) {
      this.message = () => t('chain.endpoint', { name: place.name });
      this.emit();
      return false;
    }
    if (this.guessFor(place)) {
      this.message = () => t('msg.already', { name: place.name });
      this.emit();
      return false;
    }
    const cls = this.chainClass(place);
    const g = { place, distance: cls, order: this.guesses.length };
    this.lastImproved = cls === CHAIN.onPath;
    this.guesses.push(g);
    this.lastGuess = g;
    this.message = null;
    const path = shortestPath(this.places, this.chainStart, this.chainEnd, new Set(this.guesses.map((x) => x.place.id)));
    if (path) {
      this.chainPath = path;
      this.status = 'won';
      this.finishChain();
    } else if (this.guesses.length >= this.chainLimit) {
      this.status = 'lost';
      this.finishChain();
    }
    this.emit();
    return true;
  }

  finishChain() {
    const before = totalXP(Stats.load);
    const badgesBefore = earnedBadgeIds(Stats.load);
    ChainStats.record(this.category, { won: this.status === 'won', guesses: this.guesses.length, optimal: this.chainOptimal });
    this.rewardAndBadges(before, badgesBefore);
  }

  // MARK: Harita boyaması (map.js bunları kullanır; Swift: GameModel.mapMark)

  /** { kind: 'plain'|'heat'|'found'|'reveal'|'chainEnd'|'chain'|'chainHint', value } */
  mapMark(place) {
    const has = (list) => list.some((p) => p.id === place.id);
    if (this.mode === 'chain') {
      if (this.isChainEnd(place)) return { kind: 'chainEnd' };
      const g = this.guessFor(place);
      if (g) return { kind: 'chain', value: g.distance };
      if (this.status === 'lost' && has(this.chainShortest)) return { kind: 'chainHint' };
      return { kind: 'plain' };
    }
    if (this.mode === 'timed') {
      if (has(this.timedFound)) return { kind: 'found' };
      if (has(this.timedSkipped)) return { kind: 'reveal' };
    }
    if (place.id === this.answer.id && this.mapRevealsAnswer) {
      if (this.status === 'won') return { kind: 'found' };
      if (this.status === 'lost') return { kind: 'reveal' };
    }
    const g = this.mapGuessFor(place);
    return g ? { kind: 'heat', value: g.distance } : { kind: 'plain' };
  }

  mapShowsLabel(place) {
    const has = (list) => list.some((p) => p.id === place.id);
    if (this.mode === 'chain') {
      return this.isChainEnd(place) || !!this.guessFor(place) || (this.status === 'lost' && has(this.chainShortest));
    }
    if (this.mode === 'timed' && (has(this.timedFound) || has(this.timedSkipped))) return true;
    return (this.showsGuessNames && !!this.mapGuessFor(place)) || (this.mapRevealsAnswer && place.id === this.answer.id);
  }

  mapLabelRank(place) {
    if (this.mode === 'chain') return this.isChainEnd(place) ? -1 : this.guessFor(place)?.order ?? 1000;
    return place.id === this.answer.id ? -1 : this.mapGuessFor(place)?.distance ?? 1e9;
  }

  mapHoverText(place) {
    const has = (list) => list.some((p) => p.id === place.id);
    const name = flaggedName(place);
    if (this.mode === 'chain') {
      if (this.isChainEnd(place)) return name;
      const g = this.guessFor(place);
      if (g) return `${name} · ${t(`chain.class.${g.distance}`)}`;
      return this.status === 'lost' && has(this.chainShortest) ? name : null;
    }
    if (this.mode === 'timed') {
      if (has(this.timedFound)) return `${name} ✓`;
      if (has(this.timedSkipped)) return name;
    }
    // Uzman modunda oyun sürerken adlar ve mesafeler gizli.
    if (!this.showsGuessNames) return null;
    const g = this.mapGuessFor(place);
    if (g) {
      if (place.id === this.answer.id) return `${name} ✓`;
      if (g.distance === 0) return `${name} · ${t('neighbor')}`;
      return this.showsKm ? `${name} · ${formatKm(g.distance)}` : name;
    }
    return this.mapRevealsAnswer ? name : null;
  }

  /** Ses için tahminin yakınlığı 0…1. */
  feedbackProximity(g) {
    if (this.mode === 'chain') return [1, 0.6, 0.2][g.distance];
    return 1 - Math.min(1, Math.max(0, Math.sqrt(g.distance / Math.max(this.places.maxDistance, 1))));
  }

  get shareText() {
    if (this.mode === 'timed') {
      const squares = '🟩'.repeat(this.timedFound.length) + '⏭️'.repeat(this.timedSkipped.length);
      return `Atlas · ${this.places.category.title} · ${t('mode.timed')}\n${t('share.timed', { n: this.timedFound.length })}\n${squares}`;
    }
    if (this.mode === 'chain') {
      const squares = this.guesses.map((g) => ['🟩', '🟨', '⬜️'][g.distance]).join('');
      const result = this.status === 'won' ? t('share.chainWon', { n: this.guesses.length, m: this.chainOptimal }) : t('share.chainLost');
      return `Atlas · ${this.places.category.title} · ${t('mode.chain')}\n${this.chainStart.name} → ${this.chainEnd.name}\n${result}\n${squares}`;
    }
    return this.classicShareText;
  }

  get classicShareText() {
    const c = this.places.category;
    const title = this.mode === 'daily' ? `Atlas #${this.puzzleNumber} · ${c.title}` : `Atlas · ${c.title} (${t('share.practice')})`;
    const scale = this.places.maxDistance;
    const squares = this.guesses.map((g) => {
      if (g.place.id === this.answer.id) return '🟩';
      const t = g.distance / scale;
      if (t === 0) return '🟥';
      if (t < 0.1) return '🟧';
      if (t < 0.3) return '🟨';
      return '⬜️';
    }).join('');
    let result = this.status === 'won' ? t('share.won', { n: this.guesses.length }) : t('share.lost');
    if (this.hintsUsed) result += ` · ${t('share.hints', { n: this.hintsUsed })}`;
    if (this.expert) result += ` · ${t('share.expert')}`;
    return `${title}\n${result}\n${squares}`;
  }
}
