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
import { HintBadge } from "../components/HintBadge";
import { KeyCap } from "../components/KeyCap";
import { Caption } from "../components/Caption";
import { modes, theme } from "../theme";
import { FONT } from "../font";

const CONTENT_W = 1120;
const CONTENT_H = 660;
const SELECT = 52; // frame the user picks region "1"

export const SceneScroll: React.FC<{ durationInFrames: number }> = ({
  durationInFrames,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const c = modes.scroll.color;

  const win = spring({ frame, fps, config: { damping: 16, stiffness: 90 } });
  const yaw = interpolate(win, [0, 1], [20, 8]) + Math.sin(frame / 40) * 1.2;
  const pitch = interpolate(win, [0, 1], [13, 7]);

  const selected = frame >= SELECT;
  const scrollY = interpolate(
    frame,
    [SELECT + 6, 78, 100, 120, 165],
    [0, -150, -320, -520, -900],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
  );
  const scrolling = frame > SELECT + 4 && frame < 168;
  const turbo = frame >= 120 && frame < 168;
  const jPressed = scrolling && Math.floor(frame / 6) % 2 === 0;

  const progress = interpolate(scrollY, [-900, 0], [1, 0]);

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
          <GlassWindow width={CONTENT_W} height={CONTENT_H + 46} title="Reader">
            <div style={{ position: "relative", width: "100%", height: "100%", display: "flex" }}>
              {/* Main scrollable region (1) */}
              <div
                style={{
                  flex: 1,
                  position: "relative",
                  overflow: "hidden",
                  borderRight: "1px solid rgba(255,255,255,0.06)",
                  boxShadow: selected
                    ? `inset 0 0 0 2px ${c}99, inset 0 0 40px ${c}22`
                    : "none",
                }}
              >
                <div style={{ transform: `translateY(${scrollY}px)`, padding: "40px 56px" }}>
                  <Article />
                </div>
                {/* scrollbar */}
                <div
                  style={{
                    position: "absolute",
                    right: 8,
                    top: 12,
                    bottom: 12,
                    width: 6,
                    borderRadius: 3,
                    background: "rgba(255,255,255,0.06)",
                  }}
                >
                  <div
                    style={{
                      position: "absolute",
                      left: 0,
                      width: 6,
                      height: 90,
                      borderRadius: 3,
                      background: c,
                      top: `${progress * (CONTENT_H - 120)}px`,
                      boxShadow: `0 0 12px ${c}`,
                    }}
                  />
                </div>
                {/* region badge 1 */}
                <RegionBadge n="1" x={70} y={56} color={c} active={selected} delay={28} />
              </div>

              {/* Side region (2) */}
              <div style={{ width: 300, padding: 24, position: "relative" }}>
                <RegionBadge n="2" x={56} y={56} color={c} dim={selected} delay={34} />
                <div style={{ marginTop: 30, display: "flex", flexDirection: "column", gap: 14, opacity: selected ? 0.4 : 1 }}>
                  {["Overview", "Hint mode", "Scroll mode", "Search mode", "Settings"].map(
                    (s, i) => (
                      <div
                        key={s}
                        style={{
                          padding: "12px 14px",
                          borderRadius: 10,
                          fontSize: 16,
                          fontWeight: 600,
                          color: i === 2 ? theme.white : theme.textDim,
                          background: i === 2 ? "rgba(255,255,255,0.07)" : "transparent",
                        }}
                      >
                        {s}
                      </div>
                    ),
                  )}
                </div>
              </div>
            </div>
          </GlassWindow>
        </div>
      </Stage3D>

      {/* Vim keys HUD */}
      <VimKeysHUD jPressed={jPressed} turbo={turbo} color={c} />

      <Caption
        name={modes.scroll.name}
        tagline={modes.scroll.tagline}
        shortcut={[...modes.scroll.shortcut]}
        color={c}
        inAt={26}
        durationInFrames={durationInFrames}
      />
    </AbsoluteFill>
  );
};

const RegionBadge: React.FC<{
  n: string;
  x: number;
  y: number;
  color: string;
  active?: boolean;
  dim?: boolean;
  delay: number;
}> = ({ n, x, y, color, active, dim, delay }) => (
  <div style={{ position: "absolute", left: x, top: y, transform: "translate(-50%,-50%)" }}>
    <HintBadge
      label={n}
      color={color}
      delay={delay}
      dim={dim ? 1 : 0}
      active={active}
      activeAt={SELECT}
      size={28}
    />
  </div>
);

const VimKeysHUD: React.FC<{ jPressed: boolean; turbo: boolean; color: string }> = ({
  jPressed,
  turbo,
  color,
}) => (
  <div
    style={{
      position: "absolute",
      top: 92,
      left: "50%",
      transform: "translateX(-50%)",
      display: "flex",
      alignItems: "center",
      gap: 10,
    }}
  >
    <KeyCap>H</KeyCap>
    <KeyCap pressed={jPressed} accent={jPressed ? color : undefined}>
      J
    </KeyCap>
    <KeyCap>K</KeyCap>
    <KeyCap>L</KeyCap>
    {turbo ? (
      <div
        style={{
          marginLeft: 12,
          padding: "8px 16px",
          borderRadius: 10,
          fontWeight: 800,
          fontSize: 18,
          color: "#14141A",
          background: color,
          boxShadow: `0 0 24px ${color}`,
          fontFamily: theme.fontMono,
        }}
      >
        ⇧ DASH
      </div>
    ) : null}
  </div>
);

const Article: React.FC = () => (
  <div style={{ color: theme.white, maxWidth: 640 }}>
    <div style={{ fontSize: 15, fontWeight: 700, color: modes.scroll.color, letterSpacing: 1 }}>
      KEYBOARD-FIRST
    </div>
    <h1 style={{ fontSize: 44, fontWeight: 900, margin: "10px 0 18px", letterSpacing: -1 }}>
      Never reach for the mouse again
    </h1>
    {[
      "Hopr detects every scrollable region in the active window — editors, web pages, terminals — and lets you drive them with Vim-style keys.",
      "Pick a target region with 1–9, then scroll with H, J, K and L. Hold Shift to engage Dash, a turbo scroll for covering long pages in a blink.",
      "Because it reads the real Accessibility tree, it works the same across native apps and the browser. No extensions, no per-app setup.",
      "Everything happens on a global hotkey, from a background menu-bar agent. Your hands stay on the home row, your focus stays on the work.",
    ].map((p, i) => (
      <p key={i} style={{ fontSize: 21, lineHeight: 1.7, color: theme.textDim, margin: "0 0 22px" }}>
        {p}
      </p>
    ))}
    <div
      style={{
        padding: 22,
        borderRadius: 14,
        background: "rgba(48,209,88,0.10)",
        border: "1px solid rgba(48,209,88,0.3)",
        fontSize: 19,
        color: theme.white,
        margin: "6px 0 26px",
      }}
    >
      Tip: regions are numbered automatically — just glance and press.
    </div>
    {[
      "Scrolling is momentum-aware and pixel-precise, so you land exactly where you mean to.",
      "Combined with Hint and Search modes, the entire macOS UI becomes addressable from the keyboard.",
    ].map((p, i) => (
      <p key={i} style={{ fontSize: 21, lineHeight: 1.7, color: theme.textDim, margin: "0 0 22px" }}>
        {p}
      </p>
    ))}
  </div>
);
