(function (root, factory) {
    if (typeof module === 'object' && module.exports) {
        module.exports = factory();
    } else {
        const api = factory();
        root.createSoundfontCache = api.createSoundfontCache;
        root.installSoundfontFetchCache = api.installSoundfontFetchCache;
    }
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
    function createSoundfontCache(options) {
        const opts = options || {};
        const cacheStorage = opts.cacheStorage || (typeof caches !== 'undefined' ? caches : null);
        const version = opts.version || '1';
        const cacheName = `tmd-soundfont-v${version}`;
        const inFlight = new Map();
        let cachePromise = null;

        function getCache() {
            if (!cacheStorage || typeof cacheStorage.open !== 'function') {
                return Promise.resolve(null);
            }
            if (!cachePromise) {
                cachePromise = Promise.resolve(cacheStorage.open(cacheName)).catch(() => null);
            }
            return cachePromise;
        }

        async function fetchResource(url, fetchImpl) {
            const loader = fetchImpl || (typeof fetch === 'function' ? fetch : null);
            if (!loader) throw new Error('No network loader is available');

            const existing = inFlight.get(url);
            if (existing) {
                const response = await existing;
                return response && response.clone ? response.clone() : response;
            }

            const request = (async () => {
                const cache = await getCache();
                if (cache && typeof cache.match === 'function') {
                    try {
                        const cached = await cache.match(url);
                        if (cached) return cached;
                    } catch (_) {
                        // Persistent cache is an optimization; use the network if it fails.
                    }
                }

                const response = await loader(url);
                if (cache && response && response.ok !== false && typeof cache.put === 'function') {
                    try {
                        await cache.put(url, response.clone ? response.clone() : response);
                    } catch (_) {
                        // A cache write failure must not interrupt playback.
                    }
                }
                return response;
            })();

            inFlight.set(url, request);
            try {
                return await request;
            } finally {
                inFlight.delete(url);
            }
        }

        return {
            cacheName,
            fetch: fetchResource
        };
    }

    function installSoundfontFetchCache(audioLoader, options) {
        if (!audioLoader || typeof audioLoader.fetch !== 'function') return null;

        const originalFetch = audioLoader.fetch.bind(audioLoader);
        const cache = createSoundfontCache(options);
        audioLoader.fetch = url => cache.fetch(url, originalFetch);
        return cache;
    }

    return { createSoundfontCache, installSoundfontFetchCache };
});
