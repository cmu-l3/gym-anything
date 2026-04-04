# Test Capture Devices Task

**Difficulty**: 🟡 Medium  
**Skills**: Capture device configuration, recording controls, quality verification  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Use VLC's capture device functionality to record a brief test video from the system webcam and microphone, then verify the recording was successful. This represents a real-world workflow for remote workers who need to quickly verify their audio/video equipment before important video calls.

## Task Description

The agent must:
1. Open VLC's capture device interface
2. Configure video and audio input devices
3. Start capture preview
4. Record for approximately 5 seconds
5. Stop recording
6. Verify recording file was created

## Expected Results

- Recording file created in `/home/ga/Videos/` directory
- Recording contains both video and audio streams
- Recording duration is approximately 5 seconds (3-10 second range acceptable)
- Recording has reasonable quality (valid codecs, proper resolution)

## Verification Criteria

1. ✅ **Recording File Exists**: Video file found in ~/Videos/ directory
2. ✅ **Video Stream Present**: Valid video stream detected
3. ✅ **Audio Stream Present**: Valid audio stream detected
4. ✅ **Appropriate Duration**: Recording is 3-10 seconds long
5. ✅ **Reasonable Quality**: Valid resolution and file size

**Pass Threshold**: 85% (requires both A/V streams with correct duration)

## Skills Tested

- Menu navigation (Media → Open Capture Device)
- Device selection and configuration
- Recording controls (start/stop)
- File output verification
- Understanding of A/V capture workflow

## Context & Motivation

**Scenario**: You have an important client presentation starting in 10 minutes. Yesterday, a colleague had technical issues with their webcam during a meeting. You want to do a quick sanity check to ensure your camera and microphone are working properly before joining the call.

**User's Goal**: Quickly verify A/V equipment works and produces acceptable quality.

**Time Pressure**: Only a few minutes available before the meeting starts.

## Controls

- **Menu**: Media → Open Capture Device (or Ctrl+C)
- **Record Button**: Red circle icon in VLC control bar
- **Stop Button**: Square icon to end capture
- **Keyboard**: 
  - `Ctrl+C`: Open capture device dialog
  - `Ctrl+R`: Start recording (when capture active)

## Notes

- VLC saves recordings to ~/Videos/ by default with timestamp-based filenames
- Recording includes both video and audio if both devices are selected
- The task uses a test video device (fake camera) for reproducibility
- Target recording duration: ~5 seconds (tolerance: 3-10 seconds)