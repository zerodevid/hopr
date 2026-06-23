import React from "react";
import {
  AbsoluteFill,
  useCurrentFrame,
  useVideoConfig,
  spring,
  interpolate,
} from "remotion";
import { Background } from "../components/Background";
import { Stage3D } from "../components/Stage3D";
import { GlassWindow } from "../components/GlassWindow";
import { DashboardUI, CONTENT_W, CONTENT_H } from "../components/DashboardUI";
import { TypeText } from "../components/TypeText";
import { Caption } from "../components/Caption";
import { modes, theme } from "../theme";
import { FONT } from "../font";

const PANEL_IN = 24;
const TYPE_START = 40;
const RESULTS_AT = 70;
const CONFIRM = 124;

type Result = {
  label: string;
  title: string;
  role: string;
  box: { x: number; y: number; w: number; h: number };
};

const RESULTS: Result[] = [
  { label: "A", title: "Sent", role: "Mailbox", box: { x: 392, y: 612, w: 250, h: 50 } },
  { label: "S", title: "Settings", role: "Menu Item", box: { x: 392, y: 666, w: 250, h: 50 } },
  { label: "D", title: "Search", role: "Text Field", box: { x: 690, y: 320, w: 720, h: 60 } },
];

export const SceneSearch: React.FC<{ durationInFrames: number }> = ({
  durationInFrames,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const c = modes.search.color;

  const win = spring({ frame, fps, config: { damping: 16, stiffness: 90 } });
  const yaw = interpolate(win, [0, 1], [-14, -5]) + Math.sin(frame / 45) * 1;
  const pitch = interpolate(win, [0, 1], [10, 5]);

  const panel = spring({
    frame: frame - PANEL_IN,
    fps,
    config: { damping: 15, mass: 0.8, stiffness: 120 },
  });

  // selection index walks down as the user presses ↓
  const sel = frame >= 112 ? 2 : frame >= 98 ? 1 : 0;
  const confirmed = frame >= CONFIRM;
  const confirmProg = interpolate(frame, [CONFIRM, CONFIRM + 14], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const active = RESULTS[sel];

  return (
    <AbsoluteFill style={{ fontFamily: FONT }}>
      <Background tint={c} />

      {/* Background app, blurred & dimmed to focus the HUD */}
      <Stage3D perspective={1700} rotateY={yaw} rotateX={pitch} originY="46%">
        <div
          style={{
            transform: `scale(${interpolate(win, [0, 1], [0.82, 1])})`,
            opacity: win,
            filter: `blur(${interpolate(panel, [0, 1], [0, 5])}px) brightness(${interpolate(
              panel,
              [0, 1],
              [1, 0.62],
            )})`,
            transformStyle: "preserve-3d",
          }}
        >
          <GlassWindow width={CONTENT_W} height={CONTENT_H + 46} title="Mail — Inbox">
            <DashboardUI />
          </GlassWindow>
        </div>
      </Stage3D>

      {/* Highlight box tracking the selected element */}
      {!confirmed || confirmProg < 1 ? (
        <HighlightBox box={active.box} color={c} flash={confirmProg} />
      ) : null}

      {/* Search HUD */}
      <AbsoluteFill style={{ alignItems: "center", justifyContent: "center" }}>
        <div
          style={{
            width: 760,
            transform: `translateY(${interpolate(panel, [0, 1], [40, -40])}px) scale(${interpolate(
              panel,
              [0, 1],
              [0.9, 1],
            )}) scale(${1 - confirmProg * 0.06})`,
            opacity: panel * (1 - confirmProg),
          }}
        >
          <div
            style={{
              borderRadius: 22,
              overflow: "hidden",
              background: "rgba(26,27,36,0.72)",
              backdropFilter: "blur(30px)",
              WebkitBackdropFilter: "blur(30px)",
              border: `1px solid ${theme.glassStroke}`,
              boxShadow: `0 40px 120px rgba(0,0,0,0.6), 0 0 0 1px ${c}22, 0 0 60px ${c}33`,
            }}
          >
            {/* Search field */}
            <div
              style={{
                display: "flex",
                alignItems: "center",
                gap: 18,
                padding: "26px 30px",
                borderBottom: "1px solid rgba(255,255,255,0.08)",
              }}
            >
              <span style={{ fontSize: 30, opacity: 0.6 }}>🔍</span>
              <div style={{ fontSize: 34, fontWeight: 600, color: theme.white }}>
                <TypeText text="se" startAt={TYPE_START} cps={6} />
              </div>
            </div>

            {/* Results */}
            <div style={{ padding: 12 }}>
              {RESULTS.map((r, i) => (
                <ResultRow
                  key={r.title}
                  r={r}
                  index={i}
                  selected={i === sel}
                  color={c}
                  appearAt={RESULTS_AT + i * 6}
                />
              ))}
            </div>
          </div>

          {/* Arrow / enter hints */}
          <div
            style={{
              display: "flex",
              justifyContent: "center",
              gap: 22,
              marginTop: 20,
              color: theme.textFaint,
              fontSize: 18,
              fontFamily: theme.fontMono,
            }}
          >
            <span>↑ ↓ navigate</span>
            <span style={{ color: confirmed ? c : theme.textFaint }}>↵ confirm</span>
          </div>
        </div>
      </AbsoluteFill>

      <Caption
        name={modes.search.name}
        tagline={modes.search.tagline}
        shortcut={[...modes.search.shortcut]}
        color={c}
        inAt={26}
        durationInFrames={durationInFrames}
      />
    </AbsoluteFill>
  );
};

const ResultRow: React.FC<{
  r: Result;
  index: number;
  selected: boolean;
  color: string;
  appearAt: number;
}> = ({ r, selected, color, appearAt }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const enter = spring({ frame: frame - appearAt, fps, config: { damping: 16 } });
  return (
    <div
      style={{
        display: "flex",
        alignItems: "center",
        gap: 18,
        padding: "16px 18px",
        borderRadius: 14,
        background: selected ? `${color}22` : "transparent",
        boxShadow: selected ? `inset 0 0 0 1.5px ${color}88` : "none",
        opacity: enter,
        transform: `translateX(${interpolate(enter, [0, 1], [24, 0])}px)`,
      }}
    >
      <div
        style={{
          width: 40,
          height: 40,
          borderRadius: 10,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          fontFamily: theme.fontMono,
          fontWeight: 800,
          fontSize: 20,
          color: "#fff",
          background: `linear-gradient(180deg, ${color}, ${color}cc)`,
          boxShadow: `0 4px 12px ${color}66`,
        }}
      >
        {r.label}
      </div>
      <div style={{ flex: 1 }}>
        <div style={{ fontSize: 22, fontWeight: 700, color: theme.white }}>{r.title}</div>
        <div style={{ fontSize: 15, color: theme.textDim }}>{r.role}</div>
      </div>
      {selected ? (
        <div style={{ color, fontSize: 22 }}>↵</div>
      ) : null}
    </div>
  );
};

const HighlightBox: React.FC<{
  box: { x: number; y: number; w: number; h: number };
  color: string;
  flash: number;
}> = ({ box, color, flash }) => (
  <div
    style={{
      position: "absolute",
      left: box.x,
      top: box.y,
      width: box.w,
      height: box.h,
      borderRadius: 12,
      border: `2.5px solid ${color}`,
      boxShadow: `0 0 ${24 + flash * 50}px ${color}, inset 0 0 ${20 + flash * 40}px ${color}55`,
      background: `${color}${flash > 0 ? "33" : "14"}`,
      transition: "none",
    }}
  />
);
