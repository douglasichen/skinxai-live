# Eczema Twin: final report

**Your Apple Watch knows when you scratch. Claude tells you why.**
Native SwiftUI app for iPhone (iOS 17 or later) and Apple Watch (watchOS 10 or later). Built for CalHacks 13.0.

## In one minute
- **Builds pass:** iPhone and watch for the simulator, and the iPhone app for a real device.
- **Tests pass:** 84 EczemaKit tests pass. The 3 live AI tests are skipped without a key. I ran them once with DeepSeek V4.1 Flash: 3 of 3 passed, in English.
- **Screenshots:** 12 final screenshots are in `docs/screens/`.
- **Videos:** these are in `shots/` (on this computer, not in git).
  - `final-tour.mp4`: the automatic demo tour.
  - `final-insight.mp4`: the Insight reveal.
  - `final-prompt.mp4`: the watch scratch alert.
- **What changed:** no app code. Two fixes:
  1. The iPhone app had no icon. It now uses the watch icon.
  2. The Xcode project is now in git, so you can open it and press Run without xcodegen.

## 1. What was built, screen by screen
All screens use the Raft look: yellow top bars, white paper, ink edges, colored stickers, Space Grotesk and Space Mono fonts. Every screen has motion:
- cards rise in one after another
- numbers count up
- bars grow
- rings fill
- every tap gives a small haptic

The app respects Reduce Motion.

### iPhone
There are four tabs (Today · Trends · Insight · Test) and a pink + button.

1. **Today** (01-today.png)
   - A ring shows today's minutes of scratching, counting up. It is orange when above your usual and lime when normal.
   - A sticker compares today with your usual, for example "▲ 3.5× your usual".
   - One line says when it happened ("Mostly at night, 1–5 am"), with the episode and intense counts.
   - A 24-hour bar chart has a "now" marker. "Episodes" opens the list of today's episodes.
   - The pink card "Claude found a likely trigger" opens Insight. During a test it says "Day N of your test".
   - Sleep and Stress (HRV) cards have 7-day mini bars.
   - The "Around you · auto" card shows humidity (orange "dry"), air quality, pollen and temperature.
2. **Trends** (02-trends.png)
   - A 7 days / 14 days / All switch.
   - A big "min / day this week" number with "▲ up 160% from last week".
   - Daily bars: flare days orange, recovery lime, a dashed "your usual" line, and markers where things started (new wash, dry air, exam stress, test).
   - Tap a bar to see that day's minutes, worst hour, sleep, HRV, humidity and tags.
   - A "What changed" list, and sleep and stress lines with the flare days shaded.
3. **Insight** (03-insight.png)
   1. A thinking card with a pixel spinner and 3 status lines.
   2. The summary types itself out.
   3. Suspect cards fly in by rank, with confidence bars.
   4. Suspect #1 has a timeline: an arc from the day the body wash started to the flare, "+2 days".

   Below the suspects: a "Can't separate yet" note, a red block if there are warning signs, "Start a 10-day test: pause the body wash →", the disclaimer, "Share with my doctor" and "Re-run analysis". Small print says "Bundled analysis" or the live model name.
4. **Test** (04-test-day6.png, 05-test-day10.png)
   - A ring shows "N of 10 days", with 10 day tiles.
   - "With wash" and "Paused" bars compare the two, with "▼ x% less so far".
   - The DEMO button "Fast-forward a day" moves the story on.
   - On day 10 the card flips to "Confirmed: The body wash is a trigger for you." with confetti and a success haptic. "Run it again from day 1" starts over.
   - With no test running, the screen explains the suggested test.
5. **Quick tag sheet** (06-tag.png): the pink + button.
   - One-tap chips. Things already in today's log show a check.
   - "Scan a product label" uses the camera or a photo. The iPhone reads the label and flags fragrance and other common irritants, offline.
   - "Save" adds the tags to today and shows a toast.
6. **Onboarding** (07-onboarding.png): 3 pages.
   1. "Your skin keeps a diary. Eczema Twin reads it."
   2. What is tracked for you.
   3. Permissions (Health, Location, Notifications) and the watch status.

   It shows on the very first launch only, and again from Settings → Replay onboarding.
7. **Report** (08-report.png): "Share with my doctor".
   - One page: the 14-day chart, the top suspects, sleep and stress against calm days, what changed, the next step or the test result, and a disclaimer.
   - "Share PDF" exports a real PDF.
8. **Settings** (09-settings.png): tap the "D" avatar.
   - your name
   - the Demo story switch (demo story or your own data)
   - Time travel (story day 1–14, test day 1–10) and "Play the demo tour"
   - Claude model and API key
   - °C or °F
   - Replay onboarding
   - About
9. **Demo tour:** Settings → "Play the demo tour", or the launch argument `-autoplay tour`.
   - Today → Claude card → Insight → Start test → fast-forward to day 10 → Trends, in about 30 seconds.
   - Any touch stops it.

### Apple Watch
10. **Ring** (10-watch-ring.png)
    - Today's minutes against your usual (a white tick marks your usual), with the episode and intense counts.
    - The "Start detecting" button turns on live detection.
    - Tap the ring to flip to the ratio. A long press asks the demo question.
11. **Scratch alert** (11-watch-alert.png)
    - A pulsing hand tile with ripple rings and a strong haptic.
    - "Were you scratching?" with what was measured ("4.3 Hz · just now") and No / Yes buttons.
    - The answer trains the personal model on the watch. Then the ring returns and the number ticks up.
12. **Recent** (12-watch-recent.png)
    - Turn the Digital Crown to get here.
    - The latest episodes with time, length and Hz.
    - A status card: detection, the all-day recorder, the last sync to the iPhone, answers learned, and Reset learning.

## 2. How the demo flows (about 3 minutes)
**Before:** Demo story on (the default). Time travel at Day 14. Open the watch app.

**On stage:**
1. **Today:** "40 min, 3.5× usual, mostly 1–5 am." The minutes depend on the hour.
2. **Watch:** Long-press the ring, then tap Yes; the ring ticks up. For a fully real moment, tap Start detecting and scratch your forearm for about 10 seconds. A Yes counts on the iPhone too.
3. **Insight:** Tap the Claude card. Show the reveal and the "+2 days" arc. Dry air started one day later, so Claude can't separate them yet.
4. **Test:** Tap "Start a 10-day test". Tap "Fast-forward a day" up to day 10. "Confirmed" appears with confetti.
5. **Trends:** Flare, then recovery.
6. **Doctor:** Insight → "Share with my doctor" shows the PDF.

**Backups:** Settings → "Play the demo tour", or play shots/final-tour.mp4.

**The demo works fully offline.** With a key, "Re-run analysis" asks Claude live for up to 20 seconds, then falls back to the bundled analysis.

## 3. Real device and demo story
**Works with real data on your iPhone and watch:**
- Live scratch detection on the watch: the accelerometer at 50 Hz. A workout session keeps it running with the screen off. If Health says no, a 1-hour background session, else only while the app is open.
- All-day recording: 12 hours, read when you open the app and in background refreshes.
- Yes/No answers train the model.
- Watch → iPhone sync (WatchConnectivity).
- "Your own data" mode: watch episodes, Apple Health (sleep, HRV, resting heart rate, workouts), and Open-Meteo weather, air and pollen by location.
- Live Claude through OpenRouter with your key.
- A flare notification (two days above 1.5× usual).
- The label scanner and the PDF report.

**Demo story only:**
- Douglas's 14 days and bundled case #3.
- Fast-forwarding the test and the result moment.
- Time travel and the tour.
- The watch long-press question.

**Important:** the team had no real iPhone or Apple Watch. The real-device parts compile for a device and were tested only in simulators. Try live detection on your wrist before the demo.

## 4. Install on your iPhone and Apple Watch (from your MacBook)
Summary:
- Open EczemaTwin.xcodeproj. It is in git now, so no xcodegen is needed.
- Turn on Developer Mode on the iPhone and the watch.
- Run the EczemaTwin scheme on the iPhone, then EczemaTwinWatch on the watch.

The team (Personal Team 35AD3DPH6Y) is already set.

### Step by step
Install on your iPhone and Apple Watch from the MacBook. You need Xcode 27.1, signed in with the free Apple ID "jackythe King (Personal Team)". Team 35AD3DPH6Y is already set in the project.

A. Get the code
1. Put the main branch on the MacBook: git clone or pull, or copy the folder.
2. Open EczemaTwin.xcodeproj. It is in git now, so you don't need xcodegen.
3. If you edit project.yml: run `brew install xcodegen` once, then `xcodegen generate`.

B. iPhone
1. Plug the iPhone in with a cable. Unlock it and tap Trust This Computer.
2. In Xcode, at the top: scheme EczemaTwin, destination your iPhone.
3. Check the signing: click the project → target EczemaTwin → Signing & Capabilities. "Automatically manage signing" is on and Team is "jackythe King (Personal Team)". Do the same check for target EczemaTwinWatch.
4. On the iPhone: Settings → Privacy & Security → Developer Mode → On. The iPhone restarts; confirm Turn On. (The switch appears only after the iPhone has been connected to Xcode once.)
5. Press Run (⌘R). The first time takes a few minutes while Xcode prepares the iPhone.
6. If the iPhone says "Untrusted Developer": Settings → General → VPN & Device Management → your Apple ID → Trust. Open the app again.

C. Apple Watch
1. The watch must be paired with this iPhone, unlocked, and near it. Keep Wi-Fi and Bluetooth on, and the iPhone plugged in.
2. In Xcode: Window → Devices and Simulators. Wait while Xcode prepares the watch the first time (5–15 minutes).
3. On the watch: Settings → Privacy & Security → Developer Mode → On. The watch restarts; confirm.
4. In Xcode: scheme EczemaTwinWatch, destination your Apple Watch → Run. The iPhone app also carries the watch app and may install it by itself if Automatic App Install is on, but Run is the sure way.
5. On the watch, open Eczema Twin and allow Motion & Fitness. The first time you tap Start detecting, allow Health (the workout session).

D. Free Apple ID notes
- Apps stop opening after 7 days: plug in and press Run again for each scheme. Your data stays.
- If you see "Failed to register bundle identifier", pick a new unique ID in three places:
  1. Target EczemaTwin → General → Bundle Identifier.
  2. Target EczemaTwinWatch → General → Bundle Identifier: the same plus .watchkitapp.
  3. App/Watch/Info.plist → WKCompanionAppBundleIdentifier: the new iPhone ID.
- If Xcode refuses HealthKit for the free team: remove HealthKit from both targets. The app still works without Health data, and the watch uses the 1-hour background session instead of a workout.

AI key: get one at openrouter.ai → Keys. Then on the iPhone: "D" avatar → Settings → Claude → paste the API key → Save ("In Keychain"). Keep Claude Sonnet 5.5, or pick another model. Then Insight → "Re-run analysis". With no key or no network, the bundled analysis is used.

## 5. Set the AI key
1. Get a key at openrouter.ai → Keys → Create key, and add some credit.
2. On the iPhone: "D" avatar → Settings → Claude → API key: paste it → Save. The sticker changes to "In Keychain".
3. Pick a model:
   - Claude Sonnet 5.5: the default, best for the demo
   - Opus 5.5: most careful
   - Haiku 5.5: fastest
   - DeepSeek V4.1 Flash: cheap, for tests
   - "Other model": any OpenRouter model ID
4. Insight → "Re-run analysis" (with your own data: "Analyze what I have"). The small print changes to "<model> · live".
5. To remove it: Settings → Claude → Remove.

How the key is kept and what happens without it:
- It is stored only in this iPhone's Keychain (service com.jackyzhong.eczematwin2.ai, account openrouter-api-key).
- It is never logged and is only sent to openrouter.ai.
- With no key, no network, or an error: the bundled analysis in the demo story, or an honest note with your own data.

## 6. Known issues
1. The iPhone does not tell the watch which data it shows. The watch side is built; the iPhone side is not (still open from the last integration). The watch always shows the day-14 demo story ('DEMO STORY · SET ON YOUR IPHONE') with your live detections on top, even when the iPhone is on test days or your own data. A Yes on the watch's long-press demo alert counts only on the watch. Real live detections count on both. Fix: DataModeController should call WCSession.updateApplicationContext(["dataMode", "expDay", "storyDay"]) whenever these change (contract in App/Watch/Services/PhoneLink.swift). Not added in this pass because of the no-new-features rule.
2. Settings time travel and the tour change the story day directly, so a live Claude case file turns back into the bundled one.
3. The DeepSeek dev model once wrote its summary in Chinese although the prompt asks for English; the JSON still worked. Today's DeepSeek V4.1 Flash run was 3 of 3 in English. Claude is the demo default.
4. The iPhone ring is full at 3× your usual. The watch ring is full at 60 minutes or 3× your usual, whichever is more. The same minutes fill the two rings differently.
5. Between midnight and 7 am, the phone and watch show 'today' through 7 am. This is on purpose, for night rehearsals.
6. The simulator sometimes replays a cached launch image that is a little too saturated, for less than a second. This does not happen on a fresh install.
7. Some select(.x) call sites still use the default haptic. Each tap still gives one haptic.
8. Not tested on real hardware. Live detection (CoreMotion, workout session, extended runtime), the all-day CMSensorRecorder, the WatchConnectivity link, HealthKit, the camera and notifications ran only in simulators; the device build compiles. Live detection with a workout session uses watch battery.
9. Free Personal Team limits: installed apps stop opening after 7 days (press Run again), at most 3 of the team's apps on a device, 10 new app IDs per week. If the bundle ID 'com.jackyzhong.eczematwin2' cannot be registered, change it for both targets and set WKCompanionAppBundleIdentifier to match.
10. The simulator on Mac mini 2 is set to Chinese, so the raw videos (*-raw.mp4) start on a Chinese home screen. The final videos are trimmed, and the app itself is English only.
11. The tour video is 31 s, not 40 s: simctl stops writing frames while the screen is still. The whole tour is in it.

## 7. Files
- **Screenshots** (`docs/screens/`, 01 to 12): iPhone 16 Plus and Watch Series 11 (46 mm) simulators, iOS and watchOS 27. The status bar is fixed at 9:41. The data is from about 7 pm.
- **Videos** (`shots/final-tour.mp4`, `final-insight.mp4`, `final-prompt.mp4`): trimmed. The raw recordings are `*-raw.mp4`.
- **Remake them:**
  - Build: `scripts/rb <name> all`
  - Screenshots: `scripts/shot <name> <screen>` and `scripts/watchshot <name> <screen>`
  - Videos: `scripts/video <name> ios today 40 -autoplay tour`
