// Small helpers shared by the pages (load before the page scripts).
(() => {
  const ease = (t) => 1 - Math.pow(1 - t, 3);
  const still = matchMedia("(prefers-reduced-motion: reduce)");
  const counts = new WeakMap();   // element → its latest count; a newer count on the same element ends the older one
  // Count a number up from `from` to `to`, starting after `delay` ms; `fmt` formats each frame. The element shows
  // the start value at once. Under reduced motion it shows the final value straight away.
  function countUp(el, to, { ms = 900, delay = 0, from = 0, fmt = (v) => Math.round(v) } = {}) {
    const id = {};
    counts.set(el, id);
    if (still.matches) { el.textContent = fmt(to); return; }
    el.textContent = fmt(from);
    let t0 = 0;
    const step = (now) => {
      if (counts.get(el) !== id) return;
      t0 = t0 || now;
      const t = Math.min(1, (now - t0) / ms);
      el.textContent = fmt(from + (to - from) * ease(t));
      if (t < 1) requestAnimationFrame(step);
    };
    setTimeout(() => requestAnimationFrame(step), delay);
  }
  const esc = (s) => String(s).replace(/[&<>"]/g, (ch) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[ch]));
  // API base: same origin when served by the Worker; for local work (python3 -m http.server) add
  // ?api=https://eczema-twin-live.zhongzhenyu190.workers.dev to use the deployed relay.
  const API = (new URLSearchParams(location.search).get("api") || "").replace(/\/$/, "");
  const api = (path) => API + path;
  const wsUrl = (path) => API ? API.replace(/^http/, "ws") + path : `${location.protocol === "https:" ? "wss:" : "ws:"}//${location.host}${path}`;
  window.twinUI = { ease, countUp, esc, api, wsUrl, sleep: (ms) => new Promise((r) => setTimeout(r, ms)) };
})();
