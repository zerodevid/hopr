import React from "react";
import { useCurrentFrame, useVideoConfig, spring, interpolate } from "remotion";
import { theme } from "../theme";

/** Returns true if a hex color is perceptually light (→ use dark text). */
const isLight = (hex: string) => {
  const h = hex.replace("#", "");
  const r = parseInt(h.slice(0, 2), 16);
  const g = parseInt(h.slice(2, 4), 16);
  const b = parseInt(h.slice(4, 6), 16);
  return (0.299 * r + 0.587 * g + 0.114 * b) / 255 > 0.62;
};

/**
 * A Hopr-style hint label: a letter badge that springs in with a 3D pop.
 * When `active`, it flashes brighter and scales up (a "typed match").
 */
export const HintBadge: React.FC<{
  label: string;
  color?: string;
  delay?: number;
  active?: boolean;
  activeAt?: number;
  dim?: number; // 0 = full, 1 = filtered-out (prefix no longer matches)
  size?: number;
}> = ({
  label,
  color = theme.accent,
  delay = 0,
  active = false,
  activeAt = 9999,
  dim = 0,
  size = 30,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const pop = spring({
    frame: frame - delay,
    fps,
    config: { damping: 12, mass: 0.6, stiffness: 140 },
  });

  const activeProg = active
    ? spring({
        frame: frame - activeAt,
        fps,
        config: { damping: 10, mass: 0.5, stiffness: 200 },
      })
    : 0;

  const scale = pop * (1 + activeProg * 0.45) * (1 - dim * 0.25);
  const z = interpolate(pop, [0, 1], [-60, 0]) + activeProg * 40;
  const dark = isLight(color);
  const fg = dark ? "#14141A" : "#FFFFFF";

  return (
    <div
      style={{
        transform: `translateZ(${z}px) scale(${scale})`,
        opacity: pop * (1 - dim * 0.86),
        filter: dim > 0 ? `saturate(${1 - dim * 0.7})` : undefined,
        transformStyle: "preserve-3d",
      }}
    >
      <div
        style={{
          fontFamily: theme.fontMono,
          fontSize: size,
          fontWeight: 800,
          lineHeight: 1,
          letterSpacing: 1,
          color: fg,
          padding: `${size * 0.28}px ${size * 0.42}px`,
          borderRadius: size * 0.34,
          background: `linear-gradient(180deg, ${color}, ${shade(color, -14)})`,
          border: "1px solid rgba(255,255,255,0.35)",
          boxShadow: `0 6px 14px rgba(0,0,0,0.45), 0 0 ${18 + activeProg * 30}px ${color}${active ? "cc" : "88"}`,
          textShadow: dark ? "none" : "0 1px 2px rgba(0,0,0,0.35)",
        }}
      >
        {label}
      </div>
    </div>
  );
};

/** Lighten/darken a hex color by percent (-100..100). */
function shade(hex: string, percent: number) {
  const h = hex.replace("#", "");
  const num = parseInt(h, 16);
  const amt = Math.round(2.55 * percent);
  const r = Math.min(255, Math.max(0, (num >> 16) + amt));
  const g = Math.min(255, Math.max(0, ((num >> 8) & 0xff) + amt));
  const b = Math.min(255, Math.max(0, (num & 0xff) + amt));
  return `#${((1 << 24) + (r << 16) + (g << 8) + b).toString(16).slice(1)}`;
}
