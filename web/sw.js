// Çevrimdışı çalışma: dosyalar önbelleğe alınır, internet yokken oradan verilir.
const CACHE = 'atlas-v11';
const ASSETS = [
  './', 'index.html', 'style.css', 'manifest.webmanifest',
  'js/app.js', 'js/game.js', 'js/map.js', 'js/places.js', 'js/daily.js', 'js/colors.js', 'js/confetti.js', 'js/i18n.js', 'js/store.js', 'js/version.js', 'js/brand.js', 'js/progression.js',
  'data/world.json', 'data/provinces.json', 'data/strings.json', 'data/hints.json',
  'icons/icon-192.png', 'icons/icon-512.png', 'icons/apple-touch-icon.png', 'icons/favicon-32.png', 'fonts/bricolage-800.woff2',
];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(ASSETS)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim()),
  );
});

self.addEventListener('fetch', (e) => {
  const url = new URL(e.request.url);
  if (e.request.method !== 'GET' || url.origin !== location.origin || url.pathname.startsWith('/api/')) return;
  // Ağ öncelikli: internet varken güncellemeler hemen gelir; yoksa önbellekten çalışır.
  e.respondWith(
    caches.open(CACHE).then(async (cache) => {
      try {
        const res = await fetch(e.request);
        if (res.ok) cache.put(e.request, res.clone());
        return res;
      } catch {
        // Veri dosyaları sürüm parametresiyle (?v=) istenir; çevrimdışıyken parametresiz kopya da olur.
        return (await cache.match(e.request)) || (await cache.match(e.request, { ignoreSearch: true })) || Response.error();
      }
    }),
  );
});
