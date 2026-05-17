import type { Config } from "tailwindcss";

const config: Config = {
  darkMode: ["class"],
  content: [
    "./app/**/*.{ts,tsx}",
    "./components/**/*.{ts,tsx}",
    "./lib/**/*.{ts,tsx}",
  ],
  theme: {
    container: {
      center: true,
      padding: "1rem",
      screens: { "2xl": "1440px" },
    },
    extend: {
      colors: {
        // Pulled from website/LAYOUT.md (paper-aligned palette)
        bg: "#0a0a0a",
        surface: "#141414",
        elevated: "#1a1a1a",
        border: "#262626",
        muted: "#a1a1aa",
        fg: "#f5f5f5",
        accent: {
          DEFAULT: "#22d3ee",
          soft: "rgba(34, 211, 238, 0.12)",
          ring: "rgba(34, 211, 238, 0.35)",
        },
        purple: {
          DEFAULT: "#a78bfa",
          soft: "rgba(167, 139, 250, 0.12)",
        },
        success: "#4ade80",
        warn: "#f59e0b",
        danger: "#f87171",
      },
      fontFamily: {
        display: ["'Space Grotesk'", "system-ui", "sans-serif"],
        body: ["Inter", "system-ui", "sans-serif"],
        mono: ["'JetBrains Mono'", "ui-monospace", "monospace"],
      },
      borderRadius: {
        sm: "6px",
        md: "10px",
        lg: "14px",
        xl: "18px",
      },
      boxShadow: {
        soft: "0 1px 2px rgba(0,0,0,0.4)",
        elevated: "0 8px 24px rgba(0,0,0,0.32)",
        glow: "0 0 0 1px rgba(34, 211, 238, 0.35), 0 8px 24px rgba(34, 211, 238, 0.12)",
      },
      animation: {
        "spin-slow": "spin 6s linear infinite",
        pulseSoft: "pulseSoft 2.4s ease-in-out infinite",
      },
      keyframes: {
        pulseSoft: {
          "0%, 100%": { opacity: "0.8" },
          "50%": { opacity: "0.35" },
        },
      },
    },
  },
  plugins: [],
};

export default config;
