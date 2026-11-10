import type { NextConfig } from "next";

// بناء الموبايل: تصدير ثابت كامل بلا خادم — البيانات محلية داخل الجهاز
// MOBILE_EXPORT=1 ./node_modules/.bin/next build
const isMobileExport = process.env.MOBILE_EXPORT === "1";

const nextConfig: NextConfig = isMobileExport
  ? {
      output: "export",
      images: { unoptimized: true },
      typescript: { ignoreBuildErrors: true },
      reactStrictMode: false,
    }
  : {
      output: "standalone",
      typescript: {
        ignoreBuildErrors: true,
      },
      reactStrictMode: false,
    };

export default nextConfig;
