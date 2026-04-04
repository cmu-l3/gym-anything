# Burn Subtitles Permanently Task

**Difficulty**: 🟡 Medium  
**Skills**: Media conversion, subtitle burning, format understanding  
**Duration**: 90-120 seconds  
**Steps**: ~35

## Objective

Convert a video file by permanently burning (hardcoding) subtitle text into the video frames, creating a self-contained video file compatible with any device, even those without subtitle support.

## Task Description

The agent must:
1. Open VLC's conversion dialog (Media → Convert/Save)
2. Add the source video file and subtitle file
3. Enable subtitle overlay/burning option
4. Configure output format (H.264 MP4)
5. Start conversion and wait for completion

## Expected Results

- Converted video created at `/home/ga/Videos/converted/film_with_burned_subs.mp4`
- Subtitles rendered directly into video frames (not as separate track)
- Video maintains original resolution (1280x720) and duration (~30s)
- Audio preserved in output

## Verification Criteria

1. ✅ **Output Exists**: Converted video file found and valid
2. ✅ **Duration Match**: Video duration ~30s (±2s tolerance)
3. ✅ **Resolution Preserved**: Output is 1280x720
4. ✅ **Audio Present**: Audio stream exists in output
5. ✅ **No Subtitle Tracks**: Video has NO separate subtitle streams (burned in)

**Pass Threshold**: 75%

## Skills Tested

- Media conversion workflow
- Subtitle handling (external → burned-in)
- Format/codec selection
- Progress monitoring
- Understanding embedded vs burned subtitles

## Real-World Context

**Scenario**: A family member traveling internationally wants to watch a foreign film on an old Android tablet that doesn't support external subtitle files. They need subtitles permanently embedded in the video so it works on any device.

## Controls

- **Menu**: Media → Convert/Save (Ctrl+R)
- **Checkboxes**: "Show more options" → "Use a subtitle file"
- **Button**: Convert/Save
- **Profile**: Choose H.264 + MP3 (MP4)
- **Critical**: Enable "Overlay subtitles on the video" option

## CLI Alternative
