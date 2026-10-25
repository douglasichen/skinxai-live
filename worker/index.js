// Eczema Twin live relay: Apple Watch -> this Worker -> big-screen web page.
//   POST /api/ingest   (watch, Bearer INGEST_KEY)  {samples:[[t,m]...], windows:[...], events:[...]}
//   GET  /api/live     WebSocket for the web page (live batches + status)
//   GET  /api/events   recent scratch episodes (for "last night")
//   POST /api/reset    (Bearer INGEST_KEY) clear stored episodes
//   POST /api/analyze  ask the model (OpenRouter) about the story + live episodes; bundled fallback on the page
import { DurableObject } from "cloudflare:workers";

const json = (obj, status = 200) =>
  new Response(JSON.stringify(obj), { status, headers: { "content-type": "application/json", "access-control-allow-origin": "*" } });

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === "OPTIONS") {
      return new Response(null, { headers: { "access-control-allow-origin": "*", "access-control-allow-headers": "authorization,content-type", "access-control-allow-methods": "GET,POST,OPTIONS" } });
    }
    const room = env.ROOM.get(env.ROOM.idFromName("live-v2"));
    if (url.pathname === "/api/ingest" || url.pathname === "/api/reset") {
      const auth = request.headers.get("authorization") || "";
      if (!env.INGEST_KEY || auth !== `Bearer ${env.INGEST_KEY}`) return json({ error: "unauthorized" }, 401);
      return room.fetch(request);
    }
    if (["/api/live", "/api/events", "/api/status", "/api/label", "/api/recording", "/api/recordings"].includes(url.pathname)) return room.fetch(request);
    if (url.pathname === "/api/analyze" && request.method === "POST") return analyze(request, env);
    if (url.pathname === "/api/chat" && request.method === "POST") return chat(request, env);
    if (url.pathname === "/api/orders" && request.method === "GET") return nessieOrders(url, env);
    return env.ASSETS.fetch(request);
  },
};

export class LiveRoom extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.ctx.blockConcurrencyWhile(async () => {
      this.ctx.storage.sql.exec(`CREATE TABLE IF NOT EXISTS episodes (id TEXT PRIMARY KEY, start REAL, end REAL, seconds REAL, intense INTEGER, hz REAL, received REAL)`);
      this.ctx.storage.sql.exec(`CREATE TABLE IF NOT EXISTS rec_labels (rec_id TEXT, t REAL, action TEXT, label TEXT, phase TEXT)`);
      this.ctx.storage.sql.exec(`CREATE TABLE IF NOT EXISTS rec_batches (rec_id TEXT, received REAL, body TEXT)`);
      this.lastSeen = (await this.ctx.storage.get("lastSeen")) || null;
      this.rec = (await this.ctx.storage.get("rec")) || null;
    });
  }

  async fetch(request) {
    const url = new URL(request.url);
    if (url.pathname === "/api/live") {
      if (request.headers.get("Upgrade") !== "websocket") return json({ error: "expected websocket" }, 426);
      const pair = new WebSocketPair();
      this.ctx.acceptWebSocket(pair[1]);
      pair[1].send(JSON.stringify({ type: "hello", lastSeen: this.lastSeen, now: Date.now() / 1000 }));
      return new Response(null, { status: 101, webSocket: pair[0] });
    }
    if (url.pathname === "/api/ingest" && request.method === "POST") {
      let body;
      try { body = await request.json(); } catch { return json({ error: "bad json" }, 400); }
      const now = Date.now() / 1000;
      this.lastSeen = now;
      this.ctx.storage.put("lastSeen", now);
      const events = Array.isArray(body.events) ? body.events.slice(0, 200) : [];
      for (const e of events) {
        if (e && e.type === "end" && e.id) {
          this.ctx.storage.sql.exec(`INSERT OR REPLACE INTO episodes (id,start,end,seconds,intense,hz,received) VALUES (?,?,?,?,?,?,?)`,
            String(e.id), +e.t || now, +e.end || now, +e.seconds || 0, e.intense ? 1 : 0, +e.hz || 0, now);
        }
      }
      const batch = {
        type: "batch", receivedAt: now, sentAt: body.sentAt || null, live: !!body.live,
        backing: String(body.backing || "").slice(0, 20), appState: String(body.appState || "").slice(0, 12),
        samples: Array.isArray(body.samples) ? body.samples.slice(0, 2000) : [],
        raw: Array.isArray(body.raw) ? body.raw.slice(0, 4000) : [],
        windows: Array.isArray(body.windows) ? body.windows.slice(0, 100) : [],
        events,
      };
      // A labelled test recording is running: keep everything the watch sends (it ends itself after 15 min).
      if (this.rec && now - this.rec.start < 900) {
        this.ctx.storage.sql.exec(`INSERT INTO rec_batches (rec_id, received, body) VALUES (?,?,?)`, this.rec.id, now,
          JSON.stringify({ raw: batch.raw, windows: batch.windows, events: batch.events, sentAt: batch.sentAt }));
      }
      const msg = JSON.stringify(batch);
      for (const ws of this.ctx.getWebSockets()) { try { ws.send(msg); } catch {} }
      return json({ ok: true, clients: this.ctx.getWebSockets().length });
    }
    if (url.pathname === "/api/events") {
      const since = +(url.searchParams.get("since") || 0);
      const rows = this.ctx.storage.sql.exec(`SELECT id,start,end,seconds,intense,hz FROM episodes WHERE start >= ? ORDER BY start`, since).toArray();
      return json({ episodes: rows.map(r => ({ ...r, intense: !!r.intense })), lastSeen: this.lastSeen });
    }
    if (url.pathname === "/api/status") return json({ lastSeen: this.lastSeen, clients: this.ctx.getWebSockets().length, now: Date.now() / 1000, recording: this.rec });
    if (url.pathname === "/api/label" && request.method === "POST") {
      let b = {};
      try { b = await request.json(); } catch {}
      const now = Date.now() / 1000;
      const action = String(b.action || "step").slice(0, 16), label = String(b.label || "").slice(0, 80), phase = String(b.phase || "").slice(0, 16);
      if (action === "start") {
        this.rec = { id: new Date().toISOString().replace(/[:.]/g, "-"), start: now, name: String(b.name || "test").slice(0, 60) };
        await this.ctx.storage.put("rec", this.rec);
      }
      if (!this.rec) return json({ error: "no recording" }, 409);
      const id = this.rec.id;
      this.ctx.storage.sql.exec(`INSERT INTO rec_labels (rec_id, t, action, label, phase) VALUES (?,?,?,?,?)`, id, now, action, label, phase);
      if (action === "end") { this.rec = null; await this.ctx.storage.delete("rec"); }
      const msg = JSON.stringify({ type: "label", id, t: now, action, label, phase });
      for (const ws of this.ctx.getWebSockets()) { try { ws.send(msg); } catch {} }
      return json({ ok: true, id });
    }
    if (url.pathname === "/api/recordings") {
      const rows = this.ctx.storage.sql.exec(`SELECT rec_id, MIN(t) AS start, MAX(t) AS end, COUNT(*) AS labels FROM rec_labels GROUP BY rec_id ORDER BY start DESC LIMIT 20`).toArray();
      return json({ recordings: rows });
    }
    if (url.pathname === "/api/recording") {
      const id = url.searchParams.get("id") || "";
      const labels = this.ctx.storage.sql.exec(`SELECT t, action, label, phase FROM rec_labels WHERE rec_id = ? ORDER BY t`, id).toArray();
      const batches = this.ctx.storage.sql.exec(`SELECT received, body FROM rec_batches WHERE rec_id = ? ORDER BY received`, id).toArray()
        .map((r) => ({ received: r.received, ...JSON.parse(r.body) }));
      return json({ id, labels, batches });
    }
    if (url.pathname === "/api/reset" && request.method === "POST") {
      this.ctx.storage.sql.exec(`DELETE FROM episodes`);
      const msg = JSON.stringify({ type: "reset" });
      for (const ws of this.ctx.getWebSockets()) { try { ws.send(msg); } catch {} }
      return json({ ok: true });
    }
    return json({ error: "not found" }, 404);
  }

  async webSocketMessage(ws, message) {
    if (message === "ping") ws.send(JSON.stringify({ type: "pong", lastSeen: this.lastSeen, now: Date.now() / 1000 }));
  }
  async webSocketClose(ws, code) { try { ws.close(code, "bye"); } catch {} }
}

async function analyze(request, env) {
  if (!env.OPENROUTER_KEY) return json({ error: "no key" }, 503);
  let body = {};
  try { body = await request.json(); } catch {}
  const model = body.model || env.ANALYSIS_MODEL || "anthropic/claude-sonnet-5.5";
  const system = `You are the trigger-finding assistant inside SkinXAI. You get a nightly log for one person: minutes of scratching during sleep measured by their Apple Watch, sleep, humidity, and anything that changed. Find their most likely personal flare trigger. Consider 1-3 day delays, check whether each change came before or after the rise began, and rule things out when the timing does not fit. Sleep loss during a flare is usually a result of scratching, not a cause. Use confidence low/medium/high honestly; never diagnose. Talk to the person directly ("you"). Reply with JSON only, no prose around it: {"summary": "2-3 plain sentences", "suspects": [{"title": "at most 4 words", "confidence": "low|medium|high", "lag": "at most 6 words", "evidence": "at most 2 short sentences"}] (2-3 suspects, most likely first), "nextStep": "one or two sentences: a simple test to confirm"}`;
  const ask = async () => {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 25000);
    try {
      const r = await fetch("https://openrouter.ai/api/v1/chat/completions", {
        method: "POST", signal: controller.signal,
        headers: { authorization: `Bearer ${env.OPENROUTER_KEY}`, "content-type": "application/json" },
        body: JSON.stringify({ model, max_tokens: 1500, temperature: 0.3, messages: [{ role: "system", content: system }, { role: "user", content: JSON.stringify(body.log || {}) }] }),
      });
      const j = await r.json();
      const text = (j.choices && j.choices[0] && j.choices[0].message && j.choices[0].message.content) || "";
      const a = text.indexOf("{"), b = text.lastIndexOf("}");
      if (a < 0 || b <= a) throw new Error(`no json (${r.status}) ${text.slice(0, 80)}`);
      return JSON.parse(text.slice(a, b + 1));
    } finally { clearTimeout(timer); }
  };
  let last;
  for (let attempt = 0; attempt < 2; attempt++) {
    try { return json({ model, caseFile: await ask() }); } catch (e) { last = e; if (String(e).includes("abort")) break; }
  }
  return json({ error: "analysis failed", detail: String(last).slice(0, 160) }, 502);
}

// ---------- Claude chat (the "Claude" page): real model, our tools, steered by instructions ----------
// The page runs the tools itself (the data lives in web/story.js) and sends the conversation back;
// this endpoint only adds the instructions and tool list and asks the model for its next turn.
const CHAT_MODELS = ["anthropic/claude-opus-5.5", "anthropic/claude-sonnet-5.5", "anthropic/claude-haiku-5.5", "deepseek/deepseek-v4.1-flash"];

const CHAT_SYSTEM = (today) => `You are Claude, connected to SkinXAI: an app that measures how much a person scratches in their sleep with their Apple Watch. You are talking with Douglas, a 21-year-old student with eczema, inside the Eczema Twin app. Today is ${today}.
The app has three pages. Summary shows whether last night was normal and lists possible triggers. Trends shows his nights as charts. You are Insight: you help him narrow the possible triggers down by elimination, using his data.

How you write (strict):
- Each reply is ONE short sentence (at most 15 words), or one short sentence plus a short list (at most 4 items, each a few words).
- Say only what he needs right now. No background lectures, no repeating what a card already shows, no markdown headings.
- Use the exact product names from order_history (e.g. "Brightwell Ocean Breeze Body Wash"), never just "body wash".
- Never give a diagnosis; you look for patterns in his data.
Every reply starts with that short text before any tool call. Until you have called show_conclusion, every reply must also call a tool: if you say you will check or ask something, do it with a tool call in that same reply.

What you may ask: ONLY what his data can't tell you. The tools already give you his scratching, purchases (dates, ingredients, materials, repeat or new), weather, calendar, sleep and HRV. HRV is his stress level: never ask about stress, exams, sleep, weather or what he bought. Good questions are about what isn't in the data: where the itch is worst, whether he washed new clothing before wearing it, whether he actually uses a product every day.
Ask ONE question per turn with ask_user (never two in the same turn), a few words long, with 2-3 short answer options.

When he asks why his eczema is bad:
1. Gather data first: call scratch_history, order_history, weather_history, calendar_events and sleep_history (several in one turn is fine).
2. Find what changed one to three days before his scratching started rising. New things that touch the skin every day (soaps, body wash, lotion, detergent, clothing) are the prime suspects; a first purchase is more suspicious than a repeat.
3. Call show_timeline to mark that change and show_product for that product (its exact name).
4. Rule the rest out. Use the data for what it can answer (repeat detergent, HRV, humidity) and ask at most 2 short questions for what it can't. After each answer, one short sentence on what it rules in or out, then the next step in the same reply.
5. Call show_conclusion exactly once: the most likely cause, your confidence, what you ruled out with a one-line reason each, and a simple test (stop that product for 5 nights while the watch keeps measuring). Then one short closing sentence.
If he asks about an earlier flare instead (for example the one about two weeks before this one), work the same way with 30 nights of data. When two new things were bought on the same day just before it (for example a new piece of clothing and a new laundry detergent), say in one sentence that the data alone can't separate them, then ask, one per turn, using the flare's exact nights from the data (e.g. "Oct 6-9"):
a. "Did you use the [exact detergent name] only on [flare nights]?" with options like "Yes, only then" / "No, kept using it after".
b. "Did you wear the [exact clothing name] only on [flare nights]?" with options like "Yes, only then" / "No, wore it after too".
Whatever he kept using after the flare ended without scratching is ruled out; what he used only on the flare nights is the suspect. So a = no, b = yes points to the clothing; a = yes, b = no points to the detergent. Only if both are yes, ask one last question: where the itch was worst (only where the garment touched, or everywhere clothes and sheets touch). If both are no, say neither fits and look again. Comment on each answer in one short sentence, call show_timeline for that change, and finish with show_conclusion.
Never start this process on your own: only when he asks.
Only use facts returned by the tools. If an answer points somewhere else, take it seriously and say in one sentence what would tell the two apart.`;

// The "mi" story (app build 18+ sends story: "mi"): four short flares over 74 nights, each after a
// different new product; the shared cause is hidden in the ingredient lists. Claude must find it.
const CHAT_SYSTEM_MI = (today) => `You are Claude, connected to SkinXAI: an app that measures how much a person scratches in their sleep with their Apple Watch. You are talking with Douglas, a 21-year-old student with eczema, inside the Eczema Twin app. Today is ${today}.
The app has three pages. Summary shows whether last night was normal and lists possible triggers. Trends shows his nights as charts. You are Insight: you find what is really behind his flares, using all of his data, by elimination.

How you write (strict):
- Each reply is ONE short sentence (at most 15 words), or one short sentence plus a short list (at most 4 items, each a few words). The one exception is the sentence in step 6 that names the shared ingredient.
- Say only what he needs right now. No background lectures, no repeating what a card already shows, no markdown headings.
- Use exact product names from order_history. Write dates like "Sep 27", never 2026-09-27.
- Never give a diagnosis; you look for patterns in his data and suggest how to confirm them.
Every reply starts with that short text before any tool call. Until you have called show_conclusion, every reply must also call a tool: if you say you will check or ask something, do it with a tool call in that same reply.

What you may ask: ONLY what his data can't tell you. The tools give you his scratching, purchases (dates, ingredients, materials, new or repeat), weather, calendar, sleep and HRV (his stress level). Never ask about stress, exams, sleep, weather, travel dates or what he bought. Good questions are about use, which the data can't see: whether he stopped using a product, whether he still uses or wears something, where the itch was.
Ask ONE question per turn with ask_user (never two in the same turn), a few words long, with 2-3 short answer options.

When he asks why his eczema is bad (or about any flare):
1. Gather ALL the data first: scratch_history with 74 nights, order_history with 120 days, weather_history with 74 days, calendar_events with 120 days, sleep_history with 74 nights (all in one turn).
2. Find every flare in the whole history, not only the current one, and what was new in the 1-3 days before each.
3. Test the obvious explanations against ALL flares and all calm nights: a single product, a product type, fragrance, wool, stress (HRV, exams), dry air, travel. An explanation survives only if it is present before every flare and absent (or tolerated) on calm stretches; things he uses every day without flaring are tolerated. Compare ingredient lists across the flare products and the products he tolerates, and treat chemical name variants of the same substance as one.
4. Call show_timeline once with markers for each flare's new product so he sees the pattern. In that reply, say only that each flare followed a new product. Do NOT name the shared ingredient yet.
5. Before naming any cause, look for anything in the data that contradicts your best explanation, for example a product that fits it but was not followed by a flare. The data only shows purchases, not use. Say plainly that this product doesn't seem to follow the pattern, then ask whether he actually used it (ask_user, short options such as "Yes, regularly" / "Only once or twice" / "No, never opened"). Still do NOT name the ingredient in this turn. ask_user must be the ONLY tool call in that reply: no cards, no conclusion; stop and wait for his answer.
6. Your reply right after his answer is text plus ONE card, show_product for the most suspicious item. Its text (never empty) is exactly this form: "You had [N] flares right after buying these [N] different products that share this ingredient: [ingredient]." then a short list of the [N] products, then one short sentence on what his answer about the exception means. No show_conclusion in this reply.
7. In the next reply, one short sentence, then show_conclusion exactly once: the most likely cause (it may be an ingredient rather than a product), your confidence, what you ruled out with a reason of a few words each, and next_step: exactly ONE action in one short sentence. When the cause is an ingredient, the action covers every product that contains it, not just the latest one (for example "Stop using every product that lists [ingredient], including these [N] and [any unused one], and let your watch track the next 5 nights."). One call to action only: no second suggestion, no "also", and don't repeat it anywhere else. The conclusion card ends the conversation: write nothing after it.
Never start this process on your own: only when he asks.
Only use facts returned by the tools. If an answer points somewhere else, take it seriously and say in one sentence what would tell the two apart.`;

const CHAT_TOOLS = [
  { name: "scratch_history", description: "Minutes of scratching measured by the Apple Watch for each of the last nights, plus his usual level.", parameters: { type: "object", properties: { nights: { type: "integer", description: "How many nights, up to 30" } }, required: ["nights"] } },
  { name: "order_history", description: "His online orders (Amazon): exact product name, category, purchase date, whether he bought it before, and ingredients or material when listed.", parameters: { type: "object", properties: { days: { type: "integer" } }, required: ["days"] } },
  { name: "weather_history", description: "Daily outdoor humidity and temperature where he lives.", parameters: { type: "object", properties: { days: { type: "integer" } }, required: ["days"] } },
  { name: "calendar_events", description: "Events from his calendar (exams, travel, deadlines).", parameters: { type: "object", properties: { days: { type: "integer" } }, required: ["days"] } },
  { name: "sleep_history", description: "Hours of sleep, wake-ups and HRV (heart-rate variability, ms; lower = more stress) per night from Apple Health, plus his usual HRV.", parameters: { type: "object", properties: { nights: { type: "integer" } }, required: ["nights"] } },
  { name: "show_timeline", description: "Show his nightly scratching chart as a card in the conversation, with one change marked on it.", parameters: { type: "object", properties: { marker_date: { type: "string", description: "YYYY-MM-DD of the change" }, marker_label: { type: "string", description: "Short label with the product name, e.g. 'Bought Brightwell Ocean Breeze Body Wash'" }, note: { type: "string", description: "One short sentence about the timing (at most 12 words)" } }, required: ["marker_date", "marker_label"] } },
  { name: "show_product", description: "Show the suspected product as a card in the conversation.", parameters: { type: "object", properties: { name: { type: "string", description: "The exact product name from order_history" }, purchase_date: { type: "string" }, flagged_ingredients: { type: "array", items: { type: "string" } }, note: { type: "string" } }, required: ["name", "purchase_date"] } },
  { name: "ask_user", description: "Ask Douglas one short question (a few words) with 2-3 short answer buttons. Only ask what the data can't tell. The result is his answer.", parameters: { type: "object", properties: { question: { type: "string" }, options: { type: "array", items: { type: "string" }, minItems: 2, maxItems: 3 } }, required: ["question", "options"] } },
  { name: "show_conclusion", description: "Show the conclusion as a card in the conversation. Call it once.", parameters: { type: "object", properties: { cause: { type: "string", description: "The most likely cause in at most 8 words, with the product name, e.g. 'Brightwell Ocean Breeze Body Wash'" }, confidence: { type: "string", enum: ["low", "medium", "high"] }, ruled_out: { type: "array", minItems: 2, description: "Each explanation you ruled out (e.g. the detergent, stress via HRV, the dry air), with a reason of a few words", items: { type: "object", properties: { item: { type: "string" }, reason: { type: "string" } }, required: ["item", "reason"] } }, next_step: { type: "string" } }, required: ["cause", "confidence", "ruled_out", "next_step"] } },
].map((f) => ({ type: "function", function: f }));

const CHAT_TOOLS_MI = CHAT_TOOLS.map((t) => {
  const f = JSON.parse(JSON.stringify(t.function));
  if (f.name === "scratch_history") f.parameters.properties.nights.description = "How many nights, up to 74";
  if (["weather_history", "sleep_history", "calendar_events", "order_history"].includes(f.name)) {
    const k = Object.keys(f.parameters.properties)[0];
    f.parameters.properties[k].description = f.name === "order_history" || f.name === "calendar_events" ? "How many days, up to 120" : "How many, up to 74";
  }
  if (f.name === "show_timeline") {
    f.description = "Show his nightly scratching chart as a card in the conversation, with one or more changes marked on it.";
    f.parameters = { type: "object", properties: {
      markers: { type: "array", minItems: 1, description: "Each change to mark", items: { type: "object", properties: {
        date: { type: "string", description: "YYYY-MM-DD" }, label: { type: "string", description: "Short label, e.g. the product name" } }, required: ["date", "label"] } },
      note: { type: "string", description: "One short sentence (at most 12 words)" } }, required: ["markers"] };
  }
  if (f.name === "show_conclusion") {
    f.parameters.properties.cause.description = "The most likely cause in at most 8 words (a product or an ingredient)";
    f.parameters.properties.next_step = { type: "string", description: "Exactly one action, one short sentence. The only call to action in the conversation." };
  }
  return { type: "function", function: f };
});

async function chat(request, env) {
  if (!env.OPENROUTER_KEY) return json({ error: "no key" }, 503);
  let body = {};
  try { body = await request.json(); } catch { return json({ error: "bad json" }, 400); }
  const model = CHAT_MODELS.includes(body.model) ? body.model : CHAT_MODELS[0];
  const mi = body.story === "mi";
  const today = /^[A-Za-z]+, [A-Za-z]+ \d{1,2}, \d{4}$/.test(body.today || "") ? body.today : new Date().toDateString();
  const raw = Array.isArray(body.messages) ? body.messages.slice(-80) : [];
  let size = 0;
  const messages = [];
  for (const m of raw) {
    if (!m || !["user", "assistant", "tool"].includes(m.role)) continue;
    const content = typeof m.content === "string" ? m.content.slice(0, 12000) : "";
    size += content.length;
    const out = { role: m.role, content };
    if (m.role === "assistant" && Array.isArray(m.tool_calls)) {
      out.tool_calls = m.tool_calls.slice(0, 8).map((c) => ({ id: String(c.id).slice(0, 80), type: "function",
        function: { name: String(c.function && c.function.name).slice(0, 40), arguments: String(c.function && c.function.arguments || "{}").slice(0, 4000) } }));
    }
    if (m.role === "tool") out.tool_call_id = String(m.tool_call_id || "").slice(0, 80);
    messages.push(out);
  }
  if (!messages.length || size > 80000) return json({ error: "bad conversation" }, 400);
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 40000);
  try {
    const message = await chatTurn(env.OPENROUTER_KEY, model, today, mi, messages, controller.signal);
    return json({ model, message });
  } catch (e) {
    return json({ error: "chat failed", detail: String(e).slice(0, 160) }, 502);
  } finally { clearTimeout(timer); }
}

// One assistant turn. A question ends the turn (anything queued after ask_user waits for his answer).
// In the "mi" story, the reply right after he answers a question must say something before any card: if the
// model sends only cards, ask it once more for just the words (no tools) and send them with those cards.
async function chatTurn(key, model, today, mi, messages, signal) {
  const ask = async (msgs, toolChoice) => {
    const r = await fetch("https://openrouter.ai/api/v1/chat/completions", {
      method: "POST", signal,
      headers: { authorization: `Bearer ${key}`, "content-type": "application/json" },
      body: JSON.stringify({ model, temperature: 0.3, max_tokens: 2500, tools: mi ? CHAT_TOOLS_MI : CHAT_TOOLS, tool_choice: toolChoice,
        messages: [{ role: "system", content: mi ? CHAT_SYSTEM_MI(today) : CHAT_SYSTEM(today) }, ...msgs] }),
    });
    const j = await r.json();
    const msg = j.choices && j.choices[0] && j.choices[0].message;
    if (!msg) throw new Error(`no reply ${r.status} ${JSON.stringify(j).slice(0, 120)}`);
    return { content: (msg.content || "").trim(), calls: msg.tool_calls || [] };
  };
  const endAtQuestion = (calls) => {
    const k = calls.findIndex((c) => c && c.function && c.function.name === "ask_user");
    return k >= 0 ? calls.slice(0, k + 1) : calls;
  };
  let { content, calls } = await ask(messages, "auto");
  const last = messages[messages.length - 1];
  const prev = [...messages].reverse().find((m) => m.role === "assistant");
  const afterAnswer = last && last.role === "tool" && prev && (prev.tool_calls || []).some((c) => c.function && c.function.name === "ask_user");
  if (mi && afterAnswer && !content && calls.length) {
    const words = await ask(messages, "none").catch(() => null);
    if (words && words.content) content = words.content;
  }
  return { role: "assistant", content, tool_calls: endAtQuestion(calls) };
}

// ---------- Capital One Nessie: order history for Claude's order_history tool ----------
// GET /api/orders?days=N reads the demo person's purchases from Nessie (NESSIE_KEY and NESSIE_ACCOUNT_ID are
// Worker secrets, never sent to the phone) and joins each purchase with our product catalog for ingredients,
// which Nessie doesn't have. Same JSON shape as the app's bundled order_history tool.
import nessieCatalog from "./nessie-products.json";

async function nessieOrders(url, env) {
  if (!env.NESSIE_KEY || !env.NESSIE_ACCOUNT_ID) return json({ error: "nessie not configured" }, 503);
  const days = Math.min(Math.max(parseInt(url.searchParams.get("days") || "120", 10) || 120, 1), 120);
  const since = new Date(Date.now() - days * 86400000).toISOString().slice(0, 10);
  const r = await fetch(`https://prod-api.nessieisreal.com/accounts/${env.NESSIE_ACCOUNT_ID}/purchases?key=${env.NESSIE_KEY}`);
  if (!r.ok) return json({ error: `nessie ${r.status}` }, 502);
  const rows = (await r.json()).sort((a, b) => a.purchase_date.localeCompare(b.purchase_date));
  const seen = new Set(), orders = [];
  for (const p of rows) {
    const item = p.description || "";
    if (p.purchase_date < since) { seen.add(item); continue; }
    const product = nessieCatalog.products[item] || {};
    const o = { date: p.purchase_date, item, category: product.category || "unknown", bought_before: seen.has(item), amount: p.amount };
    if (product.ingredients) o.ingredients = product.ingredients;
    if (product.material) o.material = product.material;
    orders.push(o);
    seen.add(item);
  }
  return json({ source: "Capital One Nessie (purchases) + SkinXAI product catalog (ingredients)", orders });
}

