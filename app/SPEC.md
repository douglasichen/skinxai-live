# Eczema Twin — build spec (CalHacks 13.0)

**One line:** your Apple Watch knows when you scratch; Claude tells you why.

Native SwiftUI iPhone app + Apple Watch app. Built for a 3-minute hackathon demo on stage
and for real use on Jacky's iPhone 16 Plus (iOS 27) + Apple Watch. The bar is **"looks like a
shipped Apple Design Award app"**: every screen polished, lots of meaningful motion, zero
placeholder text, zero crashes, works fully offline with the demo data.

Visual reference: `prototype/index.html` (open it, read the CSS/JS for exact layout and
motion) and the screenshots in `docs/prototype/*.png`. The native app must look **at least as
good** as the prototype, ideally better. Follow the prototype's layout and copy unless this spec
says otherwise.

---

## 1. Story and data (already built — `Packages/EczemaKit`)

Douglas, a college student with eczema. Two weeks of data (`DemoData.make(today:experimentDay:)`):

- Days 1–6 calm (~11 min scratching/day). Day 5: starts a **new scented body wash**.
  Day 6: indoor air turns **dry** (<30% humidity) and stays dry.
- Day 7 on: **flare**. Scratching ~3×, mostly 2–4 a.m.; sleep and HRV drop.
- Days 11–12: exam stress (comes after the flare started).
- Day 14 = today: ~47 min (depends on the hour; later hours are empty). Claude's **case file** is ready.
- `experimentDay: 1...10` extends the story: the user paused the body wash; scratching falls
  back toward normal (35 → 10 min/day) while the air stays dry ⇒ the body wash is confirmed.

Models (`Models.swift`): `TwinDataset` (days, episodes, baselineMinutesPerDay, caseFile,
experiment, isDemo), `DayRecord` (24 hourly scratch minutes, episodes, intense count, sleep,
wake-ups, HRV, resting HR, humidity, temp, AQI, pollen, exposures), `ScratchEpisode`,
`Exposure`/`ExposureKind` (label + emoji), `CaseFile`, `Suspect`, `Confidence`
(label + 0…1 score), `ExperimentPlan`, `Experiment`.

`AppState` (App/iOS/Shell) owns `dataset`, the selected tab, sheets and demo time travel
(`startExperiment()`, `setExperimentDay(_:)`). Read data from `app.dataset`; never hard-code
numbers that exist in the dataset. Dates are relative to "now", so format them
(`Text(date, format: .dateTime.month(.abbreviated).day())`), never hard-code "Oct 18".

---

## 2. Design language (Raft colors & layout, our motion)

Use the tokens and components in `Shared/Design` — do not invent new colors or fonts.

- **Surfaces:** yellow frame (`Twin.Palette.frame`) only on top-level top bars (`TopBar`/
  `ScreenScaffold`). Content sits on white paper. Cream (`cream`) for secondary/info cards.
  Light mode only.
- **Ink:** text and control edges are ink `#141111`. Muted 68%, hint 55%.
- **Lines:** 1pt hairline (15% ink) for card outlines and dividers; 1.5pt solid ink for
  controls, stickers, fields, the selected thing.
- **Stickers:** a block of brand color with a 1.5pt ink edge and ink text (`Sticker`, `.sticker()`).
  Badges, tags, icon tiles, rank numbers. Square-ish corners: sticker 3, chip 4, control 6,
  card 10, sheet top 16. **Nothing is round** except rings/charts, switches and sheet grabbers.
- **Color meanings (strict):** yellow = you/selected · pink = to do / main action · cyan = this
  item / progress · orange = flare / above usual / warning · lime = good / improving ·
  red = danger / see a doctor.
- **Type:** Space Grotesk for everything people read (`Twin.Typeface.sans`), Space Mono for
  what machines write: times, dates, units, counts in eyebrows (`Twin.Typeface.mono`).
  Eyebrows are UPPERCASE mono 11pt (`Eyebrow`). Big numbers 40–56pt bold, tight tracking (-1…-2).
- **Spacing:** screen side padding 16; card padding 16; gaps 12; generous whitespace.
- **Icons:** SF Symbols (weight .semibold) or the exposure emoji inside a sticker tile.
- **Watch:** black background, white text, the same brand colors and fonts; big tap targets.
- The only hard offset shadow is the pink "+" button (brand moment).

## 3. Motion (ours — lots of it, all meaningful)

Use `Twin.Motion` (spring, bouncy, slide, fill, stagger) and the helpers `RingView`, `CountUp`,
`.riseIn(delay)`, `PixelSpinner`, `TwinButtonStyle`, `PressableStyle`, `Haptics`.
Required on every screen:

1. **Entrance choreography:** sections rise in one after another (`.riseIn(i * Twin.Motion.stagger)`).
2. **Numbers count up** (`CountUp`) when they first appear and when they change.
3. **Charts grow** from zero with a spring, bar by bar (stagger ~0.03 s).
4. **Rings fill** (`RingView`).
5. **Every tap gives feedback:** press squash + haptic (`TwinButtonStyle`/`PressableStyle`).
6. **Selection moves** with `matchedGeometryEffect` (tab sticker, segmented controls, selected day).
7. **State changes animate** (`withAnimation(Twin.Motion.spring)`), lists insert/remove with transitions.
8. **Hero moments:** the Insight case file reveal, the experiment result, the watch scratch alert.
9. **Respect Reduce Motion** (`@Environment(\.accessibilityReduceMotion)`): skip movement, keep fades.
10. Loops only while something is happening (spinner while loading, the watch ripple while the alert is up).

Use `.contentTransition(.numericText())`, `PhaseAnimator`, `KeyframeAnimator`, `.symbolEffect`,
`.sensoryFeedback` where they make things nicer (iOS 17 / watchOS 10 APIs are fine).

---

## 4. Screens

Launch argument `-screen <name>` opens a screen directly (used by `scripts/shot`).

### iPhone — tab bar: Today · Trends · Insight · Test (+ pink "+" button)

**Today** (`App/iOS/Screens/Today`) — "how bad is it right now?"
- Top bar: "Today", date subtitle (e.g. "SAT · OCT 24"), `UserAvatar`.
- Hero card: eyebrow "Scratching today"; big `RingView` (progress = today ÷ (3 × usual), orange
  when above usual, lime when at/below) with the minutes counting up in the middle; a sticker
  "▲ 3.9× your usual" (orange) or "Normal day" (lime); one line: when it happened most
  ("Mostly at night, 2–4 am") and episode / intense counts.
- 24-hour bar chart under it (bars grow in, the worst hours orange with ink edge, others 15% ink;
  axis labels 12a 6a 12p 6p now; a "now" marker).
- **Claude call-to-action card** (pink soft, ink edge, shimmer sweep): "Claude found a likely
  trigger" → switches to the Insight tab. If an experiment is running instead: "Day N of your
  test" → Test tab.
- Two mini cards: Sleep (hours, wake-ups) and Stress (HRV ms, "lower than usual").
- "Around you · auto" cream card: stickers for humidity (orange when <35% "dry"), air quality,
  pollen, temperature.
- Tapping the hero opens a sheet with today's episodes (time, length, intensity flame) — nice to have.

**Trends** (`App/iOS/Screens/Trends`) — "what changed?"
- Big number: average minutes/day this week, sticker "▲ up 158% from last week" (computed).
- 14-day bar chart (or all days in the experiment story): flare days orange, a dashed
  "your usual" line, exposure markers above the bars where something started (the body wash
  sticker on day 5, dry air on day 6). Tap a bar → that bar gets selected (cyan outline,
  matchedGeometry) and a detail strip below animates to that day's numbers.
- Segmented control 7 days / 14 days / All (matchedGeometry thumb).
- "What changed" list: each exposure with its start date (sticker tile + title + date).
- Sleep & stress mini trend lines (Swift Charts `LineMark`) — nice to have.

**Insight** (`App/iOS/Screens/Insight`) — the hero of the demo.
- Top bar "Insight", subtitle "CASE #3 · <date>", sticker "✶ Claude".
- On appear (first time per launch, or when "Re-run analysis" is tapped): a **thinking** card
  with `PixelSpinner` and 3 status lines that change ("Reading 14 days of scratching, sleep and
  weather…" → "Checking what changed 1–3 days before each jump…" → "Ranking suspects…"), ~2.2 s.
- Then the **summary types out** (word by word, with a block caret).
- Then **suspect cards fly in by rank** (spring, stagger 0.15 s): rank sticker, title,
  confidence sticker (yellow for the top suspect), a confidence bar that fills (cyan), the
  evidence sentence, and for #1 an **evidence timeline**: a day strip where the start of the
  suspect (pink tile, "started <date>") connects with a drawn arc to the flare (orange tile,
  "+2 days"). The arc draws itself (`trim` animation).
- "Can't separate yet" note (orange left bar). Red flags block if any (red).
- Pink primary button "Start a 10-day test: pause the body wash →" → `app.startExperiment()`.
- Footer: "Not a diagnosis. If skin oozes, crusts or you get a fever, see a doctor today."
- Secondary: "Re-run analysis" (runs the live model when an API key is set — see §6 — else
  replays the bundled analysis), "Share with my doctor" → Report sheet.

**Test** (`App/iOS/Screens/Experiment`)
- No experiment: an empty state that explains the suggested test with a big start button.
- Running: top bar "Experiment", subtitle = plan title, cyan sticker "Day N / 10".
  Big cyan progress ring (day N of 10) counting up; 10 day tiles (done = lime, today = yellow,
  bobbing; future = paper). Comparison bars "With wash" (orange) vs "Paused" (lime) with counted
  numbers and a lime sticker "▼ 56% less so far"; tip card (cream).
- Demo controls (small, clearly secondary): "Fast-forward a day ▶︎" (calls `setExperimentDay`)
  so the stage demo can show progress; at day 10 a **result moment**: the card flips/expands to
  "Confirmed: the body wash is a trigger for you" with a burst animation + success haptic.

**Quick tag sheet** (`App/iOS/Screens/Tag`) — pink "+" opens it.
- "Anything new today?" + "Everything else is tracked for you."; a flow layout of tag chips
  (`ExposureKind.taggable`, emoji + label, 1.5pt ink edge, selected = yellow with a pop);
  "Scan a product label" button (camera; can be a polished stub if time is short);
  "Save" (yellow) adds exposures to today via `app.update`, closes the sheet, shows a HUD toast
  ("Saved · Claude will include it").

**Onboarding** (`App/iOS/Screens/Onboarding`, first launch or `-screen onboarding`) — 3 pages:
(1) "Your skin keeps a diary. Eczema Twin reads it." with an animated illustration made of
shapes (watch + scratch waves); (2) what's tracked automatically (watch scratching, sleep,
weather/air/pollen) with animated stickers; (3) permissions (Health, Location, Notifications)
with real permission requests and "Pair your watch" status. Page dots, swipe, spring transitions.

**Report** (`App/iOS/Screens/Report`) — "Share with my doctor": one-page summary (14-day chart,
top suspects, experiment result, sleep, a disclaimer) rendered in-app and exported as **PDF**
(`ImageRenderer`) through `ShareLink`.

**Settings** (`App/iOS/Screens/Settings`, avatar button): demo/real data switch, demo time
travel (story day / experiment day), AI provider + model + API key field (stored in Keychain;
never logged), units, "Replay onboarding", about.

**Demo tour** (`-autoplay tour`, owned by the shell agent): drives the app through the stage
story automatically (Today 4 s → tap the Claude card → Insight full reveal → Start test →
Experiment → fast-forward to day 10 result → Trends) so we can record a backup video.

### Apple Watch (`App/Watch`)

One screen (stage polish; it replaces the ring, the Recent page and the scratch alert):
- "Twin" title (yellow) with the big screen's two-circle mark on the clock's line.
- A big round button: **Start** (pink) / **Stop** (dark, cyan ring, the running time). While it
  monitors, a ring pings out of it (orange while a scratch is going on).
- Tonight's scratch count under it: a big number that rolls up and bumps with a light haptic on
  each detected episode (counted from Start, kept after Stop until the next Start).
- One status line from the live stream: "Connected to screen" (cyan) / "Can’t reach screen (why)"
  (orange) / "Not monitoring".
- **Live detection** (real device): `CMMotionManager` at 50 Hz inside an `HKWorkoutSession`
  (fallback `WKExtendedRuntimeSession` "physical-therapy", 1 h) + all-day `CMSensorRecorder`
  (12 h at a time, re-armed when the app opens, analysed in 1-hour slices).
  Detection algorithm in §5. Motion and episodes stream to the big screen (`LiveStreamer`).
- Sends episodes to the iPhone with `WatchConnectivity` (`transferFile` / `transferUserInfo`);
  the iPhone merges real episodes into today (real data wins over demo for today when present).

---

## 5. Scratch detection (EczemaKit/Detection, used by the watch)

Streaming detector over accelerometer samples (g, gravity included), 50 Hz:
- 3-second windows, 1.5-second hop. Remove gravity by subtracting each axis mean in the window.
- Movement gate: largest per-axis SD > 0.02 g (Lilly 2023 movement detection idea).
- Use the axis with the most motion. Dominant rate = the **first** autocorrelation peak in the
  1.5–10 Hz band that is ≥ 0.85 × the highest peak (a pure rhythm also peaks at 2×, 3× its
  period). Periodicity = that peak's height. Also the zero-crossing rate.
- Features → logistic model (periodicity, in-band score for 2.5–7 Hz, log strength, crossing
  rate), hand-set starting weights, **learns online from the user's Yes/No answers**.
- Episode = ≥ 2 scratch windows in a row, allowing a 1-window gap; trim half a hop at both ends.
  `intense` = mean SD ≥ 0.35 g. Call back as soon as an episode starts (to buzz at most once per 45 s).
- Unit tests with synthetic signals (4 Hz scratch, walking 0.9 Hz, typing noise, a single
  roll-over) — scratch detected, others ignored, faster scratch ⇒ higher Hz.

## 6. AI analysis (EczemaKit/Insight)

- **Stats first, then the model explains.** `StatsEngine` computes per exposure kind: days it
  appeared, mean scratch minutes 1–3 days after vs other days, effect ratio, and which suspects
  started on the same/adjacent day (can't separate). Baseline = median of calm days; anomaly =
  ≥ 2 days in a row above 1.5 × baseline.
- `InsightClient` sends the stats table + the daily log to an OpenAI-compatible chat endpoint
  (OpenRouter: `https://openrouter.ai/api/v1/chat/completions`) with the system prompt in
  `research/.../claude-test/system.txt` style (copy it into the package as a resource),
  asks for JSON, decodes into `CaseFile`. Model is a setting: default
  `anthropic/claude-sonnet-5.5` for the demo; DeepSeek for development testing.
  API key from the Keychain (Settings) — **never hard-coded, never logged, never in git**.
- Without a key, or offline, or on any error: use the bundled case file (`DemoData.demoCaseFile`)
  and say so in small print ("Bundled analysis"). The demo must never depend on the network.
- Never diagnose; red flags → "see a doctor today".
- Test the prompt + JSON contract from the command line with DeepSeek through OpenRouter using
  `vault-run` and the placeholder `<agent-vault:botiverse-openrouter-api-key>` in a script
  template (the secret is substituted at run time; never print it).

---

## 7. Ownership (parallel work — stay inside your area)

| Area | Owns (create/modify freely) |
|---|---|
| `watch` | `App/Watch/**`, `Packages/EczemaKit/Sources/EczemaKit/Detection/**`, its tests |
| `today-trends` | `App/iOS/Screens/Today/**`, `App/iOS/Screens/Trends/**`, `Shared/Design/Charts/**` |
| `insight-experiment` | `App/iOS/Screens/Insight/**`, `App/iOS/Screens/Experiment/**`, `Packages/EczemaKit/Sources/EczemaKit/Insight/**` (+ Resources it needs), its tests |
| `shell` | `App/iOS/Shell/**` (tab bar, root, autoplay tour), `App/iOS/Screens/Tag|Onboarding|Report|Settings/**`, `App/iOS/Services/**` (WatchLink receive, HealthKit, location, Keychain), `Packages/EczemaKit/Sources/EczemaKit/Environment/**` |

Shared files (`Shared/Design/Theme.swift`, `Shared/Design/Components.swift`,
`Packages/EczemaKit/Sources/EczemaKit/Models.swift`, `DemoData.swift`, `AppState.swift`,
`project.yml`): **additive changes only** (new properties/methods/components; never rename or
change existing behavior), keep them minimal and list them in your final report. If you need a
new shared UI component, put it in your own folder first.

Never edit another area's files. Never run `git push`. Don't send any chat messages.

## 8. Build, run, look — every change

```
scripts/rb <name> ios|watch|all|device    # remote build on Mac mini 2 (errors only)
scripts/shot <name> <screen> [wait] [args] # iPhone screenshot -> shots/<name>-<screen>.png
scripts/watchshot <name> <screen> [wait]   # watch screenshot
scripts/video <name> ios|watch <screen> <secs> [args]  # mp4 + frames every 0.5 s
cd Packages/EczemaKit && swift test -Xswiftc -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks -Xlinker -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks
```
- `<name>` = your area name (each name has its own remote copy, DerivedData and simulators).
- Open every screenshot / video frame with the **Read** tool and judge it honestly against the
  prototype and this spec. Iterate until it is excellent. "It compiles" is not done.
- Builds take ~30 s–2 min; screenshots ~20–60 s. Shut your simulators down when you finish
  (`source scripts/common.sh; rssh "xcrun simctl shutdown all"` is NOT allowed — only shut down
  your own: `rssh "xcrun simctl shutdown 'ET-<name>-iPhone'; xcrun simctl shutdown 'ET-<name>-Watch'"`).
- Swift 5 language mode, iOS 17 / watchOS 10 deployment, Xcode 27.1 (iOS 27 SDK).
- Commit often on your branch with clear messages ending with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
