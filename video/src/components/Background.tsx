import React from "react";
import { AbsoluteFill, useCurrentFrame, interpolate } from "remotion";
import { theme } from "../theme";

/**
 * Animated dark mesh-gradient backdrop with slowly drifting colored orbs,
 * a fine grid, a vignette and subtle grain. Sets the "clean & modern" mood.
 */
export const Background: React.FC<{ tint?: string }> = ({
  tint = theme.accent,
}) => {
  const frame = useCurrentFrame();

  const drift = (speed: number, amp: number, phase: number) =>
    Math.sin((frame / speed) + phase) * amp;

  return (
    <AbsoluteFill style={{ backgroundColor: theme.bg0, overflow: "hidden" }}>
      {/* Base vertical gradient */}
      <AbsoluteFill
        style={{
          background: `radial-gradient(120% 120% at 50% -10%, ${theme.bg2} 0%, ${theme.bg1} 38%, ${theme.bg0} 100%)`,
        }}
      />

      {/* Drifting colored orbs */}
      <Orb
        color={tint}
        size={1100}
        x={interpolate(frame, [0, 600], [-200, 60]) + drift(90, 40, 0)}
        y={-220 + drift(70, 30, 1)}
        opacity={0.38}
      />
      <Orb
        color={theme.hues.indigo}
        size={900}
        x={1250 + drift(110, 50, 2)}
        y={620 + drift(80, 36, 0.5)}
        opacity={0.3}
      />
      <Orb
        color={theme.hues.pink}
        size={620}
        x={680 + drift(130, 60, 3)}
        y={980 + drift(100, 30, 2)}
        opacity={0.16}
      />

      {/* Fine grid */}
      <AbsoluteFill
        style={{
          backgroundImage:
            "linear-gradient(rgba(255,255,255,0.035) 1px, transparent 1px), linear-gradient(90deg, rgba(255,255,255,0.035) 1px, transparent 1px)",
          backgroundSize: "64px 64px",
          maskImage:
            "radial-gradient(80% 70% at 50% 42%, black 30%, transparent 78%)",
          WebkitMaskImage:
            "radial-gradient(80% 70% at 50% 42%, black 30%, transparent 78%)",
        }}
      />

      {/* Vignette */}
      <AbsoluteFill
        style={{
          background:
            "radial-gradient(110% 90% at 50% 45%, transparent 55%, rgba(0,0,0,0.55) 100%)",
        }}
      />
    </AbsoluteFill>
  );
};

const Orb: React.FC<{
  color: string;
  size: number;
  x: number;
  y: number;
  opacity: number;
}> = ({ color, size, x, y, opacity }) => (
  <div
    style={{
      position: "absolute",
      left: x,
      top: y,
      width: size,
      height: size,
      borderRadius: "50%",
      background: `radial-gradient(circle at 50% 50%, ${color} 0%, transparent 68%)`,
      opacity,
      filter: "blur(40px)",
    }}
  />
);
