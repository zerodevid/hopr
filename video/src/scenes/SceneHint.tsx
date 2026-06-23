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
import { DashboardUI, TARGETS, CONTENT_W, CONTENT_H } from "../components/DashboardUI";
import { HintBadge } from "../components/HintBadge";
import { Caption } from "../components/Caption";
import { modes, theme } from "../theme";
import { FONT } from "../font";

const TYPE_Q = 92;
const TYPE_S = 104;
const ACTIVATE = 112;
const CLICK = 116;

export const SceneHint: React.FC<{ durationInFrames: number }> = ({
  durationInFrames,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const c = modes.hint.color;

  const win = spring({
    frame,
    fps,
    config: { damping: 16, mass: 1, stiffness: 90 },
  });
  const yaw = interpolate(win, [0, 1], [-22, -9]) + Math.sin(frame / 40) * 1.2;
  const pitch = interpolate(win, [0, 1], [13, 7]);

  const typedLen = frame >= TYPE_S ? 2 : frame >= TYPE_Q ? 1 : 0;
  const typed = ["", "Q", "QS"][typedLen];
  const fadeAt = (at: number) =>
    interpolate(frame, [at, at + 5], [0, 1], {
      extrapolateLeft: "clamp",
      extrapolateRight: "clamp",
    });

  const clickId = frame >= CLICK ? "cta" : undefined;
  const focusId = frame >= TYPE_S ? "cta" : undefined;

  return (
    <AbsoluteFill style={{ fontFamily: FONT }}>
      <Background tint={c} />

      <Stage3D perspective={1700} rotateY={yaw} rotateX={pitch} originY="46%">
        <div
          style={{
            transform: `scale(${interpolate(win, [0, 1], [0.82, 1])})`,
            opacity: win,
            transformStyle: "preserve-3d",
          }}
        >
          <GlassWindow
            width={CONTENT_W}
            height={CONTENT_H + 46}
            title="Mail — Inbox"
          >
            <div style={{ position: "relative", width: "100%", height: "100%" }}>
              <DashboardUI focusId={focusId} clickId={clickId} />

              {/* Hint badge overlay (shares the window's tilt) */}
              <div
                style={{
                  position: "absolute",
                  inset: 0,
                  transformStyle: "preserve-3d",
                }}
              >
                {TARGETS.map((t, i) => {
                  let dim = 0;
                  if (typedLen >= 1 && !t.label.startsWith("Q"))
                    dim = fadeAt(TYPE_Q);
                  else if (typedLen >= 2 && t.label !== "QS")
                    dim = fadeAt(TYPE_S);
                  return (
                    <div
                      key={t.id}
                      style={{
                        position: "absolute",
                        left: t.x,
                        top: t.y,
                        transform: "translate(-50%,-50%)",
                      }}
                    >
                      <HintBadge
                        label={t.label}
                        color={c}
                        delay={30 + i * 3}
                        dim={dim}
                        active={t.label === "QS"}
                        activeAt={ACTIVATE}
                        size={26}
                      />
                    </div>
                  );
                })}
              </div>

              <ClickRipple x={379} y={400} at={CLICK} color={c} />
            </div>
          </GlassWindow>
        </div>
      </Stage3D>

      {/* Typed-input HUD */}
      <TypedHUD typed={typed} color={c} />

      <Caption
        name={modes.hint.name}
        tagline={modes.hint.tagline}
        shortcut={[...modes.hint.shortcut]}
        color={c}
        inAt={26}
        durationInFrames={durationInFrames}
      />
    </AbsoluteFill>
  );
};

const TypedHUD: React.FC<{ typed: string; color: string }> = ({
  typed,
  color,
}) => {
  if (!typed) return null;
  return (
    <div
      style={{
        position: "absolute",
        top: 96,
        left: "50%",
        transform: "translateX(-50%)",
        display: "flex",
        alignItems: "center",
        gap: 14,
        padding: "12px 22px",
        borderRadius: 999,
        background: "rgba(20,21,28,0.7)",
        border: `1px solid ${color}55`,
        boxShadow: `0 0 30px ${color}40`,
        backdropFilter: "blur(12px)",
        fontFamily: theme.fontMono,
      }}
    >
      <span style={{ color: theme.textDim, fontSize: 18 }}>Typing</span>
      <span
        style={{
          color: "#fff",
          fontSize: 26,
          fontWeight: 800,
          letterSpacing: 6,
        }}
      >
        {typed}
      </span>
    </div>
  );
};

const ClickRipple: React.FC<{
  x: number;
  y: number;
  at: number;
  color: string;
}> = ({ x, y, at, color }) => {
  const frame = useCurrentFrame();
  if (frame < at) return null;
  const p = interpolate(frame, [at, at + 18], [0, 1], {
    extrapolateRight: "clamp",
  });
  return (
    <div
      style={{
        position: "absolute",
        left: x,
        top: y,
        transform: `translate(-50%,-50%) scale(${0.3 + p * 2})`,
        width: 120,
        height: 120,
        borderRadius: "50%",
        border: `3px solid ${color}`,
        opacity: 1 - p,
        pointerEvents: "none",
      }}
    />
  );
};
