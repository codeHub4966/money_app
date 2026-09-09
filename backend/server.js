import 'dotenv/config';
import express from 'express';
import cors from 'cors';

const app = express();
app.use(cors());
app.use(express.json({ limit: '2mb' }));

const PORT = process.env.PORT || 8787;
const GEMINI_API_KEY = process.env.GEMINI_API_KEY;
const GEMINI_MODEL = process.env.GEMINI_MODEL || 'gemini-3.6-flash';
const GEMINI_TIMEOUT_MS = 25_000;

const RECEIPT_FIELDS = [
  'merchant',
  'transaction_date',
  'total_amount',
  'currency',
  'suggested_category',
  'suggested_wallet',
];

app.get('/health', (req, res) => {
  res.json({ ok: true, hasApiKey: Boolean(GEMINI_API_KEY) });
});

app.post('/api/receipt/parse', async (req, res) => {
  if (!GEMINI_API_KEY) {
    return res.status(500).json({ error: 'GEMINI_API_KEY is not configured on the server.' });
  }

  const { ocrText, lowConfidenceFields, categories, wallets } = req.body ?? {};

  if (typeof ocrText !== 'string' || ocrText.trim().length === 0) {
    return res.status(400).json({ error: 'ocrText is required.' });
  }

  const safeLowConfidenceFields = Array.isArray(lowConfidenceFields)
    ? lowConfidenceFields.filter((f) => typeof f === 'string')
    : [];
  const safeCategories = Array.isArray(categories)
    ? categories.filter((c) => typeof c === 'string' && c.trim().length > 0)
    : [];
  const safeWallets = Array.isArray(wallets)
    ? wallets.filter((w) => typeof w === 'string' && w.trim().length > 0)
    : [];

  const prompt = buildPrompt({
    ocrText,
    lowConfidenceFields: safeLowConfidenceFields,
    categories: safeCategories,
    wallets: safeWallets,
  });

  try {
    const geminiJson = await callGemini(prompt);
    const parsed = extractJson(geminiJson);

    if (!parsed) {
      return res.status(502).json({ error: 'Gemini returned an unparseable response.' });
    }

    return res.json(normalizeResult(parsed));
  } catch (err) {
    if (err.name === 'AbortError') {
      return res.status(504).json({ error: 'Gemini request timed out.' });
    }
    if (err.status === 429) {
      return res.status(429).json({ error: 'Gemini rate limit exceeded.' });
    }
    console.error('[receipt/parse] Gemini call failed:', err);
    return res.status(502).json({ error: 'Gemini call failed.' });
  }
});

function buildPrompt({ ocrText, lowConfidenceFields, categories, wallets }) {
  return `You are extracting structured data from a retail receipt for a personal finance app.

The receipt was already OCR-scanned and parsed locally. The local parser was NOT confident about
these fields: ${lowConfidenceFields.length > 0 ? lowConfidenceFields.join(', ') : '(none listed)'}.
Focus your effort on getting those right, but return every field.

FULL OCR TEXT (verbatim, may contain OCR noise/typos):
"""
${ocrText}
"""

EXISTING EXPENSE/INCOME CATEGORIES (choose "suggested_category" ONLY from this exact list, or null):
${categories.length > 0 ? categories.map((c) => `- ${c}`).join('\n') : '(no categories provided)'}

EXISTING WALLETS/ACCOUNTS (choose "suggested_wallet" ONLY from this exact list, or null):
${wallets.length > 0 ? wallets.map((w) => `- ${w}`).join('\n') : '(no wallets provided)'}

RULES:
1. "total_amount" must be the FINAL amount the customer paid. Do NOT return the subtotal, tax/GST/SST,
   service charge, cash tendered, change given, or a discount amount as the total — those are different
   numbers on the receipt and must not be confused with the grand total.
2. "suggested_category" must be exactly one string from the EXISTING CATEGORIES list above, or null if
   none fit. Never invent a new category name.
3. "suggested_wallet" must be exactly one string from the EXISTING WALLETS list above, or null. Only
   return a wallet if the receipt contains a clear payment clue (e.g. "CASH", "VISA", "MASTERCARD", a
   bank name, "Touch 'n Go", "TNG", "DuitNow", "GrabPay", "Boost", "ShopeePay", card last-4 digits, etc.)
   that reliably maps to one of the listed wallets. If you are not confident, return null. Never invent
   a wallet name that isn't in the list.
4. "transaction_date" must be an ISO 8601 date string ("YYYY-MM-DD"), or null if not found.
5. "total_amount" must be a plain number (no currency symbol), or null if not found.
6. "currency" is a best-effort 3-letter ISO code (e.g. "MYR", "USD") if identifiable, else null.
7. "merchant" is the business/store name, or null if not identifiable.

Respond with ONLY a single JSON object with exactly these keys, no markdown, no explanation:
${JSON.stringify(RECEIPT_FIELDS)}`;
}

async function callGemini(prompt, attempt = 1) {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${GEMINI_API_KEY}`;

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), GEMINI_TIMEOUT_MS);

  try {
    const response = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        contents: [{ role: 'user', parts: [{ text: prompt }] }],
        generationConfig: {
          temperature: 0,
          responseMimeType: 'application/json',
        },
      }),
      signal: controller.signal,
    });

    if (!response.ok) {
      // 503 from Gemini means "temporarily overloaded, retry shortly" per
      // Google's own error message — worth one quick retry before giving
      // up and letting the client fall back to the local parser result.
      if (response.status === 503 && attempt < 2) {
        clearTimeout(timeout);
        await new Promise((r) => setTimeout(r, 1000));
        return callGemini(prompt, attempt + 1);
      }
      const error = new Error(`Gemini API responded with ${response.status}`);
      error.status = response.status;
      throw error;
    }

    return await response.json();
  } finally {
    clearTimeout(timeout);
  }
}

function extractJson(geminiResponse) {
  const text = geminiResponse?.candidates?.[0]?.content?.parts?.[0]?.text;
  if (typeof text !== 'string') return null;

  try {
    return JSON.parse(text);
  } catch {
    // Fallback: Gemini occasionally wraps JSON in prose/markdown despite
    // responseMimeType — pull out the first {...} block and retry.
    const match = text.match(/\{[\s\S]*\}/);
    if (!match) return null;
    try {
      return JSON.parse(match[0]);
    } catch {
      return null;
    }
  }
}

function normalizeResult(raw) {
  const asString = (v) => (typeof v === 'string' && v.trim().length > 0 ? v.trim() : null);
  const asNumber = (v) => {
    if (typeof v === 'number' && Number.isFinite(v)) return v;
    if (typeof v === 'string') {
      const n = Number(v.replace(/[^\d.-]/g, ''));
      return Number.isFinite(n) ? n : null;
    }
    return null;
  };

  return {
    merchant: asString(raw.merchant),
    transaction_date: asString(raw.transaction_date),
    total_amount: asNumber(raw.total_amount),
    currency: asString(raw.currency),
    suggested_category: asString(raw.suggested_category),
    suggested_wallet: asString(raw.suggested_wallet),
  };
}

app.listen(PORT, () => {
  console.log(`Receipt AI backend listening on port ${PORT}`);
});
