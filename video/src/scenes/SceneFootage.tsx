import React from "react";
import { AbsoluteFill } from "remotion";
import { Background } from "../components/Background";
import { FootageStage, Spotlight, ZoomKey } from "../components/FootageStage";
import { Caption } from "../components/Caption";
import { modes } from "../theme";
import { FONT } from "../font";

/**
 * A demo beat built from REAL screen footage with cinematic zoom/pan,
 * framed on the 3D stage, with the matching mode caption + (optional) spotlights.
 */
export const SceneFootage: React.FC<{
  mode: keyof typeof modes;
  src: string; // under public/, e.g. "footage/hint.mov"
  keys: ZoomKey[];
  startFrom?: number;
  tilt?: number;
  spotlights?: { fx: number; fy: number; at: number; size?: number }[];
  durationInFrames: number;
}> = ({ mode, src, keys, startFrom = 0, tilt = -6, spotlights = [], durationInFrames }) => {
  const m = modes[mode];
  return (
    <AbsoluteFill style={{ fontFamily: FONT }}>
      <Background tint={m.color} />

      <FootageStage src={src} keys={keys} startFrom={startFrom} tilt={tilt}>
        {spotlights.map((s, i) => (
          <Spotlight key={i} fx={s.fx} fy={s.fy} at={s.at} size={s.size} color={m.color} />
        ))}
      </FootageStage>

      <Caption
        name={m.name}
        tagline={m.tagline}
        shortcut={[...m.shortcut]}
        color={m.color}
        inAt={20}
        durationInFrames={durationInFrames}
      />
    </AbsoluteFill>
  );
};
