const test = require('node:test');
const assert = require('node:assert/strict');

const {
  createSoundfontCache,
  installSoundfontFetchCache
} = require('../media/soundfont-cache.js');

class FakeCache {
  constructor() {
    this.entries = new Map();
  }

  async match(request) {
    return this.entries.get(request) || undefined;
  }

  async put(request, response) {
    this.entries.set(request, response);
  }
}

class FakeCacheStorage {
  constructor() {
    this.caches = new Map();
    this.openedNames = [];
  }

  async open(name) {
    this.openedNames.push(name);
    if (!this.caches.has(name)) this.caches.set(name, new FakeCache());
    return this.caches.get(name);
  }
}

test('stores a fetched SoundFont resource and reuses it on the next request', async () => {
  const storage = new FakeCacheStorage();
  let fetchCount = 0;
  const fetchImpl = async () => {
    fetchCount += 1;
    return new Response('piano-samples');
  };
  const cache = createSoundfontCache({ cacheStorage: storage, version: '1' });

  const first = await cache.fetch('https://example.test/piano.js', fetchImpl);
  const second = await cache.fetch('https://example.test/piano.js', fetchImpl);

  assert.equal(await first.text(), 'piano-samples');
  assert.equal(await second.text(), 'piano-samples');
  assert.equal(fetchCount, 1);
  assert.deepEqual(storage.openedNames, ['tmd-soundfont-v1']);
});

test('isolates resources by cache version', async () => {
  const storage = new FakeCacheStorage();
  const cacheV1 = createSoundfontCache({ cacheStorage: storage, version: '1' });
  const cacheV2 = createSoundfontCache({ cacheStorage: storage, version: '2' });

  await cacheV1.fetch('https://example.test/piano.js', async () => new Response('v1'));
  await cacheV2.fetch('https://example.test/piano.js', async () => new Response('v2'));

  assert.deepEqual(storage.openedNames, ['tmd-soundfont-v1', 'tmd-soundfont-v2']);
  assert.equal(await (await cacheV2.fetch('https://example.test/piano.js', async () => {
    throw new Error('network should not be used');
  })).text(), 'v2');
});

test('falls back to the network when persistent cache operations fail', async () => {
  const cache = createSoundfontCache({
    cacheStorage: {
      async open() {
        throw new Error('storage unavailable');
      }
    },
    version: '1'
  });

  const response = await cache.fetch('https://example.test/piano.js', async () => new Response('network'));

  assert.equal(await response.text(), 'network');
});

test('deduplicates concurrent requests for the same resource', async () => {
  const storage = new FakeCacheStorage();
  let fetchCount = 0;
  let resolveFetch;
  const fetchImpl = () => {
    fetchCount += 1;
    return new Promise(resolve => {
      resolveFetch = () => resolve(new Response('shared'));
    });
  };
  const cache = createSoundfontCache({ cacheStorage: storage, version: '1' });

  const first = cache.fetch('https://example.test/piano.js', fetchImpl);
  const second = cache.fetch('https://example.test/piano.js', fetchImpl);
  await new Promise(resolve => setImmediate(resolve));
  resolveFetch();

  const responses = await Promise.all([first, second]);

  assert.equal(fetchCount, 1);
  assert.equal(await responses[0].text(), 'shared');
  assert.equal(await responses[1].text(), 'shared');
});

test('installs the persistent cache around the SoundFont loader fetch', async () => {
  const storage = new FakeCacheStorage();
  let networkCount = 0;
  const audioLoader = {
    fetch: async () => {
      networkCount += 1;
      return new Response('cached-loader-resource');
    }
  };

  installSoundfontFetchCache(audioLoader, { cacheStorage: storage, version: '1' });
  await audioLoader.fetch('https://example.test/piano.js');
  await audioLoader.fetch('https://example.test/piano.js');

  assert.equal(networkCount, 1);
});
