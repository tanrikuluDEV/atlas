// Ülke bayrakları: emoji; KKTC'nin emojisi olmadığı için küçük bir SVG. (Swift: FlagView.swift)
// Windows bayrak emojilerini çizmez (yalnızca "DE" gibi harfler görünür); orada bayraklar gösterilmez.

let supported = null;

/** Tarayıcı bayrak emojisini renkli çiziyor mu? Bir kez ölçülür. */
export function flagsSupported() {
  if (supported != null) return supported;
  try {
    const c = document.createElement('canvas');
    c.width = c.height = 24;
    const ctx = c.getContext('2d', { willReadFrequently: true });
    ctx.font = '20px sans-serif';
    ctx.textBaseline = 'top';
    ctx.fillText('🇹🇷', 0, 0);
    const d = ctx.getImageData(0, 0, 24, 24).data;
    // Harf olarak çizilirse pikseller gri/siyah olur; bayrakta belirgin kırmızı vardır.
    supported = false;
    for (let i = 0; i < d.length; i += 4) {
      if (d[i + 3] > 100 && d[i] > 150 && d[i + 1] < 90 && d[i + 2] < 90) { supported = true; break; }
    }
  } catch {
    supported = false;
  }
  return supported;
}

const NORTH_CYPRUS = `<svg class="flag-svg" viewBox="0 0 30 20" aria-hidden="true"><rect width="30" height="20" rx="1.6" fill="#fff" stroke="rgba(0,0,0,.15)" stroke-width=".5"/><rect y="2" width="30" height="2.2" fill="#e30a17"/><rect y="15.8" width="30" height="2.2" fill="#e30a17"/><circle cx="13.2" cy="10" r="4" fill="#e30a17"/><circle cx="14.2" cy="10" r="3.2" fill="#fff"/><polygon points="16.70,10.00 17.99,9.55 18.01,8.19 18.83,9.28 20.14,8.88 19.36,10.00 20.14,11.12 18.83,10.72 18.01,11.81 17.99,10.45" fill="#e30a17"/></svg>`;

/** Bayrak HTML'i (adın önüne konur); bayrağı yoksa boş metin. */
export function flagHTML(place) {
  if (!place?.iso2) return '';
  if (place.iso2 === 'CY-N') return `<span class="flag">${NORTH_CYPRUS}</span>`;
  return flagsSupported() ? `<span class="flag" aria-hidden="true">${place.flag}</span>` : '';
}

/** Düz metinde bayraklı ad (harita etiketi, ipucu balonu). */
export function flaggedName(place) {
  return place.flag && flagsSupported() ? `${place.flag} ${place.name}` : place.name;
}
