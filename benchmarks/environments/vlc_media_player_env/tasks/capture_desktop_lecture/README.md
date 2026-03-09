# Capture Desktop Lecture Task

**Difficulty**: 🟡 Medium  
**Skills**: Capture device configuration, recording controls, output verification  
**Duration**: 120 seconds  
**Steps**: ~15

## Objective

Use VLC's screen capture feature to record desktop activity for personal documentation. This task tests the agent's ability to configure capture devices and manage recording sessions.

## Task Description

The agent must:
1. VLC launches in clean state
2. A target window with visible content is displayed on desktop
3. Navigate to Media → Open Capture Device
4. Select "Desktop" capture mode
5. Set appropriate frame rate (10-15 fps)
6. Start capture playback and enable recording
7. Record for 10-15 seconds
8. Stop recording

## Expected Results

- Video recording file created in VLC's output directory
- Recording duration: 8-15 seconds (minimum 8s)
- Valid video format with desktop capture properties
- Reasonable file size for duration

## Verification Criteria

1. ✅ **Recording Exists**: Video file found in expected locations
2. ✅ **Sufficient Duration**: Recording is at least 8 seconds long
3. ✅ **Valid Format**: Video has proper codec and container
4. ✅ **Reasonable Size**: File size appropriate for screen recording
5. ✅ **Playable**: Video can be opened and analyzed
6. ✅ **Desktop Properties**: Resolution consistent with screen capture

**Pass Threshold**: 75% (4/6 criteria)

## Skills Tested

- Capture device menu navigation
- Desktop/screen capture mode selection
- Frame rate configuration
- Recording button usage
- Understanding of capture workflows
- Output file location awareness

## Controls

- **Menu**: Media → Open Capture Device (Ctrl+C)
- **Capture mode dropdown**: Select "Desktop"
- **Frame rate**: Set to 10-15 fps
- **Play button**: Start capture stream
- **Record button**: Red circle in playback controls
- **Stop button**: End capture

## Real-World Scenario

A graduate student needs to capture a live-streamed lecture that won't be archived. They must quickly set up desktop recording using VLC without missing content.

## Notes

- Desktop capture is resource-intensive
- Frame rate of 10-15 fps is sufficient for presentation/lecture content
- Higher frame rates increase file size unnecessarily
- Recording location varies by VLC version and OS