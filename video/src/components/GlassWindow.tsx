import React from "react";
import { theme } from "../theme";

/**
 * A clean macOS-style application window used as the demo surface.
 * Glassy chrome, traffic lights, optional toolbar. Sized in CSS px.
 */
export const GlassWindow: React.FC<{
  width: number;
  height: number;
  title?: string;
  toolbar?: React.ReactNode;
  children: React.ReactNode;
  style?: React.CSSProperties;
}> = ({ width, height, title, toolbar, children, style }) => {
  return (
    <div
      style={{
        width,
        height,
        borderRadius: 18,
        overflow: "hidden",
        position: "relative",
        background: "rgba(22,23,30,0.92)",
        border: `1px solid ${theme.glassStroke}`,
        boxShadow:
          "0 2px 0 rgba(255,255,255,0.05) inset, 0 60px 120px rgba(0,0,0,0.55), 0 12px 32px rgba(0,0,0,0.45)",
        ...style,
      }}
    >
      {/* Title bar */}
      <div
        style={{
          height: 46,
          display: "flex",
          alignItems: "center",
          padding: "0 18px",
          gap: 14,
          background:
            "linear-gradient(180deg, rgba(58,60,74,0.65), rgba(34,36,46,0.65))",
          borderBottom: "1px solid rgba(255,255,255,0.06)",
        }}
      >
        <div style={{ display: "flex", gap: 9 }}>
          <Dot color="#FF5F57" />
          <Dot color="#FEBC2E" />
          <Dot color="#28C840" />
        </div>
        {title ? (
          <div
            style={{
              flex: 1,
              textAlign: "center",
              color: theme.textDim,
              fontSize: 15,
              fontWeight: 600,
              letterSpacing: 0.2,
              marginRight: 52,
            }}
          >
            {title}
          </div>
        ) : (
          <div style={{ flex: 1 }} />
        )}
      </div>

      {toolbar ? (
        <div
          style={{
            padding: "10px 16px",
            borderBottom: "1px solid rgba(255,255,255,0.05)",
            background: "rgba(255,255,255,0.02)",
          }}
        >
          {toolbar}
        </div>
      ) : null}

      <div style={{ position: "relative", flex: 1, height: "100%" }}>
        {children}
      </div>
    </div>
  );
};

const Dot: React.FC<{ color: string }> = ({ color }) => (
  <div
    style={{
      width: 13,
      height: 13,
      borderRadius: "50%",
      background: color,
      boxShadow: "inset 0 0 0 0.5px rgba(0,0,0,0.25)",
    }}
  />
);
