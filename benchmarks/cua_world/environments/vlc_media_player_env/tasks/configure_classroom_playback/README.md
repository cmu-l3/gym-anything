# Configure Classroom Playback Task

**Difficulty**: 🟡 Easy-Medium  
**Skills**: VLC preferences navigation, multi-setting configuration, understanding group viewing requirements  
**Duration**: 180 seconds  
**Steps**: ~50

## Objective

Configure VLC Media Player for optimal classroom/group viewing by adjusting subtitle appearance, audio normalization, hardware acceleration, and audio boost settings to accommodate large-room viewing conditions.

## Task Description

**Scenario**: A teacher needs to show an educational documentary to 30 students in a classroom with a projector, rear-mounted speakers, and an aging computer. Students previously complained about unreadable subtitles, inaudible dialogue, and stuttering playback. Configure VLC to address these issues.

The agent must:
1. Open VLC Preferences (Tools → Preferences or Ctrl+P)
2. Increase subtitle font size for back-row visibility
3. Enable audio normalization/compression for consistent volume
4. Disable hardware acceleration to prevent stuttering on old hardware
5. Apply audio boost for weak classroom speakers
6. Enable bold subtitle rendering for projector contrast

## Expected Results

VLC configuration file (`vlcrc`) contains:
- Subtitle size ≥24pt or relative scaling ≥150%
- Audio normalization/compression enabled
- Hardware acceleration disabled
- Audio gain ≥3dB
- Bold subtitle rendering enabled

## Verification Criteria

1. ✅ **Config Accessible**: VLC config file parsed successfully
2. ✅ **Subtitle Size**: Font size ≥24pt or scaling ≥150%
3. ✅ **Audio Normalization**: Normalization or compression enabled
4. ✅ **Hardware Acceleration**: Disabled or set to none/software
5. ✅ **Audio Boost**: Gain ≥3dB
6. ✅ **Bold Subtitles**: Bold rendering enabled

**Pass Threshold**: 70% (4/6 criteria minimum)

## Skills Tested

- Multi-tab preferences navigation
- Understanding of VLC configuration options
- Context-aware setting adjustment (group vs. individual viewing)
- Accessibility considerations (readability, audio clarity)
- Performance tuning (hardware acceleration trade-offs)

## Controls

- **Ctrl+P**: Open Preferences
- Navigate through: Subtitle/OSD, Audio, Input/Codecs tabs
- Adjust sliders and checkboxes
- Save settings

## Real-World Context

This task simulates a common frustration for educators: software that works fine on their laptop fails in the classroom environment due to different viewing distances, ambient noise, older hardware, and projector limitations. Understanding these constraints is essential for effective technology use in education.