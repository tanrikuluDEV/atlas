// Arayüz: panel, arama, tahmin listesi, pencereler. Harita map.js'te, oyun mantığı game.js'te.
import { CATEGORIES, categoryById, loadData, placeSet } from './places.js';
import { LANGUAGES, detectLanguage, languageInfo, nativeName, formatKm, formatNumber, language, loadStrings, locale, onLanguageChange, setLanguage, t } from './i18n.js';
import { Game, Stats, TIMED_DURATION, isClassic, store } from './game.js';
import { ChainStats, TimedStats, supportsChain } from './modes.js';
import { MapView, drawCategoryThumb, drawDiscoveryMap } from './map.js';
import { dayIndex } from './daily.js';
import { confetti } from './confetti.js';
import { VERSION } from './version.js';
import { levelCardHTML, playLevelCard, splashStarted } from './brand.js';
import { progress, totalXP } from './progression.js';
import { COLORS, applyTheme, heatColor, isDark, onThemeChange, setThemePreference, themePreference } from './colors.js';
import { allBadges } from './badges.js';
import * as feedback from './feedback.js';
import { flagHTML, flaggedName } from './flags.js';
import * as board from './board.js';

const $ = (id) => document.getElementById(id);
const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const fmt1 = (v) => formatNumber(v, { minimumFractionDigits: 1, maximumFractionDigits: 1 });
/** **kalın** işaretlerini HTML'e çevirir (çeviri metinleri Mac/iPhone'la ortak, orada Markdown). */
const bold = (s) => esc(s).replace(/\*\*(.+?)\*\*/g, '<b>$1</b>');
const isPhone = () => window.matchMedia('(max-width: 760px)').matches;

let game;
let map;
let last = { roundID: -1, lastGuess: null, highlighted: null, category: null, showResult: false, status: null, replayStep: null };

/** Tahminin yakınlığı 0…1 (1 = komşu); renk skalasıyla aynı karekök ölçeği. */
const proximity = (g, max) => 1 - Math.min(1, Math.max(0, Math.sqrt(g.distance / Math.max(max, 1))));
const heatLevel = (p) => (p >= 1 ? 5 : p > 0.8 ? 4 : p > 0.6 ? 3 : p > 0.35 ? 2 : 1);

/** Bir sonraki günlük bulmacaya (yerel gece yarısı) kalan süre, "05:12:33". */
function countdownText() {
  const now = new Date();
  const next = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1);
  const s = Math.max(0, Math.floor((next - now) / 1000));
  const pad = (n) => String(n).padStart(2, '0');
  return t('countdown', { time: `${pad(Math.floor(s / 3600))}:${pad(Math.floor(s / 60) % 60)}:${pad(s % 60)}` });
}
const countdownHTML = () => `<p class="countdown muted">🕒 <span>${esc(countdownText())}</span></p>`;
setInterval(() => document.querySelectorAll('.countdown span').forEach((el) => { el.textContent = countdownText(); }), 1000);

function badgeHTML(b) {
  const pct = b.earned ? 100 : Math.round((b.current / b.target) * 100);
  const sub = b.earned || b.target === 1 ? b.detail : `${b.current}/${b.target}`;
  return `<div class="badge-item ${b.earned ? 'earned' : ''}" title="${esc(b.detail)}">
    <span class="badge-icon" style="--p:${pct}%">${b.icon}</span>
    <b>${esc(b.name)}</b>
    <span>${esc(sub)}</span>
  </div>`;
}

const splash = splashStarted();

async function start() {
  await Promise.all([loadData(), loadStrings().then(detectLanguage)]);
  $('loading').remove();

  game = new Game(render);
  // Geliştirme: yerel sunucuda (tools/cdp.mjs testleri) oyun nesnesine konsoldan erişilebilsin.
  if (location.hostname === '127.0.0.1') window.atlasGame = game;
  game.showDistance = store.get('atlas.showDistance', true);
  map = new MapView($('map'), game);
  onThemeChange(() => { map.draw(); render(); });
  onLanguageChange(() => {
    applyStaticTexts();
    map.updateLegend();
    last.category = null; // yer tutucu metni de yenilensin
    render();
    renderSuggestions();
  });

  applyStaticTexts();
  setupToolbar();
  setupGuessInput();
  render();

  // İlk açılışta yardım, açılış animasyonu bitince gelir.
  await splash.done();
  // Davet bağlantısıyla gelindiyse gruba katılma penceresi (yardımdan önce).
  const invite = board.takeInviteFromURL();
  if (invite && invite !== board.group()?.id) openJoin(invite);
  else if (!store.get('atlas.helpSeen', false)) {
    store.set('atlas.helpSeen', true);
    openHelp();
  }
  board.syncResults();
  // Gün değişince günlük bulmacayı yenile.
  setInterval(() => game.refreshDayIfNeeded(), 60_000);
  document.addEventListener('visibilitychange', () => { if (!document.hidden) game.refreshDayIfNeeded(); });
}

// MARK: - Araç çubuğu

function setupToolbar() {
  $('categoryButton').addEventListener('click', () => openCategoryPicker());
  const langSelect = $('languageSelect');
  langSelect.innerHTML = LANGUAGES.map((l) => `<option value="${l.id}">${l.flag} ${esc(nativeName(l.id))}</option>`).join('');
  langSelect.addEventListener('change', () => setLanguage(langSelect.value));
  $('modeSegmented').addEventListener('click', (e) => {
    const mode = e.target.closest('button')?.dataset.mode;
    if (mode) game.switchMode(mode);
  });
  $('newGameButton').addEventListener('click', () => game.newRound());
  $('statsButton').addEventListener('click', () => openStats());
  $('boardButton').addEventListener('click', () => openBoard());
  $('settingsButton').addEventListener('click', () => openSettings());
  $('themeButton').addEventListener('click', () => setThemePreference(isDark() ? 'light' : 'dark'));
  applyTheme();
  $('helpButton').addEventListener('click', () => openHelp());
  $('giveUpButton').addEventListener('click', () => game.giveUp());
  $('skipButton').addEventListener('click', () => { game.skipTimed(); $('guessInput').focus(); });

  // Oyun bittiyse Enter yeni oyunu başlatır (düğmeler kendi Enter'ını işler).
  document.addEventListener('keydown', (e) => {
    if (e.key !== 'Enter' || !game.isOver || document.querySelector('dialog[open]')) return;
    if (e.target.closest?.('button, select, input, a')) return;
    e.preventDefault();
    game.newRound();
  });
  // Sekmeye ya da pencereye geri dönülünce tahmin kutusu yeniden seçilsin.
  window.addEventListener('focus', restoreFocus);

  // Mac uygulamasındaki kısayollar
  document.addEventListener('keydown', (e) => {
    if (!(e.metaKey || e.ctrlKey) || e.altKey) return;
    if (e.key === 'n' || e.key === 'N') { e.preventDefault(); closeDialogs(); game.newRound(); }
    else if (e.key === 'd') { e.preventDefault(); game.switchMode('daily'); }
    else if (e.key === 'i') { e.preventDefault(); openStats(); }
    else if (/^[1-8]$/.test(e.key)) { e.preventDefault(); game.switchCategory(CATEGORIES[Number(e.key) - 1].id); }
  });
}

/** index.html'deki sabit metinler ve araç çubuğu seçicileri seçili dile göre yazılır. */
function applyStaticTexts() {
  const set = (id, text, attrs = ['title', 'aria-label']) => {
    const el = $(id);
    for (const a of attrs) if (a === 'text') el.textContent = text; else el.setAttribute(a, text);
  };
  set('categoryButton', t('category'));
  set('languageLabel', t('language'), ['title']);
  set('languageSelect', t('language'), ['aria-label']);
  set('modeSegmented', t('mode'), ['aria-label']);
  document.querySelectorAll('#modeSegmented button').forEach((b) => { b.textContent = t(`mode.${b.dataset.mode}`); });
  set('newGameButton', t('newPractice'), ['title']);
  set('newGameButton', t('newGame'), ['aria-label']);
  set('themeButton', t('theme.toggle'));
  set('statsButton', t('stats'));
  set('boardButton', t('board.title'));
  set('settingsButton', t('settings'));
  set('helpButton', t('help'));
  set('mapCanvas', t('map'), ['aria-label']);
  set('mapLegend', t('map.legend'), ['aria-label']);
  document.querySelector('[data-zoom="in"]').setAttribute('aria-label', t('map.zoomIn'));
  document.querySelector('[data-zoom="out"]').setAttribute('aria-label', t('map.zoomOut'));
  const reset = document.querySelector('[data-zoom="reset"]');
  reset.setAttribute('aria-label', t('map.reset'));
  reset.title = t('map.reset');
  set('guessButton', t('guess'), ['text']);
  set('giveUpButton', t('giveUp'), ['text']);
  set('skipButton', t('timed.skip'), ['text']);
  $('languageSelect').value = language();
  $('languageFlag').textContent = languageInfo().flag;
  document.querySelector('meta[name="description"]')?.setAttribute('content', `Atlas · ${t('app.tagline')}`);
}

// MARK: - Tahmin girişi

let suggestionItems = [];
let activeSuggestion = 0;

function setupGuessInput() {
  const input = $('guessInput');
  const list = $('suggestions');

  input.addEventListener('input', () => { activeSuggestion = 0; renderSuggestions(); });
  input.addEventListener('keydown', (e) => {
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      if (!suggestionItems.length) return;
      e.preventDefault();
      const d = e.key === 'ArrowDown' ? 1 : -1;
      activeSuggestion = (activeSuggestion + d + suggestionItems.length) % suggestionItems.length;
      renderSuggestions();
    } else if (e.key === 'Escape') {
      input.value = '';
      renderSuggestions();
    }
  });
  $('guessForm').addEventListener('submit', (e) => {
    e.preventDefault();
    const text = input.value;
    const exact = game.places.match(text);
    if (exact) guess(exact);
    else if (suggestionItems[activeSuggestion]) guess(suggestionItems[activeSuggestion]);
    else if (text.trim()) game.submitText(text);
  });
  // Dokunmada klavye kapanmasın diye pointerdown'da seçilir.
  list.addEventListener('pointerdown', (e) => {
    const li = e.target.closest('li');
    if (!li) return;
    e.preventDefault();
    guess(game.places.place(Number(li.dataset.id)));
  });
  list.addEventListener('pointermove', (e) => {
    const li = e.target.closest('li');
    if (li && e.pointerType === 'mouse') {
      const i = Number(li.dataset.index);
      if (i !== activeSuggestion) { activeSuggestion = i; renderSuggestions(); }
    }
  });
}

function guess(place) {
  const input = $('guessInput');
  if (game.submit(place)) {
    input.value = '';
    renderSuggestions();
  }
  input.focus();
}

function renderSuggestions() {
  const input = $('guessInput');
  const list = $('suggestions');
  const text = input.value;
  $('guessButton').disabled = !text.trim();
  suggestionItems = game.places.suggestions(text).filter((p) => !game.guessFor(p));
  const exact = game.places.match(text);
  if (!suggestionItems.length || (suggestionItems.length === 1 && exact?.id === suggestionItems[0].id)) {
    list.hidden = true;
    return;
  }
  const showCode = game.category === 'turkey';
  list.innerHTML = suggestionItems.map((p, i) =>
    `<li role="option" data-id="${p.id}" data-index="${i}" class="${i === activeSuggestion ? 'active' : ''}">
       <span>${flagHTML(p)}${esc(p.name)}</span>${showCode ? `<span class="code">${p.code}</span>` : ''}
     </li>`).join('');
  list.hidden = false;
}

function focusInput() {
  const input = $('guessInput');
  // Telefonda kendiliğinden klavye açmak haritayı kapatır; yalnızca masaüstünde odaklan.
  if (isPhone()) return;
  setTimeout(() => {
    if (!input.closest('[hidden]') && !document.querySelector('dialog[open]')) input.focus({ preventScroll: true });
  }, 50);
}

// MARK: - Çizim

function render() {
  if (!map) return;
  const c = game.places.category;

  if (last.category !== game.category) {
    map.setPlaces(game.places);
    $('guessInput').placeholder = t(`placeholder.${c.kind}`);
  }
  if (last.mode !== game.mode) map.updateLegend();
  if (last.roundID !== game.roundID) {
    $('guessInput').value = '';
    renderSuggestions();
    // Bitmiş bir oyuna dönülünce (ör. çözülmüş günlük bulmaca) gizli yer odakta kalsın; zincirde iki uç görünsün.
    if (game.mode === 'chain' && game.chainStart) setTimeout(() => map.focusMany([game.chainStart, game.chainEnd]), last.category === game.category ? 0 : 60);
    else if (game.isOver) map.focus(game.answer);
    else if (last.category === game.category) map.reset();
    focusInput();
  }
  // Zamana karşı: bulunan yer yeşil nabızla parlar.
  if (game.timedFound.length > (last.timedFound ?? 0) && game.mode === 'timed') {
    map.celebrate(game.timedFound[game.timedFound.length - 1]);
    feedback.won();
  }
  if (game.mode === 'chain' && game.lastGuess && game.lastGuess !== last.lastGuess) {
    // Zincirde kamera iki ucu göstermeye devam eder; rota tamamlanınca yeşil nabız.
    if (game.status === 'won') { game.chainPath.forEach((p) => map.celebrate(p)); feedback.won(); confetti(); }
    else feedback.guessMade(game.feedbackProximity(game.lastGuess), game.lastImproved), map.pulse(game.lastGuess.place);
  } else if (game.lastGuess && game.lastGuess !== last.lastGuess) {
    if (game.status === 'won') feedback.won();
    else feedback.guessMade(proximity(game.lastGuess, game.places.maxDistance), game.lastImproved && game.guesses.length > 1);
    // Uzman modunda kamera tahmine uçmaz (yerini bilmek oyunun parçası); yalnızca parlar.
    if (!game.expert || game.status === 'won') map.focus(game.lastGuess.place);
    if (game.status === 'won') {
      // Bulunca: yeşil nabız ve konfeti.
      map.celebrate(game.answer);
      confetti();
    } else {
      map.pulse(game.lastGuess.place);
    }
  }
  if (game.highlighted && game.highlighted !== last.highlighted) map.focus(game.highlighted);
  // Pes edilince gizli yer de gösterilsin.
  if (game.status === 'lost' && last.status === 'playing' && last.roundID === game.roundID) {
    if (game.mode === 'chain') map.focusMany([game.chainStart, game.chainEnd, ...game.chainShortest]);
    else map.focus(game.answer);
    feedback.lost();
  }
  // Rota tekrarı: önce tüm harita, sonra her tahmine sırayla uçup parlar; sonunda gizli yer.
  if (game.replayStep !== last.replayStep && last.roundID === game.roundID) {
    const step = game.replayStep;
    if (step == null) { if (game.isOver) map.focus(game.answer); }
    else if (step === 0) map.reset();
    else {
      const place = game.replayPlace(step);
      map.focus(place);
      if (step === game.replayLength && place.id === game.answer.id && game.status === 'won') map.celebrate(place);
      else map.pulse(place);
    }
  }
  if (game.showResult && !last.showResult) setTimeout(openResult, 450);
  // Günlük bulmaca bitince sonuç arkadaş grubuna gider.
  if (game.mode === 'daily' && game.isOver && last.status === 'playing' && last.roundID === game.roundID) board.syncResults();

  last = { roundID: game.roundID, lastGuess: game.lastGuess, highlighted: game.highlighted, category: game.category, showResult: game.showResult, status: game.status, replayStep: game.replayStep, expert: last.expert, mode: game.mode, timedFound: game.timedFound.length };

  // Araç çubuğu
  $('categoryName').textContent = c.title;
  $('categoryIcon').textContent = c.icon;
  document.querySelectorAll('#modeSegmented button').forEach((b) => b.setAttribute('aria-selected', b.dataset.mode === game.mode));
  $('newGameButton').hidden = game.mode === 'daily';
  document.title = game.mode === 'daily' ? `Atlas #${game.puzzleNumber} · ${c.title}` : `Atlas · ${c.title}`;

  // Başlık
  $('panelCategory').textContent = isPhone() && isClassic(game.mode) ? `${c.icon} ${game.places.subtitle()}` : `${c.icon} ${c.title}`;
  $('panelTitle').innerHTML = esc(panelTitle())
    + (game.expert ? ` <span class="expert-tag" title="${esc(t('set.expertHint'))}">🙈 ${esc(t('expert.tag'))}</span>` : '');
  // Lejant uzman moduna göre (km ya da yakın/uzak).
  if (last.expert !== game.expert) { last.expert = game.expert; map.updateLegend(); }
  $('panelSubtitle').textContent = isClassic(game.mode) ? game.places.subtitle() : '';
  $('panelSubtitle').hidden = !isClassic(game.mode);

  // Oyun sonu / giriş
  const chainBlocked = game.mode === 'chain' && !game.chainAvailable;
  $('guessForm').hidden = game.isOver || chainBlocked;
  renderModeBox();
  const over = $('gameOver');
  over.hidden = !game.isOver;
  if (game.isOver && !isClassic(game.mode)) {
    over.innerHTML = game.mode === 'timed' ? timedOverHTML() : chainOverHTML();
    over.querySelector('[data-action="result"]').onclick = openResult;
    over.querySelector('[data-action="new"]').onclick = () => game.newRound();
  } else if (game.isOver) {
    const won = game.status === 'won';
    over.innerHTML = `
      <div class="status ${won ? 'won' : 'lost'}">${won ? `✓ ${t('over.won')}` : t(`over.hidden.${c.kind}`)}</div>
      <div class="answer">${flagHTML(game.answer)}${esc(game.answer.name)}</div>
      <div class="actions">
        <button class="button" data-action="result">${t('result')}</button>
        <button class="button primary" data-action="new" title="Enter">${t('newGame')}</button>
      </div>
      <button class="link replay-button" data-action="replay">${game.replayStep == null ? `▶ ${t('replay.button')}` : `■ ${t('replay.stop')}`}</button>
      ${game.mode === 'daily' ? `<button class="link board-link" data-action="board">🏆 ${t(board.group() ? 'board.title' : 'board.invitePrompt')}</button><hr>${countdownHTML()}${otherDailiesHTML()}` : ''}`;
    over.querySelector('[data-action="board"]')?.addEventListener('click', () => openBoard());
    over.querySelector('[data-action="result"]').onclick = openResult;
    over.querySelector('[data-action="replay"]').onclick = () => (game.replayStep == null ? game.startReplay() : game.stopReplay());
    over.querySelectorAll('[data-category]').forEach((b) => { b.onclick = () => game.switchCategory(b.dataset.category); });
    over.querySelector('[data-action="new"]').onclick = () => game.newPractice();
  }

  // Geri bildirim
  const fb = $('feedback');
  if (game.message) fb.textContent = game.message;
  else if (game.lastGuess && !game.isOver) fb.textContent = feedbackText(game.lastGuess);
  else fb.textContent = '';

  renderHeat();

  const closest = game.closest;
  const closestEl = $('closest');
  closestEl.hidden = !closest || game.isOver || game.mode === 'chain';
  if (closest && !game.isOver) {
    closestEl.innerHTML = `<span class="muted">${t('closest')}</span><strong>${esc(distanceLabel(closest, true))}</strong>`;
  }

  renderHints();
  renderGuesses();
  $('guessCount').textContent = game.mode === 'timed' ? t('timed.score', { n: game.timedFound.length }) : t('guesses', { n: game.guesses.length });
  const started = game.mode === 'timed' ? !!game.timedStart : game.guesses.length > 0;
  $('giveUpButton').hidden = game.isOver || !started;
  $('giveUpButton').textContent = t(game.mode === 'timed' ? 'timed.finish' : 'giveUp');
  $('skipButton').hidden = game.mode !== 'timed' || game.isOver || !game.timedStart;
  map.draw();
}

function panelTitle() {
  const c = game.places.category;
  return { daily: t(`panel.daily.${c.kind}`), practice: t('mode.practice'), timed: t('timed.title'), chain: t('chain.title') }[game.mode];
}

const routeText = (path) => path.map((p) => esc(p.name)).join(' → ');
const timedClock = (ms) => { const s = Math.ceil(ms / 1000); return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`; };

/** Süreli: sayaç ya da "Başla" kartı. Zincir: başlangıç → bitiş kartı ya da kategori uyarısı. */
function renderModeBox() {
  const box = $('modeBox');
  const c = game.places.category;
  let html = '';
  if (game.mode === 'timed' && !game.isOver) {
    html = game.timedStart
      ? `<div class="timed-bar"><div><b class="timed-clock">${timedClock(game.timedRemaining())}</b><span>${esc(t('timed.remaining'))}</span></div>
          <div class="right"><b class="timed-score">${game.timedFound.length}</b><span>${esc(t('timed.foundLabel'))}</span></div>
          <i class="timed-progress" style="width:${(game.timedRemaining() / TIMED_DURATION) * 100}%"></i></div>`
      : `<div class="timed-start"><b>⏱️ ${esc(t('timed.title'))}</b><p>${esc(t(`timed.intro.${c.kind}`))}</p>
          <p class="muted">${esc(t('timed.skipHint'))}</p><button class="button primary" data-action="start">▶ ${esc(t('timed.start'))}</button></div>`;
  } else if (game.mode === 'chain' && !game.chainAvailable) {
    html = `<div class="chain-card"><b>🔗 ${esc(t('chain.title'))}</b><p>${esc(t('chain.unavailable'))}</p>
      <div class="chips">${CATEGORIES.filter((x) => supportsChain(placeSet(x.id))).map((x) => `<button class="chip" data-category="${x.id}">${x.icon} ${esc(x.title)}</button>`).join('')}</div></div>`;
  } else if (game.mode === 'chain' && game.chainStart) {
    const s = game.chainStart, e = game.chainEnd;
    html = `<div class="chain-card"><div class="chain-ends">${flagHTML(s)}${esc(s.name)} <span class="muted">→</span> ${flagHTML(e)}${esc(e.name)}</div>
      ${game.isOver ? '' : `<p class="muted">${esc(t(`chain.intro.${c.kind}`, { a: s.name, b: e.name }))}</p>
      <div class="chain-left"><b class="${game.chainGuessesLeft <= 2 ? 'danger-text' : ''}">${esc(t('chain.left', { n: game.chainGuessesLeft }))}</b><span class="muted">${esc(t('chain.optimal', { n: game.chainOptimal }))}</span></div>`}</div>`;
  }
  box.hidden = !html;
  // Sayaç her saniye kendi güncellenir; kutuyu yalnızca içerik türü değişince yeniden yaz.
  const key = `${game.mode}|${game.roundID}|${game.isOver}|${!!game.timedStart}|${game.timedFound.length}|${game.guesses.length}|${language()}|${game.category}`;
  if (box.dataset.key === key) return;
  box.dataset.key = key;
  box.innerHTML = html;
  box.querySelector('[data-action="start"]')?.addEventListener('click', () => { game.startTimer(); $('guessInput').focus(); });
  box.querySelectorAll('[data-category]').forEach((b) => { b.onclick = () => game.switchCategory(b.dataset.category); });
}

setInterval(() => {
  if (!game || game.mode !== 'timed' || !game.timedStart || game.isOver) return;
  const ms = game.timedRemaining();
  const clock = document.querySelector('.timed-clock');
  if (clock) { clock.textContent = timedClock(ms); clock.classList.toggle('danger-text', ms <= 20_000); }
  const bar = document.querySelector('.timed-progress');
  if (bar) bar.style.width = `${(ms / TIMED_DURATION) * 100}%`;
}, 250);

function timedOverHTML() {
  const r = game.timedResult;
  return `<div class="status" style="color:var(--accent)">⏱️ ${esc(t('timed.over'))}</div>
    <div class="answer">${esc(t(`timed.result.${game.places.category.kind}`, { n: game.timedFound.length }))}</div>
    ${r ? `<p class="${r.isRecord ? 'record' : 'muted'}">${esc(r.isRecord ? t('timed.record') : t('timed.best', { n: r.best }))}</p>` : ''}
    <p class="muted">${esc(t('timed.lastHidden', { name: game.answer.name }))}</p>
    ${foundChipsHTML()}
    <div class="actions"><button class="button" data-action="result">${t('result')}</button>
      <button class="button primary" data-action="new" title="Enter">${t('newGame')}</button></div>`;
}

function chainOverHTML() {
  const won = game.status === 'won';
  return `<div class="status ${won ? 'won' : 'lost'}">${won ? `✓ ${esc(t('chain.won'))}` : esc(t('chain.lost'))}</div>
    ${won ? `<p>${esc(t(game.guesses.length === game.chainOptimal ? 'chain.perfect' : 'chain.foundIn', { n: game.guesses.length, m: game.chainOptimal }))}</p>` : ''}
    <h2>${esc(t(won ? 'chain.yourRoute' : 'chain.shortest'))}</h2>
    <p class="route">${routeText(won ? game.chainPath : game.chainShortest)}</p>
    <div class="actions"><button class="button" data-action="result">${t('result')}</button>
      <button class="button primary" data-action="new" title="Enter">${t('newGame')}</button></div>`;
}

/** Süreli turda bulunan ve pas geçilen yerler. */
function foundChipsHTML() {
  if (!game.timedFound.length && !game.timedSkipped.length) return '';
  const chip = (p, found) => `<span class="chip ${found ? 'found' : 'skipped'}">${flagHTML(p)}${esc(p.name)} ${found ? '✓' : '⏭'}</span>`;
  return `<div class="found-chips"><h2>${esc(t('timed.foundList'))}</h2><div class="chips">${game.timedFound.map((p) => chip(p, true)).join('')}${game.timedSkipped.map((p) => chip(p, false)).join('')}</div></div>`;
}

function distanceLabel(g, withName) {
  const name = withName ? `${g.place.name}` : '';
  // Kilometre kapalıyken de komşuluk gösterilir; yalnızca km değeri gizlenir.
  const d = game.expert ? '' : g.distance === 0 ? t('neighbor') : game.showDistance ? formatKm(g.distance) : '';
  if (!d) return name;
  return withName ? `${name} · ${d}` : d;
}

function feedbackText(g) {
  const kind = game.places.category.kind;
  if (game.mode === 'chain') return t(`chain.feedback.${g.distance}`, { name: g.place.name });
  if (game.expert) return t('feedback.colored', { name: g.place.name });
  if (g.distance === 0) return t(`feedback.neighbor.${kind}`, { name: g.place.name });
  if (!game.showDistance) return t('feedback.colored', { name: g.place.name });
  return t(`feedback.distance.${kind}`, { name: g.place.name, km: formatKm(g.distance) });
}

/** Açılan ipuçları ve "İpucu al" düğmesi; oyun bitince üç ipucu da "Bu yer hakkında" olarak görünür. */
function renderHints() {
  const el = $('hints');
  const hints = isClassic(game.mode) ? game.hints : [];
  const shown = game.isOver ? hints : hints.slice(0, game.hintsUsed);
  const canAsk = !game.isOver && game.hintsUsed < hints.length;
  el.hidden = !hints.length;
  if (!hints.length) return;
  el.innerHTML = (shown.length ? `<h2>${t(game.isOver ? 'hints.about' : 'hints.header')}</h2>
      <ol>${shown.map((h) => `<li>${esc(h)}</li>`).join('')}</ol>` : '')
    + (canAsk ? `<button class="link hint-button" id="hintButton">💡 ${esc(t('hint.take', { n: hints.length - game.hintsUsed }))}</button>` : '');
  const b = $('hintButton');
  if (b) b.onclick = () => game.useHint();
}

/** Bugünün bitmemiş diğer günlük bulmacalarına kısayollar. */
function otherDailiesHTML() {
  const day = dayIndex();
  const others = CATEGORIES.filter((c) => c.id !== game.category && !['won', 'lost'].includes(store.get(`atlas.daily.${c.id}.${day}`)?.status));
  if (!others.length) return `<p class="other-dailies-done">${esc(t('countdown.allDone'))}</p>`;
  return `<div class="other-dailies"><h2>${esc(t('countdown.others'))}</h2>
    <div class="chips">${others.map((c) => `<button class="chip" data-category="${c.id}">${c.icon} ${esc(c.title)}</button>`).join('')}</div></div>`;
}

/** Son tahminin ne kadar yakın olduğu: buzdan ateşe bir çubuk. Öncekinden yakınsa hafifçe titrer. */
let lastHeatGuess = null;
let lastHeatP = null;
function renderHeat() {
  const el = $('heat');
  const g = game.lastGuess;
  el.hidden = !g || game.isOver || game.expert || game.mode === 'chain';
  if (el.hidden) { lastHeatGuess = null; return; }
  const max = game.places.maxDistance;
  const p = proximity(g, max);
  const best = proximity(game.closest, max);
  const stops = [1, 0.8, 0.6, 0.4, 0.2, 0].map((f) => heatColor(Math.round(max * f * f), max));
  const improved = game.lastImproved && game.guesses.length > 1;
  el.innerHTML = `<div class="heat-head"><b>${esc(t(`heat.${heatLevel(p)}`))}</b>${improved ? `<span>${esc(t('heat.closer'))}</span>` : ''}</div>
    <div class="heat-track" style="background:linear-gradient(90deg,#9ecdf2,${stops.join(',')})" role="img" aria-label="${esc(t('heat.label'))}: ${esc(t(`heat.${heatLevel(p)}`))}">
      <i class="heat-best" style="left:calc(${best} * (100% - 2px))"></i>
      <i class="heat-dot" style="left:calc(${lastHeatGuess && lastHeatGuess !== g ? lastHeatP ?? p : p} * (100% - 16px));background:${heatColor(g.distance, max)}"></i>
    </div>`;
  // İşaret eski konumundan yenisine kayar.
  const dot = el.querySelector('.heat-dot');
  requestAnimationFrame(() => { dot.style.left = `calc(${p} * (100% - 16px))`; });
  if (g !== lastHeatGuess && improved && !matchMedia('(prefers-reduced-motion: reduce)').matches) {
    el.classList.remove('shake');
    void el.offsetWidth;
    el.classList.add('shake');
  }
  lastHeatGuess = g;
  lastHeatP = p;
}

let emptyKey = null;
function renderGuesses() {
  const el = $('guesses');
  if (game.mode === 'chain') {
    emptyKey = null;
    const colors = COLORS();
    el.innerHTML = game.isOver || !game.guesses.length ? '' : `<h2>${t('chain.guesses')}</h2>` + game.guesses.map((g) =>
      `<div class="guess"><span class="swatch" style="background:${colors.chain[g.distance]}"></span>
        <span class="name">${flagHTML(g.place)}${esc(g.place.name)}</span><span class="dist">${esc(t(`chain.class.${g.distance}`))}</span></div>`).join('');
    return;
  }
  if (game.mode === 'timed') {
    emptyKey = null;
    if (game.isOver) { el.innerHTML = ''; return; }
    if (!game.guesses.length) { el.innerHTML = foundChipsHTML(); return; }
  }
  if (!game.guesses.length) {
    if (game.isOver) { el.innerHTML = ''; emptyKey = null; return; }
    // Henüz tahmin yokken: kategorinin silüeti, kaç yer arasından seçildiği ve bir oyun taktiği.
    const key = `${game.category}|${game.roundID}|${language()}|${isDark()}`;
    if (key === emptyKey) return;
    emptyKey = key;
    const c = game.places.category;
    el.innerHTML = `<div class="empty-card">
      <canvas class="empty-thumb" aria-hidden="true"></canvas>
      <b>${esc(t(`empty.pool.${c.kind}`, { n: game.places.places.length }))}</b>
      <p class="muted">${esc(t('empty.start'))}</p>
      <p class="tip">💡 ${esc(t(`tip.${(game.roundID % 4) + 1}`))}</p>
    </div>`;
    drawCategoryThumb(el.querySelector('canvas'), game.places);
    return;
  }
  emptyKey = null;
  const max = game.places.maxDistance;
  el.innerHTML = `<h2>${t('guesses.header')}</h2>` + game.sortedGuesses.map((g) => {
    const isAnswer = g.place.id === game.answer.id;
    const selected = game.highlighted?.id === g.place.id;
    const color = isAnswer ? 'var(--found)' : heatColor(g.distance, max);
    // Uzman modunda oyun sürerken yalnızca renk görünür.
    const hide = game.expert && !game.isOver;
    const dist = isAnswer ? t('found') : hide ? '' : g.distance === 0 ? t('Neighbor') : game.showDistance ? formatKm(g.distance) : '';
    return `<button class="guess ${isAnswer ? 'answer' : ''} ${selected ? 'selected' : ''}" data-id="${g.place.id}" title="${t(selected ? 'highlight.remove' : 'highlight.show')}">
      <span class="swatch" style="background:${color}"></span>
      <span class="name">${flagHTML(g.place)}${esc(g.place.name)}</span>
      <span class="dist">${dist}</span>
    </button>`;
  }).join('');
  if (game.mode === 'timed') el.insertAdjacentHTML('beforeend', foundChipsHTML());
  el.querySelectorAll('.guess').forEach((b) => {
    b.onclick = () => {
      if (!game.showsGuessNames) return; // uzman modunda oyun sürerken yer haritada gösterilmez
      const p = game.places.place(Number(b.dataset.id));
      game.setHighlighted(game.highlighted?.id === p.id ? null : p);
    };
  });
}

// MARK: - Kategori seçici

/** Bir kategorinin bugünkü günlük bulmacasının durumu (kartta rozet olarak). */
function dailyStatus(categoryId, day) {
  const saved = store.get(`atlas.daily.${categoryId}.${day}`);
  const n = saved?.guessIDs?.length ?? 0;
  if (saved?.status === 'won') return { cls: 'won', text: `✓ ${t('picker.won', { n })}` };
  if (saved?.status === 'lost') return { cls: 'lost', text: t('picker.lost') };
  if (n) return { cls: 'playing', text: `${t('picker.playing')} · ${n}` };
  return { cls: 'new', text: t('picker.new') };
}

/** Kategoriler kart olarak: küçük harita, yer sayısı ve bugünkü bulmacanın durumu. */
function openCategoryPicker() {
  const day = dayIndex();
  const cards = CATEGORIES.map((c, i) => {
    const st = dailyStatus(c.id, day);
    return `<button class="cat-card${c.id === game.category ? ' selected' : ''}" data-id="${c.id}" title="⌘${i + 1}">
        <canvas class="cat-thumb" aria-hidden="true"></canvas>
        <span class="cat-info">
          <span class="cat-title">${c.icon} ${esc(c.title)}</span>
          <span class="cat-count">${esc(t(`count.${c.kind}`, { n: placeSet(c.id).places.length }))}</span>
          <span class="cat-status ${st.cls}">${esc(st.text)}</span>
        </span>
      </button>`;
  }).join('');
  showDialog('categoryDialog', `
    <div class="picker-head">
      <div><h2>${esc(t('category'))}</h2><p>${esc(t('picker.subtitle'))}</p></div>
      <button class="icon-button" data-close aria-label="${esc(t('close'))}" title="${esc(t('close'))}">
        <svg viewBox="0 0 24 24"><path d="M6 6l12 12M18 6L6 18"/></svg>
      </button>
    </div>
    <div class="picker-grid">${cards}</div>`, (d) => {
    d.querySelectorAll('.cat-card').forEach((b) => {
      b.onclick = () => { d.close(); game.switchCategory(b.dataset.id); };
    });
  });
  // Küçük haritalar pencere açılıp boyut kazanınca çizilir.
  const d = $('categoryDialog');
  d.querySelectorAll('.cat-card').forEach((b) => drawCategoryThumb(b.querySelector('canvas'), placeSet(b.dataset.id)));
  d.querySelector('.cat-card.selected')?.focus();
}

// MARK: - Pencereler

function closeDialogs() {
  document.querySelectorAll('dialog[open]').forEach((d) => d.close());
}

function showDialog(id, html, onReady) {
  const d = $(id);
  d.innerHTML = html;
  onReady?.(d);
  d.querySelectorAll('[data-close]').forEach((b) => (b.onclick = () => d.close()));
  // Arka plana tıklayınca kapansın.
  d.onclick = (e) => { if (e.target === d) d.close(); };
  // Pencere kapanınca klavye odağı oyuna geri dönsün.
  d.onclose = () => setTimeout(restoreFocus, 0);
  if (!d.open) d.showModal();
}

/** Oyun sürüyorsa tahmin kutusuna, bittiyse "Yeni oyun" düğmesine odaklanır. */
function restoreFocus() {
  if (document.querySelector('dialog[open]')) return;
  if (game.isOver) $('gameOver').querySelector('[data-action="new"]')?.focus({ preventScroll: true });
  else focusInput();
}

function summaryHTML(stats, streakLabel = t('stats.streak')) {
  return `<div class="summary">
    <div><b>${stats.played}</b><span>${t('stats.played')}</span></div>
    <div><b>${formatNumber(stats.winRate / 100, { style: 'percent' })}</b><span>${t('stats.winRate')}</span></div>
    <div><b>${stats.currentStreak}</b><span>${streakLabel}</span></div>
    <div><b>${stats.maxStreak}</b><span>${t('stats.maxStreak')}</span></div>
  </div>`;
}

function openResult() {
  if (!game.isOver) return;
  const c = game.places.category;
  const won = game.status === 'won';
  let head;
  if (game.mode === 'timed') {
    const r = game.timedResult;
    head = `<div style="font-size:44px">⏱️</div><h2>${esc(t('timed.over'))}</h2>
      <p><b>${esc(t(`timed.result.${c.kind}`, { n: game.timedFound.length }))}</b><br>
      ${r ? `<span class="${r.isRecord ? 'record' : 'muted'}">${esc(r.isRecord ? t('timed.record') : t('timed.best', { n: r.best }))}</span>` : ''}</p>`;
  } else if (game.mode === 'chain') {
    head = `<div style="font-size:44px">${won ? '🔗' : '🗺️'}</div><h2>${esc(t(won ? 'chain.won' : 'chain.lost'))}</h2>
      ${won ? `<p>${esc(t(game.guesses.length === game.chainOptimal ? 'chain.perfect' : 'chain.foundIn', { n: game.guesses.length, m: game.chainOptimal }))}</p>` : ''}
      <p class="muted" style="margin-bottom:2px">${esc(t(won ? 'chain.yourRoute' : 'chain.shortest'))}</p>
      <p class="route">${routeText(won ? game.chainPath : game.chainShortest)}</p>`;
  } else {
    head = `<div style="font-size:44px">${won ? '🎉' : '🗺️'}</div>
      <h2>${t(won ? 'congrats' : 'nextTime')}</h2>
      <p>${won
        ? `${bold(t(`result.won.${c.kind}`, { name: `**${flaggedName(game.answer)}**` }))}<br>${bold(t('result.foundIn', { n: game.guesses.length }))}`
        : bold(t(`result.lost.${c.kind}`, { name: `**${flaggedName(game.answer)}**` }))}</p>`;
  }
  showDialog('resultDialog', `
    <div class="center">
      ${head}
      ${game.reward ? levelCardHTML(game.reward.after, game.reward) : ''}
      ${game.newBadges?.length ? `<div class="new-badges"><div class="new-badges-title">${esc(t('badges.new'))}</div>
        <div class="badge-row">${game.newBadges.slice(0, 4).map(badgeHTML).join('')}</div></div>` : ''}
      ${isClassic(game.mode) ? summaryHTML(game.currentStats) : ''}
      ${game.mode === 'daily' ? countdownHTML() : ''}
      ${game.mode === 'daily' ? `<button class="link" data-action="board" style="margin:4px auto">🏆 ${t(board.group() ? 'board.title' : 'board.invitePrompt')}</button>` : ''}
      <div class="actions">
        <button class="button primary" data-action="new" autofocus title="Enter">${t('newGame')}</button>
        <button class="button" data-action="share">${t(navigator.share ? 'share' : 'copy')}</button>
        ${isClassic(game.mode) ? `<button class="button" data-action="replay">▶ ${t('replay.button')}</button>` : ''}
        <button class="button" data-close>${t('close')}</button>
      </div>
    </div>`, (d) => {
    d.querySelector('[data-action="share"]').onclick = share;
    // Pencere kapanınca haritada tahminler sırayla yeniden oynatılır.
    d.querySelector('[data-action="board"]')?.addEventListener('click', () => { d.close(); openBoard(); });
    const replay = d.querySelector('[data-action="replay"]');
    if (replay) replay.onclick = () => { d.close(); setTimeout(() => game.startReplay(), 300); };
    playLevelCard(d.querySelector('.level-card'), game.reward);
    // Enter doğrudan yeni oyuna geçer (autofocus bu düğmede).
    d.querySelector('[data-action="new"]').onclick = () => { d.close(); game.newRound(); };
  });
}

async function share() {
  const text = `${game.shareText}\n${location.origin}${location.pathname}`;
  if (navigator.share) {
    try { await navigator.share({ text }); } catch { /* vazgeçildi */ }
    return;
  }
  try {
    await navigator.clipboard.writeText(text);
    toast(t('copied.toast'));
  } catch {
    toast(t('copy.failed'));
  }
}

function toast(message) {
  const t = document.createElement('div');
  t.className = 'toast';
  t.textContent = message;
  document.body.appendChild(t);
  setTimeout(() => t.remove(), 2000);
}

// İstatistikler

let statsState = null;

function openStats() {
  statsState = { category: game.category, mode: isClassic(game.mode) ? game.mode : 'practice' };
  renderStats();
}

function renderStats() {
  const { category, mode } = statsState;
  const stats = category === game.category
    ? (mode === 'daily' ? game.dailyStats : game.practiceStats)
    : Stats.load(category, mode);
  const set = placeSet(category);
  const dist = stats.distribution;
  const maxCount = Math.max(1, ...dist.map((d) => d.count));
  const avg = stats.averageGuesses;

  showDialog('statsDialog', `
    <h2 class="center">${t('stats')}</h2>
    <div class="stats-controls">
      <select id="statsCategory">${CATEGORIES.map((c) => `<option value="${c.id}" ${c.id === category ? 'selected' : ''}>${c.icon} ${c.title}</option>`).join('')}</select>
      <div class="segmented" id="statsMode">
        <button data-mode="daily" aria-selected="${mode === 'daily'}">${t('mode.daily')}</button>
        <button data-mode="practice" aria-selected="${mode === 'practice'}">${t('mode.practice')}</button>
      </div>
    </div>
    ${levelCardHTML(progress(totalXP(Stats.load)))}
    ${badgeShelfHTML()}
    <hr>
    ${summaryHTML(stats, t(mode === 'daily' ? 'stats.streakDays' : 'stats.streak'))}
    ${modesSummaryHTML(category)}
    <div class="section-title">${t('stats.distribution')}</div>
    ${dist.map((d) => `<div class="dist-row"><span class="label">${d.label}</span>
      <span class="bar-track"><div class="bar ${d.count ? '' : 'empty'}" style="width:${(d.count / maxCount) * 100}%"></div></span>
      <span class="count">${d.count}</span></div>`).join('')}
    ${avg != null ? `<p class="muted center">${t('stats.average', { v: fmt1(avg) })}</p>` : ''}
    <hr>
    ${calendarHTML(stats, mode)}
    <hr>
    ${discoveryHTML(category, set)}
    <hr>
    ${progressHTML(stats, set)}
    <p class="muted center" style="font-size:12px">${t(`stats.footer.${mode}`)} ${t('stats.footer.browser')}</p>
    <div class="actions"><button class="button" data-close>${t('close')}</button></div>
  `, (d) => {
    d.querySelector('#statsCategory').onchange = (e) => { statsState.category = e.target.value; renderStats(); };
    // Keşif haritası, pencere yerleşince (boyutu belli olunca) çizilir.
    requestAnimationFrame(() => drawDiscoveryMap(d.querySelector('#discoveryCanvas'), set, foundIds(category)));
    d.querySelector('#statsMode').onclick = (e) => {
      const m = e.target.closest('button')?.dataset.mode;
      if (m) { statsState.mode = m; renderStats(); }
    };
  });
}

/** Kategorinin zamana karşı rekoru ve zincir sonuçları. */
function modesSummaryHTML(category) {
  const timed = TimedStats.load(category), chain = ChainStats.load(category);
  if (!timed.runs.length && !chain.runs.length) return '';
  return `<div class="summary">
    ${timed.runs.length ? `<div><b>${timed.best}</b><span>⏱️ ${t('stats.timedBest')}</span></div><div><b>${timed.runs.length}</b><span>⏱️ ${t('stats.timedRuns')}</span></div>` : ''}
    ${chain.runs.length ? `<div><b>${chain.won}/${chain.played}</b><span>🔗 ${t('stats.chainWon')}</span></div><div><b>${chain.perfect}</b><span>🔗 ${t('stats.chainPerfect')}</span></div>` : ''}
  </div>`;
}

/** Rozet rafı (tüm kategoriler birlikte). */
function badgeShelfHTML() {
  const badges = allBadges(Stats.load);
  return `<div class="section-title">${t('badges.title')} <span class="muted" style="font-weight:400;font-size:13px">· ${t('badges.count', { n: badges.filter((b) => b.earned).length, total: badges.length })}</span></div>
    <div class="badge-grid">${badges.map(badgeHTML).join('')}</div>`;
}

/** Kategoride bulunan (kazanılan oyunlardaki) yerler; günlük ve alıştırma birlikte. */
function foundIds(category) {
  const ids = new Set();
  for (const mode of ['daily', 'practice']) {
    const s = category === game.category ? (mode === 'daily' ? game.dailyStats : game.practiceStats) : Stats.load(category, mode);
    for (const r of s.history) if (r.won) ids.add(r.answerID);
  }
  const set = placeSet(category);
  return new Set([...ids].filter((id) => set.place(id)));
}

function discoveryHTML(category, set) {
  const found = foundIds(category);
  const total = set.places.length;
  const pct = Math.round((found.size / total) * 100);
  const kind = set.category.kind;
  return `<div class="section-title">${t('disc.title')}</div>
    <div class="discovery-head"><b>${found.size}</b> ${t(`disc.found.${kind}`, { total })} <span class="muted">(${formatNumber(pct / 100, { style: 'percent' })})</span></div>
    <div class="discovery-bar"><span style="width:${pct}%"></span></div>
    <canvas id="discoveryCanvas" class="discovery-map" aria-label="${t('disc.mapLabel')}"></canvas>
    <p class="muted" style="font-size:12px;margin:4px 0">${t(`disc.hint.${kind}`)}</p>`;
}

const dayKey = (d) => `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`;

/** Son 18 haftanın takvimi: günlükte kaç tahminde bulduğun, alıştırmada kaç oyun oynadığın. */
function calendarHTML(stats, mode) {
  const WEEKS = 18, CELL = 12, GAP = 3, LEFT = 26, TOP = 16;
  const byDay = new Map();
  for (const r of stats.history) {
    const k = dayKey(new Date(r.date));
    if (!byDay.has(k)) byDay.set(k, []);
    byDay.get(k).push(r);
  }
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const monday = new Date(today);
  monday.setDate(today.getDate() - ((today.getDay() + 6) % 7) - (WEEKS - 1) * 7);

  const monthFmt = new Intl.DateTimeFormat(locale(), { month: 'short' });
  const fmt = new Intl.DateTimeFormat(locale(), { day: 'numeric', month: 'long' });
  let cells = '', monthLabels = '', lastMonth = -1, played = 0;
  for (let w = 0; w < WEEKS; w++) {
    for (let d = 0; d < 7; d++) {
      const day = new Date(monday);
      day.setDate(monday.getDate() + w * 7 + d);
      if (day > today) continue;
      if (d === 0 && day.getMonth() !== lastMonth) {
        lastMonth = day.getMonth();
        monthLabels += `<text x="${LEFT + w * (CELL + GAP)}" y="10">${monthFmt.format(day).replace('.', '')}</text>`;
      }
      const recs = byDay.get(dayKey(day)) ?? [];
      const date = fmt.format(day);
      let level = 0, cls = '', tip = t('cal.notPlayed', { date });
      if (recs.length) {
        played++;
        if (mode === 'daily') {
          const r = recs[0];
          if (r.won) {
            level = r.guesses <= 3 ? 4 : r.guesses <= 6 ? 3 : r.guesses <= 10 ? 2 : 1;
            tip = t('cal.foundIn', { date, n: r.guesses });
          } else { cls = 'lost'; tip = t('cal.gaveUp', { date }); }
        } else {
          const n = recs.length;
          level = n >= 5 ? 4 : n >= 3 ? 3 : n === 2 ? 2 : 1;
          tip = t('cal.games', { date, n });
        }
      }
      const isToday = day.getTime() === today.getTime();
      cells += `<rect x="${LEFT + w * (CELL + GAP)}" y="${TOP + d * (CELL + GAP)}" width="${CELL}" height="${CELL}" rx="2.5"
        class="cal-cell ${cls || `l${level}`} ${isToday ? 'today' : ''}"><title>${tip}</title></rect>`;
    }
  }
  // Pazartesi, Çarşamba, Cuma (5 Ocak 2026 bir Pazartesi).
  const wd = new Intl.DateTimeFormat(locale(), { weekday: 'short' });
  const dayNames = [0, 2, 4].reduce((a, i) => { a[i] = wd.format(new Date(2026, 0, 5 + i)).replace('.', ''); return a; }, Array(7).fill('')).map((n, i) =>
    n ? `<text x="0" y="${TOP + i * (CELL + GAP) + 9}">${n}</text>` : '').join('');
  const W = LEFT + WEEKS * (CELL + GAP), H = TOP + 7 * (CELL + GAP);
  const legend = mode === 'daily'
    ? `<span>${t('cal.fewGuesses')}</span><i class="cal-cell l4"></i><i class="cal-cell l3"></i><i class="cal-cell l2"></i><i class="cal-cell l1"></i><span>${t('cal.many')}</span><i class="cal-cell lost"></i><span>${t('cal.gaveUpShort')}</span>`
    : `<span>${t('cal.few')}</span><i class="cal-cell l1"></i><i class="cal-cell l2"></i><i class="cal-cell l3"></i><i class="cal-cell l4"></i><span>${t('cal.manyGames')}</span>`;
  return `<div class="section-title">${t('cal.title')} <span class="muted" style="font-weight:400;font-size:13px">· ${t('cal.summary', { w: WEEKS, n: played })}</span></div>
    <svg class="calendar" viewBox="0 0 ${W} ${H}" width="${W}" height="${H}">${monthLabels}${dayNames}${cells}</svg>
    <div class="cal-legend">${legend}</div>`;
}

function progressHTML(stats, set) {
  const history = stats.history;
  if (history.length < 2) {
    return `<div class="section-title">${t('prog.title')}</div><p class="muted">${t('prog.empty')}</p>`;
  }
  const wins = history.filter((r) => r.won).map((r) => r.guesses);
  const overall = wins.length ? wins.reduce((a, b) => a + b, 0) / wins.length : null;
  const recent = stats.recentAverage(10);
  let badge = '';
  if (recent != null && overall != null) {
    const diff = recent - overall;
    badge = diff < -0.05 ? `<span class="badge" style="color:var(--found)">↘ ${t('prog.improving')}</span>`
      : diff > 0.05 ? `<span class="badge" style="color:#f08c00">↗ ${t('prog.worsening')}</span>`
      : `<span class="badge muted">→ ${t('prog.steady')}</span>`;
  }

  // SVG grafik: noktalar = oyunlar, çizgi = son 5 kazanılan oyunun ortalaması.
  const W = 500, H = 170, L = 28, R = 8, T = 10, B = 22;
  const maxY = Math.max(5, ...history.map((r) => r.guesses));
  const x = (i) => L + (history.length === 1 ? 0 : (i / (history.length - 1)) * (W - L - R));
  const y = (v) => T + (1 - v / maxY) * (H - T - B);
  const windowWins = [];
  const avgPts = [];
  history.forEach((r, i) => {
    if (r.won) windowWins.push(r.guesses);
    const w = windowWins.slice(-5);
    if (w.length) avgPts.push([x(i), y(w.reduce((a, b) => a + b, 0) / w.length)]);
  });
  const ticks = [0, Math.round(maxY / 2), maxY];
  const svg = `<svg class="chart" viewBox="0 0 ${W} ${H}" preserveAspectRatio="none">
    ${ticks.map((t) => `<line x1="${L}" x2="${W - R}" y1="${y(t)}" y2="${y(t)}" stroke="var(--line)"/><text x="${L - 6}" y="${y(t) + 3}" text-anchor="end">${t}</text>`).join('')}
    <polyline fill="none" stroke="var(--primary)" stroke-width="2" points="${avgPts.map((p) => p.join(',')).join(' ')}"/>
    ${history.map((r, i) => r.won
      ? `<circle cx="${x(i)}" cy="${y(r.guesses)}" r="3.5" fill="var(--found)"/>`
      : `<path d="M${x(i) - 3.5},${y(r.guesses) - 3.5}l7,7m0,-7l-7,7" stroke="gray" stroke-width="1.6"/>`).join('')}
    <text x="${W - R}" y="${H - 6}" text-anchor="end">${t('prog.axisGame')} →</text>
  </svg>`;

  const when = new Intl.DateTimeFormat(locale(), { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' });
  const recentRows = history.slice(-5).reverse().map((r) => `
    <div class="recent-row">
      <span>${r.won ? '✅' : '❌'}</span>
      <span class="name">${esc(set.place(r.answerID)?.name ?? '?')}</span>
      <span class="muted">${r.won ? t('guesses', { n: r.guesses }) : t('prog.recentLost', { guesses: t('guesses', { n: r.guesses }) })}</span>
      <span class="when">${when.format(new Date(r.date))}</span>
    </div>`).join('');

  const fmt = (v) => (v == null ? '–' : fmt1(v));
  return `<div class="section-title">${t('prog.title')}</div>
    <div class="trend">
      <div><b>${fmt(recent)}</b><span>${t('prog.last10')}</span></div>
      <div><b>${fmt(overall)}</b><span>${t('prog.all')}</span></div>
      ${badge}
    </div>
    ${svg}
    <p class="muted" style="font-size:12px;margin:4px 0">${t('prog.legend')}</p>
    <div class="section-title">${t('prog.recent')}</div>
    <div class="recent">${recentRows}</div>`;
}

// MARK: - Arkadaş grubu ve skor tablosu

let boardCategory = null;

async function openBoard() {
  const g = board.group();
  if (!g) {
    showDialog('boardDialog', `
      <h2>🏆 ${esc(t('board.title'))}</h2>
      <p>${esc(t('board.intro'))}</p>
      <label class="field"><span>${esc(t('board.nick'))}</span><input id="nickInput" maxlength="20" autocomplete="nickname" placeholder="${esc(t('board.nickPlaceholder'))}"></label>
      <div class="actions"><button class="button" data-close>${esc(t('close'))}</button>
        <button class="button primary" id="createGroup" disabled>${esc(t('board.create'))}</button></div>`, (d) => {
      const input = d.querySelector('#nickInput');
      const btn = d.querySelector('#createGroup');
      input.oninput = () => { btn.disabled = !board.cleanNick(input.value); };
      btn.onclick = () => { board.createGroup(input.value); board.syncResults().then(() => openBoard()); openBoard(); };
      setTimeout(() => input.focus(), 50);
    });
    return;
  }
  boardCategory ??= game.category;
  renderBoard(null);
  const data = await board.fetchBoard();
  if ($('boardDialog').open) renderBoard(data);
}

function renderBoard(data) {
  const g = board.group();
  const me = board.playerId();
  const results = data?.results ?? {};
  const list = board.rank(results[boardCategory] ?? []);
  const mine = store.get(`atlas.daily.${boardCategory}.${dayIndex()}`);
  const finished = mine && mine.status !== 'playing';
  const rows = !data ? `<p class="muted center">${esc(t('board.loading'))}</p>`
    : data.error ? `<p class="muted center">${esc(t(data.error === 'storage' ? 'board.noStorage' : 'board.offline'))}</p>`
    : list.length ? `<ol class="board-list">${list.map((e, i) => `<li class="${e.player === me ? 'me' : ''}">
        <span class="pos">${e.won ? i + 1 : '–'}</span><span class="nick">${esc(e.nick)}${e.player === me ? ` <span class="muted">(${esc(t('board.you'))})</span>` : ''}</span>
        <span class="res">${e.won ? esc(t('guesses', { n: e.guesses })) : esc(t('board.gaveUp'))}${e.hints ? ` · 💡${e.hints}` : ''}${e.expert ? ' · 🙈' : ''}</span></li>`).join('')}</ol>`
    : `<p class="muted center">${esc(t('board.empty'))}</p>`;
  showDialog('boardDialog', `
    <h2>🏆 ${esc(t('board.title'))}</h2>
    <p class="muted" style="margin-top:-6px">${esc(t('board.today', { n: game.puzzleNumber }))}</p>
    <div class="chips board-cats">${CATEGORIES.map((c) => `<button class="chip ${c.id === boardCategory ? 'selected' : ''}" data-cat="${c.id}">${c.icon} ${esc(c.title)}${results[c.id]?.length ? ` <b>${results[c.id].length}</b>` : ''}</button>`).join('')}</div>
    ${rows}
    ${!finished ? `<p class="muted" style="font-size:13px">${esc(t('board.notYet'))}</p>` : ''}
    <hr>
    <div class="board-footer">
      <label class="field inline"><span>${esc(t('board.nick'))}</span><input id="nickInput" maxlength="20" value="${esc(g.nick)}"></label>
      <div class="actions">
        <button class="button primary" id="inviteButton">${esc(t('board.invite'))}</button>
        <button class="button" id="leaveGroup">${esc(t('board.leave'))}</button>
        <button class="button" data-close>${esc(t('close'))}</button>
      </div>
    </div>`, (d) => {
    d.querySelectorAll('[data-cat]').forEach((b) => { b.onclick = () => { boardCategory = b.dataset.cat; renderBoard(data); }; });
    const nick = d.querySelector('#nickInput');
    nick.onchange = () => {
      if (!board.cleanNick(nick.value)) { nick.value = g.nick; return; }
      board.setNick(nick.value);
      board.syncResults().then(() => openBoard());
    };
    d.querySelector('#inviteButton').onclick = async () => {
      const text = `${t('board.inviteText')} ${board.inviteLink()}`;
      if (navigator.share) { try { await navigator.share({ text }); } catch {} return; }
      try { await navigator.clipboard.writeText(board.inviteLink()); toast(t('board.copied')); } catch { toast(board.inviteLink()); }
    };
    d.querySelector('#leaveGroup').onclick = () => {
      if (!confirm(t('board.leaveConfirm'))) return;
      board.leaveGroup();
      d.close();
    };
  });
}

/** Davet bağlantısıyla gelen: takma adla gruba katılma. */
function openJoin(code) {
  const current = board.group();
  showDialog('boardDialog', `
    <h2>🏆 ${esc(t('board.joinTitle'))}</h2>
    <p>${esc(t('board.joinIntro'))}</p>
    ${current ? `<p class="muted" style="font-size:13px">${esc(t('board.switchWarning'))}</p>` : ''}
    <label class="field"><span>${esc(t('board.nick'))}</span><input id="nickInput" maxlength="20" autocomplete="nickname" value="${esc(current?.nick ?? '')}" placeholder="${esc(t('board.nickPlaceholder'))}"></label>
    <div class="actions"><button class="button" data-close>${esc(t('cancel'))}</button>
      <button class="button primary" id="joinGroup" ${current?.nick ? '' : 'disabled'}>${esc(t('board.join'))}</button></div>`, (d) => {
    const input = d.querySelector('#nickInput');
    const btn = d.querySelector('#joinGroup');
    input.oninput = () => { btn.disabled = !board.cleanNick(input.value); };
    btn.onclick = () => {
      board.joinGroup(code, input.value);
      store.set('atlas.helpSeen', true);
      board.syncResults().then(() => openBoard());
      openBoard();
    };
    setTimeout(() => input.focus(), 50);
  });
}

// Yardım ve ayarlar

function openHelp() {
  const legend = [0, 3, 15, 40, 100, 250, 1000].map((t) => `<span style="background:${heatColor(t, 1000)}"></span>`).join('');
  showDialog('helpDialog', `
    <h2>${t('help')}</h2>
    <p>${t('help.intro')}</p>
    <ul class="bullets">
      ${['help.b1', 'help.b2', 'help.b3', 'help.b4', 'help.b5', 'help.modes', 'help.hints', 'help.xp'].map((k) => `<li>${t(k)}</li>`).join('')}
    </ul>
    <div class="legend">${legend}</div>
    <div class="legend-labels"><span>${t('help.near')}</span><span>${t('help.far')}</span></div>
    <p class="muted" style="font-size:14px">${bold(t('help.practice'))} ${t('help.kmWeb')}</p>
    <div class="actions end"><button class="button primary" data-close>${t('help.start')}</button></div>
  `);
}

function openSettings() {
  showDialog('settingsDialog', `
    <h2>${t('settings')}</h2>
    <div class="toggle-row">
      <div>
        <div>${t('set.distance')}</div>
        <div class="muted" style="font-size:13px" id="distanceHint"></div>
      </div>
      <label class="switch"><input type="checkbox" id="distanceToggle" ${game.showDistance ? 'checked' : ''}><span></span></label>
    </div>
    <div class="toggle-row">
      <div>
        <div>${t('set.expert')}</div>
        <div class="muted" style="font-size:13px">${t('set.expertHint')}</div>
      </div>
      <label class="switch"><input type="checkbox" id="expertToggle" ${store.get('atlas.expert', false) ? 'checked' : ''}><span></span></label>
    </div>
    <div class="toggle-row">
      <div>
        <div>${t('set.sound')}</div>
        <div class="muted" style="font-size:13px">${t('set.soundHint')}</div>
      </div>
      <label class="switch"><input type="checkbox" id="soundToggle" ${feedback.soundOn() ? 'checked' : ''}><span></span></label>
    </div>
    ${feedback.canVibrate() ? `<div class="toggle-row">
      <div>
        <div>${t('set.haptics')}</div>
        <div class="muted" style="font-size:13px">${t('set.hapticsHint')}</div>
      </div>
      <label class="switch"><input type="checkbox" id="hapticsToggle" ${feedback.hapticsOn() ? 'checked' : ''}><span></span></label>
    </div>` : ''}
    <div class="toggle-row">
      <div>${t('set.theme')}</div>
      <div class="segmented" id="themeSegmented">
        <button data-theme="system" aria-selected="${themePreference() === 'system'}">${t('set.system')}</button>
        <button data-theme="light" aria-selected="${themePreference() === 'light'}">${t('set.light')}</button>
        <button data-theme="dark" aria-selected="${themePreference() === 'dark'}">${t('set.dark')}</button>
      </div>
    </div>
    <div class="actions" style="justify-content:space-between">
      <button class="button" id="settingsHelp">${t('help')}</button>
      <span class="muted" style="font-size:12px;align-self:center">${t('set.version', { v: VERSION })}</span>
      <button class="button primary" data-close>${t('done')}</button>
    </div>
  `, (d) => {
    const hint = () => {
      d.querySelector('#distanceHint').textContent = t(game.showDistance ? 'set.distanceOn' : 'set.distanceOff');
    };
    hint();
    d.querySelector('#distanceToggle').onchange = (e) => {
      game.showDistance = e.target.checked;
      store.set('atlas.showDistance', game.showDistance);
      map.updateLegend();
      hint();
      render();
    };
    d.querySelector('#expertToggle').onchange = (e) => {
      store.set('atlas.expert', e.target.checked);
      render();
    };
    d.querySelector('#soundToggle').onchange = (e) => {
      store.set('atlas.sound', e.target.checked);
      if (e.target.checked) feedback.won(); // örnek ses (tarayıcı sesi ancak dokunuşla açar)
    };
    const haptics = d.querySelector('#hapticsToggle');
    if (haptics) haptics.onchange = (e) => store.set('atlas.haptics', e.target.checked);
    d.querySelector('#settingsHelp').onclick = () => { d.close(); openHelp(); };
    d.querySelector('#themeSegmented').onclick = (e) => {
      const t = e.target.closest('button')?.dataset.theme;
      if (!t) return;
      setThemePreference(t);
      d.querySelectorAll('#themeSegmented button').forEach((b) => b.setAttribute('aria-selected', b.dataset.theme === t));
    };
  });
}

start().catch((err) => {
  console.error(err);
  splash.fail();
  $('loading').textContent = t('map.failed');
});

// Uygulama gibi çalışsın (ana ekrana ekleme, çevrimdışı).
if ('serviceWorker' in navigator && location.protocol === 'https:') {
  navigator.serviceWorker.register('sw.js', { updateViaCache: 'none' })
    .then((reg) => reg.update())
    .catch(() => {});
  // Yeni sürüm yayınlanıp devreye girince sayfayı bir kez yenile; yoksa eski dosyalar görünmeye devam eder.
  // Yarım kalmış bir alıştırma oyunu kaybolmasın diye o durumda yenileme bir sonraki açılışa kalır.
  const hadController = !!navigator.serviceWorker.controller;
  let reloading = false;
  navigator.serviceWorker.addEventListener('controllerchange', () => {
    if (!hadController || reloading) return;
    const midPractice = game && game.mode === 'practice' && game.guesses.length > 0 && !game.isOver;
    if (midPractice) return;
    reloading = true;
    location.reload();
  });
}

