import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';

// Must be set before server.js is imported, since GEMINI_API_KEY is read
// once at module load time.
process.env.GEMINI_API_KEY = 'test-key';

const { app } = await import('../server.js');

let server;
let baseUrl;

before(async () => {
  server = app.listen(0);
  await new Promise((resolve) => server.once('listening', resolve));
  const { port } = server.address();
  baseUrl = `http://127.0.0.1:${port}`;
});

after(async () => {
  await new Promise((resolve) => server.close(resolve));
});

function fakeGeminiResponse(fields) {
  return {
    candidates: [
      {
        content: {
          parts: [{ text: JSON.stringify(fields) }],
        },
      },
    ],
  };
}

// The stub replaces globalThis.fetch (used internally by server.js to call
// Gemini), so tests must keep a handle to the real fetch to reach the local
// test server themselves — otherwise their own request gets intercepted too.
const realFetch = globalThis.fetch;

function stubFetchOnce(responseBody) {
  globalThis.fetch = async () => ({
    ok: true,
    status: 200,
    json: async () => responseBody,
  });
  return () => {
    globalThis.fetch = realFetch;
  };
}

test('image-only request (no ocrText) is accepted and processed', async () => {
  const restoreFetch = stubFetchOnce(
    fakeGeminiResponse({
      merchant: 'Test Mart',
      transaction_date: '2026-09-01',
      total_amount: 12.5,
      currency: 'MYR',
      suggested_category: null,
      suggested_wallet: null,
    }),
  );
  try {
    const res = await realFetch(`${baseUrl}/api/receipt/parse`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        imageBase64: Buffer.from('fake-image-bytes').toString('base64'),
        imageMimeType: 'image/jpeg',
      }),
    });

    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.merchant, 'Test Mart');
    assert.equal(body.total_amount, 12.5);
  } finally {
    restoreFetch();
  }
});

test('text-only request (no image) is accepted and processed', async () => {
  const restoreFetch = stubFetchOnce(
    fakeGeminiResponse({
      merchant: 'Coffee Shop',
      transaction_date: '2026-09-02',
      total_amount: 8.9,
      currency: 'MYR',
      suggested_category: null,
      suggested_wallet: null,
    }),
  );
  try {
    const res = await realFetch(`${baseUrl}/api/receipt/parse`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        ocrText: 'COFFEE SHOP\nTOTAL: 8.90',
      }),
    });

    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.merchant, 'Coffee Shop');
    assert.equal(body.total_amount, 8.9);
  } finally {
    restoreFetch();
  }
});

test('request with neither ocrText nor image is rejected with 400', async () => {
  const res = await realFetch(`${baseUrl}/api/receipt/parse`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({}),
  });

  assert.equal(res.status, 400);
  const body = await res.json();
  assert.match(body.error, /ocrText or imageBase64 is required/);
});

test('request with blank ocrText and no image is rejected with 400', async () => {
  const res = await realFetch(`${baseUrl}/api/receipt/parse`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ ocrText: '   ' }),
  });

  assert.equal(res.status, 400);
});
