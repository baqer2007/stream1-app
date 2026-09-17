const { onRequest } = require('firebase-functions/v2/https');
const { logger } = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();

const MODEL = process.env.GEMINI_MODEL || 'gemini-3.6-flash';
const API_KEY = process.env.GEMINI_API_KEY;

const allowedOrigins = true;

function cors(req, res) {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
}

function safeArray(value) {
  if (!Array.isArray(value)) return [];
  return value.map(v => String(v || '').trim()).filter(Boolean).slice(0, 12);
}

function extractJson(text) {
  const raw = String(text || '').trim();
  try { return JSON.parse(raw); } catch (_) {}
  const fenced = raw.match(/```(?:json)?\\s*([\\s\\S]*?)\\s*```/i);
  if (fenced) {
    try { return JSON.parse(fenced[1]); } catch (_) {}
  }
  const first = raw.indexOf('{');
  const last = raw.lastIndexOf('}');
  if (first >= 0 && last > first) {
    try { return JSON.parse(raw.slice(first, last + 1)); } catch (_) {}
  }
  return null;
}

function fallbackPlan(message, language) {
  return {
    reply: language === 'ar'
      ? 'سأبحث داخل مكتبة ONEBR عن أقرب النتائج لطلبك.'
      : 'I will search the ONEBR library for the closest matches to your request.',
    queries: [message],
    genres: [],
    keywords: [],
    mediaType: null,
    year: null,
  };
}

exports.onebrAi = onRequest(
  { region: 'us-central1', cors: allowedOrigins, timeoutSeconds: 30, memory: '256MiB', secrets: ['GEMINI_API_KEY'] },
  async (req, res) => {
    cors(req, res);

    if (req.method === 'OPTIONS') {
      return res.status(204).send('');
    }
    if (req.method !== 'POST') {
      return res.status(405).json({ error: 'POST only' });
    }

    try {
      const authHeader = String(req.headers.authorization || '');
      if (!authHeader.startsWith('Bearer ')) {
        return res.status(401).json({ error: 'Authentication required' });
      }

      const idToken = authHeader.substring(7);
      await admin.auth().verifyIdToken(idToken);

      if (!API_KEY) {
        logger.error('GEMINI_API_KEY is not configured');
        return res.status(503).json({ error: 'AI backend is not configured' });
      }

      const body = req.body || {};
      const message = String(body.message || '').trim();
      const language = body.language === 'en' ? 'en' : 'ar';
      const history = Array.isArray(body.history) ? body.history.slice(-10) : [];

      if (!message) {
        return res.status(400).json({ error: 'message is required' });
      }

      const historyText = history.map(item => {
        const role = item && item.role === 'assistant' ? 'assistant' : 'user';
        return `${role}: ${String(item && item.text || '').slice(0, 500)}`;
      }).join('\n');

      const systemPrompt = `You are ONEBR AI, a movie and TV discovery assistant.
Your job is to understand the user's natural-language request and convert it into a search plan for an existing movie/series library.
Never invent availability. Never claim a title exists in the ONEBR library. Do not output fake ratings, cast, links, or streaming sources.
The client will perform the actual library search after you return the plan.
Understand Arabic dialects and English. Handle follow-up context from the conversation.
For similarity requests, generate useful semantic search phrases describing the requested work, genre, themes, tone, era, and related concepts.
For recommendations, create several search queries rather than naming imaginary titles.
Return ONLY valid JSON matching the requested schema.`;

      const userPrompt = `Language: ${language}\nConversation history:\n${historyText || '(none)'}\n\nLatest user request:\n${message}`;

      const endpoint = `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(MODEL)}:generateContent`;
      const payload = {
        systemInstruction: { parts: [{ text: systemPrompt }] },
        contents: [{ role: 'user', parts: [{ text: userPrompt }] }],
        generationConfig: {
          temperature: 0.25,
          responseMimeType: 'application/json',
          responseSchema: {
            type: 'OBJECT',
            properties: {
              reply: { type: 'STRING' },
              queries: { type: 'ARRAY', items: { type: 'STRING' } },
              genres: { type: 'ARRAY', items: { type: 'STRING' } },
              keywords: { type: 'ARRAY', items: { type: 'STRING' } },
              mediaType: { type: 'STRING', nullable: true },
              year: { type: 'INTEGER', nullable: true },
            },
            required: ['reply', 'queries', 'genres', 'keywords'],
          },
        },
      };

      const aiResponse = await fetch(endpoint, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-goog-api-key': API_KEY,
        },
        body: JSON.stringify(payload),
      });

      if (!aiResponse.ok) {
        const errorText = await aiResponse.text();
        logger.error('Gemini request failed', { status: aiResponse.status, body: errorText.slice(0, 1000) });
        return res.status(502).json(fallbackPlan(message, language));
      }

      const data = await aiResponse.json();
      const text = data?.candidates?.[0]?.content?.parts?.map(p => p.text || '').join('') || '';
      const parsed = extractJson(text);

      if (!parsed || typeof parsed !== 'object') {
        return res.json(fallbackPlan(message, language));
      }

      const result = {
        reply: String(parsed.reply || '').trim() || fallbackPlan(message, language).reply,
        queries: safeArray(parsed.queries),
        genres: safeArray(parsed.genres),
        keywords: safeArray(parsed.keywords),
        mediaType: parsed.mediaType === 'movie' || parsed.mediaType === 'series' ? parsed.mediaType : null,
        year: Number.isInteger(parsed.year) ? parsed.year : null,
      };

      if (result.queries.length === 0) result.queries = [message];
      return res.json(result);
    } catch (error) {
      logger.error('ONEBR AI error', error);
      return res.status(500).json({ error: 'AI request failed' });
    }
  }
);
