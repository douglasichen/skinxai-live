// SkinXAI · big-screen scratch monitor.
// Live data: WebSocket /api/live (batches from the Apple Watch via the Worker).
// Keys: 1-4 pages · F fullscreen · D demo simulation on/off · R reset counters (on Monitor).
(() => {
  const $ = (s) => document.querySelector(s);
  const RATE = 25;                 // samples per second sent by the watch
  const PX_PER_SAMPLE = 4;         // sweep speed: 100 px per second
  const motion = !matchMedia("(prefers-reduced-motion: reduce)").matches;

  // ---------- pages ----------
  const names = { monitor: "SCRATCH MONITOR", night: "LAST NIGHT", history: "HISTORY", claude: "CLAUDE" };
  const tabs = [...document.querySelectorAll(".tabs button")];
  // The yellow pill carries the tab labels again in dark ink, shifted back by as much as the pill moves: whatever
  // part of a label it covers is dark at every frame of the slide.
  const ink = $("#tabInk");
  ink.innerHTML = `<span>${tabs.map((b) => `<b>${b.textContent}</b>`).join("")}</span>`;
  let page = "monitor";
  function show(next) {
    if (!names[next]) return;
    const changed = next !== page;
    page = next;
    document.querySelectorAll(".page").forEach((p) => p.classList.toggle("on", p.id === "p-" + page));
    tabs.forEach((b) => b.classList.toggle("on", b.dataset.page === page));
    const x = tabs.find((b) => b.dataset.page === page).offsetLeft - tabs[0].offsetLeft;
    ink.style.transform = `translateX(${x}px)`;
    ink.firstChild.style.transform = `translateX(${-x}px)`;
    // a reload stays on this page (replaceState fires no hashchange)
    history.replaceState(null, "", page === "monitor" ? location.pathname + location.search : "#" + page);
    const name = $("#pageName");
    name.textContent = names[page];
    if (changed && motion) name.animate([{ opacity: 0, transform: "translateY(6px)" }, { opacity: 1, transform: "none" }], { duration: 400, easing: "cubic-bezier(.2,.7,.2,1)" });
    window.dispatchEvent(new CustomEvent("twin:page", { detail: page }));
  }
  tabs.forEach((b) => b.addEventListener("click", () => show(b.dataset.page)));
  window.twinShow = show;
  // #night, #history, #claude open that page: no cross-fade, and only once every page script is listening
  window.addEventListener("DOMContentLoaded", () => {
    const first = location.hash.slice(1);
    if (!names[first] || first === "monitor") return;
    document.body.classList.add("instant");
    show(first);
    requestAnimationFrame(() => requestAnimationFrame(() => document.body.classList.remove("instant")));
  });
  window.addEventListener("hashchange", () => show(location.hash.slice(1) || "monitor"));

  // ---------- clock ----------
  const tick = () => { $("#clock").textContent = new Date().toLocaleTimeString([], { hour12: false }); };
  tick(); setInterval(tick, 500);

  // ---------- sound ----------
  // The browser allows sound after one user gesture: the first click or key press anywhere (or the yellow pill).
  let audio = null;
  function enableSound() {
    audio = audio || new (window.AudioContext || window.webkitAudioContext)();
    audio.resume().then(() => {
      if (audio.state !== "running") return;
      $("#sound").classList.add("off");
      document.removeEventListener("pointerdown", enableSound);
      document.removeEventListener("keydown", enableSound);
    }, () => {});
  }
  document.addEventListener("pointerdown", enableSound);
  document.addEventListener("keydown", enableSound);
  $("#sound").addEventListener("click", enableSound);
  // the monitor only beeps while it is on screen (the watch keeps streaming behind the other pages)
  function beep(freq = 1046, dur = 0.09, vol = 0.18, when = 0) {
    if (!audio || audio.state !== "running" || page !== "monitor") return;
    const t = audio.currentTime + when;
    const o = audio.createOscillator(), g = audio.createGain();
    o.type = "sine"; o.frequency.value = freq;
    g.gain.setValueAtTime(0, t); g.gain.linearRampToValueAtTime(vol, t + 0.008); g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    o.connect(g).connect(audio.destination); o.start(t); o.stop(t + dur + 0.02);
  }

  // ---------- what counts as scratching on this screen ----------
  // The watch flags windows; the screen can be stricter without reinstalling the watch app:
  // ?minp=0.6 (min scratch probability) · ?maxs=0.5 (max motion strength, g) · ?mins=0.02 (min strength, g)
  const P = new URLSearchParams(location.search);
  const MINP = +(P.get("minp") || 0), MAXS = +(P.get("maxs") || Infinity), MINS = +(P.get("mins") || 0);
  const passes = (w) => !!w && !!w.scratch && (w.p ?? 1) >= MINP && (w.strength ?? MINS) <= MAXS && (w.strength ?? MINS) >= MINS;
  let lastWin = null, ignoring = false;

  // ---------- state ----------
  const queue = [];                // incoming samples {m, s}
  let scratchUntil = 0;            // performance.now() until which samples are "scratch"
  let scratching = false, scratchStartedAt = 0;
  let count = 0, totalSeconds = 0, lastScratchAt = null, currentHz = null;
  let sessionStart = Date.now();
  const strip = [];                // {start, end, intense, el} in Date.now() ms
  let lastBatchAt = 0, simulate = false, idle = true;

  function setLive() {
    const live = simulate || Date.now() - lastBatchAt < 3500;
    idle = !live;
    $("#livePill").classList.toggle("live", live && !simulate);
    $("#livePill").classList.toggle("sim", simulate);
    $("#liveText").textContent = simulate ? "SIMULATION" : live ? "WATCH LIVE" : "WAITING FOR WATCH";
    $("#modeText").textContent = simulate ? "SIMULATION" : "LIVE";
    $("#traceWrap").classList.toggle("idle", !live);
    if (!live) setMeter(0);
  }
  setInterval(setLive, 500);

  function scratchStart(hz, intense) {
    if (scratching) return;
    scratching = true; scratchStartedAt = Date.now();
    count += 1; lastScratchAt = Date.now(); if (hz) currentHz = hz;
    bump();
    $("#alarm").classList.add("on"); $("#traceWrap").classList.add("hot");
    strip.push({ start: Date.now(), end: null, intense });
    markRecent(RATE * 1.5);   // the detector needs about a second: recolour that stretch of the trace too
    beep(1318, 0.09, 0.2); beep(1318, 0.09, 0.2, 0.14);
  }
  function scratchEnd(seconds) {
    if (!scratching) return;
    scratching = false;
    const dur = seconds || (Date.now() - scratchStartedAt) / 1000;
    totalSeconds += dur; lastScratchAt = Date.now();
    const last = strip[strip.length - 1]; if (last && !last.end) last.end = Date.now();
    $("#alarm").classList.remove("on"); $("#traceWrap").classList.remove("hot");
  }
  // while scratching: a soft monitor beep every 0.6 s
  setInterval(() => { if (scratching) beep(988, 0.07, 0.12); }, 600);

  // the counter jumps and flashes on each new scratch
  function bump() {
    const v = $("#vCount");
    v.textContent = count;
    if (!motion) return;
    v.animate([{ transform: "scale(1)" }, { transform: "scale(1.16)", offset: 0.3 }, { transform: "scale(1)" }], { duration: 700, easing: "cubic-bezier(.2,.7,.2,1)" });
    $("#vFlash").animate([{ opacity: 0.35, transform: "scale(.8)" }, { opacity: 1, transform: "scale(1.15)", offset: 0.25 }, { opacity: 0.35, transform: "scale(1)" }], { duration: 1300, easing: "ease-out" });
  }
  // the intensity meter's dark cover slides back to light up the share f (0…1), in whole segments; an arm at
  // rest (under 6%) stays dark instead of blinking one segment on and off
  function setMeter(f) {
    const n = Math.max(1, Math.round($(".meter").clientWidth / 12)), lit = f < 0.06 ? 0 : Math.min(1, f);
    $("#vMeter").style.transform = `scaleX(${1 - Math.round(lit * n) / n})`;
  }

  function reset() {
    scratchEnd(0);
    count = 0; totalSeconds = 0; lastScratchAt = null; currentHz = null; sessionStart = Date.now();
    strip.length = 0; $("#strip").textContent = "";
    $("#vCount").textContent = "0";
    localStorage.setItem("twinSince", String(Date.now()));   // "last night" ignores stored scratches before this
  }

  // what this session caught, for the "last night" page
  window.twinSession = () => ({
    episodes: strip.map((s) => ({ seconds: ((s.end || Date.now()) - s.start) / 1000, intense: !!s.intense, at: s.end || Date.now() })),
  });

  // vitals text and the session strip
  const mmss = (t) => `${Math.floor(t / 60)}:${String(t % 60).padStart(2, "0")}`;
  const ago = (s) => s < 60 ? `${s} s ago` : s < 3600 ? `${Math.floor(s / 60)} min ago` : `${Math.floor(s / 3600)} h ago`;
  setInterval(() => {
    const now = Date.now();
    const live = scratching ? (now - scratchStartedAt) / 1000 : 0;
    $("#vTime").textContent = mmss(Math.round(totalSeconds + live));
    $("#vLast").textContent = lastScratchAt ? (scratching ? "now" : ago(Math.round((now - lastScratchAt) / 1000))) : "—";
    $("#vTime").classList.toggle("hot", scratching); $("#vLast").classList.toggle("hot", scratching);
    $("#vHz").textContent = currentHz ? `${currentHz.toFixed(1)} HZ BACK-AND-FORTH` : "— HZ";
    $("#vIntense").textContent = strip.filter((s) => s.intense).length;
    $("#vLongest").textContent = mmss(Math.round(Math.max(0, ...strip.map((s) => ((s.end || now) - s.start) / 1000))));
    // the whole session (at least a minute) left → right, each scratch an orange mark
    const span = Math.max(60000, now - sessionStart);
    for (const s of strip) {
      if (!s.el) s.el = $("#strip").appendChild(document.createElement("i"));
      s.el.style.left = `${Math.max(0, ((s.start - (now - span)) / span) * 100)}%`;
      s.el.style.width = `${Math.max(0.3, (((s.end || now) - s.start) / span) * 100)}%`;
      s.el.classList.toggle("live", !s.end);
    }
    $("#stripT").textContent = mmss(Math.floor((now - sessionStart) / 1000));
  }, 250);

  // ---------- data in ----------
  // A batch from the watch (through the relay) also proves the watch is live; simulated batches only take().
  function onBatch(msg) { lastBatchAt = Date.now(); take(msg); }
  function take(msg) {
    for (const s of msg.samples || []) queue.push({ m: +s[1] || 0 });
    for (const w of msg.windows || []) {
      lastWin = w;
      const ok = passes(w);
      if (ok) {
        scratchUntil = performance.now() + 1200; if (w.hz) currentHz = w.hz;
        if (ignoring && !scratching) { ignoring = false; scratchStart(w.hz, false); }
      }
      setMeter(ok ? (w.p || 0) : (w.p || 0) * 0.25);
    }
    for (const e of msg.events || []) {
      if (e.type === "start") { if (passes(lastWin)) scratchStart(e.hz, e.intense); else ignoring = true; }
      if (e.type === "end") { if (ignoring) ignoring = false; else scratchEnd(e.seconds); }
    }
    if (queue.length > RATE * 6) queue.splice(0, queue.length - RATE * 2);   // far behind: jump ahead
  }
  window.twinOnBatch = onBatch;
  window.twinLive = () => !simulate && Date.now() - lastBatchAt < 3500;

  let ws, retry = 0;
  function connect() {
    ws = new WebSocket(window.twinUI.wsUrl("/api/live"));
    ws.onopen = () => { retry = 0; };
    ws.onmessage = (ev) => {
      let msg; try { msg = JSON.parse(ev.data); } catch { return; }
      if (msg.type === "batch" && !simulate) onBatch(msg);
      if (msg.type === "reset") reset();
    };
    ws.onclose = () => { setTimeout(connect, Math.min(5000, 500 * 2 ** retry++)); };
    ws.onerror = () => { try { ws.close(); } catch {} };
  }
  connect();
  setInterval(() => { if (ws && ws.readyState === 1) ws.send("ping"); }, 15000);

  // ---------- simulation (rehearsal without a watch) ----------
  let simT = 0, simNextScratch = 4, simScratchLeft = 0, simScratchLen = 0, simTimer = null;
  function simTick() {
    const batch = { samples: [], windows: [], events: [] };
    for (let i = 0; i < RATE / 5; i++) {
      simT += 1 / RATE;
      let m = 0.006 + Math.random() * 0.01;
      if (simScratchLeft > 0) {
        m = 0.16 + 0.22 * Math.abs(Math.sin(simT * 2 * Math.PI * 4.4)) + Math.random() * 0.05;
        simScratchLeft -= 1 / RATE;
        if (simScratchLeft <= 0) batch.events.push({ type: "end", seconds: simScratchLen });
      } else if (simT >= simNextScratch) {
        simScratchLeft = simScratchLen = 4 + Math.random() * 3; simNextScratch = simT + simScratchLeft + 7 + Math.random() * 6;
        batch.events.push({ type: "start", hz: 4.2 + Math.random(), intense: Math.random() < 0.3 });
      }
      batch.samples.push([simT, m]);
    }
    if (simScratchLeft > 0) batch.windows.push({ p: 0.9, scratch: true, hz: 4.4 });
    else batch.windows.push({ p: 0.05 + Math.random() * 0.1, scratch: false });
    take(batch);
  }
  function setSim(on) {
    simulate = on; clearInterval(simTimer);
    if (on) { simTimer = setInterval(simTick, 200); } else { scratchEnd(0); }
    setLive();
  }

  document.addEventListener("keydown", (e) => {
    if (e.target.closest && e.target.closest("input, textarea, [contenteditable]")) return;   // typing in the chat
    if (e.metaKey || e.ctrlKey || e.altKey || e.repeat) return;                              // browser shortcuts (⌘R, ⌘D …)
    const k = e.key.toLowerCase();
    if (k === "f") { document.fullscreenElement ? document.exitFullscreen() : document.documentElement.requestFullscreen(); }
    if (k === "d") setSim(!simulate);
    if (k === "r" && page === "monitor") reset();
    if (["1", "2", "3", "4"].includes(e.key)) show(["monitor", "night", "history", "claude"][+e.key - 1]);
  });
  if (new URLSearchParams(location.search).get("sim") === "1") setSim(true);

  // ---------- trace (hospital-monitor sweep) ----------
  const cv = $("#trace"), ctx = cv.getContext("2d");
  const gv = $("#traceGlow"), gctx = gv.getContext("2d");   // the glow: drawn at half size, blurred by CSS
  let W = 0, H = 0, dpr = 1, cols = [], cursor = 0, phase = 0, carry = 0, lastFrame = performance.now(), smooth = 0;
  function resize() {
    dpr = window.devicePixelRatio || 1;
    const r = cv.getBoundingClientRect(); W = r.width; H = r.height;
    cv.width = Math.round(W * dpr); cv.height = Math.round(H * dpr);
    gv.width = Math.round(W / 2); gv.height = Math.round(H / 2);
    const n = Math.ceil(W / PX_PER_SAMPLE) + 1;
    if (cols.length !== n) { cols = new Array(n).fill(null); cursor = 0; }
  }
  new ResizeObserver(resize).observe(cv);
  window.addEventListener("resize", resize); resize();

  function frame(now) {
    const dt = Math.min(0.1, (now - lastFrame) / 1000); lastFrame = now;
    // play out samples at the watch's rate; speed up when the queue grows (network bursts)
    const speed = queue.length > RATE * 2 ? 2.2 : queue.length > RATE ? 1.4 : 1;
    carry += dt * RATE * speed;
    while (carry >= 1) {
      carry -= 1;
      const s = queue.length ? queue.shift() : { m: 0.004 + Math.random() * 0.004 };
      const isScratch = performance.now() < scratchUntil || scratching;
      smooth += (s.m - smooth) * 0.5;
      const g = Math.min(1, Math.pow(Math.max(0, smooth - 0.014) / 0.25, 0.6));   // 0 at rest … 1 for big motion
      phase += 1.1;
      // no watch: a flat line under "NO SIGNAL" (r scales the ripple)
      cols[cursor] = { g, ph: phase, r: idle ? 0 : 0.75 + Math.random() * 0.25, s: isScratch };
      cursor = (cursor + 1) % cols.length;
      cols[cursor] = null;                                                   // erase ahead of the pen
      for (let k = 1; k < 8; k++) cols[(cursor + k) % cols.length] = null;
    }
    if (page === "monitor") draw(dt);   // behind the other pages the sweep keeps running, undrawn
    requestAnimationFrame(frame);
  }

  // Calm baseline for any motion; while scratching the line lifts up in one smooth hump
  // (height = how hard), with only a small ripple on top.
  function markRecent(n) {
    for (let k = 1; k <= n; k++) {
      const c = cols[(cursor - k + cols.length * 4) % cols.length];
      if (!c) break;
      c.s = true;
    }
  }
  // Walk the columns oldest → newest so the hump rises and falls smoothly. A second pass rounds
  // the corners (an S-curve, no kink where it lifts off), and the drawn level D eases toward the
  // result, so a stretch recoloured by markRecent() rises smoothly instead of jumping.
  // q (1 steady … 0 climbing) quiets the ripple on the slopes, where it would look like stairs.
  function levels(dt) {
    const n = cols.length, follow = 1 - Math.exp(-dt * 8);
    let L = 0, S = 0, Q = 1, prev = null;
    for (let k = 0; k < n; k++) {
      const c = cols[(cursor + 8 + k) % n];
      if (!c) continue;
      // up while the scratching hand moves, straight back down the moment it stops
      const target = c.s && c.g > 0.12 ? 0.35 + 0.65 * c.g : 0;
      L += (target - L) * (target > L ? 0.12 : 0.1);
      const step = (L - S) * 0.25;
      S += step;
      const quiet = Math.max(0, 1 - Math.abs(step) * 40);
      Q += (quiet - Q) * (quiet < Q ? 0.3 : 0.08);
      c.L = S; c.q = Q;
      // a new column carries on from its neighbour while a recoloured stretch is still easing up
      if (c.D === undefined) c.D = prev && Math.abs(prev.D - prev.L) > 0.01 ? prev.D : S;
      else c.D += (S - c.D) * follow;
      prev = c;
    }
  }
  // ripple height as a share of H: small and calm, a little livelier for big ordinary motion
  const ampOf = (c) => (c.s ? 0.004 + 0.012 * c.g : 0.006 + 0.016 * c.g) * c.r * c.q;
  const yOf = (c, base) => base - c.D * H * 0.58 - Math.sin(c.ph) * ampOf(c) * H;
  // 0 calm (lime) … 1 lifted into the hump (orange)
  const heatOf = (c) => { const t = Math.min(1, Math.max(0, (c.D - 0.05) / 0.2)); return t * t * (3 - 2 * t); };
  const LIME = [169, 216, 119], ORANGE = [248, 161, 111];
  const tint = (t, a) => `rgba(${LIME.map((v, k) => Math.round(v + (ORANGE[k] - v) * t))},${a})`;

  function draw(dt) {
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, W, H);
    gctx.setTransform(0.5, 0, 0, 0.5, 0, 0);
    gctx.clearRect(0, 0, W, H);
    const n = cols.length, base = H * 0.76;
    levels(dt);
    // One smooth curve through the columns (the erase gap splits it in two), coloured along x:
    // lime where calm, orange where lifted. The oldest stretch, about to be erased, fades a little.
    const line = new Path2D(), grad = ctx.createLinearGradient(0, 0, (n - 1) * PX_PER_SAMPLE, 0);
    let run = [];
    const flush = () => {
      if (run.length > 1) {
        line.moveTo(run[0].x, run[0].y);
        for (let k = 1; k < run.length - 1; k++) line.quadraticCurveTo(run[k].x, run[k].y, (run[k].x + run[k + 1].x) / 2, (run[k].y + run[k + 1].y) / 2);
        line.lineTo(run[run.length - 1].x, run[run.length - 1].y);
      }
      run = [];
    };
    for (let i = 0; i < n; i++) {
      const c = cols[i];
      if (!c) { flush(); continue; }
      run.push({ x: i * PX_PER_SAMPLE, y: yOf(c, base) });
      const age = ((cursor - 1 - i + n) % n) / n;
      grad.addColorStop(i / (n - 1), tint(heatOf(c), 1 - 0.6 * Math.max(0, (age - 0.75) / 0.25)));
    }
    flush();
    for (const [cx, width, alpha] of [[gctx, 7, 0.6], [ctx, 2.6, 1]]) {   // soft glow, then the crisp line
      cx.lineJoin = "round"; cx.lineCap = "round"; cx.strokeStyle = grad; cx.lineWidth = width; cx.globalAlpha = alpha;
      cx.stroke(line);
    }

    // pen: a faint scan line, a glow and a bright dot
    const pi = (cursor - 1 + n) % n, pc = cols[pi];
    if (!pc) return;
    const x = pi * PX_PER_SAMPLE, y = yOf(pc, base), heat = heatOf(pc);
    const scan = ctx.createLinearGradient(0, y - 180, 0, y + 180);
    scan.addColorStop(0, tint(heat, 0)); scan.addColorStop(0.5, tint(heat, 0.22)); scan.addColorStop(1, tint(heat, 0));
    ctx.fillStyle = scan; ctx.fillRect(x - 0.75, y - 180, 1.5, 360);
    gctx.fillStyle = tint(heat, 1);
    gctx.beginPath(); gctx.arc(x, y, 10, 0, Math.PI * 2); gctx.fill();
    ctx.fillStyle = heat > 0.5 ? "#ffe3d2" : "#ecffd9";
    ctx.beginPath(); ctx.arc(x, y, 4, 0, Math.PI * 2); ctx.fill();
  }
  requestAnimationFrame(frame);
})();
