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
import { modes, theme } from "../theme";
import { FONT } from "../font";

export const SceneOutro: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const logoIn = spring({ frame, fps, config: { damping: 13, stiffness: 110 } });
  const word = spring({ frame: frame - 16, fps, config: { damping: 18 } });
  const tag = spring({ frame: frame - 28, fps, config: { damping: 20 } });
  const chips = spring({ frame: frame - 40, fps, config: { damping: 20 } });
  const url = spring({ frame: frame - 52, fps, config: { damping: 20 } });

  const float = Math.sin(frame / 22) * 7;
  const glow = 0.7 + Math.sin(frame / 16) * 0.3;

  return (
    <AbsoluteFill style={{ fontFamily: FONT }}>
      <Background tint={theme.accent} />

      <Stage3D perspective={1500} rotateY={Math.sin(frame / 50) * 6} rotateX={3}>
        <Layer3D z={80} y={-150 + float}>
          <div style={{ transform: `scale(${interpolate(logoIn, [0, 1], [0.5, 1])})`, opacity: logoIn }}>
            <HoprLogo size={190} glow={glow} />
          </div>
        </Layer3D>
      </Stage3D>

      <AbsoluteFill
        style={{
          alignItems: "center",
          justifyContent: "center",
          flexDirection: "column",
          paddingTop: 200,
        }}
      >
        <div
          style={{
            fontSize: 120,
            fontWeight: 900,
            letterSpacing: -4,
            color: theme.white,
            opacity: word,
            transform: `translateY(${interpolate(word, [0, 1], [40, 0])}px)`,
            textShadow: "0 10px 50px rgba(0,0,0,0.5)",
          }}
        >
          Hopr
        </div>

        <div
          style={{
            fontSize: 32,
            fontWeight: 500,
            color: theme.textDim,
            marginTop: 6,
            opacity: tag,
            transform: `translateY(${interpolate(tag, [0, 1], [30, 0])}px)`,
          }}
        >
          Your whole Mac, on the home row.
        </div>

        {/* Mode chips */}
        <div
          style={{
            display: "flex",
            gap: 16,
            marginTop: 40,
            opacity: chips,
            transform: `translateY(${interpolate(chips, [0, 1], [30, 0])}px)`,
          }}
        >
          {Object.values(modes).map((m) => (
            <div
              key={m.name}
              style={{
                display: "flex",
                alignItems: "center",
                gap: 10,
                padding: "12px 22px",
                borderRadius: 999,
                background: "rgba(255,255,255,0.05)",
                border: `1px solid ${m.color}55`,
                fontSize: 20,
                fontWeight: 600,
                color: theme.white,
              }}
            >
              <span
                style={{
                  width: 10,
                  height: 10,
                  borderRadius: "50%",
                  background: m.color,
                  boxShadow: `0 0 12px ${m.color}`,
                }}
              />
              {m.name}
            </div>
          ))}
        </div>

        <div
          style={{
            marginTop: 44,
            display: "flex",
            alignItems: "center",
            gap: 18,
            opacity: url,
            transform: `translateY(${interpolate(url, [0, 1], [24, 0])}px)`,
          }}
        >
          <span
            style={{
              fontSize: 22,
              fontWeight: 700,
              color: "#fff",
              padding: "14px 28px",
              borderRadius: 14,
              background: `linear-gradient(180deg, ${theme.accentBright}, ${theme.accent})`,
              boxShadow: `0 10px 30px ${theme.accentGlow}`,
            }}
          >
            Free & open source
          </span>
          <span style={{ fontSize: 22, color: theme.textDim, fontFamily: theme.fontMono }}>
            github.com/zerodevid/hopr
          </span>
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
