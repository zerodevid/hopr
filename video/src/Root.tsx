import React from "react";
import { Composition } from "remotion";
import { TransitionSeries, linearTiming } from "@remotion/transitions";
import { fade } from "@remotion/transitions/fade";

import { SceneHook } from "./scenes/SceneHook";
import { SceneHint } from "./scenes/SceneHint";
import { SceneScroll } from "./scenes/SceneScroll";
import { SceneSearch } from "./scenes/SceneSearch";
import { SceneOutro } from "./scenes/SceneOutro";

const FPS = 30;
const W = 1920;
const H = 1080;

// Scene lengths (frames @30fps) for the full promo.
const D = { hook: 105, hint: 165, scroll: 185, search: 175, outro: 130 };
const XF = 16; // cross-fade length

const totalPromo =
  D.hook + D.hint + D.scroll + D.search + D.outro - 4 * XF;

const HoprPromo: React.FC = () => (
  <TransitionSeries>
    <TransitionSeries.Sequence durationInFrames={D.hook}>
      <SceneHook />
    </TransitionSeries.Sequence>
    <TransitionSeries.Transition presentation={fade()} timing={linearTiming({ durationInFrames: XF })} />

    <TransitionSeries.Sequence durationInFrames={D.hint}>
      <SceneHint durationInFrames={D.hint} />
    </TransitionSeries.Sequence>
    <TransitionSeries.Transition presentation={fade()} timing={linearTiming({ durationInFrames: XF })} />

    <TransitionSeries.Sequence durationInFrames={D.scroll}>
      <SceneScroll durationInFrames={D.scroll} />
    </TransitionSeries.Sequence>
    <TransitionSeries.Transition presentation={fade()} timing={linearTiming({ durationInFrames: XF })} />

    <TransitionSeries.Sequence durationInFrames={D.search}>
      <SceneSearch durationInFrames={D.search} />
    </TransitionSeries.Sequence>
    <TransitionSeries.Transition presentation={fade()} timing={linearTiming({ durationInFrames: XF })} />

    <TransitionSeries.Sequence durationInFrames={D.outro}>
      <SceneOutro />
    </TransitionSeries.Sequence>
  </TransitionSeries>
);

// Shorter social cut: hook + two fast demos + outro.
const T = { hook: 90, hint: 150, search: 160, outro: 95 };
const TXF = 14;
const totalTeaser = T.hook + T.hint + T.search + T.outro - 3 * TXF;

const HoprTeaser: React.FC = () => (
  <TransitionSeries>
    <TransitionSeries.Sequence durationInFrames={T.hook}>
      <SceneHook />
    </TransitionSeries.Sequence>
    <TransitionSeries.Transition presentation={fade()} timing={linearTiming({ durationInFrames: TXF })} />
    <TransitionSeries.Sequence durationInFrames={T.hint}>
      <SceneHint durationInFrames={T.hint} />
    </TransitionSeries.Sequence>
    <TransitionSeries.Transition presentation={fade()} timing={linearTiming({ durationInFrames: TXF })} />
    <TransitionSeries.Sequence durationInFrames={T.search}>
      <SceneSearch durationInFrames={T.search} />
    </TransitionSeries.Sequence>
    <TransitionSeries.Transition presentation={fade()} timing={linearTiming({ durationInFrames: TXF })} />
    <TransitionSeries.Sequence durationInFrames={T.outro}>
      <SceneOutro />
    </TransitionSeries.Sequence>
  </TransitionSeries>
);

export const RemotionRoot: React.FC = () => {
  return (
    <>
      <Composition
        id="HoprPromo"
        component={HoprPromo}
        durationInFrames={totalPromo}
        fps={FPS}
        width={W}
        height={H}
      />
      <Composition
        id="HoprTeaser"
        component={HoprTeaser}
        durationInFrames={totalTeaser}
        fps={FPS}
        width={W}
        height={H}
      />
    </>
  );
};
