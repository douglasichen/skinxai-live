// Claude (#p-claude): a real conversation with Claude through /api/chat, laid out like Claude.ai (thread left,
// artifacts right). The Worker adds the instructions and the tool list; this page runs the tools (data in
// window.twinStory), draws the artifacts and puts Claude's questions to Douglas. See POLISH-SPEC.md §3.4.
// Keys on this page: Enter sends · R new conversation · P replays the last completed conversation (no network).
// ?model=deepseek/deepseek-v4.1-flash talks to a cheaper model while developing.
(() => {
  const $ = (s, root = document) => root.querySelector(s);
  const S = window.twinStory, { api, esc, sleep } = window.twinUI;
  const MODEL = new URLSearchParams(location.search).get("model") || "";
  const DEFAULT_MODEL = "anthropic/claude-sonnet-5.5";
  const STARTER = "My eczema has been really bad the last few nights. Can you look at my scratching history and help me figure out why?";
  const NUDGE = "Go ahead";        // the suggested reply when Claude stops before its conclusion (see offerNudge)
  const SAVE_KEY = "twinChat";     // localStorage: the last completed conversation of each model ("twinChat:<model>")
  const CPS = 80;                  // typewriter speed, characters per second
  const CARD_MS = 600;             // every tool card spins at least this long, so it can be read
  const THINK_MS = 600;            // "Claude is thinking…" never just flashes
  const TIMEOUT_MS = 45000;
  const calm = matchMedia("(prefers-reduced-motion: reduce)").matches;

  const page = $("#p-claude"), chat = $("#chat"), thread = $("#thread"), feed = $("#feed");
  const input = $("#chatInput"), sendBtn = $("#chatSend");
  const el = (tag, cls, html) => { const e = document.createElement(tag); if (cls) e.className = cls; if (html != null) e.innerHTML = html; return e; };
  const nextPaint = () => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));

  // ---------- icons (drawn here; no logo files) ----------
  const icon = (paths, w = 1.8) => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${paths}</svg>`;
  // Claude's sparkle: eight rounded rays, alternately long and short.
  const SPARK = icon([0, 1, 2, 3, 4, 5, 6, 7].map((k) => {
    const a = (k * Math.PI) / 4, r = k % 2 ? 6.4 : 9.6;
    return `<path d="M12 12L${(12 + r * Math.sin(a)).toFixed(2)} ${(12 - r * Math.cos(a)).toFixed(2)}"/>`;
  }).join(""), 2.6);
  const CHECK = icon('<path d="M5 12.5l4.5 4.5L19 7.5"/>', 2.8);
  const SERVERS = {   // [colour, icon]
    eczema_twin: ["var(--lime)", '<circle cx="9" cy="12" r="5.2"/><circle cx="15" cy="12" r="5.2"/>'],
    amazon: ["var(--orange)", '<path d="M4 7.6 12 4l8 3.6v8.8L12 20l-8-3.6z"/><path d="M4 7.6l8 3.6 8-3.6M12 11.2V20"/>'],
    weather: ["var(--cyan)", '<path d="M12 3.6c3.1 4.2 5.9 7.3 5.9 10.6a5.9 5.9 0 0 1-11.8 0c0-3.3 2.8-6.4 5.9-10.6z"/>'],
    google_calendar: ["var(--yellow)", '<rect x="4" y="5.5" width="16" height="14.5" rx="2.5"/><path d="M4 10.2h16M8.5 3.5v4M15.5 3.5v4"/>'],
    apple_health: ["var(--pink)", '<path d="M12 19.6s-7.2-4.4-7.2-9.8A3.9 3.9 0 0 1 12 7.7a3.9 3.9 0 0 1 7.2 2.1c0 5.4-7.2 9.8-7.2 9.8z"/>'],
  };
  const TOOL_SERVER = { scratch_history: "eczema_twin", order_history: "amazon", weather_history: "weather", calendar_events: "google_calendar", sleep_history: "apple_health" };
  const ART = {   // the artifact tools: colour, icon, page in the panel
    show_timeline: { color: "var(--pink)", page: 0, icon: '<path d="M4.5 20v-8M9.5 20V8M14.5 20v-5M19.5 20V4"/>' },
    show_product: { color: "var(--orange)", page: 0, icon: '<path d="M9.5 3.5h5M12 3.5V7"/><rect x="9.5" y="7" width="5" height="3" rx="1"/><rect x="6.5" y="10" width="11" height="10.5" rx="2.6"/>' },
    show_conclusion: { color: "var(--lime)", page: 1, icon: '<circle cx="12" cy="12" r="8.5"/><path d="M8.3 12.3l2.6 2.6 4.9-5.4"/>' },
  };

  // ---------- small formatting helpers ----------
  const day = (iso) => { const [y, m, d] = String(iso).split("-").map(Number); return y && m && d ? new Date(y, m - 1, d) : null; };
  const md = (iso) => { const d = day(iso); return d ? S.md(d) : String(iso); };
  const span = (s) => {   // "2026-10-10 to 2026-10-12" → "Oct 10–12"
    const [a, b] = String(s).split(" to ");
    if (!b) return md(a);
    const [ma, da] = md(a).split(" "), [mb, db] = md(b).split(" ");
    return ma === mb ? `${ma} ${da}–${db}` : `${md(a)} – ${md(b)}`;
  };
  const count = (k, word) => `${k} ${word}${k === 1 ? "" : "s"}`;
  const cap = (s) => s.charAt(0).toUpperCase() + s.slice(1);
  const modelName = (id) => id.split("/").pop().split("-").map(cap).join(" ");
  const fmtArgs = (a) => Object.entries(a).map(([k, v]) => `${k}: ${typeof v === "string" ? `"${v}"` : JSON.stringify(v)}`).join(", ");
  const argsOf = (call) => { try { const a = JSON.parse(call.function.arguments || "{}"); return a && typeof a === "object" && !Array.isArray(a) ? a : {}; } catch { return {}; } };

  // One human line per data tool, computed from its result.
  const SUMMARY = {
    scratch_history: (r) => `${count(r.nights.length, "night")} · last 3: ${r.nights.slice(-3).map((x) => x.scratch_minutes).join(", ")} min · usual ${r.usual_minutes_per_night}`,
    order_history: (r) => {
      const fresh = r.orders.filter((o) => o.category === "personal care" && !o.bought_before).length;
      return `${count(r.orders.length, "order")} · ${fresh} personal-care item${fresh === 1 ? "" : "s"} never bought before`;
    },
    weather_history: (r) => {
      const h = r.days.map((x) => x.humidity_percent), t = r.days.map((x) => x.high_f);
      return `${count(r.days.length, "day")} · humidity ${Math.min(...h)}–${Math.max(...h)}% · ${Math.min(...t)}–${Math.max(...t)}°F · ${r.location}`;
    },
    calendar_events: (r) => {
      const e = r.events.find((x) => x.note) || r.events[0];
      return count(r.events.length, "event") + (e ? ` · ${e.title.replace(/\s*\(.*?\)/g, "")} ${span(e.date)}${e.note ? `, ${e.note}` : ""}` : "");
    },
    sleep_history: (r) => {
      const h = r.nights.map((x) => x.hours_asleep), last = r.nights[r.nights.length - 1];
      const before = h.length > 3 ? h.slice(0, -3) : h, usual = before.reduce((a, b) => a + b, 0) / before.length;
      return `${count(r.nights.length, "night")} · usually ${usual.toFixed(1)} h · last night ${last.hours_asleep} h, ${count(last.wake_ups, "wake-up")}`;
    },
  };

  // ---------- state ----------
  let gen = 0;            // bumps on R and P; async work from an older conversation checks it and stops
  let messages = [];      // the conversation for /api/chat (OpenAI style; the Worker adds the system prompt)
  let latencies = [];     // ms per assistant reply, kept so a replay has the same rhythm
  let startedAt = 0;      // when this conversation began: the dates its timeline uses
  let busy = false;       // Claude's turn (waiting for the API or playing a reply)
  let pendingAsk = null;  // answers the open ask_user question (a click or a typed answer)
  let replaying = false;
  let shownProduct = null; // show_product's arguments, so the conclusion can show the same bottle
  let inflight = null;    // the /api/chat request in progress, aborted when the conversation is wiped
  let modelId = MODEL || DEFAULT_MODEL;

  // ---------- thread ----------
  // No scrollbar: the feed slides up (transform) so the newest line stays in view.
  function follow() {
    if (!page.classList.contains("on")) return;   // hidden: keep the position for when the page comes back
    const over = Math.max(0, feed.offsetHeight - thread.clientHeight);
    feed.style.transform = over ? `translateY(${-over}px)` : "";
    thread.classList.toggle("over", over > 0);
  }
  const ro = new ResizeObserver(follow);
  ro.observe(feed); ro.observe(thread);

  function row(kind, html) { const r = el("div", `msg ${kind}`, html); feed.append(r); return r; }
  // Douglas's message. When it comes from the suggestion, an answer button or the input box, the bubble flies
  // from there into place (transform only). His first message waits a moment where it starts while the greeting
  // fades, so it doesn't fly across it. Returns when the bubble lands (ms after now).
  function userSays(text, from) {
    const f = from && !calm ? from.getBoundingClientRect() : null;
    const hold = leaveEmpty() && f ? 120 : 0;
    dropNudge();
    feed.querySelectorAll(".msg.error").forEach((e) => e.remove());   // an old "Try again" would resend a finished turn
    const r = row("user", `<div class="bubble">${esc(text)}</div>`);
    if (!f) return 0;
    const b = $(".bubble", r);
    r.style.animation = "none";
    const t = b.getBoundingClientRect();
    b.animate([{ transform: `translate(${f.left - t.left}px, ${f.top - t.top}px)` }, { transform: "none" }],
      { duration: 650, delay: hold, fill: "backwards", easing: "cubic-bezier(.2, .8, .25, 1)" });
    return hold + 650;
  }
  const claudeRow = () => row("claude", `<div class="av">${SPARK}</div><div class="body"></div>`);
  // Where Claude's next block goes: the current Claude message, or a new one after Douglas spoke.
  function claudeBody() {
    const last = feed.lastElementChild;
    return $(".body", last && last.classList.contains("claude") && !last.classList.contains("thinking") ? last : claudeRow());
  }
  function thinkingRow() {
    const r = claudeRow();
    r.classList.add("thinking");
    $(".body", r).innerHTML = `<span class="think">Claude is thinking<i>.</i><i>.</i><i>.</i></span>`;
    return r;
  }
  function settle(r) { r.classList.remove("thinking"); $(".body", r).innerHTML = ""; }
  // A turn can end before the conclusion (Claude says what it will check next but doesn't ask). Offer Douglas a
  // one-click reply under it, like the suggestion on the empty page; nothing is sent unless he clicks it.
  const SUGGEST_ICON = icon('<path d="M7 17 17 7M9 7h8v8"/>', 2.2);
  function offerNudge(text, upTo) {
    dropNudge();
    if (concluded(upTo) || /\?\s*$/.test(text)) return;
    const r = row("nudge", `<button type="button" class="suggest"><span class="sg-ico">${SUGGEST_ICON}</span><span>${NUDGE}</span></button>`);
    $("button", r).onclick = (e) => { if (!busy && !replaying) send(NUDGE, e.currentTarget); };
  }
  function dropNudge() { const n = $(".msg.nudge", feed); if (n) n.remove(); }
  // The greeting goes on Douglas's first message; true if it was still there.
  function leaveEmpty() { const e = $("#chatEmpty"); if (e.classList.contains("gone")) return false; e.classList.add("gone"); return true; }

  // Claude's text → HTML: paragraphs, simple lists, **bold**, *italic*. Everything else stays plain text.
  // In each block, consecutive list lines become a list ("1." ones numbered) and the lines between them a paragraph,
  // so "Here's my plan:" followed by bullets reads as an intro and a list.
  function rich(text) {
    const inline = (s) => esc(s).replace(/\*\*(.+?)\*\*/g, "<b>$1</b>").replace(/\*\*/g, "").replace(/\*([^*\s][^*]*?)\*/g, "<i>$1</i>");
    const bullet = /^([-*•]|\d+[.)])\s+/;
    const part = (lines) => {
      if (!bullet.test(lines[0])) return `<p>${lines.map(inline).join("<br>")}</p>`;
      const tag = /^\d/.test(lines[0]) ? "ol" : "ul";
      return `<${tag}>${lines.map((l) => `<li>${inline(l.replace(bullet, ""))}</li>`).join("")}</${tag}>`;
    };
    return String(text).trim().split(/\n\s*\n/).map((block) => {
      const runs = [];
      for (const l of block.split("\n").map((x) => x.trim().replace(/^#+\s*/, "")).filter(Boolean)) {
        const last = runs[runs.length - 1];
        if (last && bullet.test(last[0]) === bullet.test(l)) last.push(l); else runs.push([l]);
      }
      return runs.map(part).join("");
    }).join("");
  }

  // Typewriter: the paragraph is laid out up front with every character invisible, then the characters
  // fade in at CPS per second, so lines never jump while Claude "types".
  async function typeText(parent, text, my, cls = "say") {
    const html = rich(text), box = el("div", cls, html);
    parent.append(box);
    if (calm) return;
    const chars = [], nodes = [], walk = document.createTreeWalker(box, NodeFilter.SHOW_TEXT);
    while (walk.nextNode()) nodes.push(walk.currentNode);
    for (const node of nodes) {
      const frag = document.createDocumentFragment();
      for (const ch of node.data) { const c = el("span", "c"); c.textContent = ch; frag.append(c); chars.push(c); }
      node.replaceWith(frag);
    }
    await new Promise((done) => {
      const t0 = performance.now();
      let shown = 0;
      const step = (now) => {
        if (my !== gen) return done();
        const n = Math.min(chars.length, Math.floor(((now - t0) / 1000) * CPS));
        while (shown < n) chars[shown++].classList.add("on");
        if (shown < chars.length) requestAnimationFrame(step); else done();
      };
      requestAnimationFrame(step);
    });
    await sleep(200);
    if (my === gen) box.innerHTML = html;   // plain text again once it is all visible
  }

  // A tool call in the thread: icon, the call in monospace, a spinner that becomes a check, then one line.
  function toolCard(parent, color, iconPaths, callHTML, waitText, tag = "div") {
    const c = el(tag, `tool${tag === "button" ? " art" : ""}`, `<span class="ico">${icon(iconPaths)}</span>
      <span class="call">${callHTML}</span><span class="st"><i class="spin"></i>${CHECK}</span>
      <span class="sum"><span class="wait">${waitText}</span><span class="res"></span></span>`);
    c.style.setProperty("--c", color);
    parent.append(c);
    return { card: c, done(line) { $(".res", c).textContent = line; c.classList.add("done"); } };
  }

  async function runTool(parent, name, a, recorded) {
    const server = TOOL_SERVER[name];
    const [color, paths] = SERVERS[server];
    const t = toolCard(parent, color, paths, `<span class="srv">${server}</span> · <b>${esc(name)}</b>(${esc(fmtArgs(a))})`, "Running…");
    const t0 = performance.now();
    let result;
    try { result = recorded || S.tools[name](a); } catch (e) { result = { error: String(e.message || e) }; }
    await sleep(CARD_MS - (performance.now() - t0));
    let line;
    try { line = SUMMARY[name](result); } catch { line = result.error ? "Couldn't read this data" : "Done"; }
    t.done(line);
    await sleep(200);   // let the check land before the next card
    return result;
  }

  // ask_user: Claude's question with option buttons. Douglas clicks one or types his own answer.
  // In a replay the recorded answer is clicked for him after a moment.
  async function askUser(parent, a, my, recorded) {
    const options = (Array.isArray(a.options) ? a.options : []).map((o) => String(o).trim()).filter(Boolean).slice(0, 4);
    const card = el("div", "ask");
    parent.append(card);
    await typeText(card, String(a.question || "").trim() || "Can you tell me more?", my, "q");
    if (my !== gen) return null;
    // "fresh": no hover look until the pointer moves, so the option that lands under a resting cursor doesn't look chosen
    const opts = el("div", "opts fresh", options.map((o, k) => `<button type="button" class="opt" style="--d:${k}">${esc(o)}</button>`).join(""));
    opts.addEventListener("pointermove", () => opts.classList.remove("fresh"), { once: true });
    card.append(opts);
    const buttons = [...opts.children];
    // a long answer that wraps reads better as a left-aligned box than as a centred two-line pill
    buttons.forEach((b) => b.classList.toggle("wrap", b.offsetHeight > 2 * parseFloat(getComputedStyle(b).lineHeight)));
    const answer = await new Promise((resolve) => {
      pendingAsk = resolve;
      composerState();
      buttons.forEach((b) => { b.onclick = () => resolve({ text: b.textContent, from: b }); });
      if (recorded == null) return;
      const b = buttons.find((x) => x.textContent === recorded);
      buttons.forEach((x) => { if (x !== b) x.disabled = true; });
      sleep(1800).then(async () => {
        if (my !== gen || pendingAsk !== resolve) return;
        if (b) { b.classList.add("press"); await sleep(180); } else await typeIn(recorded, my);
        if (my === gen) resolve({ text: recorded, from: b || input });
      });
    });
    if (my !== gen) return null;
    pendingAsk = null;
    card.classList.add("answered");
    buttons.forEach((b) => { b.disabled = true; b.classList.remove("press"); b.classList.toggle("picked", b.textContent === answer.text); });
    if (document.activeElement && card.contains(document.activeElement)) document.activeElement.blur();
    await sleep(260);
    userSays(answer.text, answer.from);
    composerState();
    await sleep(calm ? 0 : 450);
    return answer.text;
  }

  // ---------- artifact panel ----------
  const slots = { show_timeline: $("#slotTimeline"), show_product: $("#slotProduct"), show_conclusion: $("#slotConclusion") };
  const TOP = 60;                                  // chart scale, minutes
  const hot = (m) => m > S.USUAL * 1.5;            // "clearly above usual", the same rule as History
  // The 14 nights as of time t: a replay keeps the dates of the day it was recorded.
  const nightsAsOf = (t) => S.NIGHTS.map((_, i) => { const d = new Date(t); d.setHours(12, 0, 0, 0); return new Date(d - (S.NIGHTS.length - i) * 864e5); });

  function timelineHTML(a, at) {
    const days = nightsAsOf(at), N = days.length;
    const mi = days.map(S.iso).indexOf(String(a.marker_date || "").trim().slice(0, 10));
    const ri = S.NIGHTS.findIndex(hot), lag = mi >= 0 && ri > mi ? ri - mi : 0;
    const calmNights = S.NIGHTS.filter((m) => !hot(m)), lo = Math.min(...calmNights), hi = Math.max(...calmNights);   // his usual range
    const x = (i) => ((i + 0.5) / N) * 100, y = (m) => (m / TOP) * 100;
    const left = mi >= N / 2;                      // the flag hangs to the left of the marker when it is on the right half
    // Same language as History: calm nights grey with their values in one row above the usual band; hot nights
    // dim orange up to his usual and bright above it, values big on their caps.
    const cols = S.NIGHTS.map((m, i) => `<div class="tl-col${hot(m) ? " hot" : ""}${i === mi ? " mark" : ""}" style="--i:${i}">
      <i style="height:${y(m)}%">${hot(m) ? `<u style="height:${(((m - S.USUAL) / m) * 100).toFixed(1)}%"></u>` : ""}</i>
      <b style="bottom:${y(hot(m) ? m : hi)}%">${m}</b></div>`).join("");
    const marker = mi < 0 ? "" : `<div class="tl-mark" style="left:${x(mi)}%"></div>
      <span class="tl-flag${left ? " left" : ""}" style="${left ? `right:${100 - x(mi)}%;max-width:${x(mi)}%` : `left:${x(mi)}%;max-width:${100 - x(mi)}%`}"><span class="lbl">${esc(a.marker_label || "Change")}</span><span>· ${S.wd(days[mi])} ${S.md(days[mi])}</span></span>`;
    const bracket = !lag ? "" : `<div class="tl-lag${left ? "" : " low"}" style="left:${x(mi)}%;width:${x(ri) - x(mi)}%"><span>${lag === 1 ? "1 day later" : `${lag} days later`}</span></div>
      <i class="tl-drop${left ? "" : " low"}" style="left:${x(ri)}%;bottom:calc(${y(S.NIGHTS[ri])}% + var(--lab))"></i>`;
    const axis = days.map((d, i) => `<span class="${i === mi ? "mark" : hot(S.NIGHTS[i]) ? "hot" : ""}"><b>${S.wd(d).toUpperCase()}</b>${d.getDate()}</span>`).join("");
    return `<div class="art-card tl">
      <div class="art-head"><span class="ek">MINUTES OF SCRATCHING · LAST 14 NIGHTS</span>
        <span class="legend"><span><i class="lg-band"></i>his usual range</span><span><i class="lg-hot"></i>above usual</span>${mi < 0 ? "" : `<span><i class="lg-mark"></i>change</span>`}</span></div>
      <div class="tl-plot">
        <div class="tl-band" style="bottom:${y(lo)}%;height:${y(hi - lo)}%"></div>
        <div class="tl-usual" style="bottom:${y(S.USUAL)}%"><span><b>USUAL</b>${S.USUAL} min</span></div>
        <div class="tl-cols">${cols}${marker}${bracket}</div></div>
      <div class="tl-axis">${axis}</div>
      ${a.note ? `<p class="art-note rv" style="--t:2.3s">${esc(a.note)}</p>` : ""}
    </div>`;
  }

  // A generic pump bottle (no brand).
  const BOTTLE = (size, id) => `<svg class="bottle" viewBox="0 0 128 256" aria-hidden="true">
    <defs><linearGradient id="${id}Body" x1="0" x2="1"><stop offset="0" stop-color="#ffb8cf"/><stop offset=".42" stop-color="#fe7da8"/><stop offset="1" stop-color="#b8486e"/></linearGradient>
      <linearGradient id="${id}Cap" x1="0" x2="1"><stop offset="0" stop-color="#59615c"/><stop offset="1" stop-color="#1d2320"/></linearGradient></defs>
    <ellipse cx="64" cy="249" rx="44" ry="5" fill="#000" opacity=".55"/>
    <rect x="20" y="20" width="34" height="9" rx="4.5" fill="url(#${id}Cap)"/><rect x="46" y="14" width="40" height="18" rx="5" fill="url(#${id}Cap)"/>
    <rect x="58" y="31" width="12" height="20" fill="url(#${id}Cap)"/><rect x="42" y="49" width="44" height="22" rx="6" fill="url(#${id}Cap)"/>
    <path d="M47 55h34M47 60h34M47 65h34" stroke="#000" stroke-opacity=".28" stroke-width="1.4"/>
    <rect x="18" y="68" width="92" height="178" rx="26" fill="url(#${id}Body)"/>
    <rect x="27" y="86" width="9" height="140" rx="4.5" fill="#fff" opacity=".3"/>
    <rect x="36" y="114" width="64" height="98" rx="10" fill="#f6efe6"/>
    <text x="68" y="148" text-anchor="middle" font-family="Space Mono" font-weight="700" font-size="14" letter-spacing="2" fill="#3b2730">BODY</text>
    <text x="68" y="167" text-anchor="middle" font-family="Space Mono" font-weight="700" font-size="14" letter-spacing="2" fill="#3b2730">WASH</text>
    <path d="M50 182c6-5 12-5 18 0s12 5 18 0" stroke="#fe7da8" stroke-width="2.6" fill="none" stroke-linecap="round"/>
    ${size ? `<text x="68" y="201" text-anchor="middle" font-family="Space Mono" font-size="9" letter-spacing="1" fill="#7b6670">${esc(size.toUpperCase())}</text>` : ""}
  </svg>`;

  const norm = (s) => String(s).toLowerCase().replace(/[^a-z]/g, "").replace(/s$/, "");
  function productOf(a) {
    const name = String(a.name || "Product").trim(), key = norm(name.split(",")[0]);
    const order = S.orders().find((o) => o.date === a.purchase_date && o.category === "personal care")
      || S.orders().find((o) => key && norm(o.item.split(",")[0]) === key);
    const flagged = (Array.isArray(a.flagged_ingredients) ? a.flagged_ingredients : []).map((f) => String(f).trim()).filter(Boolean);
    const isFlagged = (ing) => flagged.some((f) => { const A = norm(ing), B = norm(f); return A && B && (A.includes(B) || B.includes(A)); });
    const list = (order && order.ingredients ? S.BODY_WASH_INGREDIENTS : []).map((i) => ({ name: i, flag: isFlagged(i) }));
    flagged.filter((f) => !list.some((i) => i.flag && (norm(i.name).includes(norm(f)) || norm(f).includes(norm(i.name))))).forEach((f) => list.push({ name: f, flag: true }));
    return { name, order, list };
  }

  function productHTML(a) {
    const { name, order, list } = productOf(a);
    const bought = day(a.purchase_date) ? md(a.purchase_date) : order ? md(order.date) : "";
    const meta = [order && order.bought_before === false ? "<b>First purchase</b>" : "", bought ? `ordered ${bought}` : "", "Amazon"].filter(Boolean).join(" · ");
    const size = order && order.item.includes(",") ? order.item.split(",").pop().trim() : "";
    let k = 0;
    return `<div class="art-card prod">
      <div class="prod-pic">${BOTTLE(size, "bwProd")}</div>
      <div class="prod-info">
        <span class="ek rv" style="--t:.2s">SUSPECTED PRODUCT</span>
        <h3 class="rv${name.length > 22 ? " long" : ""}" style="--t:.3s">${esc(name)}</h3>
        <div class="prod-meta rv" style="--t:.4s">${meta}</div>
        ${list.length ? `<div class="ingr-head rv" style="--t:.55s"><span class="ek">INGREDIENTS</span><span class="prod-hint"><i></i>common contact allergens</span></div>
        <div class="ingr">${list.map((i, n) => `<span class="rv${i.flag ? " flag" : ""}" style="--t:${(0.6 + n * 0.05).toFixed(2)}s${i.flag ? `;--f:${(1.15 + k++ * 0.22).toFixed(2)}s` : ""}">${esc(i.name)}</span>`).join("")}</div>` : ""}
        ${a.note ? `<p class="art-note rv" style="--t:1.6s">${esc(a.note)}</p>` : ""}
      </div>
    </div>`;
  }

  function conclusionHTML(a) {
    const lv = { low: 1, medium: 2, high: 3 }[String(a.confidence || "").toLowerCase()] || 2;
    const ruled = (Array.isArray(a.ruled_out) ? a.ruled_out : []).map((r) => (typeof r === "string" ? { item: r } : r || {})).filter((r) => r.item).slice(0, 6);
    const cause = String(a.cause || "Not sure yet");
    const product = shownProduct && productOf(shownProduct), key = product ? norm(product.name.split(",")[0]) : "";
    const pic = key && norm(cause).includes(key) ? `<div class="concl-pic rv" style="--t:.4s">${BOTTLE(product.order && product.order.item.includes(",") ? product.order.item.split(",").pop().trim() : "", "bwConcl")}</div>` : "";
    return `<div class="art-card concl">
      <div class="concl-top"><div class="concl-cause">
        <span class="ek rv" style="--t:.15s">MOST LIKELY CAUSE</span>
        <h3 class="cause rv ${cause.length > 140 ? "xs" : cause.length > 90 ? "s" : cause.length > 50 ? "m" : ""}" style="--t:.25s">${esc(cause)}</h3>
        <div class="conf rv" style="--t:.5s"><span class="ek">CONFIDENCE</span><span class="meter3 lv${lv}"><i></i><i></i><i></i></span><b>${["LOW", "MEDIUM", "HIGH"][lv - 1]}</b></div>
      </div>${pic}</div>
      ${ruled.length ? `<span class="ek rv" style="--t:.9s">RULED OUT</span>
      <ul class="ruled${ruled.length > 2 ? " two" : ""}">${ruled.map((r, k) => `<li class="rv" style="--t:${(1 + k * 0.25).toFixed(2)}s"><s>${esc(r.item)}</s>${r.reason ? `<span>${esc(r.reason)}</span>` : ""}</li>`).join("")}</ul>` : ""}
      ${a.next_step ? `<div class="try rv" style="--t:${(1.3 + ruled.length * 0.25).toFixed(2)}s"><span class="ek">TRY THIS</span><p>${esc(a.next_step)}</p></div>` : ""}
      <p class="disc rv" style="--t:${(1.6 + ruled.length * 0.25).toFixed(2)}s">Not a diagnosis — patterns in your data. A dermatologist can confirm with a patch test.</p>
    </div>`;
  }

  let artPage = 0;
  function showPage(p) {
    artPage = p;
    $("#artTrack").style.transform = p ? "translateY(-100%)" : "";
    $("#artTabs").querySelectorAll("button").forEach((b) => b.classList.toggle("on", +b.dataset.page === p));
  }

  function addTab(name, label) {
    const tabs = $("#artTabs"), was = new Map([...tabs.children].map((t) => [t, t.getBoundingClientRect().left]));
    let b = tabs.querySelector(`[data-tool="${name}"]`);
    if (!b) {
      b = el("button");
      b.type = "button"; b.dataset.tool = name; b.dataset.page = ART[name].page;
      b.style.order = Object.keys(ART).indexOf(name);
      b.style.setProperty("--c", ART[name].color);
      b.onclick = () => showPage(ART[name].page);
      tabs.append(b);
    }
    b.innerHTML = `${icon(ART[name].icon)}<span>${esc(label)}</span>`;
    // the tabs sit at the right edge: the ones already there glide over to make room instead of jumping
    if (!calm) was.forEach((x, t) => {
      const dx = x - t.getBoundingClientRect().left;
      if (Math.abs(dx) > 0.5) t.animate([{ transform: `translateX(${dx}px)` }, { transform: "none" }], { duration: 400, easing: "cubic-bezier(.2, .8, .25, 1)" });
    });
  }

  // Very long model text: the card steps its whole type scale down (at most twice) until it fits.
  function fit(card) {
    card.classList.remove("tight", "tighter");
    for (const step of ["tight", "tighter"]) {
      if (!card.clientHeight || card.scrollHeight <= card.clientHeight + 1) return;
      card.classList.add(step);
    }
  }

  // Timeline and product share the first page; while only one of them is there, it waits in the middle.
  // Returns true when the waiting card has to move to make room.
  function layoutEvidence(fresh) {
    const t = slots.show_timeline, p = slots.show_product, gap = parseFloat(getComputedStyle(t.parentNode).rowGap) || 0;
    let moved = false;
    const place = (slot, px) => {
      const v = px ? `translateY(${px}px)` : "";
      if (slot.style.transform === v) return;
      if (slot === fresh) slot.style.transition = "none"; else moved = true;
      slot.style.transform = v;
      if (slot === fresh) { void slot.offsetHeight; slot.style.transition = ""; }
    };
    place(t, t.firstChild && !p.firstChild ? (p.offsetHeight + gap) / 2 : 0);
    place(p, p.firstChild && !t.firstChild ? -(t.offsetHeight + gap) / 2 : 0);
    return moved;
  }

  const TITLES = { show_timeline: () => "Scratching timeline", show_product: (a) => productOf(a).name, show_conclusion: () => "Conclusion" };
  const ART_LINE = {
    show_timeline: (a, at) => {
      const days = nightsAsOf(at), i = days.map(S.iso).indexOf(String(a.marker_date || "").slice(0, 10));
      const when = i >= 0 ? `${S.wd(days[i])} ${S.md(days[i])}` : md(a.marker_date || "");
      return `Marked ${when}${a.marker_label ? `: ${a.marker_label}` : ""}`;
    },
    show_product: (a) => {
      const { order, list } = productOf(a), k = list.filter((i) => i.flag).length;
      return `${order && order.bought_before === false ? "First purchase · " : ""}${count(k, "flagged ingredient")}`;
    },
    show_conclusion: (a) => {
      const k = Array.isArray(a.ruled_out) ? a.ruled_out.length : 0;
      return `${cap(String(a.confidence || "medium").toLowerCase())} confidence · ${count(k, "thing")} ruled out`;
    },
  };
  const DRAW_MS = { show_timeline: 2200, show_product: 1500, show_conclusion: 1400 };   // from the start of each reveal

  // show_timeline / show_product / show_conclusion: an artifact card in the thread and the artifact in the panel.
  async function showArtifact(parent, name, a, my) {
    const t = toolCard(parent, ART[name].color, ART[name].icon, `<b>${esc(TITLES[name](a))}</b><span class="kind">ARTIFACT</span>`, "Drawing…", "button");
    t.card.type = "button";
    t.card.onclick = () => showPage(ART[name].page);
    const t0 = performance.now(), opening = !chat.classList.contains("open"), paging = artPage !== ART[name].page;
    const slot = slots[name];
    if (name === "show_product") shownProduct = a;
    slot.innerHTML = name === "show_timeline" ? timelineHTML(a, startedAt) : name === "show_product" ? productHTML(a) : conclusionHTML(a);
    fit(slot.firstElementChild);
    addTab(name, name === "show_product" ? TITLES[name](a) : name === "show_timeline" ? "Timeline" : "Conclusion");
    chat.classList.add("open");
    showPage(ART[name].page);
    const moved = layoutEvidence(slot);
    if (opening || paging || moved) await sleep(calm ? 0 : opening || moved ? 650 : 400);   // let the panel (or its page) slide in, or the other card make room
    await nextPaint();
    if (my !== gen) return;
    slot.firstElementChild.classList.add("on");
    await sleep(Math.max(CARD_MS - (performance.now() - t0), calm ? 0 : DRAW_MS[name]));
    if (my !== gen) return;
    t.done(ART_LINE[name](a, startedAt));
    await sleep(300);
  }

  // ---------- one assistant reply: its text, then its tool calls in order ----------
  // Returns the tool results for the API. `recorded` (replay) maps tool_call_id → the saved result.
  async function play(m, my, recorded) {
    const calls = m.tool_calls || [];
    let text = (m.content || "").trim();
    for (const c of calls) {   // a question Claude also wrote into its text is shown once, on the question card
      const q = c.function.name === "ask_user" ? String(argsOf(c).question || "").trim() : "";
      if (q && text.includes(q)) text = text.replace(q, "").trim();
    }
    if (text) await typeText(claudeBody(), text, my);
    const out = [];
    for (const c of calls) {
      if (my !== gen) return null;
      const name = c.function.name, a = argsOf(c), rec = recorded ? recorded.get(c.id) : undefined;
      let result;
      if (S.tools[name]) result = await runTool(claudeBody(), name, a, rec);
      else if (name === "ask_user") result = { answer: await askUser(claudeBody(), a, my, rec ? String(rec.answer) : null) };
      else if (ART[name]) { await showArtifact(claudeBody(), name, a, my); result = { shown: true }; }
      else result = { error: `There is no tool called ${name}.` };
      out.push({ role: "tool", tool_call_id: c.id, content: JSON.stringify(result) });
    }
    return my === gen ? out : null;
  }

  // The reply as it goes back into the conversation: string content, a usable id on every call, and
  // arguments that parse (malformed ones become {}).
  function tidy(m, round) {
    const calls = (Array.isArray(m.tool_calls) ? m.tool_calls : []).filter((c) => c && c.function && c.function.name)
      .map((c, k) => ({ id: String(c.id || `call_${round}_${k}`), type: "function", function: { name: String(c.function.name), arguments: JSON.stringify(argsOf(c)) } }));
    const out = { role: "assistant", content: typeof m.content === "string" ? m.content : "" };
    if (calls.length) out.tool_calls = calls;
    return out;
  }

  async function fetchReply() {
    const ctl = inflight = new AbortController(), timer = setTimeout(() => ctl.abort(), TIMEOUT_MS);
    try {
      const r = await fetch(api("/api/chat"), {
        method: "POST", signal: ctl.signal, headers: { "content-type": "application/json" },
        body: JSON.stringify({ ...(MODEL && { model: MODEL }), today: S.today(), messages }),
      });
      const j = await r.json().catch(() => ({}));
      if (!r.ok || !j.message) throw new Error(j.error ? `${j.error}${j.status ? ` (${j.status})` : ""}` : `HTTP ${r.status}`);
      if (j.model) setModel(j.model);
      return j.message;
    } catch (e) {
      throw e.name === "AbortError" ? new Error(`no answer after ${TIMEOUT_MS / 1000} s`) : e;
    } finally { clearTimeout(timer); }
  }

  // The loop: send the conversation, show the reply, run its tools, send the results; stop at a reply without tools.
  // `lead`: Douglas's message is still flying into place, so "Claude is thinking…" waits for it (the request doesn't).
  async function converse(my, lead = 0) {
    busy = true; composerState();
    let said = "";
    for (let round = 0; round < 16; round++) {
      const t0 = performance.now(), asked = fetchReply();
      asked.catch(() => {});   // handled below; this only keeps the browser quiet while we wait
      if (lead) { await sleep(lead); lead = 0; if (my !== gen) return; }
      const think = thinkingRow();
      let reply;
      try {
        reply = tidy(await asked, messages.length);
        if (!reply.content.trim() && !reply.tool_calls) throw new Error("empty reply");
      } catch (err) {
        if (my !== gen) return;
        think.remove();
        failed(err, my);
        return;
      }
      if (my !== gen) return;
      latencies.push(Math.round(performance.now() - t0));
      await sleep(THINK_MS - (performance.now() - t0));
      if (my !== gen) return;
      settle(think);
      messages.push(reply);
      said = reply.content.trim();
      const results = await play(reply, my, null);
      if (!results) return;
      if (!reply.tool_calls) break;
      messages.push(...results);
    }
    busy = false; composerState();
    save();
    offerNudge(said);
  }

  function failed(err, my) {
    busy = false; composerState();
    const r = row("error", `<div class="av">!</div><div class="body"><div class="err"><b>Claude didn't answer</b><span>${esc(err.message || err)}</span><button type="button">Try again</button></div></div>`);
    $("button", r).onclick = () => { if (my !== gen || busy) return; r.remove(); converse(my); };
  }

  function send(text, from) {
    if (!messages.length) startedAt = Date.now();
    $("#chatTag").classList.remove("on");   // after a replay, Douglas carries on live
    const landed = userSays(text, from);
    messages.push({ role: "user", content: text });
    converse(gen, Math.max(0, landed - 200));   // "Claude is thinking…" shows up as his bubble settles
  }

  // ---------- save and replay ----------
  const concluded = (list = messages) => list.some((m) => (m.tool_calls || []).some((c) => c.function.name === "show_conclusion"));
  function save() {
    if (replaying || !concluded()) return;
    try { localStorage.setItem(`${SAVE_KEY}:${modelId}`, JSON.stringify({ v: 1, model: modelId, at: startedAt, messages, ms: latencies })); } catch {}
  }
  // What P replays: the newest conversation with this page's model (Claude on stage), else the newest of any model.
  // The plain "twinChat" key is the single save of earlier versions.
  function saved() {
    const all = Object.keys(localStorage).filter((k) => k === SAVE_KEY || k.startsWith(SAVE_KEY + ":"))
      .map((k) => { try { return JSON.parse(localStorage.getItem(k)); } catch { return null; } })
      .filter((r) => r && Array.isArray(r.messages) && r.messages.length)
      .sort((a, b) => (b.at || 0) - (a.at || 0));
    return all.find((r) => r.model === (MODEL || DEFAULT_MODEL)) || all[0] || null;
  }

  // A recorded message Douglas typed: it appears in the box, then goes out.
  async function typeIn(text, my) {
    for (let i = 1; i <= text.length && my === gen; i++) { input.value = text.slice(0, i); composerState(); await sleep(1000 / 32); }
    await sleep(300);
    if (my === gen) { input.value = ""; composerState(); }
  }

  async function replay() {
    const rec = saved();
    if (!rec) { toast("No saved conversation yet. Finish one first."); return; }
    const my = await wipe();
    if (my !== gen) return;
    replaying = true; busy = true; startedAt = rec.at || Date.now(); setModel(rec.model || modelId);
    $("#chatTag").classList.add("on");
    composerState();
    const results = new Map(rec.messages.filter((m) => m.role === "tool").map((m) => { try { return [m.tool_call_id, JSON.parse(m.content)]; } catch { return [m.tool_call_id, {}]; } }));
    let k = 0;
    await sleep(700);
    for (const [i, m] of rec.messages.entries()) {
      if (my !== gen) return;
      if (m.role === "user") {
        const nudge = $(".msg.nudge button", feed);
        const chip = !feed.childElementCount && m.content === STARTER ? $("#chatSuggest") : nudge && m.content === NUDGE ? nudge : null;
        if (chip) { await sleep(900); chip.classList.add("press"); await sleep(180); } else await typeIn(m.content, my);
        if (my !== gen) return;
        userSays(m.content, chip || input);
      } else if (m.role === "assistant") {
        const think = thinkingRow();
        await sleep(Math.min(3500, Math.max(THINK_MS + 200, (rec.ms && rec.ms[k++]) || 1500)));
        if (my !== gen) return;
        settle(think);
        if (!(await play(m, my, results))) return;
        if (!m.tool_calls && i < rec.messages.length - 1) offerNudge(m.content.trim(), rec.messages.slice(0, i + 1));
      }
    }
    messages = rec.messages.slice(); latencies = (rec.ms || []).slice();
    replaying = false; busy = false; composerState();
  }

  // ---------- new conversation ----------
  // Fade the page out, clear everything, fade back in. Returns the new generation.
  async function wipe() {
    const my = ++gen;
    pendingAsk = null; busy = true; replaying = false;   // busy: nothing goes into the old thread while it fades out
    if (inflight) inflight.abort();
    chat.classList.add("wipe");
    await sleep(calm ? 0 : 260);
    if (my !== gen) return my;
    messages = []; latencies = []; startedAt = 0; shownProduct = null; busy = false;
    feed.innerHTML = "";
    Object.values(slots).forEach((s) => { s.innerHTML = ""; s.style.transform = ""; });
    $("#artTabs").innerHTML = "";
    showPage(0);
    chat.classList.remove("open");
    $("#chatEmpty").classList.remove("gone");
    $("#chatSuggest").classList.remove("press");
    $("#chatTag").classList.remove("on");
    input.value = "";
    setModel(MODEL || DEFAULT_MODEL);
    follow(); composerState(); greet();
    void chat.offsetHeight;   // apply the cleared layout before the transitions come back
    chat.classList.remove("wipe");
    return my;
  }

  // ---------- composer, header bits, keys ----------
  function setModel(id) { modelId = id; $("#chatModel").textContent = modelName(id); }

  function composerState() {
    const asking = !!pendingAsk && !replaying;
    input.readOnly = replaying;
    input.placeholder = replaying ? "Replaying a saved conversation…" : asking ? "Type your own answer…" : busy ? "Claude is working…"
      : messages.length ? "Reply to Claude…" : "How can I help you today?";
    sendBtn.disabled = replaying || (busy && !asking) || !input.value.trim();
    input.style.height = "auto";   // the box grows with the text, up to three lines (chat.css max-height)
    input.style.height = `${input.scrollHeight}px`;
  }

  function submit() {
    const text = input.value.trim();
    if (!text || replaying) return;
    if (pendingAsk) pendingAsk({ text, from: input });   // a typed answer to Claude's question
    else if (!busy) send(text, input);
    else return;
    input.value = "";
    input.blur();                       // so the page shortcuts work again
    composerState();
  }

  let toastTimer = 0;
  function toast(text) {
    const t = $("#chatToast");
    t.textContent = text; t.classList.add("on");
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => t.classList.remove("on"), 2600);
  }

  function greet() {
    const h = new Date().getHours();
    $("#chatHello").textContent = `Good ${h < 5 ? "evening" : h < 12 ? "morning" : h < 18 ? "afternoon" : "evening"}, Douglas`;
  }

  $(".hello .spark").innerHTML = SPARK;
  $("#chatServers").innerHTML = Object.entries(SERVERS).map(([name, [color, paths]]) => `<span class="server" style="--c:${color}"><i>${icon(paths)}</i>${name}</span>`).join("");
  $("#chatSuggest").innerHTML = `<span class="sg-ico">${SUGGEST_ICON}</span><span>${esc(STARTER)}</span>`;
  $("#chatSuggest").addEventListener("click", () => { if (!busy && !replaying && !messages.length) send(STARTER, $("#chatSuggest")); });
  $("#composer").addEventListener("submit", (e) => { e.preventDefault(); submit(); });
  input.addEventListener("input", composerState);
  input.addEventListener("keydown", (e) => {
    if (e.key === "Escape") input.blur();
    if (e.key === "Enter" && !e.shiftKey && !e.isComposing) { e.preventDefault(); submit(); }   // Shift+Enter: a new line
  });
  document.addEventListener("keydown", (e) => {
    if (e.target.closest && e.target.closest("input, textarea, [contenteditable]")) return;   // typing in the chat
    if (!page.classList.contains("on") || e.metaKey || e.ctrlKey || e.altKey || e.repeat) return;
    if (e.key === "r" || e.key === "R") wipe();
    if (e.key === "p" || e.key === "P") replay();
  });
  const refit = () => Object.values(slots).forEach((s) => s.firstElementChild && fit(s.firstElementChild));
  window.addEventListener("twin:page", (e) => { if (e.detail === "claude") { greet(); follow(); refit(); layoutEvidence(); } });
  window.addEventListener("resize", () => { refit(); layoutEvidence(); });
  setModel(modelId); greet(); composerState();
})();
