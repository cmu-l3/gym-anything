# Configure ASL Practice Task

**Difficulty**: 🟡 Medium  
**Skills**: Configuration management, accessibility setup, hotkey customization  
**Duration**: 90 seconds  
**Steps**: ~40

## Objective

Configure VLC Media Player to create an optimal American Sign Language (ASL) learning workflow for practicing signs from video tutorials.

## Task Description

The agent must:
1. Set default playback speed to 65% (0.65x) for slow-motion clarity
2. Configure easy-access frame-step hotkeys for examining hand positions
3. Create 5 bookmarks at key vocabulary timestamps
4. Set up A-B loop for the first practice sign
5. Ensure all settings persist in VLC configuration

## Expected Results

- Playback speed configured to 60-70% range
- Frame-step hotkeys configured for accessibility
- Bookmark/playlist created with 5 practice timestamps
- A-B loop markers set (optional)
- Configuration persists in `/home/ga/.config/vlc/vlcrc`

## Verification Criteria

1. ✅ **Playback Speed Configured** (40 points): Speed set to 60-70% range
2. ✅ **Frame-Step Hotkeys** (20 points): Custom hotkeys configured
3. ✅ **Bookmarks Created** (30 points): 5 bookmarks at target timestamps
4. ✅ **A-B Loop Configured** (10 points): Loop markers set

**Pass Threshold**: 70/100 points

## Skills Tested

- VLC preferences navigation
- Hotkey customization
- Bookmark/playlist management
- A-B loop feature understanding
- Configuration persistence

## Real-World Context

Sign language learners need to see precise hand shapes and movements that blur at normal speed. This workflow enables:
- Consistent slow-motion (65%) without choppiness
- Frame-by-frame examination of hand positions
- Quick navigation between practice vocabulary
- Repeated loop practice of single signs

## Controls

- **Preferences**: Tools → Preferences (Ctrl+P)
- **Advanced Settings**: Show settings: "All"
- **Hotkeys**: Tools → Preferences → Hotkeys
- **Bookmarks**: Playback → Custom Bookmarks
- **A-B Loop**: Playback → A→B (set loop points)

## Video Timestamps

Target signs at:
- 2:15 (135s) - "understand"
- 5:47 (347s) - "practice"  
- 9:23 (563s) - "help"
- 15:08 (908s) - "friend"
- 21:34 (1294s) - "meeting"