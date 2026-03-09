# Record Synchronized Commentary Task

**Difficulty**: 🟡 Medium  
**Skills**: Audio recording, Advanced Controls, synchronized playback  
**Duration**: 180 seconds  
**Steps**: ~50

## Objective

Record synchronized audio commentary while playing back a video in VLC, creating a separate time-aligned audio track. This simulates real-world workflows for coaches, teachers, and content creators adding voice-over annotations.

## Task Description

The agent must:
1. VLC launches with a 3-minute test video (game footage simulation)
2. Enable VLC's Advanced Controls to access the record button
3. Start recording before or during playback
4. Record for at least 2 minutes while video plays
5. Stop recording and save the audio file

## Expected Results

- Audio commentary file created in `/home/ga/Videos/` or `/home/ga/Videos/recorded_commentary/`
- Recording duration: 120-210 seconds (matches 2-3 minutes of video)
- File size: Minimum 200KB (indicates actual audio content)
- Valid audio format (MP3, WAV, or OGG)

## Verification Criteria

1. ✅ **Audio File Exists**: Recorded audio file found in output
2. ✅ **Valid Properties**: Audio has valid codec, duration, sample rate
3. ✅ **Sufficient Duration**: Recording is at least 120 seconds
4. ✅ **Sufficient Size**: File size indicates real audio content (>200KB)

**Pass Threshold**: 75% (3/4 criteria)

## Skills Tested

- Advanced Controls menu navigation
- Record button identification and usage
- Understanding of synchronized recording
- Timing coordination (start recording with playback)
- File output verification

## Real-World Use Cases

- Sports coaches annotating game footage
- Teachers creating narrated tutorials  
- Film students recording director commentary
- Researchers documenting video analysis
- Accessibility professionals creating audio descriptions

## Controls

- **Menu**: View → Advanced Controls (shows record button)
- **Record Button**: Red circle icon in control bar (toggle on/off)
- **Keyboard**: Space to play/pause
- **Alternative**: Media → Convert/Save for advanced recording

## Notes

In the test environment, audio recording captures the video's audio track as a simulation of microphone input. In production, this would record from a real microphone while video plays.