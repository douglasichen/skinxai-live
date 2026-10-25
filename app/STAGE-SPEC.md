# Eczema Twin — stage build (CalHacks demo), 2026-10-24

Jacky approved a clickable prototype: **`prototype/v5.html`** (open it in a browser or read its HTML/CSS/JS:
it holds the exact layout, copy, numbers and motion). Build it into this native iPhone app. Where this
file and the prototype disagree, this file wins. `SPEC.md` §2 (design language) and §3 (motion) still
apply in full.

**Hard rules from Jacky**
- **Keep the app's existing style exactly.** Use the tokens and components in `Shared/Design`
  (`Twin.Palette`, `Twin.Typeface`, `Sticker`, cards, `RingView`, `CountUp`, `PixelSpinner`,
  `TwinButtonStyle`, `PressableStyle`, `Haptics`, `TopBar`/`ScreenScaffold`, `PermissionRow`…). No new
  colors, fonts or visual languages. The prototype was written in that style; copy it, don't restyle it.
- **It must feel like a real, shipped product in real use.** Nothing visible says demo, prototype,
  simulation, story, mock or test in normal use. Demo controls exist only behind the hidden gesture (§2).
- No model switch, no API key field, no provider settings anywhere. Claude runs on our server (§5).
- English UI copy, short plain sentences, second person ("your usual", not "his usual").

**The stage flow** (the iPhone is mirrored to the big screen with a USB-C → HDMI cable):
1. Douglas taps **Start** on the watch (watch app build 9, unchanged) and lies down "asleep".
2. The phone is on **Today**. A small cyan **"● Live"** sticker appears in the top bar next to the
   avatar. Jacky taps it → the phone turns to **landscape** and shows the **live monitor** (bars, §4).
3. Douglas scratches → new bars grow long and orange, the count pops. He stops → the bars shrink back.
4. Douglas taps **Stop** on the watch ("wakes up") → the monitor closes by itself, the phone is
   portrait on Today again, toast "Good morning, Douglas · last night is ready".
5. Today shows **last night** (41 min, 3.4× usual). The pink card "Up 3 nights in a row · Ask Claude
   what changed" leads to **Insight**. Trends shows 14 nights with three markers.
6. On **Insight** Douglas asks Claude (real Claude Sonnet 5.5 through our server, real tool calls) →
   tool cards → a timeline card → the body wash card → three questions (detergent, stress, where it
   itches) → the conclusion card ("The new body wash" + what was ruled out + a 5-night test).
7. Tapping the avatar **D** shows what the app can read (the onboarding permissions page, §2).

---

## 1. Data — `StageStory` (EczemaKit) — area `foundation`

One source of truth for every number on screen and for Claude's tools: a port of
`/Users/jackytheking/.slock/agents/bdc71284-08a6-463e-b0a7-dd5dac54b8d9/projects/eczema-twin-live/web/story.js`
with these **new numbers** (prototype v5):

- `nights` (minutes of scratching per night, oldest → last night):
  `[9, 14, 11, 8, 15, 12, 10, 16, 13, 11, 17, 24, 29, 41]`; `usual = 12`.
- `episodes` per night: `[8, 11, 9, 7, 12, 10, 8, 12, 11, 9, 13, 16, 19, 23]`.
- Night `i` started on the evening of `nightDate(i)` = today at noon minus `(14 − i)` days (night 13 =
  last night). Dates are always relative to now (the demo runs on Oct 24 and 25).
- Body wash: first ordered the day before night 10, used from night 10 on (`bodyWashNight = 10`).
  Dry air only on night 13 (humidity 29%). Midterm exams: nights 1–3.
- `sleepHours`: `[7.4, 7.1, 6.2, 6.0, 6.4, 7.5, 7.3, 7.2, 7.6, 7.0, 6.9, 6.4, 5.6, 5.1]`;
  `wakeUps`: `[0, 1, 1, 1, 0, 0, 1, 0, 0, 1, 1, 1, 2, 2]`;
  `humidity`: `[52, 49, 55, 51, 47, 50, 53, 48, 51, 50, 49, 47, 46, 29]`;
  `highF`: `[64, 66, 63, 61, 65, 67, 66, 64, 63, 65, 66, 64, 63, 68]`;
  `hrvMs`: last night 38, usual 52 (a 14-value array that drops over the last 3 nights is fine).
  Air quality 41 (good), pollen low, location "Berkeley, CA".
- **Last night**: 11:04 PM → 6:52 AM, 41 min, 23 episodes, 7 intense, woke up 2×, worst 2–4 AM.
  Minutes per clock hour 11 PM…6 AM: `[1, 3, 6, 10, 11, 6, 3, 1]`, split into **32 quarter-hour
  buckets** with a fixed seeded RNG (the prototype's `drawNight()` shows the idea: four random weights
  per hour, a weight < 0.18 becomes 0, normalized so each hour keeps its total). Deterministic.
- Orders (17, same items/dates/flags as story.js `orders()`, including the body wash with its
  ingredient list and `bought_before: false`), calendar events (same as story.js; midterms nights 1–3).
- **Tools** (`StageStory.runTool(name:arguments:) -> [String: Any]` or a JSON-encodable equivalent):
  `scratch_history`, `order_history`, `weather_history`, `calendar_events`, `sleep_history` returning
  **exactly the JSON shape and keys of story.js** (`usual_minutes_per_night`, `measured_by`,
  `nights[{night_of, weekday, scratch_minutes, scratch_episodes}]`, `last_night_worst_hours`,
  `source`, `orders[{date, item, category, bought_before, note?, ingredients?}]`,
  `location`, `days[{date, humidity_percent, high_f}]`, `events[{date, title, note?}]`,
  `nights[{night_of, hours_asleep, wake_ups}]`), dates as `YYYY-MM-DD` in the phone's time zone.
- Unit tests (Swift Testing): numbers, totals per hour, 32 buckets sum to 41 min, tool JSON keys and
  shapes, dates relative to a fixed "now", body wash is the only personal-care item never bought before.
- Also update the backup web page's `web/story.js` in `projects/eczema-twin-live` to the same `NIGHTS`
  and `EPISODES` (only those two arrays; do not deploy — the main agent deploys).

## 2. Shell — area `shell`

- **Tabs: Today · Trends · Insight** (remove Test). Remove the pink "+" button and the quick-tag
  sheet, the onboarding auto-show (keep the onboarding code only if §2's permissions page reuses
  it), the doctor report, the old Settings sheet (model picker, API key, time travel, demo tour,
  units), the demo tour / autoplay and `ShellDemoScripts`. Delete the Experiment screens and every
  reference (`.experiment` tab, `startExperiment`, `setExperimentDay`, "Start a 10-day test" etc.).
  Keep the build green and tests passing; delete tests only for code you delete.
- **Avatar "D" → "What it can read" sheet** = onboarding page 3 as it is today (yellow frame with
  the permission cards on it — `PermissionCards`/`PermissionRow`/`PermissionStatus` in
  `Screens/Onboarding/OnboardingArt.swift`; white bottom with the page eyebrow/title/body; same
  fonts and spacing). Top: "‹ Today" (or a close ×) and the "Eczema Twin" brand mark like onboarding.
  Rows: Apple Health ("Sleep, HRV, resting pulse") · Location ("Air, humidity, pollen near you") ·
  Notifications ("A heads-up when a flare starts") · Apple Watch ("Counts scratching, even asleep") ·
  **Calendar** ("Exams, deadlines and travel") · **Amazon orders** ("What you bought, and what's new
  to you"). In the stage build every row shows granted: "✓ On" (lime), Apple Watch "✓ Paired",
  Amazon "✓ Connected". Bottom: eyebrow "YOUR CHOICE", title "You decide what it can read.", body
  "Claude only reads what you turn on here, and only when you ask." Do not trigger real permission
  prompts from this sheet.
- **Hidden demo controls**: a small mono version line "Eczema Twin 1.0 (10)" at the bottom of that
  sheet; 5 taps within 1.5 s reveal a dashed card (`.demo` in the prototype): "Reset tonight's count"
  (posts `Notification.Name.twinResetTonight`), "Replay last Claude chat (offline)" (posts
  `.twinReplayChat` and switches to Insight). Nothing else.
- **Orientation**: the app is portrait-only except the live monitor. Foundation adds the plumbing
  (§6); the shell keeps it working.
- `-screen today|trends|insight|permissions` opens a screen directly (for screenshots).
- Toast host stays (Live uses it via `.twinToast` notification or the existing `ShellToasts`).

## 3. Today & Trends — area `today`

**Today** (prototype "Today"): top bar "Today" + date ("SAT · OCT 24"); trailing: `LivePill()` (from
the live area; shows nothing unless the watch is tracking) then `UserAvatar()`.
1. **Last night card**: eyebrow "LAST NIGHT" and "11:04 PM – 6:52 AM" on one row; `RingView` with
   41 counting up and "MIN" (progress 41 / (12 × 3.6), orange); right: sticker "▲ 3.4× your usual",
   "Worst **2–4 AM**." / "23 episodes, 7 intense.", mono "YOUR USUAL · 12 MIN"; under it the 32
   quarter-hour bars (grow in with a stagger; buckets > 2.2 min orange with an ink edge, others 15%
   ink) and the axis "11p 1a 3a 5a 7a".
2. **Pink CTA** (the existing Claude card style with the shimmer): "Up 3 nights in a row" /
   "Ask Claude what changed" / "→" → `app.select(.insight)`. It must not reveal the answer.
3. Sleep mini card "5.1 h" + "woke up 2×"; Stress (HRV) "38 ms" + "lower than usual".
4. "Around you · auto" cream card: "💧 Humidity 29% · dry" (orange), "🍃 Air quality 41 · good",
   "🌼 Pollen · low", "🌡 68°F".
Remove from Today: the logged-today card, the experiment card, anything with "+", episodes sheet if it
no longer fits (keep it only if it shows last night's episodes correctly).

**Trends**: top bar "Trends" / "LAST 14 NIGHTS" + avatar. Segmented "7 nights / 14 nights / All"
(14 selected; All = the same 14). Card "Minutes scratching per night": big **22** "min / night this
week" (mean of the last 7 nights, rounded), sticker "▲ up 91% from last week" (computed), 14 bars
(orange with ink edge when > 1.5 × usual), dashed "your usual" line at 12, **markers on two rows above
the chart with dotted stems down to the bar tops**: row 1 "📚 exams" over night 2 and "🧴 new wash"
over night 10; row 2 "💧 dry air" over night 13, right-aligned so it stays inside the card. Month
label + day numbers under the bars (last one bold). Tap a bar → cyan outline (matchedGeometry) and the
detail strip animates ("LAST NIGHT · 41 min · 2–4 AM worst · ▲ 3.4× usual", calm nights "calm" + lime
"normal"). "What changed" card: New body wash · first used Tue Oct 20 / Dry air · humidity 29% on Fri
Oct 23 / Midterm exams · Oct 11–13 (dates computed).

## 4. Live monitor — area `live`

Files under `App/iOS/Screens/Live/` (+ `LiveSession`). Foundation leaves stubs with the final API.
- **`LiveSession.shared`** (`ObservableObject`, main actor): `tracking`, `scratching`, `count`,
  `startedAt`, `episodes [(start, end?)]`, `reset()`. Connects to
  `wss://eczema-twin-live.zhongzhenyu190.workers.dev/api/live` (`URLSessionWebSocketTask`; send
  "ping" every 15 s; reconnect with backoff; connect while the app is active). Messages are JSON;
  use `type == "batch"`: `{live: Bool, windows: [{p, scratch, hz, strength}], events: [{type:
  "start"|"end", hz, intense, seconds}]}` and `type == "reset"`. Port the rules from
  `projects/eczema-twin-live/web/monitor.js` (`take()`): a window with `scratch == true` keeps
  "scratching" for 1.2 s; an event `start` starts an episode (count + 1) and `end` ends it.
  **Tracking** = a batch arrived in the last 3.5 s and its `live` was not `false`. A new session
  (count from 0) starts when batches resume after ≥ 60 s of silence or after a `live: false` batch.
  **Watch stopped** = a batch with `live == false`, or 8 s without batches while tracking.
- **`LivePill`**: cyan sticker with a blinking dot "Live" (prototype `.livepill`), only while
  `tracking`; tap → present `LiveMonitorView` full screen (`.fullScreenCover`) and turn the phone to
  landscape (§6 `OrientationLock`); closing returns to portrait.
- **`LiveMonitorView`** (landscape, prototype `#live` with `mon = "d"`): top row: cyan "● LIVE"
  sticker, "Sleep tracking", elapsed m:ss (mono, hint), right "APPLE WATCH · RIGHT WRIST" (mono) and
  a "Done" button. Main: a card with the **bars** (prototype `drawBars(…, "center")`): capsule bars
  6 pt wide, 5 pt gap, scrolling right → left, one new bar every 140 ms, mirrored around a faint
  center line. Calm (not scratching): short ink 16% bars, 7–18% of the height, gently rising and
  falling (sine ~0.65 s + a fixed per-bar random part) — they **never react to raw wrist motion**.
  Scratching: new bars blend (smoothstep of a soft level that rises in ~0.3 s and falls in ~0.6 s) to
  38–78% of the height with a fixed per-bar random length, **orange with a 1 pt ink edge** (the app's
  chart bars). "✋ Scratching" orange sticker top-left while scratching. Right card "SCRATCHES
  TONIGHT" with a big count (~96 pt) that pops (scale + orange) and sends one orange ripple ring on
  each new episode. Bottom: a thin session strip (whole session left → right, an orange block per
  episode). Use `TimelineView(.animation)` + `Canvas`; 60 fps; no allocations per frame beyond the
  bar list. Respect Reduce Motion (no scrolling; bars still change).
- When the watch stops while the monitor is open: dismiss it, back to portrait, Today, toast
  "Good morning, Douglas · last night is ready". When it stops while closed: just hide the pill.
- `-liveSim 1` launch argument: a built-in fake watch (tracking starts after 1 s, a scratch every
  ~6 s lasting 2–4 s) so screenshots/videos work without a watch. `-screen live` opens the monitor.
- Optional replay test: `GET https://eczema-twin-live.zhongzhenyu190.workers.dev/api/recordings` and
  `/api/recording?id=<id>` return real recorded batches (public) — useful for a unit test of the rules.

## 5. Insight — ask Claude — area `chat`

Replace the case-file Insight screen with a chat (prototype "Insight"): top bar "Insight" /
"ASK ABOUT YOUR SKIN" + sticker "✶ Claude". Thread: Claude's greeting ("Hi Douglas. I can read your
scratching, sleep, weather, calendar and orders. Ask me anything about your skin."), two suggestion
chips ("Why has my eczema been so bad the last few nights?", "How did I sleep this week?"), Douglas's
messages as yellow bubbles with an ink edge, Claude's text (sparkle + "CLAUDE" label, text revealed
word by word), a thinking row (`PixelSpinner` + "Thinking…"), and these cards:
- **Tool card list** (cream card): one row per data tool call: icon tile, a human name ("Scratch
  history · 14 nights", "Amazon orders · 120 days", "Weather · Berkeley", "Calendar", "Sleep · Apple
  Health"), a one-line result summary computed from the result (port `SUMMARY` in chat.js), a spinner
  that becomes a lime check (each row spins ≥ 0.6 s).
- **Timeline card** (`show_timeline`): 14 mini bars (hot ones orange), a pink pin sticker with
  `marker_label` at `marker_date`, axis, `note`.
- **Product card** (`show_product`): a generic pump bottle drawn with shapes (pink body, white label,
  no brand), name, "Ordered <date> · first time", the ingredient chips from the order with
  `flagged_ingredients` orange with an ink edge, legend "common contact allergens".
- **Question card** (`ask_user`): the question + 2–3 option chips; Douglas taps one or types; the
  chosen chip turns yellow, the others dim; his answer appears as a bubble.
- **Conclusion card** (`show_conclusion`): "MOST LIKELY CAUSE", `cause` big, confidence sticker
  (yellow) + a cyan bar that fills, `ruled_out` items struck through with their reason, a lime "Try
  this:" box with `next_step`, small "Not a diagnosis. A dermatologist can confirm it with a patch test."
- Composer pinned above the tab bar: text field "Ask Claude…" + pink send button; under it mono
  "POWERED BY CLAUDE · NOT A DIAGNOSIS".

**Engine** — port `projects/eczema-twin-live/web/chat.js` (read it; same protocol, same rules):
`POST https://eczema-twin-live.zhongzhenyu190.workers.dev/api/chat` with
`{"today": "Saturday, October 24, 2026", "messages": [...]}` (OpenAI-style messages: user /
assistant with `tool_calls` / tool with `tool_call_id`) → `{"model", "message": {"content",
"tool_calls"}}`. The server adds the system prompt and the tool list and holds the key; **never send
a model** (except the hidden dev launch argument `-chatModel deepseek/deepseek-v4.1-flash`, used only
for testing). For each reply: show its text; run data tools locally with `StageStory` (send the JSON
result as a tool message); render display tools and answer them `{"shown": true}`; `ask_user` waits
for Douglas and answers with his text. Send the next request when every tool call of the reply has a
result. Stop when a reply has no tool calls. 45 s timeout per request, one automatic retry, then a
"Try again" chip. If Claude stops before `show_conclusion` without asking a question, offer a
"Go ahead" suggestion chip. Save the last completed conversation (messages + tool results) to disk;
`.twinReplayChat` replays it with the same rhythm and no network. Network failures must never crash
or leave a spinner forever.

Testing the chat costs money: use `-chatModel deepseek/deepseek-v4.1-flash` for development runs (cheap).
At most one full run with the default model (Claude) at the end. Never print or log keys (the app has none).

## 6. Foundation — area `foundation` (runs first, alone)

1. `StageStory` + tests (§1) and the `story.js` array update.
2. Orientation plumbing: `UISupportedInterfaceOrientations` = portrait + landscape left/right in
   `project.yml`; an `AppDelegate` via `@UIApplicationDelegateAdaptor` returning
   `OrientationLock.mask` (default `.portrait`); `OrientationLock.set(_ mask:)` updates it, calls
   `setNeedsUpdateOfSupportedInterfaceOrientations()` and `requestGeometryUpdate` on the window scene.
3. Notification names in `App/iOS/Shell/StageNotifications.swift`: `twinResetTonight`,
   `twinReplayChat`, `twinToast` (userInfo "text").
4. Stubs with the final API so every area compiles on its own: `App/iOS/Screens/Live/LiveSession.swift`
   (published properties + `reset()` + `static let shared`), `App/iOS/Screens/Live/LivePill.swift`
   (`struct LivePill: View` that shows nothing yet).
5. Bump `CFBundleVersion` to "10" for the iPhone app and the watch app (watch code unchanged).
6. `scripts/rb foundation ios` green, `swift test` green, commit on `main`.

## 7. Ownership (parallel areas; stay inside yours)

| Area | Owns |
|---|---|
| `shell` | `App/iOS/Shell/**`, `App/iOS/EczemaTwinApp.swift`, `App/iOS/Screens/{Tag,Onboarding,Report,Settings,Experiment}/**`, `App/iOS/Services/**`, `project.yml` |
| `today` | `App/iOS/Screens/Today/**`, `App/iOS/Screens/Trends/**`, `Shared/Design/Charts/**` |
| `live` | `App/iOS/Screens/Live/**` |
| `chat` | `App/iOS/Screens/Insight/**`, `Packages/EczemaKit/Sources/EczemaKit/Insight/**` and their tests |

Shared files (`Shared/Design/Theme.swift`, `Shared/Design/Components.swift`, `Models.swift`,
`DemoData.swift`, `StageStory.swift`, `AppState.swift`): additive changes only, keep them minimal and
list them in your report. **Exception for the build phase:** if code outside your area stops compiling
only because of your area's deletions (e.g. the shell removes the Test tab and the old Today screen
still refers to it), make the smallest possible fix there and say so — the integrator keeps the owning
area's version.

Never `git push`. No chat messages. Commit often on your branch with clear messages ending with
`Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## 8. Build, run, look

`scripts/rb <name> ios` (remote build on Mac mini 2, errors only) · `scripts/shot <name> <screen>
[wait] [args]` (iPhone 16 Plus simulator screenshot → `shots/`) · `scripts/video <name> ios <screen>
<secs> [args]` · EczemaKit tests: see `SPEC.md` §8. Open every screenshot with the Read tool and judge
it against the prototype honestly; iterate until it is excellent. Shut down only your own simulators.
