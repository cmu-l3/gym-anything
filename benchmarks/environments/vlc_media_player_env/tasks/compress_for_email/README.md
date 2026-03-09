# Compress for Email Task

**Difficulty**: 🟡 Medium  
**Skills**: Video compression, format conversion, size optimization, quality-size trade-offs  
**Duration**: 180 seconds  
**Steps**: ~50

## Objective

Compress a large video file (78MB, 2min 15sec, 1080p) to under 25MB while maintaining acceptable viewing quality for email sharing. This tests the agent's ability to balance technical constraints with usability requirements.

## Task Description

The agent must:
1. Identify the source video at `/home/ga/Videos/email_source.mp4` (78MB, 1080p, 2:15 duration)
2. Use VLC's conversion feature to compress the video
3. Apply appropriate settings to achieve <25MB file size
4. Maintain watchable quality (clear video, intelligible audio)
5. Save output to `/home/ga/Videos/compressed/email_compressed.mp4`

## Expected Results

- Compressed video file < 25MB (HARD REQUIREMENT)
- Duration preserved (~2:15 ± 5 seconds)
- Reduced resolution (720p or 480p recommended)
- Efficient codec (H.264 or H.265)
- Audio present and synchronized
- No corruption or playback errors

## Verification Criteria

1. ✅ **Size Under Limit**: File size < 25MB (40 points - REQUIRED)
2. ✅ **File Valid**: Video is playable and not corrupted (15 points)
3. ✅ **Duration Preserved**: Duration within ±5% of original (10 points)
4. ✅ **Audio-Video Sync**: A/V synchronized within 500ms (10 points)
5. ✅ **Efficient Codec**: Uses H.264/H.265 or similar (10 points)
6. ✅ **Quality Retained**: Reasonable video quality maintained (10 points)
7. ✅ **Optimal Size**: File in 18-24MB range for best balance (5 points)

**Pass Threshold**: 75% (requires meeting size limit + quality criteria)

## Skills Tested

- Media conversion workflow (Media → Convert/Save)
- Codec and bitrate selection
- Resolution scaling decisions
- Quality-size trade-off understanding
- Profile configuration
- Multi-parameter optimization
- Output verification

## Real-World Scenario

You recorded a 2-minute video of a school event on your phone (1080p, 78MB). You want to email it to family members who have email attachment limits and slow internet connections. Compress it to under 25MB while keeping it clear enough to see faces and understand audio.

## Controls

- **Menu**: Media → Convert/Save (Ctrl+R)
- **Add**: Select source file
- **Profile**: Choose or customize encoding profile
- **Settings**: Adjust resolution, bitrate, codec
- **Destination**: Set output file path
- **Start**: Begin conversion

## Recommended Settings

For 2:15 video to achieve ~20-23MB:
- **Video Codec**: H.264
- **Resolution**: 854x480 or 1280x720
- **Video Bitrate**: 1200-1400 kbps
- **Audio Codec**: AAC or MP3
- **Audio Bitrate**: 128 kbps
- **Container**: MP4

## Notes

- Conversion may take 1-2 minutes
- Monitor conversion progress
- If first attempt exceeds 25MB, retry with lower settings
- Email attachment limits typically range from 10-25MB