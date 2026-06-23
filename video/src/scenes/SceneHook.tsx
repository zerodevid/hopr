import React from "react";
import {
  AbsoluteFill,
  useCurrentFrame,
  useVideoConfig,
  spring,
  interpolate,
} from "remotion";
import { Background } from "../components/Background";
import { Stage3D, Layer3D } from "../components/Stage3D";
import { HoprLogo } from "../components/HoprLogo";
import { theme } from "../theme";
import { FONT } from "../font";

export const SceneHook: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const logoIn = spring({
    frame,
    fps,
    config: { damping: 13, mass: 0.9, stiffness: 120 },
  });
  const glow = interpolate(frame, [0, 30, 90], [0, 0.5, 1], {
    extrapolateRight: "clamp",
  });
  const float = Math.sin(frame / 22) * 8;
  const camYaw = interpolate(frame, [0, 120], [-10, 8]);
  const camPitch = interpolate(frame, [0, 120], [8, 2]);

  const line1 = spring({ frame: frame - 26, fps, config: { damping: 18 } });
  const line2 = spring({ frame: frame - 40, fps, config: { damping: 18 } });
  const sub = spring({ frame: frame - 56, fps, config: { damping: 20 } });

  return (
    <AbsoluteFill style={{ fontFamily: FONT }}>
      <Background tint={theme.accent} />

      <Stage3D perspective={1500} rotateY={camYaw} rotateX={camPitch}>
        <Layer3D z={120} y={-170 + float}>
          <div
            style={{
              transform: `scale(${interpolate(logoIn, [0, 1], [0.6, 1])})`,
              opacity: logoIn,
            }}
          >
            <HoprLogo size={230} glow={glow} />
          </div>
        </Layer3D>
      </Stage3D>

      {/* Headline (flat overlay for crisp text) */}
      <AbsoluteFill
        style={{
          alignItems: "center",
          justifyContent: "center",
          flexDirection: "column",
          paddingTop: 210,
        }}
      >
        <Reveal progress={line1}>
          <h1 style={headline}>Control your entire Mac</h1>
        </Reveal>
        <Reveal progress={line2}>
          <h1 style={{ ...headline, color: theme.accentBright }}>
            without the mouse.
          </h1>
        </Reveal>
        <Reveal progress={sub}>
          <p style={subStyle}>
            Drive every button, link & field straight from the keyboard.
          </p>
        </Reveal>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

const Reveal: React.FC<{ progress: number; children: React.ReactNode }> = ({
  progress,
  children,
}) => (
  <div
    style={{
      opacity: progress,
      transform: `translateY(${interpolate(progress, [0, 1], [38, 0])}px)`,
    }}
  >
    {children}
  </div>
);

const headline: React.CSSProperties = {
  fontSize: 92,
  fontWeight: 900,
  letterSpacing: -2.5,
  color: theme.white,
  margin: 0,
  lineHeight: 1.02,
  textShadow: "0 8px 40px rgba(0,0,0,0.5)",
};

const subStyle: React.CSSProperties = {
  fontSize: 32,
  fontWeight: 500,
  color: theme.textDim,
  marginTop: 30,
  letterSpacing: -0.2,
};
