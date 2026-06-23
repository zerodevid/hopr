import React from "react";
import { useCurrentFrame } from "remotion";

/** Typewriter reveal with a blinking caret. */
export const TypeText: React.FC<{
  text: string;
  startAt?: number;
  cps?: number; // characters per second (assumes 30fps base)
  caret?: boolean;
  style?: React.CSSProperties;
}> = ({ text, startAt = 0, cps = 14, caret = true, style }) => {
  const frame = useCurrentFrame();
  const elapsed = Math.max(0, frame - startAt);
  const shown = Math.min(text.length, Math.floor((elapsed / 30) * cps));
  const done = shown >= text.length;
  const blink = Math.floor(frame / 15) % 2 === 0;

  return (
    <span style={style}>
      {text.slice(0, shown)}
      {caret && (!done || blink) ? (
        <span style={{ opacity: done ? (blink ? 1 : 0) : 1 }}>|</span>
      ) : null}
    </span>
  );
};
