import React from "react";
import { AbsoluteFill } from "remotion";

/**
 * Perspective container that gives children a real 3D camera feel.
 * Pass rotateX / rotateY / z to "fly" the whole stage.
 */
export const Stage3D: React.FC<{
  children: React.ReactNode;
  perspective?: number;
  rotateX?: number;
  rotateY?: number;
  rotateZ?: number;
  z?: number;
  originY?: string;
}> = ({
  children,
  perspective = 1600,
  rotateX = 0,
  rotateY = 0,
  rotateZ = 0,
  z = 0,
  originY = "50%",
}) => {
  return (
    <AbsoluteFill
      style={{
        perspective,
        perspectiveOrigin: `50% ${originY}`,
        transformStyle: "preserve-3d",
      }}
    >
      <AbsoluteFill
        style={{
          transformStyle: "preserve-3d",
          transform: `translateZ(${z}px) rotateX(${rotateX}deg) rotateY(${rotateY}deg) rotateZ(${rotateZ}deg)`,
          alignItems: "center",
          justifyContent: "center",
        }}
      >
        {children}
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

/** A single 3D layer placed at a given depth (translateZ) for parallax. */
export const Layer3D: React.FC<{
  children: React.ReactNode;
  z?: number;
  x?: number;
  y?: number;
  rotateX?: number;
  rotateY?: number;
  style?: React.CSSProperties;
}> = ({ children, z = 0, x = 0, y = 0, rotateX = 0, rotateY = 0, style }) => (
  <div
    style={{
      position: "absolute",
      transformStyle: "preserve-3d",
      transform: `translate3d(${x}px, ${y}px, ${z}px) rotateX(${rotateX}deg) rotateY(${rotateY}deg)`,
      ...style,
    }}
  >
    {children}
  </div>
);
