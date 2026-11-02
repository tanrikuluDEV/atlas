// Tahminlerde kısa sesler (isteğe bağlı, varsayılan kapalı) ve destekleyen telefonlarda titreşim.
// Sesler anında üretilen kısa tonlardır. Mac/iPhone/Apple TV'deki GameFeedback.swift'in karşılığı.
import { store } from './store.js';

let audio = null;

export const soundOn = () => store.get('atlas.sound', false);
export const hapticsOn = () => store.get('atlas.haptics', true);
export const canVibrate = () => typeof navigator.vibrate === 'function';

function play(notes, volume) {
  if (!soundOn()) return;
  try {
    audio ??= new (window.AudioContext || window.webkitAudioContext)();
    if (audio.state === 'suspended') audio.resume();
    const now = audio.currentTime + 0.01;
    for (const n of notes) {
      for (const [mult, gainMult] of [[1, 1], [2, 0.25]]) {
        const osc = audio.createOscillator();
        const gain = audio.createGain();
        osc.frequency.value = n.freq * mult;
        const start = now + n.start;
        // Hızlı yükselme, üstel sönüm.
        gain.gain.setValueAtTime(0, start);
        gain.gain.linearRampToValueAtTime(volume * gainMult, start + 0.006);
        gain.gain.exponentialRampToValueAtTime(0.0001, start + n.length);
        osc.connect(gain).connect(audio.destination);
        osc.start(start);
        osc.stop(start + n.length + 0.02);
      }
    }
  } catch { /* ses desteklenmiyor */ }
}

function vibrate(pattern) {
  if (hapticsOn() && canVibrate()) {
    try { navigator.vibrate(pattern); } catch { /* yok say */ }
  }
}

/** Yakınlık 0…1 (1 = komşu). Ton yaklaştıkça incelir; öncekinden yakınsa ikinci, daha ince bir nota eklenir. */
export function guessMade(proximity, improved) {
  const f = 330 * 2 ** (proximity * 1.5);
  const notes = [{ freq: f, start: 0, length: 0.16 }];
  if (improved) notes.push({ freq: f * 1.26, start: 0.09, length: 0.2 });
  play(notes, 0.22);
  if (improved) vibrate(15 + Math.round(25 * proximity));
}

export function won() {
  play([523.25, 659.25, 783.99, 1046.5].map((freq, i) => ({ freq, start: i * 0.09, length: 0.5 })), 0.2);
  vibrate([60, 60, 160]);
}

export function lost() {
  play([{ freq: 392, start: 0, length: 0.22 }, { freq: 293.66, start: 0.16, length: 0.4 }], 0.18);
  vibrate(80);
}
