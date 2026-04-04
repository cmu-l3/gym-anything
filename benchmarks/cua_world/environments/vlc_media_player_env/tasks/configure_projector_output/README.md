# Configure Projector Output Task

**Difficulty**: 🟡 Medium  
**Skills**: VLC preferences, video output configuration, resolution settings  
**Duration**: 180 seconds  
**Steps**: ~40

## Objective

Configure VLC Media Player to output video at a projector's native resolution (1280x800 WXGA) for smooth presentation playback.

## Scenario

You're a teacher preparing for tomorrow's class presentation. When you tested the video on the school projector this afternoon, playback was choppy and blurry. The IT coordinator mentioned the projector's native resolution is 1280x800, but your video is 1920x1080. Your laptop struggles to downscale in real-time.

**Challenge**: Configure VLC to output at the projector's native resolution for smooth, clear playback.

## Task Description

The agent must:
1. Open VLC's preferences/settings
2. Navigate to video output configuration
3. Set output resolution to 1280x800
4. Save configuration so it persists

## Expected Results

- VLC configuration file contains resolution settings
- Width set to 1280 pixels
- Height set to 800 pixels
- Configuration persists across VLC restarts

## Verification Criteria

1. ✅ **Config File Exists**: VLC config accessible
2. ✅ **Width Configured**: Width setting found and correct (1280)
3. ✅ **Height Configured**: Height setting found and correct (800)

**Pass Threshold**: 75%

## Skills Tested

- Advanced preferences navigation
- Video output module configuration
- Understanding resolution settings
- Configuration persistence

## Controls

- **Menu**: Tools → Preferences (Ctrl+P)
- **Advanced mode**: Click "All" at bottom left
- **Navigation**: Video → Output modules
- **Settings**: Configure width/height for video output

## Notes

This task requires understanding VLC's video output architecture. The agent may need to:
- Enable "All" settings mode (not just "Simple")
- Navigate to Video → Output modules
- Set window dimensions or output resolution
- Configuration keys vary by output module (x11, qt, etc.)