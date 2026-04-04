# Capture Stream Test Task

**Difficulty**: 🟡 Medium  
**Skills**: Network streaming, recording, verification  
**Duration**: 90 seconds  
**Steps**: ~35

## Objective

Test a network stream by playing it in VLC and recording a short test segment to verify the stream is working properly before committing to a long recording session.

## Scenario

A remote worker needs to record an important webinar but has had issues with recordings appearing successful while containing no audio or corrupted video. They want to do a "test capture" first - verify the stream URL works, record a short 20-second segment, and confirm it has working video and audio.

## Task Description

The agent must:
1. Read the network stream URL from `/home/ga/stream_url.txt`
2. Open VLC Media Player
3. Open the network stream (Media → Open Network Stream)
4. Enable Advanced Controls to access the record button
5. Start recording the stream
6. Record for approximately 20 seconds
7. Stop recording
8. Save output to `/home/ga/Videos/stream_test_capture.mp4`

## Expected Results

- Recording file created at `/home/ga/Videos/stream_test_capture.mp4`
- Recording duration: 15-30 seconds (tolerance for timing)
- Video has valid codec and resolution
- Audio has valid codec
- File size > 200 KB (ensures actual content captured)

## Verification Criteria

1. ✅ **File Exists**: Recording file found
2. ✅ **Duration Valid**: Recording is 15-30 seconds
3. ✅ **Video Track**: Valid video codec detected
4. ✅ **Audio Track**: Valid audio codec detected
5. ✅ **Minimum Quality**: File size > 200 KB

**Pass Threshold**: 75%

## Skills Tested

- Reading file contents
- Network stream menu navigation (Media → Open Network Stream)
- Advanced Controls feature (View → Advanced Controls)
- Recording feature usage
- Timing control (recording for correct duration)
- Output file management

## Controls

- **Ctrl+N**: Open Network Stream dialog
- **View → Advanced Controls**: Show recording button
- **Record button**: Red circle button (appears after enabling Advanced Controls)
- **Space**: Pause/Play
- **Ctrl+Q**: Quit VLC

## Notes

- The stream URL is provided in `/home/ga/stream_url.txt`
- Recording must be stopped manually after ~20 seconds
- VLC may prompt for output location - ensure it's set to `/home/ga/Videos/stream_test_capture.mp4`
- The stream is a local HTTP stream for testing purposes