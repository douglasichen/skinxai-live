# Eczema Twin — polish spec (CalHacks 13.0 demo)

Status: AGREED with Jacky (2026-10-24 06:30Z): body wash, no brand name; History shows only that recent nights are higher than usual; the Claude page is a **real live conversation** with Claude, steered by instructions.

## 1. What the demo is

A big screen (MacBook, fullscreen, projected; design for 1920×1080, must also look right at 1440×900) and one Apple Watch on Douglas's wrist. No iPhone app on stage.

Story, about 3 minutes:

1. **Monitor.** Douglas lies on the table "asleep" wearing the watch and scratches now and then. The big screen is a hospital-style bedside monitor: a calm green trace that lifts into an orange hump while he scratches, a "SCRATCH DETECTED" alarm with a beep, and a scratch counter.
2. **Last night.** He "wakes up": "Why is my eczema so bad today?" The screen shows last night: 41 minutes of scratching, hour by hour, worst 2–4 AM, plus the scratches the watch just caught live.
3. **History.** 14 nights against his usual (about 12 minutes a night). The last three nights are clearly higher. **No annotations or causes on this page**: Jacky narrates "look, it's much higher than before, why?"
4. **Claude.** A Claude.ai-style chat with the real model. Douglas asks Claude to look at his scratching history and find out why. Claude calls tools (scratch history, Amazon orders, weather, calendar, Apple Health), shows the product he recently bought for the first time in an artifact panel, asks a few questions to rule other things out (Douglas clicks an option or types), and concludes. The wording varies run to run; the direction is steered by the instructions and the data.

All on-screen copy is **English** (the judges read English).

## 2. Look and feel (all pages)

Keep the current identity and refine it. Don't replace it.

- Dark bedside-monitor theme. Background `#060807`, panels `#0c100e`, hairlines `rgba(169,216,119,.14)`.
- Raft palette accents: lime `#a9d877` (calm/OK), orange `#f8a16f` (scratching/alarm), pink `#fe7da8`, yellow `#ffd440` (active tab, chips), cyan `#27ccf3`, red `#f97264`.
- Fonts: Space Grotesk (text, numbers) and Space Mono (labels, small caps), already in `web/fonts/`.
- Readable from the back of a room: headline 40–56 px, big numbers 56–120 px, labels at least 12 px.
- Motion everywhere, purposeful and smooth (60 fps, `transform`/`opacity` only):
  - page transitions
  - count-ups
  - bars growing in sequence
  - cards rising in
  - typing text
  - tool-call spinners turning into checks
- No jank and no layout shift. Respect `prefers-reduced-motion`.
- Nothing may overflow or clip at 1920×1080 or 1440×900. No scrollbars on any page.

## 3. Pages

### 3.1 Monitor (`#p-monitor`)
Keep all behaviour and data plumbing; polish the visuals.
- **Header**:
  - brand and page name
  - tabs Monitor / Last night / History / Claude
  - status dot with WAITING FOR WATCH / WATCH LIVE / SIMULATION
  - clock
- **Patient strip**: PATIENT DOUGLAS · BED 1, SENSOR, MODE, and the "● Record test" button.
- **Trace**: sweep monitor.
  - Calm green ripple for any motion.
  - While scratching, the line lifts into one smooth orange hump (height = intensity) with a small ripple, and drops back when the hand stops.
  - Pen dot, erase gap, faint grid.
  - **Keep the current rendering model**: the `cols` ring buffer, `levels()`, `markRecent()`, `ampOf`/`yOf`. Make it prettier: smoother curve, nicer glow, maybe a subtle scanline. Don't make it busier.
- **Vitals**: SCRATCHES (huge, orange, bumps on each new scratch), SCRATCH TIME, INTENSITY meter + Hz, LAST SCRATCH.
- **Alarm**: "SCRATCH DETECTED" pill, pulsing while scratching; beep on start (WebAudio, after first click).
- **Session strip** at the bottom.
- **Recording overlay** ("Record test", key T): keep it working.

### 3.2 Last night (`#p-night`)
- Eyebrow "LAST NIGHT · THU 11:04 PM → 6:52 AM" (weekday from the date).
- Headline "Douglas scratched **41** minutes in his sleep." Chip "▲ 3.4× his usual".
- Cards: scratch episodes, intense, woke up, worst hours.
- Hour-by-hour bars 11P–6A with values; 2–4 AM hot. Add a pink "NOW" bar with the live seconds when the watch caught scratches this session (`window.twinSession()`, or `/api/events` since the reset marker).
- Note "Includes N scratches the watch caught live just now."

### 3.3 History (`#p-history`) — only "higher than his usual", no causes
- Eyebrow "LAST 14 NIGHTS · SAME WATCH, EVERY NIGHT".
- Headline "Since Tuesday: **31** min a night. His usual is 12." (weekday computed).
- Chip "▲ 2.6× his usual, 3 nights running".
- 14 bars (oldest → last night) with values; weekday and date axis; dashed "his usual · 12 min" line with its label in the right margin.
- The last three nights orange, the rest neutral. Make the "higher than usual" story obvious at a glance:
  - a subtle shaded band for the usual range;
  - the gap between the usual line and the last three bars visibly emphasized.
- **No** annotations, flags, product names or "what changed" anywhere on this page. Jacky narrates.

### 3.4 Claude (`#p-claude`) — real conversation with Claude, steered
**Backend, already live and working** (don't change it; tell the lead if it must change):
- `POST /api/chat` with `{model, today, messages}` → `{model, message: {role: "assistant", content, tool_calls}}`.
- `messages` is the OpenAI-style conversation **without** the system prompt (the Worker adds it, together with the tool list):
  - user messages;
  - assistant messages with `tool_calls`;
  - tool messages `{role: "tool", tool_call_id, content: JSON string}`.
- `today` comes from `twinStory.today()`.
- Models:
  - `anthropic/claude-sonnet-5.5` is the default and the demo model;
  - `deepseek/deepseek-v4.1-flash` is cheap and for development. **Use DeepSeek while building and testing**: add `?model=deepseek/deepseek-v4.1-flash`. Run at most two full conversations with Claude, at the end.
- The instructions make the model:
  1. gather data with the data tools;
  2. call `show_timeline` and `show_product` for the suspect;
  3. ask exactly three questions with `ask_user` (detergent, stress, where it itches), one per turn — it sometimes asks two in one turn, so handle that;
  4. comment on each answer;
  5. call `show_conclusion`;
  6. say one closing sentence.
- A full run takes about 6 s on DeepSeek and about 30 s on Claude, over about 8 round trips.
- Tested end to end: it concludes "the new body wash" with both models (`/tmp/et-chat/loop.mjs` is the reference client loop).

**The page runs the tools** (data is in `web/story.js`, `window.twinStory`):
- Data tools return JSON from `twinStory.tools[name](args)`:
  - `scratch_history`, `order_history`, `weather_history`, `calendar_events`, `sleep_history`.
- UI tools render in the artifact panel. Each returns `{"shown": true}` as its tool result:
  - `show_timeline {marker_date, marker_label, note}`
  - `show_product {name, purchase_date, flagged_ingredients[], note}`
  - `show_conclusion {cause, confidence, ruled_out[{item, reason}], next_step}`
- `ask_user {question, options[2-3]}` renders the question with option buttons. Its tool result is `{"answer": "<what Douglas chose or typed>"}`.
- Loop:
  1. Send the conversation.
  2. Render the assistant text.
  3. Run its tool calls **in order**: show each one, and wait for Douglas on `ask_user`.
  4. Append the tool results and send again.
  5. Stop when a reply has no tool calls.

**Layout and look** (Claude.ai-like, in our dark theme; don't copy Anthropic's logo file — draw a simple sparkle):
- **Left (about 45%): the thread.**
  - Douglas's messages: light bubbles, right-aligned.
  - Claude's messages: plain text with the sparkle avatar, revealed by a fast typewriter (60–90 chars/s), because the API is not streaming.
  - Tool calls: compact cards in the thread. Each has a server icon and a monospace call, e.g. `eczema_twin · scratch_history(nights: 14)` or `amazon · order_history(days: 30)`.
    - Server names: `weather`, `google_calendar`, `apple_health`, plus the two above.
    - A spinner turns into a check, with at least 600 ms per card for readability.
    - Then a one-line human summary computed from the result, e.g. "14 nights · last 3: 22, 31, 41 min · usual 12" or "17 orders · 1 personal-care item never bought before".
  - A "Claude is thinking…" indicator (pulsing sparkle) while waiting for the API.
- **Input box at the bottom.**
  - Before the first message, show one suggestion chip: "My eczema has been really bad the last few nights. Can you look at my scratching history and help me figure out why?" Click sends it; typing works too.
  - During `ask_user` the option buttons show under Claude's question. Douglas can also type an answer.
- **Right (about 55%): the artifact panel.** Slides in on the first `show_*` call; later artifacts stack as cards or tabs:
  - **Timeline**: the 14-night chart. A pink marker on `marker_date` with `marker_label`, the usual line, and a bracket showing the delay to the rise. `note` sits underneath.
  - **Product**: a generic bottle drawn in SVG; `name` (no brand); "First purchase · ordered <date> · Amazon"; the ingredient list from `twinStory.BODY_WASH_INGREDIENTS` with `flagged_ingredients` highlighted, and a hint "common contact allergens".
  - **Conclusion**: the cause in big type, a confidence meter, "Ruled out" items (each with a strike-through and its reason), "Try this" (`next_step`), and the disclaimer "Not a diagnosis — patterns in your data. A dermatologist can confirm with a patch test."

**Stage safety**:
- Every completed conversation is saved to `localStorage`. On the Claude page, `P` replays the last completed conversation with the same animations and no network (fallback if the Wi-Fi dies).
- `R` on the Claude page starts a new conversation.
- If `/api/chat` fails or times out (45 s): an error bubble with "Try again", which resends.
- While the input box has focus, global shortcuts (1–4, F, D, R, T) must not fire. `monitor.js` and `rec.js` already ignore keys typed into inputs.

### 3.5 Apple Watch app (SwiftUI, `projects/eczema-twin-app/App/Watch`)
Drastically simplify to **one screen**:
- App name / small mark at top.
- One big circular button: **Start** (pink) / **Stop** (dark with cyan ring); a pulsing ring while monitoring.
- Under it: tonight's scratch count (big number, counts up on each episode) and one status line: "Connected to screen" (cyan) / "Can't reach screen" (orange) / "Not monitoring".
- A gentle haptic on each detected scratch is fine. **No** Yes/No prompt, **no** ring of minutes vs usual, **no** Recent screen, **no** demo story, **no** iPhone sync UI.
- Keep, untouched in behaviour:
  - `LiveMonitor` (workout session, motion, detector with `DetectorConfig.live`)
  - `LiveStreamer`, `WatchModel.screenLink` / `screenDetail` / `screenSent`
  - the Health permission flow
- Remove dead screens and code paths only where that is clean. Don't rewrite the services.
- Must build for the watch simulator (`scripts/rb <name> watch`). Screenshot with `scripts/watchshot <name> ring` (adjust the `-screen` routing if needed).
- **Never** launch the simulator with `-stream`: a simulator must not send fake data to the real big screen.

## 4. Controls (must keep working)
Keys:
- `1`–`4`: pages.
- `F`: fullscreen.
- `D`: simulation on/off (also `?sim=1`).
- `R`: reset on Monitor; new conversation on Claude.
- `T`: record test.
- Claude page: Enter sends; `P` replays the last saved conversation.

URL hash `#night`, `#history`, `#claude` opens that page.

## 5. Code layout and rules
- Web app: `projects/eczema-twin-live/web`. Plain HTML/CSS/JS, no build step, no frameworks, no CDN dependencies (offline-safe on stage).
- Worker: `worker/index.js`. **Don't change it** unless a page truly needs a new endpoint.
- Shared story data (nights, sleep, humidity, dates, orders, tool implementations) is in `web/story.js` (`window.twinStory`). Shared helpers are in `web/common.js` (`window.twinUI`: `countUp`, `esc`, `sleep`, `api(path)`, `wsUrl(path)`). Night, History and Claude all read from these.
- One JS file and one CSS file per page:
  - `monitor.js` / `style.css` (base + monitor)
  - `night.js` + `night.css`
  - `history.js` + `history.css`
  - `chat.js` + `chat.css`
  - `rec.js`
  Each agent edits only its page's files and its own `<section>` in `index.html`.
- **No deploying, no secrets, no `wrangler` commands.** The lead deploys.
- Verify every change with real screenshots before finishing:
  - Playwright for Python with `channel="chrome"` (bundled Chromium isn't installed).
  - Serve `web/` with `python3 -m http.server <your port>`.
  - Add `?api=https://eczema-twin-live.zhongzhenyu190.workers.dev` so the page uses the deployed relay and `/api/chat`.
  - Use `?sim=1` for live-looking data.
  - Check 1920×1080 and 1440×900.
  - Capture mid-animation frames as well as final ones.
- Keep the code readable and match the surrounding style.
