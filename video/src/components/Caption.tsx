import React from "react";
import { useCurrentFrame, useVideoConfig, spring, interpolate } from "remotion";
import { theme } from "../theme";
import { KeyCombo } from "./KeyCap";

/**
 * Lower caption bar for each demo scene: mode name, tagline, shortcut keys.
 * Slides up + fades in, then eases out near the end of `durationInFrames`.
 */
export const Caption: React.FC<{
  name: string;
  tagline: string;
  shortcut: string[];
  color: string;
  inAt?: number;
  durationInFrames: number;
}> = ({ name, tagline, shortcut, color, inAt = 0, durationInFrames }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const enter = spring({
    frame: frame - inAt,
    fps,
    config: { damping: 18, mass: 0.8, stiffness: 110 },
  });
  const exit = interpolate(
    frame,
    [durationInFrames - 16, durationInFrames - 4],
    [0, 1],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
  );

  const y = interpolate(enter, [0, 1], [60, 0]) + exit * 40;
  const opacity = enter * (1 - exit);

  return (
    <div
      style={{
        position: "absolute",
        bottom: 70,
        left: 0,
        right: 0,
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        gap: 22,
        transform: `translateY(${y}px)`,
        opacity,
      }}
    >
      <div style={{ display: "flex", alignItems: "center", gap: 16 }}>
        <span
          style={{
            width: 12,
            height: 12,
            borderRadius: "50%",
            background: color,
            boxShadow: `0 0 18px ${color}`,
          }}
        />
        <span
          style={{
            fontSize: 38,
            fontWeight: 800,
            color: theme.white,
            letterSpacing: -0.5,
          }}
        >
          {name}
        </span>
        <span style={{ color: theme.textFaint, fontSize: 30 }}>·</span>
        <span style={{ fontSize: 30, color: theme.textDim, fontWeight: 500 }}>
          {tagline}
        </span>
      </div>
      <KeyCombo keys={shortcut} accent={color} />
    </div>
  );
};
