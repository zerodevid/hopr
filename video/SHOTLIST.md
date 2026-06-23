# 🎬 Hopr demo — recording shot list

You record 3 short clips; I turn them into the demo with cinematic zoom in/out,
captions and keycap overlays. Read the labels on screen and type them naturally —
that's the part automation can't do reliably, so it's all you. 🙌

## Before you start (once)

- **Run Hopr** and make sure **Accessibility** is granted (it drives the demo).
- **Turn on Do Not Disturb / Focus** so no notifications pop in.
- **Clean the screen**: one app visible, hide private windows, tidy desktop.
- Pick a recognizable, visually clean app to demo on — **Safari** (a simple page
  with clear buttons/links) works great; VS Code, Mail or System Settings are fine too.
- Move **deliberately** and **pause ~1s between actions** — those pauses are where
  I push in / pull out the zoom. Leave ~1s of stillness at the very start and end.

## How to record

```bash
cd video
./record-demo.sh hint   10     # 10s clip → public/footage/hint.mov
./record-demo.sh scroll 9      # → public/footage/scroll.mov
./record-demo.sh search 10     # → public/footage/search.mov
```

First run pops a macOS prompt → **System Settings ▸ Privacy & Security ▸ Screen
Recording ▸ enable your Terminal**, then run the command again.
(Prefer the GUI? `⌘⇧5` ▸ *Record Entire Screen* ▸ stop when done, then drop the
file in `video/public/footage/` named `hint.mov` / `scroll.mov` / `search.mov`.)

---

## Clip 1 — `hint` (~10s) · Hint Mode

1. **0–1s** — sit still on the target app.
2. Press **⌘⇧Space** → hint labels appear on every clickable element.
3. **Pause ~1.5s** — let all the labels sit there (this is the “wow” shot; I zoom
   out to show the density).
4. **Type the letters of one clear label** on a prominent button/link → it clicks.
5. **~1.5s** — let the result of the click show (page/state changes).
6. Hold still ~1s.

## Clip 2 — `scroll` (~9s) · Scroll Mode

1. **0–1s** — still, on a **long/scrollable page** (a Safari article is perfect).
2. Press **⌘⇧J** → numbered region badges appear.
3. Press the **number of the main reading region** (often `1`).
4. Tap **J** a few times → it scrolls down (let it be visible).
5. **Hold ⇧ then J** → turbo **Dash** scroll (covers lots of page fast).
6. Optional: tap **K** to scroll back up a little.
7. Hold still ~1s.

## Clip 3 — `search` (~10s) · Search Mode

1. **0–1s** — still.
2. Press **⌘⇧/** → the translucent search HUD appears (centered).
3. **Type a short query** that matches a visible button/link (e.g. part of its name).
4. Results dropdown shows up; use **↑ / ↓** to move the selection — the highlight
   box tracks the element on screen.
5. Press **Enter** → it clicks the selected element.
6. Hold still ~1s.

---

## When you're done

Just tell me **“clips ready”**. I'll:
- pull frames from each clip to find exactly where the action happens,
- set the zoom focal points + timing to match,
- assemble `HoprPromoReal` (3D hook → 3 real-footage demos → 3D outro),
- render `out/hopr-promo-real.mp4` and send you preview frames.

Re-recording any single clip later is fine — just overwrite the same filename.
