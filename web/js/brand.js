// Claude Design'daki "Atlas 1a · Küre-pin" kimliği: logo işareti, açılış ve seviye kartı.
// Mac/iPhone/Apple TV'deki Brand.swift'in karşılığı. Renkler style.css'te (--brand-*).
import { formatNumber, t } from './i18n.js';

const PIN = 'M50 94 C50 94 16 60 16 38 A34 34 0 1 1 84 38 C84 60 50 94 50 94Z';

/** Logo işareti: pinin içinde küre. Renkler CSS değişkeni ya da renk adı olabilir. */
export function markSVG({ pin = 'var(--brand-navy)', lines = 'var(--brand-cream)', equator = 'var(--brand-orange)', size = 24, cls = '' } = {}) {
  return `<svg class="mark ${cls}" width="${size}" height="${size}" viewBox="0 0 100 100" aria-hidden="true">
    <path d="${PIN}" fill="${pin}"/>
    <circle cx="50" cy="38" r="20" fill="none" stroke="${lines}" stroke-width="4"/>
    <line x1="30" y1="38" x2="70" y2="38" stroke="${equator}" stroke-width="4"/>
    <ellipse class="meridian" cx="50" cy="38" rx="8" ry="20" fill="none" stroke="${lines}" stroke-width="4"/>
  </svg>`;
}

/** İçinde seviye numarası yazan turuncu pin. */
export function levelPinSVG(level, size = 64) {
  return `<svg class="level-pin" width="${size}" height="${size}" viewBox="0 0 100 100" role="img" aria-label="${t('level.n', { n: level })}">
    <path d="${PIN}" fill="var(--brand-orange)"/>
    <text x="50" y="38" text-anchor="middle" dominant-baseline="central" font-size="${level >= 100 ? 26 : 34}">${level}</text>
  </svg>`;
}

const fmt = (n) => formatNumber(n);

/**
 * Seviye kartı. `reward` verilirse (sonuç penceresi) kart önce oyundan önceki hâli gösterir;
 * `playLevelCard` kazanılan puanı canlandırır.
 */
export function levelCardHTML(progress, reward = null) {
  const animated = reward && reward.after.xp > reward.before.xp;
  const shown = animated ? reward.before : progress;
  const gained = reward ? reward.after.xp - reward.before.xp : 0;
  const levelUp = reward && reward.after.level > reward.before.level;
  return `<div class="level-card ${animated ? 'pending' : ''}">
    ${levelUp ? `<div class="level-up">${t('level.up')}</div>` : ''}
    <div class="level-row">
      <div class="level-pin-wrap">${levelPinSVG(shown.level)}</div>
      <div>
        <div class="level-name">${t('level.n', { n: shown.level })}</div>
        ${reward ? `<div class="xp-gain ${gained ? '' : 'none'}">${gained ? t('xp.gained', { n: gained }) : t('xp.none')}</div>` : ''}
      </div>
    </div>
    <div class="xp-track"><div class="xp-bar" style="width:${Math.max(3, shown.fraction * 100)}%"></div></div>
    <div class="xp-labels"><span>${fmt(progress.xp)} XP</span><span>${fmt(progress.next)}</span></div>
  </div>`;
}

const wait = (ms) => new Promise((r) => setTimeout(r, ms));

export async function playLevelCard(card, reward) {
  if (!card || !reward || reward.after.xp <= reward.before.xp) return;
  const bar = card.querySelector('.xp-bar');
  const setLevel = (n) => {
    card.querySelector('.level-pin-wrap').innerHTML = levelPinSVG(n);
    card.querySelector('.level-name').textContent = t('level.n', { n });
  };
  if (matchMedia('(prefers-reduced-motion: reduce)').matches) {
    setLevel(reward.after.level);
    bar.style.width = `${Math.max(3, reward.after.fraction * 100)}%`;
    card.classList.remove('pending');
    card.classList.add('shown');
    return;
  }
  await wait(350);
  card.classList.remove('pending');
  card.classList.add('gain');
  if (reward.after.level === reward.before.level) {
    bar.style.width = `${Math.max(3, reward.after.fraction * 100)}%`;
    return;
  }
  bar.style.transition = 'width .7s ease-in';
  bar.style.width = '100%';
  await wait(700);
  setLevel(reward.after.level);
  card.classList.add('leveled');
  bar.style.transition = 'none';
  bar.style.width = '3%';
  await wait(30);
  bar.style.transition = '';
  bar.style.width = `${Math.max(3, reward.after.fraction * 100)}%`;
}

// MARK: - Açılış

/**
 * Açılış: pin düşer, dalga yayılır, "Atlas" belirir (index.html'deki #splash, CSS animasyonları).
 * Veri hâlâ yükleniyorsa pin süzülmeye ve meridyen dönmeye başlar (yükleme animasyonu).
 */
export function splashStarted() {
  const splash = document.getElementById('splash');
  const started = performance.now();
  const loadingTimer = setTimeout(() => splash?.classList.add('waiting'), 1500);
  return {
    async done() {
      if (!splash) return;
      const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
      const left = reduce ? 0 : 1500 - (performance.now() - started);
      if (left > 0) await wait(left);
      clearTimeout(loadingTimer);
      splash.classList.add('hide');
      setTimeout(() => splash.remove(), 400);
    },
    fail() {
      clearTimeout(loadingTimer);
      splash?.remove();
    },
  };
}
