// Douglas's last 14 nights and everything Claude's tools can read. Shared by Last night, History and Claude.
// Night i started on the evening of nightDate(i); night 13 is last night. The trigger in this story is a
// body wash he ordered for the first time the day before night 10 and started using that evening.
(() => {
  const DAY = 86400000;
  const USUAL = 12;                                                        // minutes a night, his usual
  const NIGHTS = [9, 14, 11, 8, 15, 12, 10, 16, 13, 11, 17, 24, 29, 41]; // minutes of scratching, oldest → last night
  const EPISODES = [8, 11, 9, 7, 12, 10, 8, 12, 11, 9, 13, 16, 19, 23];
  const SLEEP = [7.4, 7.1, 6.2, 6.0, 6.4, 7.5, 7.3, 7.2, 7.6, 7.0, 6.9, 6.4, 5.6, 5.1];
  const WAKES = [0, 1, 1, 1, 0, 0, 1, 0, 0, 1, 1, 1, 2, 2];
  const HUMIDITY = [52, 49, 55, 51, 47, 50, 53, 48, 51, 50, 49, 47, 46, 29];
  const TEMP_F = [64, 66, 63, 61, 65, 67, 66, 64, 63, 65, 66, 64, 63, 68];
  const BODY_WASH = 10, DRY = 13, EXAMS = [1, 3];
  const LAST_NIGHT_HOURS = [["11P", 1], ["12A", 3], ["1A", 6], ["2A", 10], ["3A", 11], ["4A", 6], ["5A", 3], ["6A", 1]];
  const LAST_NIGHT = { episodes: 23, intense: 7, woke: 2, worst: "2–4 AM", from: "11:04 PM", to: "6:52 AM" };
  // The 16 nights before those 14 (nights -16 … -1; the app's StageHistory), so the tools go back 30 nights.
  // Nights -4 … -1 are an earlier flare: on the day of night -5 he bought his first wool sweater and a scented
  // detergent sample, used both on exactly those four nights and stopped both on the day of night 0.
  const EARLIER = {
    nights: [10, 9, 12, 10, 16, 12, 10, 13, 11, 11, 14, 10, 19, 27, 31, 22],
    episodes: [8, 8, 11, 8, 12, 10, 9, 10, 10, 9, 11, 7, 14, 18, 20, 15],
    sleep: [7.9, 6.9, 5.5, 7.6, 7.6, 7.4, 6.9, 7.8, 6.9, 7.2, 6.7, 7.7, 6.8, 6.6, 6.6, 6.9],
    wakes: [0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 1, 0, 1, 2, 2, 1],
    humidity: [28, 60, 53, 49, 63, 50, 68, 29, 49, 58, 51, 71, 61, 61, 70, 48],
    temp: [81, 67, 76, 74, 73, 67, 75, 74, 69, 67, 67, 68, 71, 70, 64, 64],
  };
  const MAX_NIGHTS = 30;                                                   // how far back the tools go (14 by default)
  // HRV (ms; lower = more stress): the last 14 nights as measured; before them his usual 52 with small
  // night-to-night noise, a dip on the earlier flare's nights and after short nights (as the app's Trends).
  const HRV = [53, 51, 52, 54, 50, 52, 53, 51, 52, 53, 51, 46, 42, 38], USUAL_HRV = 52;
  const hrv = (i) => {
    if (i >= 0) return HRV[i];
    const dip = { [-4]: 4, [-3]: 7, [-2]: 8, [-1]: 5 }[i] || 0;
    const noise = (((i * 37 + 1000003) % 7) + 7) % 7 - 3;
    return USUAL_HRV + noise - dip - (at(SLEEP, EARLIER.sleep, i) < 6.5 ? 3 : 0);
  };
  const at = (list, earlier, i) => (i >= 0 ? list[i] : earlier[earlier.length + i]);
  const lastN = (n) => Array.from({ length: n }, (_, k) => NIGHTS.length - n + k); // night numbers, oldest first

  const nightDate = (i) => { const d = new Date(); d.setHours(12, 0, 0, 0); return new Date(d - (NIGHTS.length - i) * DAY); };
  const dayOffset = (i, delta) => new Date(nightDate(i).getTime() + delta * DAY);
  const iso = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
  const wd = (d, long) => d.toLocaleDateString("en-US", { weekday: long ? "long" : "short" });
  const md = (d) => d.toLocaleDateString("en-US", { month: "short", day: "numeric" });
  const today = () => new Date().toLocaleDateString("en-US", { weekday: "long", month: "long", day: "numeric", year: "numeric" });

  // ---- orders: repeat purchases, plus one personal-care item he has never bought before ----
  const BODY_WASH_INGREDIENTS = ["Water", "Sodium Laureth Sulfate", "Cocamidopropyl Betaine", "Fragrance (Parfum)", "Glycerin",
    "Sodium Chloride", "Methylisothiazolinone", "Citric Acid"];
  function orders() {
    const o = (i, delta, item, category, extra) => ({ date: iso(dayOffset(i, delta)), item, category, ...extra });
    return [
      o(0, -60, "Tide Free & Clear Liquid Detergent, 92 loads", "household", { bought_before: true, note: "same product every month for 2 years" }),
      o(0, -52, "Peet's Major Dickason's Coffee Beans, 2 lb", "grocery", { bought_before: true }),
      o(0, -45, "CeraVe Moisturizing Cream, 16 oz", "personal care", { bought_before: true, note: "repeat purchase, uses daily" }),
      o(0, -40, "Five Star Spiral Notebooks, 5 pack", "school", { bought_before: true }),
      o(0, -33, "Colgate Total Toothpaste, 2 pack", "personal care", { bought_before: true }),
      o(0, -30, "Tide Free & Clear Liquid Detergent, 92 loads", "household", { bought_before: true, note: "same product every month for 2 years" }),
      o(0, -24, "Anker USB-C Charging Cable, 6 ft", "electronics", { bought_before: false }),
      o(0, -20, "RXBAR Protein Bars, 12 count", "grocery", { bought_before: true }),
      o(0, -15, "Method Free + Clear Hand Soap Refill", "household", { bought_before: true }),
      o(0, -8, "Duracell AAA Batteries, 8 pack", "school", { bought_before: true }),
      o(0, -5, "Northfield Lambswool Crewneck Sweater", "clothing", { bought_before: false, note: "first wool sweater" }),
      o(0, -5, "FreshMeadow Spring Bloom Detergent, trial size", "household", { bought_before: false, note: "trial size" }),
      o(2, 0, "Peet's Major Dickason's Coffee Beans, 2 lb", "grocery", { bought_before: true }),
      o(3, 0, "Tide Free & Clear Liquid Detergent, 92 loads", "household", { bought_before: true, note: "same product every month for 2 years" }),
      o(5, 0, "Darn Tough Merino Wool Socks, 3 pairs", "clothing", { bought_before: false, note: "washed before wearing" }),
      o(7, 0, "Nissin Top Ramen, 24 pack", "grocery", { bought_before: true }),
      o(BODY_WASH, -1, "Brightwell Ocean Breeze Body Wash, 18 fl oz", "personal care", { bought_before: false, note: "first time ordering any body wash; delivered next day",
        ingredients: BODY_WASH_INGREDIENTS }),
      o(11, 0, "Philips LED Desk Lamp Bulb", "household", { bought_before: true }),
      o(12, 0, "RXBAR Protein Bars, 12 count", "grocery", { bought_before: true }),
    ];
  }

  // ---- the tools Claude can call (the page runs them; results go back to the model as JSON) ----
  const clampN = (n, max, dflt = max) => Math.max(1, Math.min(max, Math.round(+n || dflt)));
  const tools = {
    scratch_history({ nights } = {}) {
      return {
        usual_minutes_per_night: USUAL, measured_by: "Apple Watch, every night",
        nights: lastN(clampN(nights, MAX_NIGHTS, 14)).map((i) => ({ night_of: iso(nightDate(i)), weekday: wd(nightDate(i), true),
          scratch_minutes: at(NIGHTS, EARLIER.nights, i), scratch_episodes: at(EPISODES, EARLIER.episodes, i) })),
        last_night_worst_hours: LAST_NIGHT.worst,
      };
    },
    order_history({ days } = {}) {
      const since = Date.now() - clampN(days, 120) * DAY;
      return { source: "Amazon order history", orders: orders().filter((x) => new Date(x.date).getTime() >= since) };
    },
    weather_history({ days } = {}) {
      return { location: "Berkeley, CA", days: lastN(clampN(days, MAX_NIGHTS, 14)).map((i) => ({ date: iso(nightDate(i)),
        humidity_percent: at(HUMIDITY, EARLIER.humidity, i), high_f: at(TEMP_F, EARLIER.temp, i) })) };
    },
    calendar_events({ days } = {}) {
      return { events: [
        { date: `${iso(nightDate(EXAMS[0]))} to ${iso(nightDate(EXAMS[1]))}`, title: "Midterm exams (CS 61B, Math 54)", note: "stressful week" },
        { date: iso(nightDate(6)), title: "Dentist" },
        { date: iso(nightDate(9)), title: "Team project deadline" },
        { date: iso(new Date(Date.now() + DAY)), title: "CalHacks 13.0 (hackathon)" },
      ] };
    },
    sleep_history({ nights } = {}) {
      return { source: "Apple Health", usual_hrv_ms: USUAL_HRV, nights: lastN(clampN(nights, MAX_NIGHTS, 14)).map((i) => ({ night_of: iso(nightDate(i)),
        hours_asleep: at(SLEEP, EARLIER.sleep, i), wake_ups: at(WAKES, EARLIER.wakes, i), hrv_ms: hrv(i) })) };
    },
  };

  window.twinStory = { USUAL, NIGHTS, EPISODES, SLEEP, WAKES, HUMIDITY, TEMP_F, BODY_WASH, DRY, EXAMS, LAST_NIGHT_HOURS, LAST_NIGHT,
    BODY_WASH_INGREDIENTS, EARLIER, nightDate, dayOffset, iso, wd, md, today, orders, tools };
})();
