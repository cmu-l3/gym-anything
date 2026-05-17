/** @type {import('next').NextConfig} */
const backend = process.env.EXPERT_CONSOLE_BACKEND ?? "http://127.0.0.1:8765";

const nextConfig = {
  reactStrictMode: true,
  async rewrites() {
    return [
      { source: "/api/:path*", destination: `${backend}/api/:path*` },
    ];
  },
};

export default nextConfig;
