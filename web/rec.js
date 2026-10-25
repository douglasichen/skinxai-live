// Labelled test recording: the big screen walks you through a set of moves while the relay
// stores the watch's raw motion, so the scratch detector can be tuned on real data. Key T or the button.
(() => {
  const $ = (s) => document.querySelector(s);
  const STEPS = [
    ["still", "Hold your arm still", 10],
    ["scratch_light", "Scratch your forearm lightly", 10],
    ["scratch_normal", "Scratch your forearm normally", 10],
    ["scratch_hard", "Scratch your forearm hard", 10],
    ["scratch_head", "Scratch your head or neck", 10],
    ["pat_thigh", "Pat your thigh", 10],
    ["wave", "Wave your hand", 10],
    ["typing", "Type or use your phone", 10],
    ["gesture", "Talk with your hands", 10],
  ];
  const REST = 4;
  let running = false, cancelled = false, msgTimer = 0;

  const post = (body) => fetch(window.twinUI.api("/api/label"), { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) })
    .then((r) => r.json()).catch(() => ({}));
  const wait = (ms) => new Promise((r) => setTimeout(r, ms));

  async function countdown(seconds, onTick) {
    const t0 = performance.now();
    while (!cancelled) {
      const left = seconds - (performance.now() - t0) / 1000;
      if (left <= 0) break;
      onTick(left);
      await wait(100);
    }
  }

  function show(step, text, num, frac, hint) {
    $("#recStep").textContent = step; $("#recText").textContent = text;
    $("#recNum").textContent = num; $("#recBar").style.transform = `scaleX(${frac})`;
    $("#recOv").classList.toggle("msg", num === "");   // a message, not a countdown: no number, no bar
    if (hint !== undefined) $("#recHint").textContent = hint;
  }

  async function run() {
    if (running) return;
    const ov = $("#recOv");
    clearTimeout(msgTimer);   // one timer for the message below: a second press shows it for the full time again
    if (!window.twinLive || !window.twinLive()) {
      ov.classList.add("on");
      show("TEST RECORDING", "Start monitoring on the watch first", "", 0, "Then press Record test again");
      msgTimer = setTimeout(() => ov.classList.remove("on"), 3500);
      return;
    }
    running = true; cancelled = false; ov.classList.add("on"); ov.classList.remove("go");
    const start = await post({ action: "start", name: "labelled test" });
    for (let i = 0; i < STEPS.length && !cancelled; i++) {
      const [label, text, secs] = STEPS[i];
      ov.classList.remove("go");
      await countdown(REST, (left) => show(`NEXT · ${i + 1} OF ${STEPS.length}`, text, Math.ceil(left), 0, "Get ready, keep still"));
      if (cancelled) break;
      ov.classList.add("go");
      await post({ action: "step", label, phase: "start" });
      await countdown(secs, (left) => show(`NOW · ${i + 1} OF ${STEPS.length}`, text, Math.ceil(left), 1 - left / secs, "Esc to cancel"));
      await post({ action: "step", label, phase: "end" });
    }
    await post({ action: "end" });
    ov.classList.remove("go");
    show("TEST RECORDING", cancelled ? "Cancelled" : "Done. Thank you!", "", cancelled ? 0 : 1, start.id ? `Saved as ${start.id}` : "");
    await wait(3500);
    ov.classList.remove("on"); running = false;
  }

  $("#recBtn").addEventListener("click", run);
  document.addEventListener("keydown", (e) => {
    if (e.target.closest && e.target.closest("input, textarea, [contenteditable]")) return;
    if (e.metaKey || e.ctrlKey || e.altKey || e.repeat) return;   // ⌘T opens a browser tab, not a recording; a held T is one press
    if ((e.key === "t" || e.key === "T") && $("#p-monitor").classList.contains("on")) run();
    if (e.key === "Escape" && running) cancelled = true;
  });
})();
