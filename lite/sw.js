/*
 * Mode hors ligne : garde une copie de l'appli sur l'iPad.
 * Après une première ouverture avec internet, l'appli s'ouvre sans connexion.
 * Quand internet est là, la nouvelle version est téléchargée en arrière-plan
 * et utilisée à l'ouverture suivante.
 * (Les données, elles, sont déjà sur l'iPad, dans Safari.)
 */
var CACHE = 'stock-alimentaire-v1';
var FILES = [
  './',
  'index.html',
  'style.css',
  'logic.js',
  'app.js',
  'manifest.json',
  'favicon.png',
  'vendor/zxing-0.21.3.min.js',
  'icons/apple-touch-icon.png',
  'icons/Icon-192.png',
  'icons/Icon-512.png'
];

self.addEventListener('install', function (event) {
  event.waitUntil(caches.open(CACHE).then(function (cache) { return cache.addAll(FILES); }));
  self.skipWaiting();
});

self.addEventListener('activate', function (event) {
  event.waitUntil(caches.keys().then(function (keys) {
    return Promise.all(keys.filter(function (k) { return k !== CACHE; }).map(function (k) { return caches.delete(k); }));
  }));
});

self.addEventListener('fetch', function (event) {
  var req = event.request;
  if (req.method !== 'GET') return;
  // Seulement les fichiers de l'appli (pas Open Food Facts).
  if (new URL(req.url).origin !== self.location.origin) return;
  event.respondWith(caches.open(CACHE).then(function (cache) {
    return cache.match(req, { ignoreSearch: true }).then(function (cached) {
      var network = fetch(req).then(function (res) {
        if (res && res.ok) cache.put(req, res.clone());
        return res;
      }).catch(function () { return cached; });
      // Copie locale tout de suite si on l'a, sinon le réseau.
      return cached || network;
    });
  }));
});
