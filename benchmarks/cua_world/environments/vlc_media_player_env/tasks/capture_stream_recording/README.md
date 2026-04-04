# Capture Stream Recording Task

**Difficulty**: 🟡 Medium  
**Skills**: Network streaming, recording configuration, output management  
**Duration**: 120 seconds  
**Steps**: ~40

## Objective

Configure VLC to record a network stream (HTTP video) to a local file, capturing at least 30 seconds of content with verifiable video and audio.

## Task Description

The agent must:
1. Open a network stream URL in VLC
2. Configure VLC to record/convert the stream (not just play it)
3. Set output destination path
4. Record at least 30 seconds of content
5. Verify the recording is valid and playable

## Expected Results

- Recording file created at `/home/ga/Videos/captures/recorded_stream.mp4`
- File size > 500 KB (indicates actual content captured)
- Valid video and audio codecs present
- Duration of at least 25 seconds (accounting for startup latency)
- File is playable and not corrupted

## Verification Criteria

1. ✅ **File Exists**: Recording file found at expected location
2. ✅ **Adequate Size**: File size > 500 KB
3. ✅ **Valid Codec**: Video codec detected
4. ✅ **Sufficient Duration**: Recording ≥ 25 seconds
5. ✅ **Valid Resolution**: Reasonable video dimensions

**Pass Threshold**: 70%

## Skills Tested

- Network stream URL handling
- Convert/Save dialog navigation
- Output format and destination selection
- Time management (recording for duration)
- File system navigation
- Understanding VLC recording vs playback modes

## Controls

- **Menu**: Media → Open Network Stream (Ctrl+N)
- **Menu**: Media → Convert/Save (Ctrl+R)
- **Recording**: Start/Stop recording appropriately

## Human Context

**Scenario**: A user wants to record a live-streamed conference/webinar that's only available for a limited time. They need to capture the stream for later viewing since they can't watch it all right now.

**Real-world use**: Time-shifted viewing of educational content, lectures, live events that aren't archived.

## Notes

The stream is served locally via HTTP to simulate a live streaming source. In real-world usage, this would be an actual streaming URL (e.g., HLS stream, RTSP, etc.).

VLC's "Convert/Save" feature is used to record streams, not just the play button.