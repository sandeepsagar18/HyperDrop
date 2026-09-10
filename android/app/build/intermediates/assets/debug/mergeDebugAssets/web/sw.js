const CACHE_NAME = 'hyperdrop-offline-v2';
const ASSETS = [
    '/',
    '/index.html',
    '/css/style.css',
    '/css/icons.css',
    '/js/app.js'
];

self.addEventListener('install', (e) => {
    self.skipWaiting();
});

self.addEventListener('activate', (e) => {
    e.waitUntil(
        caches.keys().then((keys) => {
            return Promise.all(
                keys.map((key) => {
                    if (key !== CACHE_NAME) {
                        return caches.delete(key);
                    }
                })
            );
        }).then(() => self.clients.claim())
    );
});

// Network-First with Cache Fallback for seamless offline & instant updates
self.addEventListener('fetch', (e) => {
    if (e.request.url.includes('/api/') || e.request.url.includes('/ws')) {
        return;
    }
    e.respondWith(
        fetch(e.request)
            .then((networkRes) => {
                if (networkRes && networkRes.status === 200) {
                    const resClone = networkRes.clone();
                    caches.open(CACHE_NAME).then((cache) => cache.put(e.request, resClone));
                }
                return networkRes;
            })
            .catch(() => caches.match(e.request))
    );
});
