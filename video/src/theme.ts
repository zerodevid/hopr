// Hopr brand design system — derived from the app's real palette.
// Dark squircle background, white mascot, system-blue accent + preset hues.

export const theme = {
  // Backgrounds
  bg0: "#08080C",
  bg1: "#15151B",
  bg2: "#2B2D3A",

  // Text
  white: "#FFFFFF",
  textDim: "rgba(255,255,255,0.62)",
  textFaint: "rgba(255,255,255,0.32)",

  // Accent — macOS system blue (Hopr's default hint label color)
  accent: "#007AFF",
  accentBright: "#3B9BFF",
  accentGlow: "rgba(0,122,255,0.55)",

  // Preset hint hues (match GeneralTab swatches)
  hues: {
    yellow: "#FCDF22",
    blue: "#007AFF",
    indigo: "#5E5CE6",
    green: "#30D158",
    orange: "#FF9F0A",
    pink: "#FF375F",
  },

  // Surfaces / glass
  glassFill: "rgba(30,32,44,0.55)",
  glassStroke: "rgba(255,255,255,0.12)",
  glassHighlight: "rgba(255,255,255,0.22)",

  // Fonts
  fontMono:
    '"SF Mono", ui-monospace, "Roboto Mono", "Menlo", monospace',
} as const;

// Per-mode accent + metadata used across the demo scenes.
export const modes = {
  hint: {
    name: "Hint Mode",
    shortcut: ["⌘", "⇧", "Space"],
    color: theme.hues.blue,
    tagline: "Click anything by typing.",
  },
  scroll: {
    name: "Scroll Mode",
    shortcut: ["⌘", "⇧", "J"],
    color: theme.hues.green,
    tagline: "Scroll with H J K L.",
  },
  search: {
    name: "Search Mode",
    shortcut: ["⌘", "⇧", "/"],
    color: theme.hues.indigo,
    tagline: "Find any element, instantly.",
  },
} as const;
