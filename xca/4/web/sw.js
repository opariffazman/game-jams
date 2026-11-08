// build.sh fills in the version and file list below so every release gets its own cache.
const VERSION = '__VERSION__';
const FILES = __FILES__;
const CACHE = 'rails-' + VERSION;

// One file at a time, so a missing file never blocks the rest and install never rejects.
async function precache() {
  try {
    const cache = await caches.open(CACHE);
    await Promise.all(FILES.map(async (file) => {
      try {
        if (await cache.match(file)) return;
        const response = await fetch(file, { cache: 'reload' });
        if (response.ok) await cache.put(file, response);
      } catch (e) { /* the network path still serves this file */ }
    }));
  } catch (e) { /* storage blocked or full: run without the cache */ }
}

async function dropOldCaches() {
  try {
    const names = await caches.keys();
    await Promise.all(names.filter((n) => n.startsWith('rails-') && n !== CACHE).map((n) => caches.delete(n)));
    await self.clients.claim();
  } catch (e) { /* ignore */ }
}

async function cacheFirst(request) {
  try {
    const hit = await caches.match(request, { cacheName: CACHE, ignoreSearch: true });
    if (hit) return hit;
  } catch (e) { /* fall through to the network */ }
  return fetch(request);
}

self.addEventListener('install', (event) => { event.waitUntil(precache().then(() => self.skipWaiting())); });
self.addEventListener('activate', (event) => { event.waitUntil(dropOldCaches()); });
self.addEventListener('fetch', (event) => {
  const { request } = event;
  // Range requests need partial responses, which the cache does not return.
  if (request.method !== 'GET' || request.headers.has('range') || new URL(request.url).origin !== self.location.origin) return;
  event.respondWith(cacheFirst(request));
});
