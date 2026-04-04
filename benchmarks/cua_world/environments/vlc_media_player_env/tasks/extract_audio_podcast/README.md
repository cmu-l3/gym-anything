# Extract Audio from Conference Video Task

**Difficulty**: 🟡 Medium  
**Skills**: Audio extraction, format conversion, transcoding  
**Duration**: 120-180 seconds  
**Steps**: ~40

## Objective

Extract audio from a conference presentation video and save it as an MP3 file for commute listening using VLC's conversion/transcoding feature.

## Task Description

The agent must:
1. VLC launches empty (no file loaded)
2. Navigate to Media → Convert/Save (Ctrl+R)
3. Select source video: `/home/ga/Videos/conferences/Tech_Conference_2024.mp4`
4. Choose audio-only conversion profile (MP3)
5. Save output to: `/home/ga/Music/podcasts/Tech_Conference_2024.mp3`
6. Start and complete the conversion

## Scenario

You've downloaded a 2-hour conference presentation video to watch at home, but your morning commute is the perfect time to listen to it instead. Extract just the audio track and save it as an MP3 file. The audio-only version should be much smaller and easier to manage on mobile devices.

## Expected Results

- MP3 file created at `/home/ga/Music/podcasts/Tech_Conference_2024.mp3`
- Audio-only format (no video stream)
- Duration preserved from source video (~120 seconds)
- Reasonable bitrate (128-192 kbps recommended)
- Significantly smaller file size than source video

## Verification Criteria

1. ✅ **File Exists**: MP3 file created in output directory
2. ✅ **Valid Format**: File is valid MP3 (verified via codec analysis)
3. ✅ **Audio-Only**: No video stream present
4. ✅ **Duration Match**: Duration matches source (±2s tolerance)
5. ✅ **Quality Check**: Bitrate in reasonable range (96-256 kbps)

**Pass Threshold**: 70%

## Skills Tested

- VLC conversion/transcoding feature knowledge
- Media menu navigation (Media → Convert/Save)
- File dialog interaction (source selection)
- Profile selection (audio vs video profiles)
- Output path specification
- Process completion monitoring
- Understanding of media formats

## Controls

- **Menu**: Media → Convert/Save (or Ctrl+R)
- **Workflow**:
  1. Click "Add" to select source file
  2. Click "Convert/Save" button
  3. Select profile: "Audio - MP3" from dropdown
  4. Click "Browse" to set destination
  5. Navigate to output directory
  6. Enter filename
  7. Click "Start" to begin conversion
  8. Wait for completion

## Common Pitfalls

- Selecting video profile instead of audio-only profile
- Forgetting to specify output filename
- Not waiting for conversion to complete
- Using "Save" instead of "Convert/Save"
- Wrong output directory

## Notes

The source video is a 2-minute test version (description mentions 2 hours conceptually). Conversion time is typically 10-30 seconds for this duration. The conversion runs in the background and VLC shows a progress indicator.