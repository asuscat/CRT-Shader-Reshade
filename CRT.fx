// ============================================================================
// CRT.fx - Dusha CRT Scanning & Phosphor Decay + Blacklight Strobe +
// Chudnovsky PI calibration + CRT geometry/halation/bezel
// + RF / analogue signal path (ported from crt_overlay.py)
// + BFI Presenter strobe (ported from crt_overlay.py / artzox BFI Presenter)
// + Selectable RNG engines incl. an entropy-pool "best available true RNG"
//
// EVERYTHING IS OPTIONAL. Default state = original Dusha behaviour only.
//   RF / Analogue Signal   : "Enable RF Signal Path"  (default OFF)
//   BFI Strobe             : "Enable BFI"              (default OFF)
//   Dusha decay / PI / etc : unchanged, "Enable Dusha CRT Pass" (default ON)
//
// Licence note: the BFI code is a port of "BFI Presenter shader v1.0.10",
// Copyright (C) 2026 artzox, GPL-3.0-or-later. This file is therefore
// GPL-3.0-or-later as well.
//
// REQUIREMENTS: DX10+/Vulkan/OpenGL (uses uint/bit ops + RGBA32F state
// textures). Not DX9.
//
// NOT PORTED (cannot exist inside a shader): window/overlay handling, screen
// capture, VSync/DwmFlush control, thread/process/GPU priority, Tk menu,
// CPU/GPU/RAM sensor readers. Sensor-driven noise is replaced by the
// "Interference Driver" list below (frame-time load proxy, LFO, mouse, RNG).
// BFI needs the GAME to run at exactly your display refresh rate (VSync on,
// G-SYNC/VRR off). It flickers on purpose: photosensitivity warning.
// ============================================================================

// === PRESETS (original Dusha colour presets) ===
uniform int Preset <
    ui_type = "combo";
    ui_label = "Color Preset";
    ui_items = "Manual\0Vibrant\0Old TV\0";
    ui_tooltip = "Reset to defaults before use.\n\nManual: Use slider settings.\nVibrant: Punchy colors, artistic effect, no black frames (Contrast 2.0, Brightness 40.0, Softclip 0.9, Decay Speed 1.0).\nOld TV: Warm vintage feel, 288 scanlines at 1440p (Contrast 1.5, Brightness 5.0, Softclip 0.85, Saturation 1.1,\nHue 2.0, Phosphor Tint RGB(255, 242, 217), Scanlines 3px with 2px gaps, Scanline Darkness 0.5, Decay Speed 8.0).\n\nNOTE: When a preset is active, sliders used by that preset are ignored.";
> = 0;

uniform bool Dusha_Enable <
    ui_category="CRT Timing";
    ui_label="Enable Dusha CRT Pass";
    ui_tooltip="Turn OFF to use only the RF signal path and/or BFI (the Dusha decay/scanline/strobe stage is skipped).";
> = true;

// === CRT TIMING ===
uniform int FramesPerEffect < 
    ui_category="CRT Timing"; 
    ui_type="slider"; 
    ui_min=1; ui_max=12; ui_step=1; 
    ui_label="Frames per Decay Cycle"; 
    ui_tooltip="Duration of full decay cycle in frames. Decay is an extended and more complex version of a display trick technique called BFI (Black Frame Insertion). \nEach cycle consists of one bright frame followed by progressively darker frames as the phosphor decays. \nExample: At 160hz with 4 frames per cycle - 1 bright frame + 3 decay frames = 40 visible bright frames per second. 2 frames per decay - 1 bright + 1 dark/black is simple BFI (50/50). \nHigher number of dark/black frames in cycle improves motion clarity up to a point, but reduces perceived brightness and may cause flicker at lower framerates. \nThis and the options below control the decay cycle behaviour. Fine-tune to get the right balance of bright/dark/black frames for your specific use case.\n\nNOTE: EVEN number of frames per cycle may cause temporary image retention/burn-in on LCD displays. 1 bright + 1 black (pure BFI) will cause it quicker. ODD numbers and OLED are safe.\nMild protection is enabled by default but can be further tuned in the LCD Burn-in Protection section.";
> = 3;

uniform int DecayMode < 
    ui_category="CRT Timing"; 
    ui_type="combo"; 
    ui_items="Uniform Pulse\0Raster Sweep\0"; 
    ui_label="Decay Mode"; 
    ui_tooltip="Decay simulation type:\n\nUniform Pulse: all pixels decay in sync.\nRaster Sweep: decay phase offset increases from top to bottom.";
> = 0;

uniform float RasterFrequency < 
    ui_category="CRT Timing"; 
    ui_type="slider"; 
    ui_min=0.001; ui_max=1.0; ui_step=0.001; 
    ui_label="Raster Frequency Multiplier"; 
    ui_tooltip="Adjusts the speed/spacing of Raster Sweep mode."; 
> = 0.050;

uniform float DebugSlowFactor < 
    ui_category="CRT Timing"; 
    ui_type="slider"; 
    ui_min=1.0; ui_max=500.0; ui_step=1.0; 
    ui_label="Debug: Slow Motion Factor"; 
    ui_tooltip="Slows down the decay/timing simulation for debugging or demonstration."; 
> = 1.0;

uniform bool DebugFrameStep < 
    ui_label = "Debug: Slow Motion Frame Step";
    ui_category="CRT Timing";  
    ui_tooltip="Locks decay cycle to discrete frame steps instead of continuous interpolation. \nUse with Slow Motion Factor to step through each frame of the decay cycle one at a time for debugging or demonstration purposes. \nCurrent frame number is displayed in the top right corner of the screen."; 
>;

// === CRT DISPLAY ===
uniform float BeamVoltage < 
    ui_category="CRT Display"; 
    ui_type="slider"; 
    ui_min=0.01; ui_max=10.0; ui_step=0.01; 
    ui_label="Contrast";
    ui_tooltip="Controls image contrast via gamma curve.\n\nHigher values can be compensated with Brightness to create more vivid image.\n\nTechnical: Simulates electron beam accelerating voltage affecting the phosphor's power-law response curve."; 
> = 1.0;

uniform float BeamCurrent < 
    ui_category="CRT Display"; 
    ui_type="slider"; 
    ui_min=0.1; ui_max=1000.0; ui_step=1.0; 
    ui_label="Brightness"; 
    ui_tooltip="Controls overall image brightness.\n\nCompensates for the darkening from contrast curve. Adjust together with Contrast for best results, higher Contrast needs higher Brightness.\n\nTechnical: Simulates electron beam current strength (number of electrons striking the phosphor per frame)."; 
> = 1.0;

uniform float MidtoneContrast < 
    ui_category="CRT Display"; 
    ui_type="slider"; 
    ui_min=0.0; ui_max=50.0; ui_step=0.01; 
    ui_label="Midtone Boost"; 
    ui_tooltip="Boosts contrast in midtones without crushing shadows or blowing highlights too much. Can be used to fine-tune authentic CRT punch."; 
> = 0.30;

uniform float ToneMapStrength < 
    ui_category="CRT Display"; 
    ui_type="slider"; 
    ui_min=0.00; ui_max=1.0; ui_step=0.01; 
    ui_label="Softclip Strength"; 
    ui_tooltip = "Phosphor saturation compression strength.\n\n0.0 = Disabled (default) - no highlight rolloff. At default Contrast (1.0) and Brightness (1.0) this produces the most accurate CRT-like output with no extra processing applied to highlights.\n\n0.1 - 0.9 = Partial compression - softens highlights progressively. Useful when boosting Contrast and Brightness above defaults.\n\n1.0 = Full Reinhard softclip - strong highlight rolloff. Physically models phosphor saturation at high beam drive levels. Recommended when using high Contrast/Brightness values to prevent harsh clipping.";
> = 0.0;

// === CRT TUBE & PHOSPHOR EXTRAS ===
uniform float Curvature_Strength <
    ui_category="CRT Tube & Phosphor Extras";
    ui_type="slider";
    ui_min=0.0; ui_max=0.5; ui_step=0.005;
    ui_label="CRT Tube Curvature";
> = 0.0;

uniform float Bezel_Blur_Radius <
    ui_category="CRT Tube & Phosphor Extras";
    ui_type="slider";
    ui_min=1.0; ui_max=64.0; ui_step=0.5;
    ui_label="Bezel Gaussian Blur Radius (px)";
    ui_tooltip="Spread radius of the Gaussian edge-fill blur in the curved bezel border area.";
> = 24.0;

uniform float Bezel_Dimming <
    ui_category="CRT Tube & Phosphor Extras";
    ui_type="slider";
    ui_min=0.0; ui_max=1.0; ui_step=0.01;
    ui_label="Bezel Ambient Dimming";
    ui_tooltip="How much the Gaussian edge-fill blur is dimmed inside the bezel border (0 = full brightness, 1 = dark).";
> = 0.25;

uniform float Vignette_Strength <
    ui_category="CRT Tube & Phosphor Extras";
    ui_type="slider";
    ui_min=0.0; ui_max=1.0; ui_step=0.01;
    ui_label="Corner Vignette Strength";
> = 0.0;

uniform float Raster_Width <
    ui_category="CRT Tube & Phosphor Extras";
    ui_type="slider";
    ui_min=0.0; ui_max=2.0; ui_step=0.01;
    ui_label="Raster Seam Width (0..2, Default 1)";
> = 1.0;

uniform float Beam_Horizontal_Spread <
    ui_category="CRT Tube & Phosphor Extras";
    ui_type="slider";
    ui_min=0.0; ui_max=1.0; ui_step=0.01;
    ui_label="Horizontal Beam Softness";
> = 0.0;

uniform float Beam_Deconvergence <
    ui_category="CRT Tube & Phosphor Extras";
    ui_type="slider";
    ui_min=0.0; ui_max=4.0; ui_step=0.05;
    ui_label="Horizontal RGB Deconvergence (px)";
> = 0.0;

uniform float Halation_Strength <
    ui_category="CRT Tube & Phosphor Extras";
    ui_type="slider";
    ui_min=0.0; ui_max=1.5; ui_step=0.01;
    ui_label="Phosphor Halation / Bloom";
> = 0.0;

uniform float Halation_Radius <
    ui_category="CRT Tube & Phosphor Extras";
    ui_type="slider";
    ui_min=1.0; ui_max=12.0; ui_step=0.25;
    ui_label="Halation Radius (Pixels)";
> = 4.0;

uniform float Halation_Threshold <
    ui_category="CRT Tube & Phosphor Extras";
    ui_type="slider";
    ui_min=0.0; ui_max=1.0; ui_step=0.01;
    ui_label="Halation Luma Threshold";
> = 0.45;

// === COLOR ADJUSTMENT ===
uniform float Saturation < 
    ui_category="CRT Display"; 
    ui_type="slider"; 
    ui_min=0.0; ui_max=2.0; ui_step=0.01; 
    ui_label="Color Saturation"; 
    ui_tooltip="Adjusts color intensity. 0 = grayscale, 1 = normal, >1 = oversaturated.\n\nTypical CRT TV 'Color' control."; 
> = 1.0;

uniform float3 TintColor <
    ui_category = "CRT Display";
    ui_type = "color";
    ui_label = "Phosphor Tint";
    ui_tooltip = "Tints the image with a color cast. Set Color Saturation to 0 first for true monochrome phosphor effect.\n\nWhite: no tint (default)\nGreen: P31 terminal monitor\nAmber: P3 amber monitor\nCool blue-white: cold phosphor";
> = float3(1.0, 1.0, 1.0);

uniform float Hue < 
    ui_category="CRT Display"; 
    ui_type="slider"; 
    ui_min=-180.0; ui_max=180.0; ui_step=0.1; 
    ui_label="Hue Shift"; 
    ui_tooltip="Shifts all colors around the color wheel. ±180° range.\n\nTypical CRT TV 'Hue' control."; 
> = 0.0;

// === PHOSPHOR DECAY ===
uniform float DecaySpeed < 
    ui_category="Phosphor Decay"; 
    ui_type="slider"; 
    ui_min=0.01; ui_max=50.0; ui_step=0.01; 
    ui_label="Global Decay Speed"; 
    ui_tooltip="Overall speed of phosphor decay. Higher = decay cycle fades to black quicker (more dark/black frames). \n\nFaster decay increases motion clarity but creates stroboscopic 'judder' as the eye loses temporal information between frames."; 
> = 10.0;

uniform int DecayLevels < 
    ui_category="Phosphor Decay"; 
    ui_type="slider"; 
    ui_min=1; ui_max=10; ui_step=1; 
    ui_label="Decay Stages"; 
   ui_tooltip="Number of exponential decay stages. More stages = darker later frames and a richer decay curve shape.";
> = 5;

uniform float DecayMultR < 
    ui_category="Phosphor Decay"; 
    ui_type="slider"; 
    ui_min=0.01; ui_max=5.0; ui_step=0.01; 
    ui_label="Red Decay Multiplier"; 
    ui_tooltip="Relative decay speed for red phosphors (vs global). Lower = longer persistence, higher = faster fade. \nHigher values for RGB phosphors only have noticeable effect at low Global Decay Speed settings."; 
> = 0.50;

uniform float DecayMultG < 
    ui_category="Phosphor Decay"; 
    ui_type="slider"; 
    ui_min=0.01; ui_max=5.0; ui_step=0.01; 
    ui_label="Green Decay Multiplier"; 
    ui_tooltip="Relative decay speed for green phosphors (vs global). Green typically decays faster than red."; 
> = 0.60;

uniform float DecayMultB < 
    ui_category="Phosphor Decay"; 
    ui_type="slider"; 
    ui_min=0.01; ui_max=5.0; ui_step=0.01; 
    ui_label="Blue Decay Multiplier"; 
    ui_tooltip="Relative decay speed for blue phosphors (vs global). Blue phosphors usually have the fastest decay."; 
> = 0.70;

// === 3dfx Voodoo2 PIPELINE ===
uniform bool Quantize16Bit < 
    ui_category="3dfx Voodoo2"; 
    ui_label="Enable Voodoo2 Quantize to 16-bit (5:6:5)"; 
    ui_tooltip="Simulates Voodoo2 16-bit framebuffer color precision by quantizing to 5-bit red, 6-bit green, 5-bit blue (RGB565)."; 
> = false;

uniform int DitherSize < 
    ui_category="3dfx Voodoo2"; 
    ui_type="combo"; 
    ui_items="2x2\0""4x4\0""8x8\0"; 
    ui_label="V2 Bayer Dither Size"; 
    ui_tooltip="Matrix size for Bayer ordered dithering:\n\n2x2 = finest pattern, least visible, fewer unique threshold values.\n4x4 = closest to original Voodoo2 dither pattern, default and recommended.\n8x8 = largest pattern, most visible structure, best banding reduction at higher resolutions.\n\nVoodoo2 used a small ordered dither pattern for RGB565, exact implementation was undocumented.\nTry different sizes at your resolution for best results - larger matrices work better at higher resolutions.";
> = 1;

uniform float DitherStrength < 
    ui_category="3dfx Voodoo2"; 
    ui_type="slider"; 
    ui_min=0.0; ui_max=2.0; ui_step=0.01; 
    ui_label="V2 Dither Strength"; 
    ui_tooltip="Strength of the Bayer dithering pattern.\n\n0.0 = no dithering, banding visible.\n1.0 = default, recommended starting point.\nHigher = more aggressive dithering, pattern becomes visible.";> = 1.0;

// === SCANLINES ===
uniform int ScanlineDirection <
    ui_category="Scanlines";
    ui_type="combo";
    ui_items="Horizontal\0Vertical\0Trinitron\0Crosshatch\0";
    ui_label="Scanline Direction";
    ui_tooltip="Direction of scanline pattern:\n\nHorizontal = typical CRT raster lines.\nVertical = can simulate aperture grille.\nTrinitron = horizontal scanlines + vertical RGB color separation.\nCrosshatch = grid pattern (combined H+V).";
> = 0;

uniform float ScanlineThickness < 
    ui_category="Scanlines"; 
    ui_type="slider"; 
    ui_min=1.0; ui_max=8.0; ui_step=1.0; 
    ui_label="Scanline Width (pixels)"; 
    ui_tooltip="Width of the bright scanline in pixels.\n\n1-2px = fine, good for simulating a CRT monitor at higher resolutions.\n3-4px = medium, good for simulating a TV (e.g. 3px bright + 2px gap = 288 lines at 1440p).\n5-8px = thick, good for 4K or oversized TV effect."; 
> = 2.0;

uniform float ScanlineGapSize < 
    ui_category="Scanlines"; 
    ui_type="slider"; 
    ui_min=0.0; ui_max=4.0; ui_step=1.0; 
    ui_label="Scanline Gap Width (pixels)"; 
    ui_tooltip="Width of the dark gap between bright scanlines in pixels.\n\n0 = disabled, no scanline pattern applied.\n1 = subtle gap.\n2 = moderate.\n3-4 = pronounced."; 
> = 0.0;

uniform float ScanlineDarkness < 
    ui_category="Scanlines"; 
    ui_type="slider"; 
    ui_min=0.0; ui_max=1.0; ui_step=0.01; 
    ui_label="Gap Darkness"; 
    ui_tooltip="How dark the gaps between scanlines appear.\n\n0.0 = no darkening (gaps invisible).\n0.3 = subtle gaps.\n0.5 = moderate gaps.\n0.8 = very dark gaps."; 
> = 0.5;

uniform float ApertureGrilleStrength <
    ui_category="Scanlines";
    ui_type="slider";
    ui_min=0.0; ui_max=1.0; ui_step=0.05;
    ui_label="Trinitron Color Separation";
    ui_tooltip="Controls the intensity of vertical RGB color separation in Trinitron mode.\n\n0.0 = no color separation (disabled).\n0.15 = subtle, authentic.\n0.3 = moderate.\n1.0 = maximum separation.\n\nProduces the characteristic Trinitron greenish tint due to the green stripe dominance in the aperture grille.";
> = 0.15;

// === SPLIT SCREEN COMPARISON ===
uniform bool EnableSplitScreen <
    ui_category="Split Screen Comparison";
    ui_label="Enable Split Screen";
    ui_tooltip="Shows shader effect on left half, original image on right half for comparison (all modules: Dusha, RF, BFI).";
> = false;

uniform float SplitPosition <
    ui_category="Split Screen Comparison";
    ui_type="slider";
    ui_min=0.0; ui_max=1.0; ui_step=0.01;
    ui_label="Split Position";
    ui_tooltip="Adjusts the vertical dividing line position.\n\n0.0 = all original.\n0.5 = centered split.\n1.0 = all effect.";
> = 0.5;

uniform bool ShowDividerLine <
    ui_category="Split Screen Comparison";
    ui_label="Show Divider Line";
    ui_tooltip="Draws a visible line at the split position.";
> = true;

// === LCD BURN-IN PROTECTION ===
uniform bool LCDSafeMode <
    ui_category="LCD Burn-in Protection";
    ui_label="Enable LCD Safe Mode";
    ui_tooltip="Prevents burn-in/image retention on LCD displays by periodically breaking same frames/phases pattern.\n\nOnly needed for EVEN Frames per Decay on LCD panels. Causes brief phase flip.\n\nNot needed for: ODD Frames per Decay or OLED displays.";
> = true;

uniform int PhaseFlipMethod <
    ui_category="LCD Burn-in Protection / Phase Flip";
    ui_type="combo";
    ui_items="Phase Jump\0Frame Drop\0";
    ui_label="Phase Flip Method";
    ui_tooltip="Phase Jump: Jumps phase after accumulating enough offset.\nFrame Drop: Skip frame every interval.";
> = 0;

uniform float JumpRate <
    ui_category="LCD Burn-in Protection / Phase Flip";
    ui_type="slider";
    ui_min=0.0001; ui_max=0.1; ui_step=0.0001;
    ui_label="Phase Jump Rate";
    ui_tooltip="Controls the rate at which phase offset accumulates when using the Phase Jump method.\n\n0.0001 = very slow, non-intrusive jumps.\n0.001 = slow, subtle.\n0.01 = fast, noticeable.\n0.1 = very fast.";
> = 0.0001;

uniform int FlipRate <
    ui_category="LCD Burn-in Protection / Phase Flip";
    ui_type="slider";
    ui_min=1000; ui_max=100000; ui_step=1;
    ui_label="Frame Drop Interval";
    ui_tooltip="Defines how often phase flipping occurs when using the Frame Drop methods (measured in frames).\n\n1000 = maximum safety, frequent flips.\n5000 = balanced, less frequent flips.\n10000+ frames = minimal disruption, slower protection.";
> = 1000;

// === CHUDNOVSKY PI CALIBRATION ===
uniform bool Calibrate_Pi_Once <
    ui_category = "Chudnovsky Pi Calibration";
    ui_label = "Calibrate Pi to PC (Press Once)";
    ui_tooltip = "Toggle ON once to run high-accuracy Chudnovsky Pi evaluation and lock in a PC-calibrated Pi value. Toggle OFF and ON again to recalibrate.";
> = false;

uniform bool Reset_Pi_Calibration <
    ui_category = "Chudnovsky Pi Calibration";
    ui_label = "Reset Calibrated Pi";
    ui_tooltip = "Toggle ON once to reset the calibrated Pi value back to the uncalibrated baseline.";
> = false;

// === BLACKLIGHT STROBE (Dusha) ===
uniform bool Blacklight_Strobe_Enable <
    ui_category="Blacklight Strobe";
    ui_label="Enable Blacklight Strobe";
> = false;

uniform int Strobe_Sync_Mode <
    ui_category="Blacklight Strobe";
    ui_type="combo";
    ui_items="Global Refresh\0Scanline / Raster Sync\0";
    ui_label="Strobe Subframe Sync Mode";
    ui_tooltip="Global Refresh: Syncs strobe pulse with the global refresh/decay cycle.\nScanline / Raster Sync: Automatically follows Decay Mode & Raster Frequency across scanlines.";
> = 0;

uniform float Strobe_Rate_Hz <
    ui_category="Blacklight Strobe";
    ui_type="slider";
    ui_min=0.25; ui_max=24.0; ui_step=0.05;
    ui_label="Strobe Rate (Hz)";
> = 6.00;

uniform float Strobe_Duty_Cycle <
    ui_category="Blacklight Strobe";
    ui_type="slider";
    ui_min=0.05; ui_max=0.95; ui_step=0.01;
    ui_label="Strobe Duty Cycle";
> = 0.35;

uniform float Strobe_Edge_Softness <
    ui_category="Blacklight Strobe";
    ui_type="slider";
    ui_min=0.0; ui_max=1.0; ui_step=0.01;
    ui_label="Strobe Pulse Edge Softness";
> = 0.15;

uniform float Strobe_Phase <
    ui_category="Blacklight Strobe";
    ui_type="slider";
    ui_min=0.0; ui_max=1.0; ui_step=0.01;
    ui_label="Strobe Phase Offset";
> = 0.0;

uniform float Strobe_Base_Darken <
    ui_category="Blacklight Strobe";
    ui_type="slider";
    ui_min=0.0; ui_max=1.0; ui_step=0.01;
    ui_label="Off-Pulse Darken";
> = 0.50;

uniform float Blacklight_UV_Strength <
    ui_category="Blacklight Strobe";
    ui_type="slider";
    ui_min=0.0; ui_max=1.5; ui_step=0.01;
    ui_label="Blacklight UV Glow Strength";
> = 0.65;

uniform float Fluorescence_Response <
    ui_category="Blacklight Strobe";
    ui_type="slider";
    ui_min=0.0; ui_max=2.5; ui_step=0.02;
    ui_label="Fluorescent Highlight Pop";
> = 1.20;

uniform float3 Blacklight_UV_Color <
    ui_category="Blacklight Strobe";
    ui_type="color";
    ui_label="Blacklight UV Color";
> = float3(0.42, 0.08, 1.0);

uniform float3 Fluorescence_Tint <
    ui_category="Blacklight Strobe";
    ui_type="color";
    ui_label="Fluorescent Glow Tint";
> = float3(0.70, 0.25, 1.0);

uniform float Strobe_Hue_Sweep_Deg <
    ui_category="Blacklight Strobe";
    ui_type="slider";
    ui_min=-180.0; ui_max=180.0; ui_step=1.0;
    ui_label="Strobe Hue Sweep (Degrees)";
> = 35.0;

// ============================================================================
// === RF / ANALOGUE SIGNAL PATH (ported from crt_overlay.py) ===
// ============================================================================
uniform bool RF_Enable <
    ui_category="RF Signal: Main";
    ui_label="Enable RF Signal Path";
    ui_tooltip="Master switch for the whole analogue signal emulation: gamma-aware convolution resampling, YIQ luma/chroma bandwidth, PAL line averaging, jitter, ghosting, dot crawl, scanlines, phosphor persistence, grille mask, hum bar, snow/streak noise.\nIndependent of BFI and of the Dusha pass.";
> = false;

uniform int RF_Preset <
    ui_category="RF Signal: Main";
    ui_type="combo";
    ui_label="Signal / Shader Preset";
    ui_items="Manual (use sliders)\0PAL-N (Argentinian Famiclone) (Composite)\0PAL-M (Brazilian Famiclone) (Composite)\0PAL-D (Dendy Famiclone) (Composite)\0PAL-B (Composite)\0PAL-B (RF Cables)\0HDMI Mod\0HDMI\0Composite\0RF Cables\0";
    ui_tooltip="Stylised approximations of each signal path (not decoded signals).\nManual = the sliders below are used.\nAny other entry overrides: Lines, Luma bandwidth, Chroma bandwidth, PAL averaging, Scanlines, Phosphor mask, RF noise, Ghosting, Dot crawl, Line jitter, Saturation, Hue.\nBlur scale, persistence, curvature, gamma, kernel, reactivity are never touched by presets.";
> = 0;

uniform int RF_Kernel <
    ui_category="RF Signal: Main";
    ui_type="combo";
    ui_label="Resampling Kernel";
    ui_items="Gaussian\0Lanczos-2\0Lanczos-3\0Triangle (linear)\0Box\0Mitchell-Netravali\0";
    ui_tooltip="Convolution kernel used for the horizontal luma/chroma bandwidth limiting (13 taps at 0.5 sigma spacing).\nGaussian and Lanczos-2 are from the original overlay; the others are extras.";
> = 0;

uniform float RF_Decay <
    ui_category="RF Signal: Main";
    ui_type="slider"; ui_min=0.0; ui_max=0.95; ui_step=0.01;
    ui_label="RF Phosphor Persistence";
    ui_tooltip="Temporal persistence (instant rise, exponential decay), frame-rate independent. Separate from Dusha's Phosphor Decay.";
> = 0.30;

uniform float RF_Blur <
    ui_category="RF Signal: Main";
    ui_type="slider"; ui_min=0.0; ui_max=3.0; ui_step=0.01;
    ui_label="Blur / Bandwidth Scale";
> = 1.0;

uniform float RF_Curvature <
    ui_category="RF Signal: Main";
    ui_type="slider"; ui_min=0.0; ui_max=0.3; ui_step=0.005;
    ui_label="RF Screen Curvature";
    ui_tooltip="Separate from Dusha's 'CRT Tube Curvature' (that one has the Gaussian bezel fill). Use either or both.";
> = 0.0;

uniform float RF_Gamma <
    ui_category="RF Signal: Main";
    ui_type="slider"; ui_min=1.8; ui_max=2.8; ui_step=0.01;
    ui_label="CRT Gamma (decode)";
> = 2.4;

// --- Manual values (used only when preset = Manual) ---
uniform int RF_Lines <
    ui_category="RF Signal: Manual Values";
    ui_type="slider"; ui_min=60; ui_max=1080; ui_step=1;
    ui_label="Scanline Count (lines)";
> = 240;

uniform float RF_Luma <
    ui_category="RF Signal: Manual Values";
    ui_type="slider"; ui_min=0.0; ui_max=3.0; ui_step=0.01;
    ui_label="Luma Bandwidth Sigma (px @1920)";
> = 0.9;

uniform float RF_Chroma <
    ui_category="RF Signal: Manual Values";
    ui_type="slider"; ui_min=0.0; ui_max=8.0; ui_step=0.01;
    ui_label="Chroma Bandwidth Sigma (px @1920)";
> = 3.5;

uniform bool RF_PAL <
    ui_category="RF Signal: Manual Values";
    ui_label="PAL Chroma Line Averaging";
> = false;

uniform float RF_Scan <
    ui_category="RF Signal: Manual Values";
    ui_type="slider"; ui_min=0.0; ui_max=1.0; ui_step=0.01;
    ui_label="RF Scanlines (beam)";
> = 0.5;

uniform float RF_Mask <
    ui_category="RF Signal: Manual Values";
    ui_type="slider"; ui_min=0.0; ui_max=1.0; ui_step=0.01;
    ui_label="Phosphor Mask (aperture grille)";
> = 0.2;

uniform float RF_Noise <
    ui_category="RF Signal: Manual Values";
    ui_type="slider"; ui_min=0.0; ui_max=0.5; ui_step=0.005;
    ui_label="RF Noise (snow + streak + hum)";
> = 0.04;

uniform float RF_Ghost <
    ui_category="RF Signal: Manual Values";
    ui_type="slider"; ui_min=0.0; ui_max=0.5; ui_step=0.005;
    ui_label="Ghosting (RF echo)";
> = 0.0;

uniform float RF_Dot <
    ui_category="RF Signal: Manual Values";
    ui_type="slider"; ui_min=0.0; ui_max=1.0; ui_step=0.01;
    ui_label="Dot Crawl";
> = 0.35;

uniform float RF_Jitter <
    ui_category="RF Signal: Manual Values";
    ui_type="slider"; ui_min=0.0; ui_max=2.0; ui_step=0.01;
    ui_label="Line Jitter";
> = 0.15;

uniform float RF_Sat <
    ui_category="RF Signal: Manual Values";
    ui_type="slider"; ui_min=0.0; ui_max=2.0; ui_step=0.01;
    ui_label="RF Saturation";
> = 1.0;

uniform float RF_Hue <
    ui_category="RF Signal: Manual Values";
    ui_type="slider"; ui_min=-0.5; ui_max=0.5; ui_step=0.005;
    ui_label="RF Hue Rotation (radians, I/Q plane)";
> = 0.0;

// --- Interference driver (replaces CPU/GPU/RAM sensors) ---
uniform int RF_Driver <
    ui_category="RF Signal: Interference Driver";
    ui_type="combo";
    ui_label="Interference Driven By";
    ui_items="Off\0Manual Slider\0Frame-time Load Proxy\0Sine LFO\0Mouse Activity\0RNG Random Walk\0";
    ui_tooltip="Shaders cannot read CPU load/temperature/RAM, so these are the replacements.\nFrame-time Load Proxy: the slower your frames vs the target FPS, the more interference.\nRNG Random Walk: drifts randomly using the selected RNG engine.";
> = 0;

uniform float RF_Reactivity <
    ui_category="RF Signal: Interference Driver";
    ui_type="slider"; ui_min=0.0; ui_max=2.0; ui_step=0.01;
    ui_label="Driver Reactivity";
> = 1.0;

uniform float RF_DriveManual <
    ui_category="RF Signal: Interference Driver";
    ui_type="slider"; ui_min=0.0; ui_max=1.0; ui_step=0.01;
    ui_label="Manual Drive Level";
> = 0.5;

uniform float RF_DriveTargetFPS <
    ui_category="RF Signal: Interference Driver";
    ui_type="slider"; ui_min=15.0; ui_max=360.0; ui_step=1.0;
    ui_label="Load Proxy Target FPS";
    ui_tooltip="Drive = 50% when frame time equals this FPS, 100% at half this FPS.";
> = 60.0;

uniform float RF_DriveLFO_Hz <
    ui_category="RF Signal: Interference Driver";
    ui_type="slider"; ui_min=0.01; ui_max=2.0; ui_step=0.01;
    ui_label="LFO Rate (Hz)";
> = 0.20;

// ============================================================================
// === RNG ENGINE ===
// ============================================================================
uniform int RNG_Mode <
    ui_category="RNG Engine (signal interference)";
    ui_type="combo";
    ui_label="Random Number Engine";
    ui_items="Hoskins hash (original overlay)\0Classic frac-sin hash\0PCG3D hash (frame seeded)\0xxHash32 (frame seeded)\0Entropy-pool PCG3D\0Entropy-pool xxHash32\0";
    ui_tooltip="HLSL has no hardware RNG instruction and no way to read OS/CPU entropy. A GPU shader is a pure function, so true randomness has to come from outside.\n\nEntropy-pool modes: a 1x1 state texture accumulates entropy every frame by hashing together (a) ReShade's CPU-side 'random' source (C rand(), 15 bit, new value per pass), (b) the measured frame time bits, (c) the timer, (d) mouse movement and (e) the previous pool (feedback). Each pixel then runs a strong integer hash (PCG3D / xxHash32) of its coordinates XOR that pool.\nThis is the best available in ReShade: statistically excellent and unpredictable in practice, but NOT cryptographically true randomness.\n\nFrame seeded modes are deterministic functions of pixel + frame number.";
> = 4;

// ============================================================================
// === BFI STROBE (ported) ===
// ============================================================================
uniform bool BFI_Enable <
    ui_category="BFI Strobe";
    ui_label="Enable BFI";
    ui_tooltip="Black Frame Insertion / Variable MPRT / rolling scan. Works on its own (Dusha and RF can be off).\nWARNING: flickers on purpose (photosensitivity risk). Needs the game running at exactly the display refresh with VSync, VRR off.";
> = false;

uniform int BFI_Method <
    ui_category="BFI Strobe";
    ui_type="combo";
    ui_label="Method";
    ui_items="BFI (black frames + highlight roll-off)\0Variable MPRT (brightness budget)\0";
> = 1;

uniform int BFI_Frames <
    ui_category="BFI Strobe";
    ui_type="slider"; ui_min=2; ui_max=8; ui_step=1;
    ui_label="Frames per Cycle";
> = 2;

uniform float BFI_Gain <
    ui_category="BFI Strobe";
    ui_type="slider"; ui_min=0.3; ui_max=1.0; ui_step=0.01;
    ui_label="Gain vs Blur";
> = 1.0;

uniform float BFI_Floor <
    ui_category="BFI Strobe";
    ui_type="slider"; ui_min=0.0; ui_max=0.5; ui_step=0.01;
    ui_label="Dark Frame Floor";
> = 0.0;

uniform bool BFI_Rolloff <
    ui_category="BFI Strobe";
    ui_label="Highlight Roll-off (BFI method)";
> = true;

uniform float BFI_Knee <
    ui_category="BFI Strobe";
    ui_type="slider"; ui_min=0.5; ui_max=0.95; ui_step=0.01;
    ui_label="Roll-off Knee";
> = 0.75;

uniform bool BFI_Sine <
    ui_category="BFI Strobe";
    ui_label="Sine BFI";
> = false;

uniform bool BFI_Invert <
    ui_category="BFI Strobe";
    ui_label="Invert Cycle (frames > 2)";
> = false;

uniform bool BFI_Rolling <
    ui_category="BFI Strobe";
    ui_label="Rolling Scan";
> = false;

uniform float BFI_Seam <
    ui_category="BFI Strobe";
    ui_type="slider"; ui_min=0.0; ui_max=0.3; ui_step=0.005;
    ui_label="Rolling Scan: Seam";
> = 0.0;

uniform float BFI_Decay <
    ui_category="BFI Strobe";
    ui_type="slider"; ui_min=0.0; ui_max=1.0; ui_step=0.01;
    ui_label="Rolling Scan: Phosphor Decay";
> = 0.2;

uniform float BFI_RefreshHz <
    ui_category="BFI Strobe";
    ui_type="slider"; ui_min=60.0; ui_max=360.0; ui_step=0.5;
    ui_label="Display Refresh Rate (Hz)";
    ui_tooltip="ReShade cannot detect the refresh rate. Set it to your display's fixed refresh.";
> = 60.0;

uniform bool BFI_Hitch <
    ui_category="BFI Strobe: Hitch Guard";
    ui_label="Hitch Guard";
    ui_tooltip="Pauses strobing (steady average picture) after missed refreshes.";
> = true;

uniform float BFI_HoldMs <
    ui_category="BFI Strobe: Hitch Guard";
    ui_type="slider"; ui_min=0.0; ui_max=3000.0; ui_step=10.0;
    ui_label="Pause After a Hitch (ms)";
> = 1000.0;

uniform int BFI_Consec <
    ui_category="BFI Strobe: Hitch Guard";
    ui_type="slider"; ui_min=1; ui_max=6; ui_step=1;
    ui_label="Consecutive Misses to Trigger";
> = 2;

uniform float BFI_Tolerance <
    ui_category="BFI Strobe: Hitch Guard";
    ui_type="slider"; ui_min=0.2; ui_max=0.9; ui_step=0.01;
    ui_label="Frame Time Tolerance";
> = 0.75;

uniform bool BFI_LCD <
    ui_category="BFI Strobe: LCD";
    ui_label="LCD: Prevent Image Retention";
    ui_tooltip="Fades to the steady picture, shifts the cycle one frame, fades back (even frame counts only).";
> = false;

uniform int BFI_LCD_Sec <
    ui_category="BFI Strobe: LCD";
    ui_type="slider"; ui_min=1; ui_max=300; ui_step=1;
    ui_label="Seconds of Full Strobe Between Swaps";
> = 5;

uniform bool BFI_Status <
    ui_category="BFI Strobe";
    ui_label="Show Status Square (green/amber/red, bottom-left)";
> = false;

//--------------------------------------------------------------------------------
// Runtime Parameters (provided by ReShade runtime)
#include "ReShade.fxh"

// Integer modulo without the % operator (avoids bitwise/integer-modulo limits on SM3 / DX9)
int imod(int a, int b) { return a - b * (a / b); }

// Renderer compatibility: __RENDERER__ = 0x9000 (DX9), 0xA000/0xB000/0xC000 (DX10/11/12),
// 0x14300+ (OpenGL), 0x20000 (Vulkan). Integer/bit-op RNG needs SM4+, so DX9 gets a
// float-only RNG path (same options, different maths).
#if (__RENDERER__ >= 0xA000)
    #define CRT_SM4 1
#else
    #define CRT_SM4 0
#endif
uniform int   FrameCount   < source="framecount"; >;
uniform float Timer_Ms     < source="timer"; >;
uniform float FrameTime_Ms < source="frametime"; >;
uniform int   RandomCPU    < source="random"; min=0; max=32767; >;   // C rand(): new value every pass
uniform float2 MouseDelta  < source="mousedelta"; >;

//--------------------------------------------------------------------------------
// Compile-time constants 
#define PHI 1.61803398875 // Golden ratio
#define MAX_DECAY_LEVELS 10
#define INV_31 0.032258064516129 // 1/31
#define INV_63 0.015873015873016 // 1/63

//--------------------------------------------------------------------------------
// Textures
//--------------------------------------------------------------------------------
texture2D PiCalibTex { Width = 1; Height = 1; Format = RG32F; };
texture2D PiCalibTexB { Width = 1; Height = 1; Format = RG32F; };
sampler2D PiCalibBSampler { Texture = PiCalibTexB; MagFilter = POINT; MinFilter = POINT; MipFilter = NONE; };
sampler2D PiCalibSampler {
    Texture = PiCalibTex;
    MagFilter = POINT; MinFilter = POINT; MipFilter = NONE;
};

// Signal state, ping-pong (4 x 1 RGBA32F)
//  px0: BFI until, ft EMA, drift, consecutive misses
//  px1: LCD swap sx, sy, sz, sw
//  px2: t0 (ms), init flag, -, -
//  px3: entropy pool (24-bit), interference drive, random walk, -
texture2D SigStateA { Width = 4; Height = 1; Format = RGBA32F; };
texture2D SigStateB { Width = 4; Height = 1; Format = RGBA32F; };
sampler2D SigStateASampler { Texture = SigStateA; MagFilter = POINT; MinFilter = POINT; MipFilter = NONE; };
sampler2D SigStateBSampler { Texture = SigStateB; MagFilter = POINT; MinFilter = POINT; MipFilter = NONE; };

// RF signal path
texture2D RFLinTex  { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
texture2D RFHistTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
texture2D RFEncTex  { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
sampler2D RFLinSampler  { Texture = RFLinTex;  MagFilter = LINEAR; MinFilter = LINEAR; MipFilter = NONE; };
sampler2D RFHistSampler { Texture = RFHistTex; MagFilter = LINEAR; MinFilter = LINEAR; MipFilter = NONE; };
sampler2D RFEncSampler  { Texture = RFEncTex;  MagFilter = LINEAR; MinFilter = LINEAR; MipFilter = NONE; };

//--------------------------------------------------------------------------------
// Chudnovsky Pi (unchanged)
void comp_add(inout float hi, inout float lo, float term) {
    float s = hi + term;
    float v = s - hi;
    lo += (hi - (s - v)) + (term - v);
    hi = s;
}

float compute_chudnovsky_pi(bool high_precision_pass) {
    const float C = 640320.0;
    const float sqrt_C = sqrt(C);
    const float C_3_2 = C * sqrt_C;
    const float C_3 = C * C * C;

    float sum_hi = 0.0;
    float sum_lo = 0.0;

    float t0 = (12.0 * 13591409.0) / C_3_2;
    comp_add(sum_hi, sum_lo, t0);

    float t1 = -(12.0 * 720.0 * (13591409.0 + 545140134.0)) / (6.0 * C_3 * C_3_2);
    comp_add(sum_hi, sum_lo, t1);

    if (high_precision_pass) {
        float t2 = (12.0 * 479001600.0 * (13591409.0 + 2.0 * 545140134.0)) / (720.0 * 8.0 * C_3 * C_3 * C_3_2);
        comp_add(sum_hi, sum_lo, t2);

        float ratio_18_9 = 18.0 * 17.0 * 16.0 * 15.0 * 14.0 * 13.0 * 12.0 * 11.0 * 10.0;
        float t3 = -(12.0 * ratio_18_9 * (13591409.0 + 3.0 * 545140134.0)) / (216.0 * C_3 * C_3 * C_3 * C_3_2);
        comp_add(sum_hi, sum_lo, t3);
    }

    float inv_pi = sum_hi + sum_lo;
    return 1.0 / inv_pi;
}

// ReShade FX has no fmodp(); positive-modulo helper
float fmodp(float x, float y) { return x - y * floor(x / y); }

// State texture reads via tex2Dlod at texel centres (integer texel fetch is not available on DX9)
float4 FetchA(int x) { return tex2Dlod(SigStateASampler, float4((float(x) + 0.5) * 0.25, 0.5, 0.0, 0.0)); }
float4 FetchB(int x) { return tex2Dlod(SigStateBSampler, float4((float(x) + 0.5) * 0.25, 0.5, 0.0, 0.0)); }

float RF_Drive() { return FetchA(3).y; }

//--------------------------------------------------------------------------------
// RNG engines
#if CRT_SM4
static const uint XXP1 = 2654435761u;
static const uint XXP2 = 2246822519u;
static const uint XXP3 = 3266489917u;
static const uint XXP4 = 668265263u;
static const uint XXP5 = 374761393u;

uint pcg_hash(uint v) {
    uint st = v * 747796405u + 2891336453u;
    uint wd = ((st >> ((st >> 28u) + 4u)) ^ st) * 277803737u;
    return (wd >> 22u) ^ wd;
}

uint3 pcg3d(uint3 v) {
    v = v * 1664525u + 1013904223u;
    v.x += v.y * v.z; v.y += v.z * v.x; v.z += v.x * v.y;
    v ^= (v >> 16u);
    v.x += v.y * v.z; v.y += v.z * v.x; v.z += v.x * v.y;
    return v;
}

uint rotl32(uint x, uint r) { return (x << r) | (x >> (32u - r)); }

uint xxhash32_3(uint3 p, uint seed) {
    uint h = seed + XXP5 + 12u;
    h += p.x * XXP3; h = rotl32(h, 17u) * XXP4;
    h += p.y * XXP3; h = rotl32(h, 17u) * XXP4;
    h += p.z * XXP3; h = rotl32(h, 17u) * XXP4;
    h ^= h >> 15u; h *= XXP2;
    h ^= h >> 13u; h *= XXP3;
    h ^= h >> 16u;
    return h;
}

// Entropy pool value (24-bit integer stored in a float) from the state texture
uint RNG_PoolSeed() { return uint(FetchA(3).x); }

// Uniform random in [0,1) from an integer lattice position (x, y, t)
float rnd01(int3 p) {
    uint3 u = uint3(p);
    if (RNG_Mode == 0) {
        float3 f = frac(float3(p) * 0.1031);
        f += dot(f, f.yzx + 33.33);
        return frac((f.x + f.y) * f.z);
    }
    if (RNG_Mode == 1) {
        return frac(sin(dot(float3(p), float3(12.9898, 78.233, 37.719))) * 43758.5453);
    }
    if (RNG_Mode == 2) {
        return float(pcg3d(u).x >> 8u) * (1.0 / 16777216.0);
    }
    if (RNG_Mode == 3) {
        return float(xxhash32_3(u, 0u) >> 8u) * (1.0 / 16777216.0);
    }
    uint s = RNG_PoolSeed();
    if (RNG_Mode == 4) {
        return float(pcg3d(u ^ uint3(s, s * XXP1, ~s)).x >> 8u) * (1.0 / 16777216.0);
    }
    return float(xxhash32_3(u, s * XXP2 + 0x9E3779B9u) >> 8u) * (1.0 / 16777216.0);
}
#else
// DX9 float-only RNG. Modes 2/3 (PCG/xxHash) fall back to float hashes; entropy-pool
// modes use a float pool in [0,1) fed by CPU rand, frame time, timer and mouse.
float rnd01(int3 p) {
    float3 f = float3(p);
    if (RNG_Mode == 0) {
        float3 g = frac(f * 0.1031);
        g += dot(g, g.yzx + 33.33);
        return frac((g.x + g.y) * g.z);
    }
    float seed = (RNG_Mode >= 4) ? FetchA(3).x * 1000.0 : 0.0;
    float h = dot(f, float3(12.9898, 78.233, 37.719)) + seed;
    if (RNG_Mode == 3 || RNG_Mode == 5) h = dot(f.zxy, float3(39.346, 11.135, 83.155)) + seed * 1.7;
    return frac(sin(h) * 43758.5453);
}
#endif

//--------------------------------------------------------------------------------
// Signal state update (entropy pool, interference drive, BFI hitch guard, LCD swap)
void BFI_Update(inout float4 s0, inout float4 s1, inout float4 s2) {
    float now = Timer_Ms;
    float until = s0.x, ftE = s0.y, drift = s0.z, consec = s0.w;
    float sx = s1.x, sy = s1.y, sz = s1.z, sw = s1.w;
    float t0 = s2.x;

    int n = clamp(BFI_Frames, 2, 8);
    float ft = clamp(FrameTime_Ms, 0.0, 1000.0);
    float P = 1000.0 / max(BFI_RefreshHz, 1.0);

    float d = drift;
    if (abs(d) > 1000.0) d = 0.0;
    d = (d + ft - P) * 0.99;
    bool missed = false;
    float tol = BFI_Tolerance * P;
    if (d > tol) { missed = true; d -= P; }
    if (d < -tol) d = -tol;
    drift = d;

    if (ftE <= 0.0 || ftE > 1000.0) ftE = P;
    ftE += (min(ft, 3.0 * P) - ftE) * 0.02;

    consec = missed ? consec + 1.0 : 0.0;

    bool trigger = false;
    float need = max(float(BFI_Consec), 1.0);
    float since = now - t0;

    if (since < 2000.0) {
        until = max(until, now + BFI_HoldMs);          // startup grace
    } else if (consec >= need) {
        trigger = true;
        consec = 0.0;
    } else if (ft > 4.0 * P) {
        trigger = true;
    }

    bool avgBad = (since > 5000.0) && (abs(ftE - P) > 0.15 * P);
    if (avgBad && !trigger && now >= until) trigger = true;

    if (trigger && now >= until) until = now + max(BFI_HoldMs, 0.0);
    if (until > now + 10000.0) until = now;

    bool paused = BFI_Hitch && (now < until);

    // LCD phase swap
    if (sw > now + 10000.0 || sw <= 0.0) { sx = 0.0; sy = 0.0; sz = 0.0; sw = now; }
    if ((!BFI_LCD) || (imod(n, 2) != 0)) {
        sy = 0.0; sz = 0.0; sw = now;
    } else {
        float stp = min(max(ft, 0.0), 100.0) / 400.0;
        if (sz < 0.5 && !paused && (now - sw) >= float(BFI_LCD_Sec) * 1000.0) sz = 1.0;
        if (sz > 0.5 && sz < 1.5) {
            sy = min(1.0, sy + stp);
            int slot = imod(FrameCount + int(sx), n);
            if (sy >= 1.0 && slot == n - 1) {
                sx = float(imod(int(sx) + n - 1, n));
                sz = 2.0;
            }
        } else if (sz > 1.5) {
            sy = max(0.0, sy - stp);
            if (sy <= 0.0) { sz = 0.0; sw = now; }
        }
    }

    s0 = float4(until, ftE, drift, consec);
    s1 = float4(sx, sy, sz, sw);
}

float4 PS_SigState(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target {
    int px = int(pos.x);
    float4 s0 = FetchA(0);
    float4 s1 = FetchA(1);
    float4 s2 = FetchA(2);
    float4 s3 = FetchA(3);
    float now = Timer_Ms;

    if (s2.y < 0.5) { s2.x = now; s2.y = 1.0; }

    // --- entropy pool ---
#if CRT_SM4
    uint m = uint(s3.x) ^ (uint(RandomCPU) * XXP1);
    m = pcg_hash(m ^ asuint(FrameTime_Ms));
    m = pcg_hash(m + asuint(Timer_Ms));
    m = pcg_hash(m ^ asuint(MouseDelta.x) ^ (asuint(MouseDelta.y) * XXP2));
    m = pcg_hash(m + uint(FrameCount));
    float pool = float(m & 0xFFFFFFu);
    float r01 = float(pcg_hash(m ^ 0xA511E9B3u) >> 8u) * (1.0 / 16777216.0);
#else
    float pool = frac(sin(dot(float4(s3.x, float(RandomCPU), FrameTime_Ms,
                     Timer_Ms * 0.001 + MouseDelta.x * 0.37 + MouseDelta.y * 1.13),
                     float4(12.9898, 78.233, 37.719, 4.581))) * 43758.5453);
    float r01 = frac(sin(pool * 91.7 + 3.1) * 43758.5453);
#endif

    // --- random walk + interference drive ---
    float rw = s3.z;
    rw = clamp(rw + (r01 - 0.5) * 0.12, 0.0, 1.0);

    float drive = s3.y;
    float tgt = 0.0;
    if (RF_Driver == 1) tgt = RF_DriveManual;
    else if (RF_Driver == 2) tgt = saturate(FrameTime_Ms / (1000.0 / max(RF_DriveTargetFPS, 1.0)) * 0.5);
    else if (RF_Driver == 3) tgt = 0.5 + 0.5 * sin(Timer_Ms * 0.001 * 6.2831853 * RF_DriveLFO_Hz);
    else if (RF_Driver == 4) tgt = saturate(length(MouseDelta) * 0.02);
    else if (RF_Driver == 5) tgt = rw;
    float dk = 1.0 - pow(0.92, max(FrameTime_Ms, 0.1) * 0.06);   // frame-rate independent 0.08/frame @60
    drive += (tgt - drive) * dk;
    float4 o3 = float4(pool, drive, rw, 0.0);

    // --- BFI state ---
    if (BFI_Enable) {
        BFI_Update(s0, s1, s2);
    } else {
        s0 = float4(0.0, 0.0, 0.0, 0.0);
        s1 = float4(0.0, 0.0, 0.0, now);
        s2.x = now;
    }

    if (px == 0) return s0;
    if (px == 1) return s1;
    if (px == 2) return s2;
    return o3;
}

float4 PS_SigStateCopy(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target {
    return FetchB(int(pos.x));
}

//--------------------------------------------------------------------------------
float4 PS_UpdatePiCalibration(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target {
    float2 prev = tex2Dlod(PiCalibSampler, float4(0.5, 0.5, 0.0, 0.0)).xy;
    float base_pi = compute_chudnovsky_pi(false);

    float latched_pi = prev.x;
    float is_calibrated = prev.y;

    if (Reset_Pi_Calibration) {
        latched_pi = base_pi;
        is_calibrated = 0.0;
    } else if (Calibrate_Pi_Once && is_calibrated < 0.5) {
        float deep_pi = compute_chudnovsky_pi(true);
        // Fresh entropy for the latch jitter (uses the selected RNG engine's pool)
        float hw_micro = rnd01(int3(FrameCount, int(Timer_Ms), RandomCPU)) * 1e-7;
        latched_pi = deep_pi + hw_micro;
        is_calibrated = 1.0;
    }

    return float4(latched_pi, is_calibrated, 0.0, 1.0);
}

float4 PS_PiCalibCopy(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target {
    return tex2Dlod(PiCalibBSampler, float4(0.5, 0.5, 0.0, 0.0));
}

float get_active_pi() {
    float2 state = tex2Dlod(PiCalibSampler, float4(0.5, 0.5, 0.0, 0.0)).xy;
    if (state.y > 0.5 && state.x > 3.0 && state.x < 3.2) {
        return state.x;
    }
    return compute_chudnovsky_pi(false);
}

//--------------------------------------------------------------------------------
// Bayer Dither Matrices (2x2, 4x4, 8x8)
static const int bayer2[4] = {0, 2, 3, 1};
static const int bayer4[16] = {
     0,  8,  2, 10,
    12,  4, 14,  6,
     3, 11,  1,  9,
    15,  7, 13,  5
};
static const int bayer8[64] = {
     0, 32,  8, 40,  2, 34, 10, 42,
    48, 16, 56, 24, 50, 18, 58, 26,
    12, 44,  4, 36, 14, 46,  6, 38,
    60, 28, 52, 20, 62, 30, 54, 22,
     3, 35, 11, 43,  1, 33,  9, 41,
    51, 19, 59, 27, 49, 17, 57, 25,
    15, 47,  7, 39, 13, 45,  5, 37,
    63, 31, 55, 23, 61, 29, 53, 21
};

//--------------------------------------------------------------------------------
// Digit overlay for debug frame counter
static const int digitRows[50] = {
    0xE, 0xA, 0xA, 0xA, 0xE, // 0
    0x4, 0xC, 0x4, 0x4, 0xE, // 1
    0xE, 0x2, 0xE, 0x8, 0xE, // 2
    0xE, 0x2, 0x6, 0x2, 0xE, // 3
    0xA, 0xA, 0xE, 0x2, 0x2, // 4
    0xE, 0x8, 0xE, 0x2, 0xE, // 5
    0xE, 0x8, 0xE, 0xA, 0xE, // 6
    0xE, 0x2, 0x4, 0x4, 0x4, // 7
    0xE, 0xA, 0xE, 0xA, 0xE, // 8
    0xE, 0xA, 0xE, 0x2, 0xE, // 9
};

int DigitPixel(int d, int col, int row) {
    int val = digitRows[d * 5 + row];
    int shift = 3 - col;
    int divided = val;
    for (int i = 0; i < shift; i++)
        divided /= 2;
    return imod(divided, 2);
}

float DrawDigit(int d, int2 pixel, int2 origin, int scale) {
    int2 local = pixel - origin;
    if (local.x < 0 || local.x >= 4 * scale) return 0.0;
    if (local.y < 0 || local.y >= 5 * scale) return 0.0;
    return DigitPixel(d, local.x / scale, local.y / scale) ? 1.0 : 0.0;
}

//--------------------------------------------------------------------------------
// Frame Sampling & CRT Geometry Helpers
// Dusha reads the RF stage output when RF is enabled, else the raw backbuffer.
float3 GetFrame(float2 uv) {
    if (RF_Enable)
        return tex2Dlod(RFEncSampler, float4(uv, 0, 0)).rgb;
    return tex2Dlod(ReShade::BackBuffer, float4(uv, 0, 0)).rgb;
}

float3 GetOriginal(float2 uv) {
    return tex2Dlod(ReShade::BackBuffer, float4(uv, 0, 0)).rgb;
}

float2 warp_tube_uv(float2 uv, float curve_amt) {
    if (curve_amt <= 0.0001) return uv;
    float2 centered = uv * 2.0 - 1.0;
    float r2 = dot(centered, centered);
    float2 curved = centered * (1.0 + curve_amt * r2 + curve_amt * 0.35 * r2 * r2);
    return curved * 0.5 + 0.5;
}

// Gaussian content-aware-style edge fill for curved bezel border regions
float3 sample_bezel_gaussian_fill(float2 warped_uv, float radius_px, float dimming) {
    float2 edge_uv = clamp(warped_uv, float2(0.001, 0.001), float2(0.999, 0.999));
    float2 px = float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT) * max(radius_px, 1.0);

    static const float2 offsets[9] = {
        float2(-1.0, -1.0), float2(0.0, -1.0), float2(1.0, -1.0),
        float2(-1.0,  0.0), float2(0.0,  0.0), float2(1.0,  0.0),
        float2(-1.0,  1.0), float2(0.0,  1.0), float2(1.0,  1.0)
    };
    static const float weights[9] = {
        0.0625, 0.1250, 0.0625,
        0.1250, 0.2500, 0.1250,
        0.0625, 0.1250, 0.0625
    };

    float3 accum = 0.0;
    [unroll]
    for (int i = 0; i < 9; ++i) {
        float2 tap_uv = clamp(edge_uv + offsets[i] * px, float2(0.0005, 0.0005), float2(0.9995, 0.9995));
        accum += GetFrame(tap_uv) * weights[i];
    }

    return accum * saturate(1.0 - dimming);
}

float3 sample_crt_beam(float2 uv, float spread_amt, float deconv_px) {
    float2 px = float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT);
    float shift_x = px.x * deconv_px;

    float3 r_tap = GetFrame(uv + float2( shift_x, 0.0));
    float3 g_tap = GetFrame(uv);
    float3 b_tap = GetFrame(uv - float2( shift_x, 0.0));
    float3 conv = float3(r_tap.r, g_tap.g, b_tap.b);

    if (spread_amt <= 0.0001) return conv;

    float blur_w = px.x * (0.5 + spread_amt * 3.5);
    float3 l_tap = GetFrame(uv - float2(blur_w, 0.0));
    float3 r2_tap = GetFrame(uv + float2(blur_w, 0.0));
    float3 h_soft = 0.25 * l_tap + 0.50 * conv + 0.25 * r2_tap;

    return lerp(conv, h_soft, saturate(spread_amt));
}

float compute_raster_width_factor(float u_coord, float raster_w) {
    float w = clamp(raster_w, 0.0, 2.0);
    if (abs(w - 1.0) <= 0.0001) return 1.0;

    float span = (w <= 1.0) ? w : lerp(1.0, 1.25, w - 1.0);
    if (span <= 0.00001) return 0.0;

    float half_span = span * 0.5;
    float dist_from_center = abs(u_coord - 0.5);
    float feather = max(BUFFER_RCP_WIDTH * 1.5, 0.002);

    return 1.0 - smoothstep(max(half_span - feather, 0.0), half_span + feather, dist_from_center);
}

//--------------------------------------------------------------------------------
// Fetch Bayer Dither Value (normalized to 0..1 range)
float GetBayerDither(int2 pixel, int size) {
    if (size == 0) return bayer2[imod(pixel.y, 2) * 2 + imod(pixel.x, 2)] * 0.333333333;
    if (size == 1) return bayer4[imod(pixel.y, 4) * 4 + imod(pixel.x, 4)] * 0.066666667;
    return bayer8[imod(pixel.y, 8) * 8 + imod(pixel.x, 8)] * 0.015873016;
}

//--------------------------------------------------------------------------------
// Blacklight Strobe Helpers
float3 strobe_rgb_to_hsv(float3 c) {
    float4 K = float4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    float4 p = lerp(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
    float4 q = lerp(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1e-10;
    return float3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

float3 strobe_hsv_to_rgb(float3 c) {
    float4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    float3 p = abs(frac(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * lerp(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

float compute_strobe_pulse(float phase_01, float duty, float softness) {
    float edge = clamp(softness * 0.5, 0.001, 0.45);
    float rise = smoothstep(0.0, edge, phase_01);
    float fall = 1.0 - smoothstep(max(duty - edge, 0.0), min(duty + edge, 1.0), phase_01);
    return saturate(rise * fall);
}

//--------------------------------------------------------------------------------
// RF signal path
struct RFP { float lines, luma, chroma, pal, scan, maskAmt, noiseAmt, ghost, dotAmt, jitter, sat, hue; };

//                                       Man  PAL-N PAL-M PAL-D PAL-B PALB-RF HDMI-M HDMI Comp  RF
static const float rfLines [10] = { 240, 288, 240, 288, 288, 288, 240, 240, 240, 240 };
static const float rfLuma  [10] = { 0.0, 1.1, 0.95, 1.0, 1.0, 1.6, 0.35, 0.0, 0.9, 1.5 };
static const float rfChroma[10] = { 0.0, 4.2, 3.6, 3.6, 3.8, 4.8, 0.35, 0.0, 3.5, 4.5 };
static const float rfPal   [10] = { 0, 1, 1, 1, 1, 1, 0, 0, 0, 0 };
static const float rfScan  [10] = { 0.0, 0.5, 0.5, 0.5, 0.5, 0.5, 0.45, 0.15, 0.5, 0.5 };
static const float rfMask  [10] = { 0.0, 0.2, 0.2, 0.2, 0.2, 0.2, 0.25, 0.10, 0.2, 0.2 };
static const float rfNoise [10] = { 0.0, 0.05, 0.05, 0.05, 0.04, 0.14, 0.0, 0.0, 0.04, 0.14 };
static const float rfGhost [10] = { 0.0, 0.0, 0.0, 0.0, 0.0, 0.12, 0.0, 0.0, 0.0, 0.12 };
static const float rfDot   [10] = { 0.0, 0.10, 0.10, 0.12, 0.08, 0.10, 0.0, 0.0, 0.35, 0.45 };
static const float rfJitter[10] = { 0.0, 0.2, 0.2, 0.25, 0.15, 0.6, 0.0, 0.0, 0.15, 0.6 };
static const float rfSat   [10] = { 1.0, 0.95, 1.05, 1.1, 1.0, 0.95, 1.0, 1.0, 1.0, 0.95 };
static const float rfHue   [10] = { 0.0, -0.05, 0.05, 0.12, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 };

RFP ResolveRF() {
    RFP p;
    int i = clamp(RF_Preset, 0, 9);
    if (i == 0) {
        p.lines = float(RF_Lines); p.luma = RF_Luma; p.chroma = RF_Chroma; p.pal = RF_PAL ? 1.0 : 0.0;
        p.scan = RF_Scan; p.maskAmt = RF_Mask; p.noiseAmt = RF_Noise; p.ghost = RF_Ghost; p.dotAmt = RF_Dot;
        p.jitter = RF_Jitter; p.sat = RF_Sat; p.hue = RF_Hue;
    } else {
        p.lines = rfLines[i]; p.luma = rfLuma[i]; p.chroma = rfChroma[i]; p.pal = rfPal[i];
        p.scan = rfScan[i]; p.maskAmt = rfMask[i]; p.noiseAmt = rfNoise[i]; p.ghost = rfGhost[i]; p.dotAmt = rfDot[i];
        p.jitter = rfJitter[i]; p.sat = rfSat[i]; p.hue = rfHue[i];
    }
    return p;
}

float RF_KW(float u) {
    float a = abs(u);
    if (RF_Kernel == 0) return exp(-0.5 * u * u);
    if (RF_Kernel == 1) {                       // Lanczos-2 (support +/-3 in u)
        float x = a / 1.5;
        if (x >= 2.0) return 0.0;
        if (x < 1e-4) return 1.0;
        float pa = 3.14159265 * x;
        return (sin(pa) / pa) * (sin(pa * 0.5) / (pa * 0.5));
    }
    if (RF_Kernel == 2) {                       // Lanczos-3 (support +/-3)
        if (a >= 3.0) return 0.0;
        if (a < 1e-4) return 1.0;
        float pa = 3.14159265 * a;
        return (sin(pa) / pa) * (sin(pa / 3.0) / (pa / 3.0));
    }
    if (RF_Kernel == 3) return max(0.0, 1.0 - a / 3.0);     // Triangle
    if (RF_Kernel == 4) return (a <= 1.5) ? 1.0 : 0.0;      // Box
    // Mitchell-Netravali B = C = 1/3, support +/-3
    float x = a / 1.5;
    const float B = 1.0 / 3.0;
    const float Cc = 1.0 / 3.0;
    if (x < 1.0)
        return ((12.0 - 9.0 * B - 6.0 * Cc) * x * x * x + (-18.0 + 12.0 * B + 6.0 * Cc) * x * x + (6.0 - 2.0 * B)) / 6.0;
    if (x < 2.0)
        return ((-B - 6.0 * Cc) * x * x * x + (6.0 * B + 30.0 * Cc) * x * x + (-12.0 * B - 48.0 * Cc) * x + (8.0 * B + 24.0 * Cc)) / 6.0;
    return 0.0;
}

float3 RF_LinAt(float2 uv) {
    return pow(max(tex2Dlod(ReShade::BackBuffer, float4(uv, 0, 0)).rgb, 0.0), RF_Gamma);
}

float3 RF_RGBtoYIQ(float3 c) {
    return float3(dot(c, float3(0.299, 0.587, 0.114)),
                  dot(c, float3(0.596, -0.274, -0.322)),
                  dot(c, float3(0.211, -0.523, 0.312)));
}

float3 RF_YIQtoRGB(float3 q) {
    return float3(q.x + 0.956 * q.y + 0.621 * q.z,
                  q.x - 0.272 * q.y - 0.647 * q.z,
                  q.x - 1.106 * q.y + 1.703 * q.z);
}

float RF_LumaAt(float2 uv, float sigma) {
    if (sigma < 0.25) return dot(RF_LinAt(uv), float3(0.299, 0.587, 0.114));
    float acc = 0.0, ws = 0.0;
    [loop]
    for (int i = -6; i <= 6; i++) {
        float u = float(i) * 0.5;
        float w = RF_KW(u);
        acc += w * dot(RF_LinAt(uv + float2(u * sigma / BUFFER_WIDTH, 0.0)), float3(0.299, 0.587, 0.114));
        ws += w;
    }
    return acc / ws;
}

float2 RF_ChromaAt(float2 uv, float sigma) {
    if (sigma < 0.25) return RF_RGBtoYIQ(RF_LinAt(uv)).yz;
    float2 acc = float2(0.0, 0.0);
    float ws = 0.0;
    [loop]
    for (int i = -6; i <= 6; i++) {
        float u = float(i) * 0.5;
        float w = RF_KW(u);
        acc += w * RF_RGBtoYIQ(RF_LinAt(uv + float2(u * sigma / BUFFER_WIDTH, 0.0))).yz;
        ws += w;
    }
    return acc / ws;
}

float4 PS_RFProcess(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target {
    if (!RF_Enable) return float4(0.0, 0.0, 0.0, 1.0);

    RFP p = ResolveRF();
    float drive = RF_Drive();
    float jitterEff = p.jitter * (1.0 + RF_Reactivity * drive * 1.5);
    float ghostEff  = p.ghost  * (1.0 + RF_Reactivity * drive);
    float scale = BUFFER_WIDTH / 1920.0;
    float lumaSig = p.luma * RF_Blur * scale;
    float chromaSig = p.chroma * RF_Blur * scale;

    // curvature
    float2 cc = uv * 2.0 - 1.0;
    cc += cc * (cc.yx * cc.yx) * RF_Curvature;
    float2 suv = cc * 0.5 + 0.5;
    float inside = step(0.0, suv.x) * step(suv.x, 1.0) * step(0.0, suv.y) * step(suv.y, 1.0);

    // per-line horizontal jitter + slow wobble
    float tsec = fmodp(Timer_Ms * 0.001, 1000.0);
    float ln = floor(uv.y * p.lines);
    float lj = rnd01(int3(int(ln), int(floor(tsec * 30.0)), 1)) - 0.5;
    float wob = sin(uv.y * 7.0 + tsec * 1.7);
    suv.x += jitterEff * (lj * 3.0 + wob * 1.5) / 1920.0;

    float lineH = 1.0 / p.lines;
    float Y = RF_LumaAt(suv, lumaSig);
    float2 IQ = RF_ChromaAt(suv, chromaSig);
    if (p.pal > 0.5) {   // PAL delay line
        IQ = 0.5 * IQ + 0.25 * (RF_ChromaAt(suv - float2(0.0, lineH), chromaSig) +
                                 RF_ChromaAt(suv + float2(0.0, lineH), chromaSig));
    }

    // dot crawl: chroma crosstalk into luma, flipping at 30 Hz
    float parity = float(imod(int(tsec * 30.0), 2));
    float checker = fmodp(floor(pos.x / scale * 0.5) + ln + parity, 2.0) * 2.0 - 1.0;
    Y += p.dotAmt * 0.35 * length(IQ) * checker;

    // RF echo (ghost)
    if (ghostEff > 0.0) Y += ghostEff * RF_LumaAt(suv - float2(16.0 / 1920.0, 0.0), lumaSig);

    float ch = cos(p.hue), sh = sin(p.hue);
    IQ = p.sat * float2(IQ.x * ch - IQ.y * sh, IQ.x * sh + IQ.y * ch);
    float3 rgb = max(RF_YIQtoRGB(float3(Y, IQ)), 0.0);

    // scanlines: beam gets fatter when brighter
    float bp = frac(uv.y * p.lines);
    float l = clamp(Y, 0.0, 1.0);
    float w = lerp(0.20, 0.45, sqrt(l));
    float beam = exp(-0.5 * pow((bp - 0.5) / w, 2.0));
    rgb *= lerp(1.0, beam, p.scan) * (1.0 + 0.2 * p.scan);

    // phosphor persistence (instant rise, exponential decay)
    float3 pv = tex2Dlod(RFHistSampler, float4(uv, 0, 0)).rgb;
    float decayK = pow(RF_Decay, max(FrameTime_Ms, 0.1) * 0.06);
    rgb = max(rgb * inside, pv * decayK);

    return float4(rgb, 1.0);
}

float3 RF_Encode(float3 c) {
    c = clamp(c, 0.0, 1.0);
    return lerp(c * 12.92, 1.055 * pow(c, 1.0 / 2.4) - 0.055, step(0.0031308, c));
}

void PS_RFEncode(float4 pos : SV_Position, float2 uv : TEXCOORD, out float4 outEnc : SV_Target0, out float4 outHist : SV_Target1) {
    if (!RF_Enable) { outEnc = float4(0, 0, 0, 1); outHist = float4(0, 0, 0, 1); return; }
    float3 lin = tex2Dlod(RFLinSampler, float4(uv, 0, 0)).rgb;
    outEnc = float4(RF_Encode(lin), 1.0);
    outHist = float4(lin, 1.0);
}

//--------------------------------------------------------------------------------
// Main Pixel Shader (Dusha)
float4 PS_Dusha(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    if (!Dusha_Enable) {
        // Dusha stage skipped: pass through RF output (or untouched image)
        return float4(RF_Enable ? GetFrame(texcoord) : GetOriginal(texcoord), 1.0);
    }

    const float active_pi = get_active_pi();
    const float pi_scale = active_pi / 3.14159265;

    // --- Get preset-overridden values ---
    float beamVoltage = BeamVoltage;
    float beamCurrent = BeamCurrent;
    float midtoneContrast = MidtoneContrast;
    float toneMapStrength = ToneMapStrength;
    float saturation = Saturation;
    float hue = Hue;
    float3 tintColor = TintColor;
    float decaySpeed = DecaySpeed;
    float ditherStrength = DitherStrength;
    bool quantize16Bit = Quantize16Bit;
    float scanlineDarkness = ScanlineDarkness;
    float scanlineThickness = ScanlineThickness;
    float scanlineGapSize = ScanlineGapSize;

    switch (Preset)
    {
        case 1: beamVoltage = 2.0; beamCurrent = 40.0; toneMapStrength = 0.9; decaySpeed = 1.0; break;
        case 2: beamVoltage = 1.5; beamCurrent = 5.0; toneMapStrength = 0.85; saturation = 1.1; hue = 2.0; tintColor = float3(1.0, 0.95, 0.85); decaySpeed = 8.0; scanlineDarkness = 0.5; scanlineThickness = 3.0; scanlineGapSize = 2.0; break;        
        default: break; // Manual: keep uniforms
    }

    // --- LCD Burn-in Protection ---
    int effectiveFrameCount = FrameCount;

    if (LCDSafeMode && (imod(FramesPerEffect, 2) == 0))
    {
        int protectionInterval = FlipRate;

        // Ensure interval doesn't align perfectly with decay cycle
        if (imod(protectionInterval, FramesPerEffect) == 0)
            protectionInterval += 1;

        if (PhaseFlipMethod == 0)
        {
            // Method 1: Phase Jump - discrete jumps
            effectiveFrameCount += int(FrameCount * JumpRate);
        }
        else if (PhaseFlipMethod == 1)
        {
            // Method 2: Frame Drop - skip frames to shift phase
            effectiveFrameCount -= FrameCount / protectionInterval;
        }
    }

    // --- CRT timing simulation ---
    const float rawFraction = frac((effectiveFrameCount * rcp(DebugSlowFactor) * rcp(FramesPerEffect)));
    const float fraction = DebugFrameStep ? floor(rawFraction * FramesPerEffect) * rcp(FramesPerEffect) : rawFraction;

    // --- CRT Tube Curvature & Beam Sampling ---
    float2 crt_uv = warp_tube_uv(texcoord, Curvature_Strength);
    bool in_bezel = (crt_uv.x < 0.0 || crt_uv.x > 1.0 || crt_uv.y < 0.0 || crt_uv.y > 1.0);

    // --- Sample source frame (sRGB encoded, ~2.2 gamma) ---
    float3 frameCurr = in_bezel
        ? sample_bezel_gaussian_fill(crt_uv, Bezel_Blur_Radius, Bezel_Dimming)
        : ((Beam_Horizontal_Spread > 0.0001 || Beam_Deconvergence > 0.0001)
            ? sample_crt_beam(crt_uv, Beam_Horizontal_Spread, Beam_Deconvergence)
            : GetFrame(crt_uv));

    float2 clamped_crt_uv = saturate(crt_uv);

    // --- Optional Phosphor Halation / Bloom ---
    if (Halation_Strength > 0.0001) {
        float2 h_step = float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT) * max(Halation_Radius, 0.5);
        float3 halo_taps = (
            GetFrame(clamp(clamped_crt_uv + float2( h_step.x, 0.0), 0.0, 1.0)) +
            GetFrame(clamp(clamped_crt_uv + float2(-h_step.x, 0.0), 0.0, 1.0)) +
            GetFrame(clamp(clamped_crt_uv + float2(0.0,  h_step.y), 0.0, 1.0)) +
            GetFrame(clamp(clamped_crt_uv + float2(0.0, -h_step.y), 0.0, 1.0)) +
            GetFrame(clamp(clamped_crt_uv + float2( h_step.x,  h_step.y) * 0.7071, 0.0, 1.0)) +
            GetFrame(clamp(clamped_crt_uv + float2(-h_step.x,  h_step.y) * 0.7071, 0.0, 1.0)) +
            GetFrame(clamp(clamped_crt_uv + float2( h_step.x, -h_step.y) * 0.7071, 0.0, 1.0)) +
            GetFrame(clamp(clamped_crt_uv + float2(-h_step.x, -h_step.y) * 0.7071, 0.0, 1.0))
        ) * 0.125;
        float halo_luma = dot(halo_taps, float3(0.2126, 0.7152, 0.0722));
        float halo_gate = smoothstep(Halation_Threshold, max(Halation_Threshold + 0.55, 0.1), halo_luma);
        frameCurr += halo_taps * Halation_Strength * halo_gate;
    }

    // --- Apply CRT power-law curve ---
    frameCurr = pow(max(frameCurr, 0.0), beamVoltage);

    // --- Midtone contrast boost. Parabola peaks at 0.5, multiplicative so blacks are unaffected. ---
    float3 midtone = frameCurr * (1.0 - frameCurr) * 4.0;
    frameCurr += frameCurr * midtone * midtoneContrast;
    
    // --- Compute Bayer dither value ---
    int2 pixelCoord = int2(pos.xy);
    float ditherVal = GetBayerDither(pixelCoord, DitherSize);

    // --- Apply optional Voodoo2 16-bit quantization and dithering ---
    float d = (ditherVal - 0.5) * ditherStrength;

    if (quantize16Bit) {
        frameCurr.r = floor(clamp(frameCurr.r * 31.0 + d, 0.0, 31.0)) * INV_31;
        frameCurr.g = floor(clamp(frameCurr.g * 63.0 + d, 0.0, 63.0)) * INV_63;
        frameCurr.b = floor(clamp(frameCurr.b * 31.0 + d, 0.0, 31.0)) * INV_31;
    }

    // --- Apply electron gun current ---
    frameCurr *= beamCurrent;

    // --- Apply timing ---
    float decayPhase;
    if (DecayMode == 0) {
        decayPhase = fraction;
    } else {
        decayPhase = frac((1.0 - clamped_crt_uv.y) * RasterFrequency + fraction);
    }

    // --- Multi-stage Per-Channel Exponential Phosphor Decay ---
    const float3 decayMult = float3(DecayMultR, DecayMultG, DecayMultB);
    const float decayBase = -decayPhase * decaySpeed * pi_scale;
    float scale = 1.0;
    float3 decay = 0.0;
    float sum = 0.0;

    [unroll]
    for (int i = 0; i < MAX_DECAY_LEVELS; ++i) {
        if (i < DecayLevels) {
            decay += scale * exp(decayBase * scale * decayMult);
            sum += scale;
            scale *= PHI;
        }
    }

    decay *= rcp(sum);

    // --- Apply phosphor decay ---
    float3 phosphorEmission = frameCurr * decay;

    // --- Apply static scanlines ---
    if (scanlineDarkness > 0.0) {
        float scanlineMask = 1.0;
        
        if (scanlineGapSize > 0.0) {
            int brightWidth = int(scanlineThickness);
            int gapWidth = int(scanlineGapSize);
            int scanlinePattern = brightWidth + gapWidth;
            
            if (ScanlineDirection == 0) { // Horizontal scanlines
                int pixelInPattern = imod(int(pos.y), scanlinePattern);
                scanlineMask = pixelInPattern < gapWidth ? (1.0 - scanlineDarkness) : 1.0;
                
            } else if (ScanlineDirection == 1) { // Vertical scanlines
                int pixelInPattern = imod(int(pos.x), scanlinePattern);
                scanlineMask = pixelInPattern < gapWidth ? (1.0 - scanlineDarkness) : 1.0;
                
            } else if (ScanlineDirection == 2) { // Trinitron
                int pixelInPatternH = imod(int(pos.y), scanlinePattern);
                float maskH = pixelInPatternH < gapWidth ? (1.0 - scanlineDarkness) : 1.0;
                
                int subPixel = imod(int(pos.x * 3.0), 3);  // 0=R, 1=G, 2=B
                float dimAmount = 1.0 - ApertureGrilleStrength;
                
                float3 apertureMask = float3(
                    subPixel == 0 ? 1.0 : dimAmount,
                    subPixel == 1 ? 1.0 : dimAmount,
                    subPixel == 2 ? 1.0 : dimAmount
                );
                
                phosphorEmission.rgb *= apertureMask * maskH;
                scanlineMask = 1.0;
                
            } else { // Crosshatch
                int pixelInPatternH = imod(int(pos.y), scanlinePattern);
                int pixelInPatternV = imod(int(pos.x), scanlinePattern);
                float maskH = pixelInPatternH < gapWidth ? (1.0 - scanlineDarkness) : 1.0;
                float maskV = pixelInPatternV < gapWidth ? (1.0 - scanlineDarkness) : 1.0;
                scanlineMask = maskH * maskV;
            }
        }
        
        phosphorEmission *= scanlineMask;
    }

    // --- Corner Vignette & Raster Seam Width ---
    if (Vignette_Strength > 0.0001) {
        float2 vig_uv = clamped_crt_uv * 2.0 - 1.0;
        float vig = saturate(1.0 - dot(vig_uv, vig_uv) * Vignette_Strength * 0.45);
        phosphorEmission *= vig;
    }
    phosphorEmission *= compute_raster_width_factor(clamped_crt_uv.x, Raster_Width);

    // --- Softclip ---
    float3 softclip = phosphorEmission / (1.0 + phosphorEmission);
    phosphorEmission = lerp(phosphorEmission, softclip, toneMapStrength);

    // --- Saturation adjustment ---
    if (saturation != 1.0) {
        float luma = dot(phosphorEmission, float3(0.299, 0.587, 0.114));
        phosphorEmission = lerp(float3(luma, luma, luma), phosphorEmission, saturation);
    }

    // --- Hue shift ---
    if (hue != 0.0) {
        float angle = radians(hue);
        float s = sin(angle);
        float c = cos(angle);
        
        float3x3 hueMatrix = float3x3(
            0.299 + 0.701*c + 0.168*s,  0.587 - 0.587*c + 0.330*s,  0.114 - 0.114*c - 0.497*s,
            0.299 - 0.299*c - 0.328*s,  0.587 + 0.413*c + 0.035*s,  0.114 - 0.114*c + 0.292*s,
            0.299 - 0.299*c + 1.250*s,  0.587 - 0.587*c - 1.050*s,  0.114 + 0.886*c - 0.203*s
        );
        
        phosphorEmission = mul(hueMatrix, phosphorEmission);
    }

    // --- Phosphor Tint ---
    if (any(tintColor != float3(1.0, 1.0, 1.0)))
        phosphorEmission *= tintColor;

    // --- Blacklight Strobe (Global Refresh or Scanline / Raster Sync) ---
    if (Blacklight_Strobe_Enable) {
        float t_sec = Timer_Ms * 0.001;
        float sync_offset = 0.0;
        if (Strobe_Sync_Mode == 0) {
            sync_offset = fraction;
        } else {
            sync_offset = (DecayMode == 1)
                ? frac((1.0 - clamped_crt_uv.y) * RasterFrequency + fraction)
                : fraction;
        }

        float strobe_phase = frac(t_sec * max(Strobe_Rate_Hz, 0.01) + Strobe_Phase + sync_offset);
        float pulse = compute_strobe_pulse(strobe_phase, Strobe_Duty_Cycle, Strobe_Edge_Softness);

        float3 hsv = strobe_rgb_to_hsv(max(phosphorEmission, 0.0));
        hsv.x = frac(hsv.x + (Strobe_Hue_Sweep_Deg / 360.0) * pulse);
        float3 stroked_col = strobe_hsv_to_rgb(hsv);

        float luma = dot(saturate(stroked_col), float3(0.2126, 0.7152, 0.0722));
        float fluor = smoothstep(0.20, 0.95, luma) * Fluorescence_Response;
        float3 uv_wash = Blacklight_UV_Color * Blacklight_UV_Strength * (0.25 + 0.75 * luma);
        float3 lit_state = stroked_col * (1.0 + fluor * Fluorescence_Tint * 0.70) + uv_wash;

        float off_mult = saturate(1.0 - Strobe_Base_Darken);
        float3 unlit_state = stroked_col * off_mult + Blacklight_UV_Color * (Blacklight_UV_Strength * 0.10);

        phosphorEmission = lerp(unlit_state, lit_state, pulse);
    }

    // --- Split Screen Comparison Mode ---
    if (EnableSplitScreen) {
        float3 original = GetOriginal(texcoord);
        
        if (texcoord.x > SplitPosition) {
            phosphorEmission = original;
        }
        
        if (ShowDividerLine && abs(texcoord.x - SplitPosition) < 2.0 * BUFFER_RCP_WIDTH) {
            phosphorEmission = float3(1.0, 1.0, 1.0);
        }
    }
    
    // --- Debug Frame Number Overlay ---
    if (DebugFrameStep) {
        int frameNum = int(floor(rawFraction * FramesPerEffect)) + 1;

        int2 pixel = int2(pos.xy);
        int dscale = 4;
        int margin = 8;

        int numDigits = FramesPerEffect >= 10 ? 2 : 1;
        int totalWidth = numDigits * 5 * dscale;

        int2 origin = int2(BUFFER_WIDTH - totalWidth - margin, margin);

        float ink = 0.0;
        if (FramesPerEffect >= 10)
            ink += DrawDigit(frameNum / 10, pixel, origin, dscale);
        ink += DrawDigit(imod(frameNum, 10), pixel, origin + int2((FramesPerEffect >= 10 ? 5 : 0) * dscale, 0), dscale);

        if (ink > 0.0)
            phosphorEmission = float3(1.0, 1.0, 0.0);
    }

    // Return as-is, preserves HDR-like bright highlights.
    return float4(phosphorEmission, 1.0);
}

//--------------------------------------------------------------------------------
// BFI presenter (ported from BFI Presenter shader v1.0.10, (C) 2026 artzox, GPL-3.0-or-later)
float3 BFI_SRGBtoLin(float3 c) {
    c = max(c, 0.0);
    return lerp(c / 12.92, pow((c + 0.055) / 1.055, 2.4), step(0.04045, c));
}

float3 BFI_Encode(float3 c) {
    c = clamp(c, 0.0, 1.0);
    return lerp(c * 12.92, 1.055 * pow(c, 1.0 / 2.4) - 0.055, step(0.0031308, c));
}

float BFI_Target(int j, int n, float litGain, float fl, bool sine, bool inv) {
    if (sine) {
        float ph = (float(j) / float(n)) * 6.28318531;
        if (inv) ph += 3.14159265;
        return lerp(fl, litGain, 0.5 + 0.5 * cos(ph));
    }
    bool isLit = inv ? (j != 0) : (j == 0);
    return isLit ? litGain : fl;
}

float3 BFI_RolloffFn(float3 lc, float g, float P, float k) {
    float m = max(max(lc.r, lc.g), lc.b);
    float3 r = lc * g;
    if (g > 1.0 && m > 1e-6) {
        float u = m / P;
        float v = g * u;
        k = clamp(k, 0.05, 0.99);
        if (u >= 1.0) r = lc;
        else if (v > k) {
            float a = (g - k) / (1.0 - k);
            float t = clamp((v - k) / (g - k), 0.0, 1.0);
            float o = k + (1.0 - k) * (1.0 - pow(1.0 - t, a));
            r = lc * (o / u);
        }
    }
    return r;
}

float BFI_MprtScale(int k, int n, float litGain, float fl, float Sx, bool sine, bool inv) {
    int k0 = 0;
    if (inv) k0 = sine ? (n / 2) : 1;
    int posn = imod(k + n - k0, n);
    float fillv[8];
    float carry = 0.0;
    [unroll]
    for (int j = 0; j < 8; j++) {
        float f = 0.0;
        if (j < n) {
            float want = BFI_Target(imod(k0 + j, n), n, litGain, fl, sine, inv) + carry;
            f = min(want, Sx);
            carry = want - f;
        }
        fillv[j] = f;
    }
    float s = 0.0;
    [unroll]
    for (int j2 = 0; j2 < 8; j2++) {
        float f2 = fillv[j2];
        if (j2 < n) {
            float add = min(carry, Sx - f2);
            carry -= add;
            if (j2 == posn) s = f2 + add;
        }
    }
    return s;
}

float3 BFI_Strobe(float3 lc, int j, int n, float litGain, bool sine, bool inv) {
    if (BFI_Method == 0) {
        float g = BFI_Target(j, n, litGain, BFI_Floor, sine, inv);
        return BFI_Rolloff ? BFI_RolloffFn(lc, g, 1.0, BFI_Knee) : lc * g;
    }
    float m = max(max(lc.r, lc.g), lc.b);
    float Sx = (m > 1e-6) ? max(1.0 / m, 1.0) : 1e6;
    return lc * BFI_MprtScale(j, n, litGain, BFI_Floor, Sx, sine, inv);
}

float BFI_DecayShare(int s, float phi, float T, float n) {
    float a = float(s) - phi;
    a = a - n * floor(a / n);
    float norm = 1.0 - exp(-n / T);
    float b = a + 1.0;
    if (b <= n) return (exp(-a / T) - exp(-b / T)) / norm;
    return (exp(-a / T) - exp(-n / T) + 1.0 - exp(-(b - n) / T)) / norm;
}

float3 BFI_Apply(float3 lc, float vy, int n, int slot, float litGain, bool inv, bool paused, float swapFade, float avgGain) {
    float3 o;
    if (paused) {
        o = lc * avgGain;                                   // hitch guard: steady average picture
#if CRT_SM4
    } else if (BFI_Rolling && BFI_Decay > 0.0) {
        float fn = float(n);
        float phi = vy * fn;
        float T = max(BFI_Decay, 0.02);
        o = float3(0.0, 0.0, 0.0);
        [unroll]
        for (int j = 0; j < 8; j++) {
            if (j < n) {
                int dd = imod(slot + n - j, n);
                float e = BFI_DecayShare(dd, phi, T, fn);
                if (e > 1e-5) o += BFI_Strobe(lc, j, n, litGain, BFI_Sine, inv) * e;
            }
        }
#endif
    } else if (BFI_Rolling) {
        float u = vy * float(n);
        int band = min(int(u), n - 1);
        float f = u - float(band);
        float hw = max(BFI_Seam * float(n) * 0.5, 1e-4);
        o = BFI_Strobe(lc, imod(slot + n - band, n), n, litGain, BFI_Sine, inv);
        float wn = 0.0;
        int nb = band;
        if (f < hw && band > 0)                    { wn = 0.5 * (1.0 - f / hw);         nb = band - 1; }
        else if (1.0 - f < hw && band + 1 < n)     { wn = 0.5 * (1.0 - (1.0 - f) / hw); nb = band + 1; }
        if (wn > 0.0) o = lerp(o, BFI_Strobe(lc, imod(slot + n - nb, n), n, litGain, BFI_Sine, inv), wn);
    } else {
        o = BFI_Strobe(lc, slot, n, litGain, BFI_Sine, inv);
    }
    if (!paused && swapFade > 0.0) o = lerp(o, lc * avgGain, swapFade);   // LCD phase-swap fade
    return o;
}

//--------------------------------------------------------------------------------
// Present pass: RF grille mask / hum / snow + streak noise, then BFI (last, in linear light)
float4 PS_Present(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target {
    float3 e = tex2Dlod(ReShade::BackBuffer, float4(uv, 0, 0)).rgb;
    if (EnableSplitScreen && uv.x > SplitPosition) return float4(e, 1.0);

    if (RF_Enable) {
        RFP p = ResolveRF();
        float drive = RF_Drive();
        float noiseEff = clamp(p.noiseAmt + RF_Reactivity * drive * 0.25, 0.0, 0.6);
        float hum = noiseEff * 0.35;
        float tsec = fmodp(Timer_Ms * 0.001, 1000.0);

        e *= 1.0 + hum * sin(uv.y * 6.2831 * 1.5 - tsec * 1.3);          // rolling hum bar

        if (p.maskAmt > 0.0) {                                               // aperture grille
            int k = int(fmodp(pos.x, 3.0));
            float3 oh = float3(k == 0 ? 1.0 : 0.0, k == 1 ? 1.0 : 0.0, k == 2 ? 1.0 : 0.0);
            e *= ((1.0 - p.maskAmt) + p.maskAmt * 1.5 * oh) / (1.0 - 0.5 * p.maskAmt);
        }

        if (noiseEff > 0.0) {                                             // RF snow + streak
            int t = int(fmodp(floor(Timer_Ms * 0.06), 4096.0));
            float snow = rnd01(int3(int(pos.x), int(pos.y), t)) - 0.5;
            float sxw = max(1.0, BUFFER_WIDTH / 1920.0 * 6.0);
            float streak = rnd01(int3(int(floor(pos.x / sxw)), int(floor(pos.y / (BUFFER_HEIGHT / p.lines))), t + 7919)) - 0.5;
            e += noiseEff * (0.65 * snow + 0.7 * streak);
        }
    }

    if (BFI_Enable) {
        e = clamp(e, 0.0, 1.0);
        float4 s0 = FetchA(0);
        float4 s1 = FetchA(1);
        int n = clamp(BFI_Frames, 2, 8);
        bool inv = BFI_Invert && (n > 2);
        float litGain = inv ? (float(n) * BFI_Gain / float(n - 1)) : (float(n) * BFI_Gain);
        bool paused = BFI_Hitch && (Timer_Ms < s0.x);
        int slot = imod(FrameCount + max(int(s1.x), 0), n);

        float avg = 0.0;
        [unroll]
        for (int j = 0; j < 8; j++)
            if (j < n) avg += BFI_Target(j, n, litGain, BFI_Floor, BFI_Sine, inv);
        avg /= float(n);

        float3 lc = BFI_SRGBtoLin(e);
        lc = BFI_Apply(lc, uv.y, n, slot, litGain, inv, paused, s1.y, avg);
        e = BFI_Encode(lc);

        if (BFI_Status && pos.x < 24.0 && pos.y > BUFFER_HEIGHT - 24.0) {
            float P = 1000.0 / max(BFI_RefreshHz, 1.0);
            if (abs(s0.y - P) > 0.1 * P) e = float3(1.0, 0.1, 0.1);
            else if (paused)             e = float3(1.0, 0.7, 0.0);
            else                         e = float3(0.1, 1.0, 0.2);
        }
    }
    return float4(e, 1.0);
}

//--------------------------------------------------------------------------------
// Technique declaration
technique Dusha {
    pass CalibratePiPass {
        VertexShader = PostProcessVS;
        PixelShader = PS_UpdatePiCalibration;
        RenderTarget = PiCalibTexB;
    }
    pass CopyPiPass {
        VertexShader = PostProcessVS;
        PixelShader = PS_PiCalibCopy;
        RenderTarget = PiCalibTex;
    }
    pass SignalStateUpdate {
        VertexShader = PostProcessVS;
        PixelShader = PS_SigState;
        RenderTarget = SigStateB;
    }
    pass SignalStateCopy {
        VertexShader = PostProcessVS;
        PixelShader = PS_SigStateCopy;
        RenderTarget = SigStateA;
    }
    pass RFProcessPass {
        VertexShader = PostProcessVS;
        PixelShader = PS_RFProcess;
        RenderTarget = RFLinTex;
    }
    pass RFEncodePass {
        VertexShader = PostProcessVS;
        PixelShader = PS_RFEncode;
        RenderTarget0 = RFEncTex;
        RenderTarget1 = RFHistTex;
    }
    pass MainPass {
        VertexShader = PostProcessVS;
        PixelShader = PS_Dusha;
    }
    pass PresentPass {
        VertexShader = PostProcessVS;
        PixelShader = PS_Present;
    }
}
