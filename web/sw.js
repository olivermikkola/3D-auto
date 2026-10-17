// Keeps the game's files on the device, so an installed game starts without
// a connection. build.sh stamps VERSION with the module's hash: a new build
// installs a new cache and drops the old one, so nobody is stuck on an old
// game. If the files can't be stored (no room), install fails and the page
// simply loads from the network as before.
const VERSION = "__VERSION__";
const CACHE = "gta-" + VERSION;
const FILES = ["./", "index.html", "gl.js", "auto.wasm", "manifest.webmanifest", "icons/icon-192.png", "icons/icon-512.png"];

self.addEventListener("install", event => {
  event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(FILES)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", event => {
  event.waitUntil(caches.keys()
    .then(keys => Promise.all(keys.filter(k => k.startsWith("gta-") && k !== CACHE).map(k => caches.delete(k))))
    .then(() => self.clients.claim()));
});

// The game's own files from the cache (the page's query string, ?map=raisio,
// doesn't make a different page); everything else from the network.
self.addEventListener("fetch", event => {
  const req = event.request;
  if (req.method !== "GET" || new URL(req.url).origin !== location.origin) return;
  event.respondWith(caches.open(CACHE)
    .then(cache => cache.match(req, {ignoreSearch: true}))
    .then(hit => hit || fetch(req)));
});
