// RE:Compile retro look for BinbunVFX (Sir: "lower the resolution of those effects").
// Effect animation is stepped to FX_FPS frames per second, like hand-drawn sprite FX.
// One edit here retimes every Binbun shader (they include this file and use FX_TIME).
#define FX_FPS 12.0
#define FX_TIME (floor(TIME * FX_FPS) / FX_FPS)
