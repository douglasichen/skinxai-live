// History (#p-history): 14 nights against his usual. Shows only that the last nights are higher; no causes.
(() => {
  const $ = (s) => document.querySelector(s);
  const S = window.twinStory, { countUp } = window.twinUI;
  const HOT = 3;                                                   // the last three nights carry the story
  const still = matchMedia("(prefers-reduced-motion: reduce)");
  // Motion, in ms after the page shows (it fades in first): calm nights rise in sequence, a beat, then the three hot ones.
  const T = { calm: 400, calmStep: 50, calmMs: 650, hot: 1100, hotStep: 170, hotMs: 900 };

  function show() {
    const n = S.NIGHTS.length, usual = S.USUAL, first = n - HOT;
    const before = S.NIGHTS.slice(0, first), avg = S.NIGHTS.slice(first).reduce((a, b) => a + b, 0) / HOT;
    const lo = Math.min(...before), hi = Math.max(...before);     // his usual range
    const top = Math.max(...S.NIGHTS) * 1.16;                      // headroom for the tallest label
    const pct = (v) => ((v / top) * 100).toFixed(2);

    // headline and chip
    $("#hSince").textContent = `Since ${S.wd(S.nightDate(first), true)}:`;
    $("#hUsual").textContent = usual;
    $("#hChange").textContent = `▲ ${(avg / usual).toFixed(1)}× his usual, ${HOT} nights running`;
    // the average counts up while the three hot nights rise, so it lands together with its evidence
    const num = $("#hAvg"), t0 = performance.now();
    num.style.minWidth = ""; num.textContent = Math.round(avg);
    document.fonts.ready.then(() => {   // reserve the final width (in em, so it survives a resize): no reflow while counting
      num.style.minWidth = `${num.getBoundingClientRect().width / parseFloat(getComputedStyle(num).fontSize)}em`;
      countUp(num, avg, { ms: T.hotMs + (HOT - 1) * T.hotStep, delay: Math.max(0, T.hot - (performance.now() - t0)) });
    });

    // plot: usual range band, dashed usual line with its label in the right margin, one column per night
    const plot = $("#hPlot");
    plot.style.setProperty("--row", pct(hi));
    plot.innerHTML = `<div class="hband" style="bottom:${pct(lo)}%;height:${pct(hi - lo)}%"></div>`
      + `<div class="hline" style="bottom:${pct(usual)}%"><i></i></div>`
      + `<div class="hlabel" style="bottom:${pct(usual)}%"><b>HIS USUAL</b><span>${usual} min</span></div>`
      + `<div class="hcols">${S.NIGHTS.map((m, i) => {
        const hot = i >= first, d = hot ? T.hot + (i - first) * T.hotStep : T.calm + i * T.calmStep;
        const over = hot ? `<i class="hx" style="height:${(((m - usual) / m) * 100).toFixed(2)}%"></i>` : "";
        return `<div class="hcol${hot ? " hot" : ""}" style="--h:${pct(m)};--d:${d}ms;--dur:${hot ? T.hotMs : T.calmMs}ms">`
          + `<i class="hbar">${over}</i><b class="hval">${m}${hot ? "<small>min</small>" : ""}</b></div>`;
      }).join("")}</div>`;
    $("#hAxis").innerHTML = S.NIGHTS.map((_, i) => {
      const d = S.nightDate(i), date = i === 0 || d.getDate() === 1 ? S.md(d) : d.getDate();
      return `<span${i >= first ? ' class="hot"' : ""}><b>${S.wd(d).toUpperCase()}</b>${date}</span>`;
    }).join("");
    $("#hChart").setAttribute("aria-label", `Minutes of scratching per night, oldest first: ${S.NIGHTS.map((m, i) =>
      `${S.wd(S.nightDate(i))} ${S.md(S.nightDate(i))} ${m}`).join(", ")}. His usual is ${usual}.`);

    // restart the choreography (CSS animations under .play); --end is when the last hot night lands
    const page = $("#p-history");
    page.style.setProperty("--end", `${T.hot + (HOT - 1) * T.hotStep + T.hotMs}ms`);
    page.classList.remove("play");
    if (!still.matches) { void page.offsetWidth; page.classList.add("play"); }
  }

  window.addEventListener("twin:page", (e) => { if (e.detail === "history") show(); });
})();
