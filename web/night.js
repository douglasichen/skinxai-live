// Last night (#p-night): the bundled night from window.twinStory plus scratches the watch caught live.
(() => {
  const $ = (s) => document.querySelector(s);
  const S = window.twinStory, { countUp } = window.twinUI;
  const TOP = 12;                  // chart scale: minutes of an hour bar at full height
  const LOOKBACK = 30 * 60e3;      // after a reload, the relay's scratches from the last 30 minutes still count as live

  // The relay's scratches since the last reset (R on Monitor), at most LOOKBACK old. A stalled network gives up
  // after 1.5 s: the bundled night is on screen already, only the live part is missing.
  async function storedEpisodes() {
    const since = Math.max(Date.now() - LOOKBACK, +(localStorage.getItem("twinSince") || 0)) / 1000;
    const ctl = new AbortController(), timer = setTimeout(() => ctl.abort(), 1500);
    try {
      const j = await (await fetch(window.twinUI.api(`/api/events?since=${since}`), { signal: ctl.signal })).json();
      return (j.episodes || []).map((e) => ({ seconds: e.seconds, intense: e.intense, at: (e.end || e.start) * 1000 }));
    } catch { return []; } finally { clearTimeout(timer); }
  }

  // the two neighbouring hours with the most scratching ("2–4 AM")
  function worstPair(hours) {
    let best = 0;
    for (let k = 1; k < hours.length - 1; k++) if (hours[k][1] + hours[k + 1][1] > hours[best][1] + hours[best + 1][1]) best = k;
    return [best, best + 1];
  }
  const hourLabel = (h) => h.replace(/([AP])$/, "<small>$1M</small>");   // "2A" → 2 AM
  const ratio = (minutes) => `▲ ${(minutes / S.USUAL).toFixed(1)}× his usual`;
  const ago = (ms) => ms < 10 * 60e3 ? "just now" : ms < 90 * 60e3 ? `${Math.round(ms / 60e3)} min ago` : "earlier today";
  // one column of the chart; its bar grows `t` ms after the chart shows and the value follows
  const column = (cls, h, value, label, t) => `<div class="col ${cls}" style="--h:${Math.min(1, h).toFixed(3)};--t:${Math.round(t)}ms">`
    + `<div class="plot"><i class="bar"></i><b class="val">${value}</b></div><span class="hr">${label}</span></div>`;
  const painted = (fn) => requestAnimationFrame(() => requestAnimationFrame(fn));   // once the start state is on screen

  let shown = 0, shownAt = 0;      // a newer show() wins over a slower earlier one
  // Each card counts up as it rises in (night.css staggers them the same way). Live scratches recount from the
  // number on screen, so a late answer from the relay carries on instead of starting over.
  const COUNTS = [["#nMin", 150], ["#nEp", 220], ["#nInt", 290]];
  function count(totals) {
    const t = performance.now() - shownAt;
    COUNTS.forEach(([id, at], k) => countUp($(id), totals[k], { delay: Math.max(0, at - t), from: +$(id).textContent || 0 }));
  }

  // The bundled night, at once: eyebrow, headline, cards and the hours with the worst two hot.
  function night(token) {
    const bars = $("#nightBars"), last = S.nightDate(S.NIGHTS.length - 1), minutes = S.NIGHTS[S.NIGHTS.length - 1];
    const hours = S.LAST_NIGHT_HOURS, [w0, w1] = worstPair(hours);
    $("#nightRange").textContent = `LAST NIGHT · ${S.wd(last).toUpperCase()} ${S.LAST_NIGHT.from} → ${S.LAST_NIGHT.to}`;
    $("#nMin").style.minWidth = `${String(minutes).length}ch`;   // the headline doesn't shift while counting
    $("#nRatio").textContent = ratio(minutes);
    $("#nWorst").textContent = S.LAST_NIGHT.worst;
    COUNTS.forEach(([id]) => { $(id).textContent = "0"; });
    count([minutes, S.LAST_NIGHT.episodes, S.LAST_NIGHT.intense]);
    countUp($("#nWake"), S.LAST_NIGHT.woke, { ms: 700, delay: 360, fmt: (v) => Math.round(v) + "×" });
    bars.classList.remove("shown");
    bars.innerHTML = hours.map(([h, m], k) => column(k === w0 || k === w1 ? "hot" : "", m / TOP, `${m}<small>min</small>`, hourLabel(h), 450 + k * 70)).join("");
    $("#nLive").classList.remove("on"); $("#nLive").textContent = "";
    painted(() => { if (token === shown) bars.classList.add("shown"); });
  }

  // What the watch caught: the totals count on, a pink NOW bar joins after the hours (making room first when the
  // chart is already up) and the note says how many and how recent.
  function addLive(live, token) {
    const bars = $("#nightBars"), note = $("#nLive"), t = performance.now() - shownAt;
    const sec = live.reduce((a, e) => a + (e.seconds || 0), 0), minutes = S.NIGHTS[S.NIGHTS.length - 1] + sec / 60;
    $("#nMin").style.minWidth = `${String(Math.round(minutes)).length}ch`;
    $("#nRatio").textContent = ratio(minutes);
    count([minutes, S.LAST_NIGHT.episodes + live.length, S.LAST_NIGHT.intense + live.filter((e) => e.intense).length]);
    // at least 5% high, so a few seconds still show, yet lower than the 1-minute hours
    const s = Math.max(1, Math.round(sec)), late = bars.classList.contains("shown");
    bars.insertAdjacentHTML("beforeend", column(`live${late ? " enter" : ""}`, Math.max(0.05, sec / 60 / TOP),
      `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`, "NOW", Math.max(300, 450 + S.LAST_NIGHT_HOURS.length * 70 - t)));
    const col = bars.lastElementChild, newest = Math.max(...live.map((e) => e.at || 0));
    note.textContent = `Includes ${live.length} scratch${live.length > 1 ? "es" : ""} the watch caught live ${ago(Date.now() - newest)}.`;
    note.style.setProperty("--t", `${Math.round(Math.max(400, 1300 - t))}ms`);
    painted(() => { if (token === shown) { col.classList.remove("enter"); note.classList.add("on"); } });
  }

  function show() {
    const token = ++shown;
    shownAt = performance.now();
    night(token);
    const local = window.twinSession ? window.twinSession().episodes : [];
    if (local.length) addLive(local, token);
    else storedEpisodes().then((live) => { if (token === shown && live.length) addLive(live, token); });
  }

  window.addEventListener("twin:page", (e) => { if (e.detail === "night") show(); });
})();
