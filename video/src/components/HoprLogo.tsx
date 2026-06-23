import React from "react";

/**
 * The Hopr app icon, inlined as SVG so we can animate it crisply.
 * Dark squircle background + white mascot (eyes are even-odd holes).
 */
export const HoprLogo: React.FC<{
  size?: number;
  glow?: number; // 0..1 — strength of the accent glow halo
  radius?: number; // corner radius override (px in icon space scaled)
}> = ({ size = 256, glow = 0, radius = 168 }) => {
  return (
    <div
      style={{
        width: size,
        height: size,
        position: "relative",
        filter:
          glow > 0
            ? `drop-shadow(0 0 ${40 * glow}px rgba(0,122,255,${0.65 * glow})) drop-shadow(0 ${size * 0.06}px ${size * 0.12}px rgba(0,0,0,0.55))`
            : `drop-shadow(0 ${size * 0.05}px ${size * 0.1}px rgba(0,0,0,0.45))`,
      }}
    >
      <svg
        width={size}
        height={size}
        viewBox="0 0 720 720"
        xmlns="http://www.w3.org/2000/svg"
        fillRule="evenodd"
        clipRule="evenodd"
      >
        <defs>
          <linearGradient id="hoprBg" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stopColor="#2B2D3A" />
            <stop offset="1" stopColor="#15151B" />
          </linearGradient>
        </defs>
        <rect
          x="0"
          y="0"
          width="720"
          height="720"
          rx={radius}
          ry={radius}
          fill="url(#hoprBg)"
        />
        <rect
          x="3"
          y="3"
          width="714"
          height="714"
          rx={radius - 3}
          ry={radius - 3}
          fill="none"
          stroke="#ffffff"
          strokeOpacity="0.06"
          strokeWidth="6"
        />
        <g transform="translate(174,140) scale(0.6061) translate(-5087,-1741)">
          <path
            fill="#ffffff"
            d="M5701,2303.899L5701,2313.5C5701,2398.219 5632.219,2467 5547.5,2467L5240.5,2467C5155.781,2467 5087,2398.219 5087,2313.5L5087,2006.5C5087,1979.95 5093.755,1954.965 5105.639,1933.172C5094.129,1873.142 5109.747,1801.411 5206.495,1741C5206.495,1741 5187.936,1797.032 5197.217,1859.197C5210.043,1855.429 5223.565,1853.293 5237.541,1853.028C5181.115,1873.083 5140.667,1926.98 5140.667,1990.25L5140.667,2264.75C5140.667,2345.1 5205.9,2410.333 5286.25,2410.333L5560.75,2410.333C5627.539,2410.333 5683.884,2365.261 5701,2303.899ZM5610.024,1853.23C5617.038,1799.93 5600.526,1753.023 5600.526,1753.023C5696.528,1809.429 5708.067,1876.923 5694.127,1931.847C5678.141,1895.428 5647.671,1866.787 5610.024,1853.23ZM5286.25,1853L5547.5,1853C5568.983,1853 5589.442,1857.423 5608.013,1865.407C5608.137,1864.788 5633.815,1879.382 5653.778,1899.604C5674.479,1920.574 5689.488,1947.219 5689.318,1947.701C5692.147,1954.51 5694.5,1961.565 5696.335,1968.826C5697.431,1975.807 5698,1982.963 5698,1990.25L5698,2264.75C5698,2340.5 5636.5,2402 5560.75,2402L5286.25,2402C5210.5,2402 5149,2340.5 5149,2264.75L5149,1990.25C5149,1914.5 5210.5,1853 5286.25,1853ZM5306.5,1994C5266.486,1994 5234,2044.858 5234,2107.5C5234,2170.142 5266.486,2221 5306.5,2221C5346.514,2221 5379,2170.142 5379,2107.5C5379,2044.858 5346.514,1994 5306.5,1994ZM5554.5,1994C5514.486,1994 5482,2044.858 5482,2107.5C5482,2170.142 5514.486,2221 5554.5,2221C5594.514,2221 5627,2170.142 5627,2107.5C5627,2044.858 5594.514,1994 5554.5,1994Z"
          />
        </g>
      </svg>
    </div>
  );
};
