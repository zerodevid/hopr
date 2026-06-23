import React from "react";
import {
  AbsoluteFill,
  OffthreadVideo,
  staticFile,
  useCurrentFrame,
  interpolate,
  spring,
  useVideoConfig,
} from "remotion";
import { Stage3D } from "./Stage3D";
import { theme } from "../theme";

/**
 * A keyframed zoom/pan ("Ken Burns" + punch-in) over real screen footage,
 * framed on a subtle 3D stage with rounded corners and a soft shadow.
 *
 * Each ZoomKey targets a focal point (fx,fy in 0..1 of the clip) at a scale.
 * Between keys, scale + focal point are smoothly interpolated.
 */
export type ZoomKey = {
  at: number; // frame (relative to scene)
  scale: number; // 1 = fit, >1 = zoomed in
  fx?: number; // focal x, 0..1 (default 0.5)
  fy?: number; // focal y, 0..1 (default 0.5)
};

export const FootageStage: React.FC<{
  src: string; // path under public/, e.g. "footage/hint.mov"
  keys: ZoomKey[];
  startFrom?: number; // trim: start the clip this many frames in
  tilt?: number; // subtle 3D yaw in degrees
  width?: number;
  height?: number;
  children?: React.ReactNode; // overlays (spotlight, etc.) drawn over the clip
}> = ({ src, keys, startFrom = 0, tilt = 0, width = 1600, height = 900, children }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const ats = keys.map((k) => k.at);
  const scale = interpolate(frame, ats, keys.map((k) => k.scale), {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const fx = interpolate(frame, ats, keys.map((k) => k.fx ?? 0.5), {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const fy = interpolate(frame, ats, keys.map((k) => k.fy ?? 0.5), {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const enter = spring({ frame, fps, config: { damping: 18, stiffness: 90 } });
  const yaw = interpolate(enter, [0, 1], [tilt * 2.2, tilt]);

  return (
    <Stage3D perspective={2000} rotateY={yaw} rotateX={interpolate(enter, [0, 1], [6, 2.5])}>
      <div
        style={{
          width,
          height,
          borderRadius: 20,
          overflow: "hidden",
          transform: `scale(${interpolate(enter, [0, 1], [0.9, 1])})`,
          opacity: enter,
          border: `1px solid ${theme.glassStroke}`,
          boxShadow:
            "0 60px 140px rgba(0,0,0,0.6), 0 14px 36px rgba(0,0,0,0.5)",
          position: "relative",
          background: "#000",
        }}
      >
        <div
          style={{
            width: "100%",
            height: "100%",
            transform: `scale(${scale})`,
            transformOrigin: `${fx * 100}% ${fy * 100}%`,
          }}
        >
          <OffthreadVideo
            src={staticFile(src)}
            startFrom={startFrom}
            style={{ width: "100%", height: "100%", objectFit: "cover" }}
          />
        </div>
        {/* Overlays live in clip space so they can track focal points */}
        <AbsoluteFill style={{ pointerEvents: "none" }}>{children}</AbsoluteFill>
      </div>
    </Stage3D>
  );
};

/** A pulsing spotlight ring to draw the eye to where the action happens. */
export const Spotlight: React.FC<{
  fx: number; // 0..1
  fy: number;
  at: number;
  color?: string;
  size?: number;
}> = ({ fx, fy, at, color = theme.accent, size = 120 }) => {
  const frame = useCurrentFrame();
  if (frame < at) return null;
  const p = (frame - at) % 30;
  const pulse = interpolate(p, [0, 30], [0.4, 1.1]);
  const op = interpolate(p, [0, 30], [0.9, 0]);
  return (
    <div
      style={{
        position: "absolute",
        left: `${fx * 100}%`,
        top: `${fy * 100}%`,
        width: size,
        height: size,
        marginLeft: -size / 2,
        marginTop: -size / 2,
        borderRadius: "50%",
        border: `3px solid ${color}`,
        transform: `scale(${pulse})`,
        opacity: op,
        boxShadow: `0 0 24px ${color}`,
      }}
    />
  );
};
