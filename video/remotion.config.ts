import { Config } from "@remotion/cli/config";

// Output / quality defaults for `remotion render` & `remotion still`.
Config.setVideoImageFormat("png"); // crisp frames for gradients & glass
Config.setStillImageFormat("png");
Config.setCodec("h264");
Config.setPixelFormat("yuv420p"); // broad player compatibility
Config.setCrf(18); // visually lossless-ish
Config.setOverwriteOutput(true);

// 3D CSS transforms render more reliably with the ANGLE renderer.
Config.setChromiumOpenGlRenderer("angle");
