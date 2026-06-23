import React from "react";
import { theme } from "../theme";

/**
 * A 3D-extruded keyboard keycap. `pressed` sinks it down for tactile feel.
 */
export const KeyCap: React.FC<{
  children: React.ReactNode;
  width?: number;
  pressed?: boolean;
  accent?: string;
  fontSize?: number;
}> = ({ children, width, pressed = false, accent, fontSize = 22 }) => {
  const depth = pressed ? 2 : 6;
  return (
    <div
      style={{
        minWidth: width ?? 48,
        height: 48,
        padding: "0 14px",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        fontFamily: theme.fontMono,
        fontSize,
        fontWeight: 700,
        color: accent ?? "rgba(255,255,255,0.92)",
        background:
          "linear-gradient(180deg, rgba(70,72,86,0.95), rgba(40,42,54,0.95))",
        borderRadius: 12,
        border: "1px solid rgba(255,255,255,0.16)",
        transform: `translateY(${pressed ? 4 : 0}px)`,
        boxShadow: `0 ${depth}px 0 rgba(0,0,0,0.5), 0 ${depth + 4}px ${depth + 8}px rgba(0,0,0,0.4), inset 0 1px 0 rgba(255,255,255,0.18)`,
        transition: "none",
      }}
    >
      {children}
    </div>
  );
};

export const KeyCombo: React.FC<{
  keys: string[];
  accent?: string;
  pressed?: boolean;
}> = ({ keys, accent, pressed }) => (
  <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
    {keys.map((k, i) => (
      <React.Fragment key={k}>
        <KeyCap accent={accent} pressed={pressed}>
          {k}
        </KeyCap>
        {i < keys.length - 1 ? (
          <span style={{ color: theme.textFaint, fontSize: 20 }}>+</span>
        ) : null}
      </React.Fragment>
    ))}
  </div>
);
