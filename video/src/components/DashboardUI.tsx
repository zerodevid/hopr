import React from "react";
import { theme } from "../theme";
import { FONT } from "../font";

export const CONTENT_W = 1180;
export const CONTENT_H = 660;

export type Target = {
  id: string;
  label: string;
  x: number; // center, in content coords
  y: number;
};

// Hint-label anchor points laid out over the interactive elements below.
export const TARGETS: Target[] = [
  { id: "compose", label: "A", x: 120, y: 44 },
  { id: "inbox", label: "S", x: 120, y: 104 },
  { id: "starred", label: "D", x: 120, y: 149 },
  { id: "sent", label: "F", x: 120, y: 194 },
  { id: "archive", label: "G", x: 120, y: 239 },
  { id: "reply", label: "H", x: 1013, y: 42 },
  { id: "forward", label: "J", x: 1071, y: 42 },
  { id: "row1", label: "K", x: 710, y: 136 },
  { id: "row2", label: "L", x: 710, y: 220 },
  { id: "row3", label: "QA", x: 710, y: 304 },
  { id: "cta", label: "QS", x: 379, y: 400 },
];

/**
 * A clean mail-style app used as the demo surface. `focusId` highlights an
 * element, `clickId` shows the pressed/clicked state.
 */
export const DashboardUI: React.FC<{
  focusId?: string;
  clickId?: string;
}> = ({ focusId, clickId }) => {
  const nav = [
    { id: "inbox", label: "Inbox", badge: "12", active: true },
    { id: "starred", label: "Starred" },
    { id: "sent", label: "Sent" },
    { id: "archive", label: "Archive" },
  ];
  const rows = [
    { id: "row1", from: "Linear", subj: "Your weekly issue digest", t: "9:24" },
    { id: "row2", from: "GitHub", subj: "12 PRs awaiting your review", t: "8:01" },
    { id: "row3", from: "Figma", subj: "Aria shared “Hopr — Brand”", t: "Tue" },
  ];

  return (
    <div style={{ display: "flex", width: "100%", height: "100%", fontFamily: FONT }}>
      {/* Sidebar */}
      <div
        style={{
          width: 240,
          height: "100%",
          background: "rgba(255,255,255,0.025)",
          borderRight: "1px solid rgba(255,255,255,0.06)",
          padding: "22px 18px",
          display: "flex",
          flexDirection: "column",
          gap: 6,
        }}
      >
        <Button
          label="✦  Compose"
          primary
          active={focusId === "compose"}
          clicked={clickId === "compose"}
        />
        <div style={{ height: 18 }} />
        {nav.map((n) => (
          <NavItem
            key={n.id}
            {...n}
            focused={focusId === n.id}
            clicked={clickId === n.id}
          />
        ))}
      </div>

      {/* Main */}
      <div style={{ flex: 1, height: "100%", display: "flex", flexDirection: "column" }}>
        {/* Header */}
        <div
          style={{
            height: 84,
            padding: "0 28px",
            display: "flex",
            alignItems: "center",
            justifyContent: "space-between",
            borderBottom: "1px solid rgba(255,255,255,0.06)",
          }}
        >
          <span style={{ fontSize: 30, fontWeight: 800, color: theme.white }}>
            Inbox
          </span>
          <div style={{ display: "flex", gap: 12 }}>
            <IconBtn glyph="↩" focused={focusId === "reply"} clicked={clickId === "reply"} />
            <IconBtn glyph="↪" focused={focusId === "forward"} clicked={clickId === "forward"} />
          </div>
        </div>

        {/* Message list */}
        <div style={{ padding: "16px 24px", display: "flex", flexDirection: "column", gap: 12 }}>
          {rows.map((r) => (
            <Row
              key={r.id}
              {...r}
              focused={focusId === r.id}
              clicked={clickId === r.id}
            />
          ))}

          <div style={{ height: 10 }} />
          <div
            style={{
              alignSelf: "flex-start",
              padding: "16px 30px",
              borderRadius: 14,
              fontSize: 20,
              fontWeight: 700,
              color: "#fff",
              background:
                focusId === "cta" || clickId === "cta"
                  ? `linear-gradient(180deg, ${theme.accentBright}, ${theme.accent})`
                  : "rgba(255,255,255,0.07)",
              border: "1px solid rgba(255,255,255,0.12)",
              boxShadow:
                focusId === "cta" ? `0 0 0 3px ${theme.accent}66` : "none",
              transform: clickId === "cta" ? "translateY(2px)" : "none",
            }}
          >
            Mark all as read
          </div>
        </div>
      </div>
    </div>
  );
};

const focusRing = (c: string) => `0 0 0 3px ${c}66, 0 0 22px ${c}55`;

const Button: React.FC<{
  label: string;
  primary?: boolean;
  active?: boolean;
  clicked?: boolean;
}> = ({ label, primary, active, clicked }) => (
  <div
    style={{
      padding: "13px 16px",
      borderRadius: 12,
      fontSize: 18,
      fontWeight: 700,
      color: "#fff",
      textAlign: "center",
      background: primary
        ? `linear-gradient(180deg, ${theme.accentBright}, ${theme.accent})`
        : "rgba(255,255,255,0.06)",
      border: "1px solid rgba(255,255,255,0.14)",
      boxShadow: active ? focusRing(theme.accent) : "0 4px 12px rgba(0,0,0,0.3)",
      transform: clicked ? "translateY(2px) scale(0.98)" : "none",
    }}
  >
    {label}
  </div>
);

const NavItem: React.FC<{
  label: string;
  badge?: string;
  active?: boolean;
  focused?: boolean;
  clicked?: boolean;
}> = ({ label, badge, active, focused, clicked }) => (
  <div
    style={{
      display: "flex",
      alignItems: "center",
      justifyContent: "space-between",
      padding: "11px 14px",
      borderRadius: 10,
      fontSize: 17,
      fontWeight: 600,
      color: active ? theme.white : theme.textDim,
      background: active ? "rgba(255,255,255,0.08)" : "transparent",
      boxShadow: focused ? focusRing(theme.accent) : "none",
      transform: clicked ? "scale(0.98)" : "none",
    }}
  >
    <span>{label}</span>
    {badge ? (
      <span
        style={{
          fontSize: 13,
          fontWeight: 700,
          color: theme.white,
          background: theme.accent,
          borderRadius: 9,
          padding: "2px 8px",
        }}
      >
        {badge}
      </span>
    ) : null}
  </div>
);

const IconBtn: React.FC<{ glyph: string; focused?: boolean; clicked?: boolean }> = ({
  glyph,
  focused,
  clicked,
}) => (
  <div
    style={{
      width: 46,
      height: 46,
      borderRadius: 12,
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
      fontSize: 22,
      color: theme.textDim,
      background: "rgba(255,255,255,0.06)",
      border: "1px solid rgba(255,255,255,0.1)",
      boxShadow: focused ? focusRing(theme.accent) : "none",
      transform: clicked ? "translateY(2px)" : "none",
    }}
  >
    {glyph}
  </div>
);

const Row: React.FC<{
  from: string;
  subj: string;
  t: string;
  focused?: boolean;
  clicked?: boolean;
}> = ({ from, subj, t, focused, clicked }) => (
  <div
    style={{
      display: "flex",
      alignItems: "center",
      gap: 16,
      padding: "16px 20px",
      borderRadius: 14,
      background: focused ? "rgba(0,122,255,0.10)" : "rgba(255,255,255,0.035)",
      border: "1px solid rgba(255,255,255,0.07)",
      boxShadow: focused ? focusRing(theme.accent) : "none",
      transform: clicked ? "scale(0.99)" : "none",
    }}
  >
    <div
      style={{
        width: 40,
        height: 40,
        borderRadius: "50%",
        background: "linear-gradient(135deg,#3B9BFF,#5E5CE6)",
        flexShrink: 0,
      }}
    />
    <div style={{ flex: 1 }}>
      <div style={{ fontSize: 18, fontWeight: 700, color: theme.white }}>{from}</div>
      <div style={{ fontSize: 16, color: theme.textDim }}>{subj}</div>
    </div>
    <div style={{ fontSize: 14, color: theme.textFaint }}>{t}</div>
  </div>
);
