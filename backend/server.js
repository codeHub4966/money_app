import 'dotenv/config';
import express from 'express';
import cors from 'cors';

const app = express();
app.use(cors());
// Raised from 2mb to fit a base64-encoded receipt photo (the client only
// sends one when the user explicitly opts into the AI check). The image is
// used only for this one request and is never written to disk.
app.use(express.json({ limit: '15mb' }));

const PORT = process.env.PORT || 8787;
const GEMINI_API_KEY = process.env.GEMINI_API_KEY;
const GEMINI_MODEL = process.env.GEMINI_MODEL || 'gemini-3.6-flash';
// Kept below the client's 15s AI timeout (see ReceiptAiConfig.timeout) so
// this backend can still return a clean error response before the client
// gives up and falls back to the local OCR/parser result.
const GEMINI_TIMEOUT_MS = 12_000;

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

  const {
    ocrText,
    lowConfidenceFields,
    categories,
    wallets,
    merchant,
    items,
    localAmount,
    localDate,
    localCategory,
    localWallet,
    imageBase64,
    imageMimeType,
  } = req.body ?? {};

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
  const safeMerchant = typeof merchant === 'string' && merchant.trim().length > 0 ? merchant.trim() : null;
  const safeItems = Array.isArray(items)
    ? items.filter((i) => typeof i === 'string' && i.trim().length > 0)
    : [];
  const safeLocalAmount = typeof localAmount === 'number' && Number.isFinite(localAmount) ? localAmount : null;
  const safeLocalDate = typeof localDate === 'string' && localDate.trim().length > 0 ? localDate.trim() : null;
  const safeLocalCategory =
    typeof localCategory === 'string' && localCategory.trim().length > 0 ? localCategory.trim() : null;
  const safeLocalWallet =
    typeof localWallet === 'string' && localWallet.trim().length > 0 ? localWallet.trim() : null;
  // The image, when present, is used only for this one request (passed
  // straight through to Gemini) and is never written to disk or retained.
  const safeImageBase64 = typeof imageBase64 === 'string' && imageBase64.trim().length > 0 ? imageBase64 : null;
  const safeImageMimeType =
    typeof imageMimeType === 'string' && imageMimeType.trim().length > 0 ? imageMimeType.trim() : 'image/jpeg';

  const prompt = buildPrompt({
    ocrText,
    lowConfidenceFields: safeLowConfidenceFields,
    categories: safeCategories,
    wallets: safeWallets,
    merchant: safeMerchant,
    items: safeItems,
    localAmount: safeLocalAmount,
    localDate: safeLocalDate,
    localCategory: safeLocalCategory,
    localWallet: safeLocalWallet,
    hasImage: Boolean(safeImageBase64),
  });

  try {
    const geminiJson = await callGemini(prompt, {
      imageBase64: safeImageBase64,
      imageMimeType: safeImageMimeType,
    });
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

function buildPrompt({
  ocrText,
  lowConfidenceFields,
  categories,
  wallets,
  merchant,
  items,
  localAmount,
  localDate,
  localCategory,
  localWallet,
  hasImage,
}) {
  return `You are extracting structured data from a retail receipt for a personal finance app.

The receipt was already OCR-scanned and parsed locally. The local parser was NOT confident about
these fields: ${lowConfidenceFields.length > 0 ? lowConfidenceFields.join(', ') : '(none listed)'}.
${hasImage
    ? `The user has explicitly asked you to visually re-check the ENTIRE receipt against the attached
photo — this is a full verification pass, not just a fix for the low-confidence fields above. The
local parser's values below (including ones it was confident about) may still be wrong — for
example it can misread a tax or service-charge line as the grand total. Trust what you can actually
read in the image over both the OCR text and the local parser's values whenever they conflict.`
    : 'No receipt image was provided — work only from the OCR text below.'}

STRUCTURED CONTEXT ALREADY EXTRACTED LOCALLY (may be wrong — verify against the image/OCR text):
- amount: ${localAmount != null ? localAmount : '(not identified locally)'}
- date: ${localDate ? localDate : '(not identified locally)'}
- merchant: ${merchant ? merchant : '(not identified locally)'}
- category: ${localCategory ? localCategory : '(not identified locally)'}
- wallet/payment: ${localWallet ? localWallet : '(not identified locally)'}
- purchased items: ${items && items.length > 0 ? items.join(', ') : '(none extracted locally)'}

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
   none fit. Never invent a new category name. When choosing it, prioritize evidence in this order:
   (a) the merchant identity, (b) the purchased items, (c) the overall receipt context/OCR text as a
   last resort. Ignore payment/footer text entirely for this decision — words like "CASH", "VISA",
   "MASTERCARD", "MAYBANK", card numbers, receipt/invoice numbers, "THANK YOU", etc. say nothing about
   what was purchased and must not influence the category. Return null rather than guess if the
   merchant and items don't clearly support any single listed category.
3. "suggested_wallet" must be exactly one string from the EXISTING WALLETS list above, or null. Only
   return a wallet if the receipt contains a clear payment clue (e.g. "CASH", "VISA", "MASTERCARD", a
   bank name, "Touch 'n Go", "TNG", "DuitNow", "GrabPay", "Boost", "ShopeePay", card last-4 digits, etc.)
   that reliably maps to one of the listed wallets. A generic card network alone (VISA/Mastercard/Debit/
   Credit) is NOT sufficient evidence unless exactly one listed wallet could plausibly be it — if more
   than one wallet could match, or the clue is ambiguous, return null. Never invent a wallet name that
   isn't in the list.
4. "transaction_date" must be an ISO 8601 date string ("YYYY-MM-DD"), or null if not found.
5. "total_amount" must be a plain number (no currency symbol), or null if not found.
6. "currency" is a best-effort 3-letter ISO code (e.g. "MYR", "USD") if identifiable, else null.
7. "merchant" is the business/store name, or null if not identifiable.

Respond with ONLY a single JSON object with exactly these keys, no markdown, no explanation:
${JSON.stringify(RECEIPT_FIELDS)}`;
}

// Entry point: starts a single overall deadline that covers every attempt,
// the retry delay, and the retry request itself — a 503 retry must NOT get
// a fresh full timeout, or the combined wait can blow past the client's 15s
// budget (see ReceiptAiConfig.timeout) and abandon the response anyway.
async function callGemini(prompt, imageOptions = {}) {
  const deadline = Date.now() + GEMINI_TIMEOUT_MS;
  return callGeminiWithDeadline(prompt, imageOptions, deadline, 1);
}

async function callGeminiWithDeadline(prompt, { imageBase64, imageMimeType } = {}, deadline, attempt) {
  const remaining = deadline - Date.now();
  if (remaining <= 0) {
    const error = new Error('Gemini request budget exhausted.');
    error.name = 'AbortError';
    throw error;
  }

  const url = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${GEMINI_API_KEY}`;

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), remaining);

  const parts = [{ text: prompt }];
  if (imageBase64) {
    parts.push({ inlineData: { mimeType: imageMimeType || 'image/jpeg', data: imageBase64 } });
  }

  try {
    const response = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        contents: [{ role: 'user', parts }],
        generationConfig: {
          temperature: 0,
          responseMimeType: 'application/json',
        },
      }),
      signal: controller.signal,
    });

    if (!response.ok) {
      // 503 from Gemini means "temporarily overloaded, retry shortly" per
      // Google's own error message — worth one quick retry, but only if
      // there's still enough of the ORIGINAL budget left; the retry shares
      // the same deadline rather than starting a fresh timeout.
      const retryDelayMs = 1000;
      if (response.status === 503 && attempt < 2 && deadline - Date.now() > retryDelayMs + 500) {
        clearTimeout(timeout);
        await new Promise((r) => setTimeout(r, retryDelayMs));
        return callGeminiWithDeadline(prompt, { imageBase64, imageMimeType }, deadline, attempt + 1);
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
