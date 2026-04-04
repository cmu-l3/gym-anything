# Salvage Corrupted Video Task

**Difficulty**: 🟡 Medium  
**Skills**: Error handling, video recovery, format conversion  
**Duration**: 180-240 seconds  
**Steps**: ~60

## Objective

Recover playable content from a corrupted video file using VLC Media Player's error-tolerant playback and conversion capabilities.

## Scenario

You have a partially corrupted MP4 file from an interrupted download. Most media players crash or refuse to open it. Your task is to use VLC to salvage as much recoverable content as possible and create a stable output file.

## Task Description

The agent must:
1. Configure VLC for maximum error resilience
2. Open the corrupted video file (`/home/ga/Videos/corrupted/interview_incomplete.mp4`)
3. Use VLC's Convert/Save feature to re-encode recoverable portions
4. Save the recovered output to `/home/ga/Videos/recovered/interview_salvaged.mp4`

## Expected Results

- Recovered video file created at specified location
- Output video is valid and playable (no corruption)
- Uses H.264 codec for wide compatibility
- Contains recovered content (15+ seconds)
- File size reflects removal of corrupted portions

## Verification Criteria

1. ✅ **File Exists**: Recovered video file found
2. ✅ **Valid Video**: Has proper codec and properties
3. ✅ **Playable Content**: Has reasonable duration (15+ seconds)
4. ✅ **Correct Format**: Uses H.264/MP4 format

**Pass Threshold**: 75%

## Skills Tested

- Understanding VLC's error handling capabilities
- Media → Convert/Save menu navigation
- Profile selection for conversion
- File corruption troubleshooting
- Output verification

## Controls

- **Menu**: Media → Convert/Save (Ctrl+R)
- **Profile**: Video - H.264 + AAC (MP4)
- **Destination**: File browser to set output path

## Notes

VLC is known for its ability to play damaged files that crash other players. The conversion process will skip over corrupted sections, creating a stable output file from recoverable portions.