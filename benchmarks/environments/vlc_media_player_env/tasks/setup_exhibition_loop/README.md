# Setup Exhibition Loop Task

**Difficulty**: 🟡 Medium  
**Skills**: Configuration management, display settings, unattended operation  
**Duration**: 90 seconds  
**Steps**: ~35

## Objective

Configure VLC Media Player to display a promotional video in professional exhibition/retail display mode with continuous looping and minimal interface visibility.

## Task Description

The agent must:
1. Launch VLC with a promotional video
2. Configure VLC for continuous looping (loop or repeat mode)
3. Enable fullscreen mode for professional display
4. Hide player controls and interface elements
5. Disable notifications and dialogs
6. Verify settings persist in VLC configuration

## Expected Results

- VLC configured with loop/repeat enabled
- Fullscreen mode enabled by default
- Minimal interface (controls hidden)
- Video title overlay disabled
- Notifications disabled
- Configuration saved to vlcrc

## Verification Criteria

1. ✅ **Loop/Repeat Enabled**: Video will loop continuously (2.0 points)
2. ✅ **Fullscreen Mode**: Runs in fullscreen (1.5 points)
3. ✅ **Minimal Interface**: Controls/menus hidden (1.0 point)
4. ✅ **Video Title Disabled**: Title overlay hidden (0.3 points)
5. ✅ **Notifications Disabled**: No popup notifications (0.2 points)

**Pass Threshold**: 70% (must have loop AND fullscreen)

## Skills Tested

- VLC preferences navigation (Tools → Preferences)
- Understanding loop vs repeat modes
- Interface customization settings
- Configuration persistence
- Professional AV setup knowledge

## Real-World Context

This configuration is used for:
- Retail store promotional displays
- Art gallery information videos
- Museum exhibition loops
- Trade show booth presentations
- Waiting room entertainment
- Corporate lobby displays

The gallery owner needs the display to run unattended all day without showing VLC's interface, which would look unprofessional.

## Controls

- **Menu**: Tools → Preferences (Ctrl+P)
- **Settings Categories**:
  - Interface → Main interfaces → Qt
  - Video → Fullscreen settings
  - Playlist → Playback control