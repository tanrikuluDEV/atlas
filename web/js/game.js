// Oyun durumu ve istatistikler. Mac/iPhone uygulamasındaki GameModel.swift ve Stats.swift'in karşılığı.
import { answerIndex, dayIndex } from './daily.js';
import { categoryIndex, hintsFor, placeSet } from './places.js';
import { t } from './i18n.js';
import { store } from './store.js';
import { progress, totalXP } from './progression.js';

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

  recordDaily(won, guesses, hints, answerID, day) {
    if (this.lastPlayedDay === day) return;
    this.lastPlayedDay = day;
    this.played += 1;
    this.history.push({ date: Date.now(), guesses, won, answerID, hints });
    if (won) {
      this.won += 1;
      this.currentStreak = this.lastWonDay === day - 1 ? this.currentStreak + 1 : 1;
      this.maxStreak = Math.max(this.maxStreak, this.currentStreak);
      this.lastWonDay = day;
    } else {
      this.currentStreak = 0;
    }
  }

  recordPractice(won, guesses, hints, answerID) {
    this.played += 1;
    this.history.push({ date: Date.now(), guesses, won, answerID, hints });
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
    if (this.guessFor(place)) {
      this.message = () => t('msg.already', { name: place.name });
      this.emit();
      return false;
    }
    const g = { place, distance: this.places.distance(place, this.answer), order: this.guesses.length };
    this.guesses.push(g);
    this.lastGuess = g;
    this.message = null;
    if (place.id === this.answer.id) {
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
    this.status = 'lost';
    this.message = null;
    this.finish();
    this.persistDaily();
    this.emit();
  }

  switchMode(mode) {
    if (mode === this.mode) return;
    this.mode = mode;
    if (mode === 'daily') this.startDaily();
    else this.newPractice(false);
    this.emit();
  }

  switchCategory(id) {
    if (id === this.category) return;
    this.category = id;
    this.places = placeSet(id);
    store.set('atlas.category', id);
    this.loadStats();
    if (this.mode === 'daily') this.startDaily();
    else this.newPractice(false);
    this.emit();
  }

  newPractice(emit = true) {
    this.mode = 'practice';
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

  setHighlighted(place) {
    this.highlighted = place;
    this.emit();
  }

  // İç işler
  startDaily() {
    this.day = dayIndex();
    const byId = this.places.placesById;
    this.answer = byId[answerIndex(this.day, categoryIndex(this.category), byId.length)];
    this.restoreDaily();
  }

  resetRound() {
    this.guesses = [];
    this.status = 'playing';
    this.message = null;
    this.lastGuess = null;
    this.highlighted = null;
    this.hintsUsed = 0;
    this.reward = null;
    this.showResult = false;
    this.roundID += 1;
  }

  loadStats() {
    this.dailyStats = Stats.load(this.category, 'daily');
    this.practiceStats = Stats.load(this.category, 'practice');
  }

  finish() {
    const won = this.status === 'won';
    const before = totalXP(Stats.load);
    if (this.mode === 'daily') {
      this.dailyStats.recordDaily(won, this.guesses.length, this.hintsUsed, this.answer.id, this.day);
      this.dailyStats.save(this.category, 'daily');
    } else {
      this.practiceStats.recordPractice(won, this.guesses.length, this.hintsUsed, this.answer.id);
      this.practiceStats.save(this.category, 'practice');
    }
    // Bu oyunun kazandırdığı puan; sonuç penceresinde canlandırılır.
    this.reward = { before: progress(before), after: progress(totalXP(Stats.load)) };
    this.showResult = true;
  }

  get dailyKey() { return `atlas.daily.${this.category}.${this.day}`; }

  persistDaily() {
    if (this.mode !== 'daily') return;
    store.set(this.dailyKey, { guessIDs: this.guesses.map((g) => g.place.id), status: this.status, hints: this.hintsUsed });
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
  }

  get shareText() {
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
    return `${title}\n${result}\n${squares}`;
  }
}
