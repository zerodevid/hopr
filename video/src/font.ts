import { loadFont } from "@remotion/google-fonts/Inter";

// Load Inter once; expose the family for use in inline styles.
const { fontFamily } = loadFont("normal", {
  weights: ["400", "500", "600", "700", "800", "900"],
});

export const FONT = fontFamily;
