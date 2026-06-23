# Hopr — Product Video (Remotion)

A clean, modern **3D product video** for Hopr, built with [Remotion](https://remotion.dev).
Structured as **hook → demo**: a punchy opener followed by fast walkthroughs of
Hint, Scroll and Search modes, then a brand outro.

Everything is code — colors, motion and timing are derived from Hopr's real
brand palette (dark squircle, white mascot, system-blue accent `#007AFF`).

---

## Quick start

```bash
cd video
npm install          # already done if node_modules exists

npm run dev          # open Remotion Studio to preview/scrub live
npm run render       # render the full promo  → out/hopr-promo.mp4
npm run render:teaser# render the short cut   → out/hopr-teaser.mp4
npm run still        # render a poster frame  → out/poster.png
```

Requires Node 18+ and ffmpeg (both present on this machine).

---

## Compositions

| ID           | Length  | Use                                            |
|--------------|---------|------------------------------------------------|
| `HoprPromo`  | ~23 s   | Full hook + 3-mode demo + outro (1920×1080)    |
| `HoprTeaser` | ~15 s   | Tighter social cut: hook + 2 demos + outro     |

Both render at 1920×1080 @ 30fps, H.264, CRF 18.

---

## Storyboard

1. **Hook (~3.5s)** — Logo materializes in 3D with an accent glow; headline
   *"Control your entire Mac without the mouse."*
2. **Hint Mode (~5.5s)** — A tilted glass app window; letter hints cascade onto
   every clickable element. Typing `Q` → `S` filters the labels live (showing the
   smart-prefix behavior) and clicks **Mark all as read** with a ripple.
   Caption: `Hint Mode · ⌘⇧Space`.
3. **Scroll Mode (~6s)** — Numbered scroll regions; region `1` is selected and the
   article scrolls with `J`, then **⇧ Dash** turbo. Caption: `Scroll Mode · ⌘⇧J`.
4. **Search Mode (~6s)** — A centered translucent HUD; typing `se` surfaces ranked
   results with letter badges, arrow keys move the selection, and a highlight box
   tracks the matching element behind. Caption: `Search Mode · ⌘⇧/`.
5. **Outro (~4s)** — Logo + `Hopr` wordmark, tagline *"Your whole Mac, on the home
   row."*, the three mode chips, and a *Free & open source* CTA.

---

## Structure

```
video/
├── remotion.config.ts        # codec / quality / renderer
├── src/
│   ├── index.ts              # registerRoot
│   ├── Root.tsx              # compositions + scene timing (durations, cross-fades)
│   ├── theme.ts              # brand palette + per-mode metadata  ← tweak look here
│   ├── font.ts               # Inter (Google Fonts)
│   ├── components/           # reusable primitives
│   │   ├── Background.tsx    #   animated mesh + grid + vignette
│   │   ├── Stage3D.tsx       #   perspective camera + parallax layers
│   │   ├── GlassWindow.tsx   #   macOS-style window chrome
│   │   ├── DashboardUI.tsx   #   the mock app + hint TARGETS
│   │   ├── HintBadge.tsx     #   letter label with spring 3D pop
│   │   ├── KeyCap.tsx        #   3D extruded keycaps
│   │   ├── Caption.tsx       #   per-scene lower caption
│   │   └── TypeText.tsx      #   typewriter helper
│   └── scenes/               # one file per beat
│       ├── SceneHook.tsx
│       ├── SceneHint.tsx
│       ├── SceneScroll.tsx
│       ├── SceneSearch.tsx
│       └── SceneOutro.tsx
└── public/                   # logo.svg, click1.m4a, click7.m4a (brand assets)
```

## Tweaking

- **Colors / accents** → `src/theme.ts` (`theme` + `modes`).
- **Pacing / order / cross-fades** → `src/Root.tsx` (`D`, `XF`, `T`, `TXF`).
- **What gets clicked / labels** → `TARGETS` in `src/components/DashboardUI.tsx`.
- Run `npm run dev` and scrub the timeline to dial in any frame.

## Possible next steps

- **Audio**: `public/click1.m4a` / `click7.m4a` (Hopr's real SFX) are ready to drop
  into scenes via `<Audio>` for tactile clicks + a background music bed.
- **9:16 vertical** cut for Reels/TikTok/Shorts (add a `1080×1920` composition).
- Swap the mock app for a real screen recording behind the same 3D stage.
