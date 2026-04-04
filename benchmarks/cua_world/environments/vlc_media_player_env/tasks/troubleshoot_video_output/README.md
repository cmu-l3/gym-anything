# Troubleshoot Video Output Task

**Difficulty**: 🟡 Medium  
**Skills**: Configuration, troubleshooting, video output modules  
**Duration**: 90-120 seconds  
**Steps**: ~40

## Objective

Configure VLC to use the OpenGL video output module to fix screen tearing and playback issues caused by incompatible default video output settings.

## Task Description

The agent must:
1. Recognize VLC is configured with automatic video output (simulating problematic state)
2. Navigate to VLC's advanced preferences
3. Locate video output module settings
4. Change output from "Automatic" to "OpenGL video output"
5. Save the configuration

## Expected Results

- VLC configuration file (vlcrc) updated with OpenGL output setting
- Setting persists after VLC restart
- Configuration change eliminates rendering artifacts

## Verification Criteria

1. ✅ **Config Accessible**: VLC config file parsed successfully
2. ✅ **OpenGL Enabled**: Video output set to OpenGL variant (gl, opengl, glx, gles2)
3. ✅ **Setting Changed**: Output changed from automatic/default

**Pass Threshold**: 75%

## Skills Tested

- Navigation to advanced/hidden settings
- Understanding video rendering concepts
- Configuration modification
- Troubleshooting methodology
- Settings persistence verification

## Real-World Context

This task simulates a common issue users face after graphics driver updates or system changes where VLC's automatic video output selection becomes incompatible with the new configuration, causing screen tearing, choppy playback, or other rendering artifacts.

**Common triggers:**
- Linux graphics driver updates (AMD, NVIDIA)
- Switching between integrated and discrete GPUs
- Using VLC in virtual machines
- External display connection
- Wayland vs. X11 migration

## Controls

- **Menu**: Tools → Preferences
- **Show All Settings**: Click "All" radio button at bottom left
- **Video Output**: Navigate to Video → Output modules → Video output module
- **Dropdown**: Select "OpenGL video output" or similar
- **Save**: Click Save button

## Notes

The video output module in VLC's vlcrc file is specified by the `vout` key. Valid OpenGL values include: `gl`, `opengl`, `glx`, `gles2`. The task verifies the configuration file directly rather than visual output quality.