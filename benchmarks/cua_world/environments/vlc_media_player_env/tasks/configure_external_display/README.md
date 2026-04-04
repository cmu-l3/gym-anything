# Configure External Display Task

**Difficulty**: 🟡 Medium  
**Skills**: Display configuration, advanced preferences navigation  
**Duration**: 90 seconds  
**Steps**: ~25

## Objective

Configure VLC Media Player to automatically use an external display (projector/secondary monitor) for fullscreen video playback instead of the primary laptop screen.

## Task Description

The agent must:
1. Launch VLC Media Player
2. Navigate to advanced preferences (Tools → Preferences → Show All)
3. Configure fullscreen display setting to use secondary display
4. Save the configuration
5. Verify the setting persists

## Expected Results

- VLC configuration modified to specify secondary display for fullscreen
- Setting `qt-fullscreen-screennumber=1` present in vlcrc
- Configuration saved and persists across sessions

## Verification Criteria

1. ✅ **Config Accessible**: VLC config file parsed successfully
2. ✅ **Display Setting Found**: Fullscreen display configuration present
3. ✅ **Correct Display Selected**: Setting points to secondary display (index 1)

**Pass Threshold**: 70%

## Skills Tested

- Advanced preferences navigation (Show All settings)
- Understanding of multi-display concepts
- Configuration file persistence
- Nested menu navigation

## Controls

- **Menu**: Tools → Preferences → Show All
- **Navigation**: Video → Fullscreen Settings
- **Setting**: Fullscreen Video Device / Screen Number
- **Keyboard**: Ctrl+P to open preferences

## Real-World Context

This is a common frustration for teachers, presenters, and home theater users who connect laptops to projectors or external displays. By default, VLC may fullscreen on the primary display (laptop), but users want it on the external display (projector/TV) where the audience can see it.

## Notes

The task simulates a dual-display environment. The verification focuses on configuration correctness rather than actual multi-display rendering, as the container environment may not support true multi-display output.