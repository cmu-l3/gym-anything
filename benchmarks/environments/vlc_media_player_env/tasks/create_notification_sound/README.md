# Create Notification Sound Task

**Difficulty**: 🟡 Medium  
**Skills**: Audio extraction, format conversion, parameter optimization  
**Duration**: 180 seconds  
**Steps**: ~50

## Objective

Extract a specific 4-second audio segment from a video file and convert it to a mobile-optimized MP3 notification sound with strict size and quality constraints.

## Task Description

The agent must:
1. Extract audio from timestamp 00:00:17 for exactly 4 seconds from source video
2. Convert to MP3 format (universally compatible with mobile devices)
3. Optimize for mobile notifications:
   - File size < 500 KB
   - Mono audio (saves space, appropriate for notifications)
   - Sample rate: 44.1kHz or 22.05kHz
   - Bitrate: 64-128 kbps
4. Save to `/home/ga/Music/notifications/custom_notification.mp3`

## Expected Results

- Notification sound file created at specified location
- Duration: 4.0 seconds (±0.5s tolerance)
- Format: MP3 with mobile-friendly parameters
- File size under 500 KB

## Verification Criteria

1. ✅ **File Exists**: Output file created (15 points)
2. ✅ **Duration Correct**: 4.0s ±0.5s tolerance (20 points)
3. ✅ **File Size**: ≤ 500 KB (20 points)
4. ✅ **Format**: MP3 codec (15 points)
5. ✅ **Channels**: Mono preferred, stereo acceptable (10 points)
6. ✅ **Sample Rate**: 44.1kHz or 22.05kHz (10 points)
7. ✅ **Bitrate**: 64-128 kbps optimal (10 points)

**Pass Threshold**: 70%

## Skills Tested

- Media → Convert/Save dialog navigation
- Time range specification (start/stop time)
- Audio codec configuration
- Format profile customization
- Understanding of audio parameters
- Mobile optimization knowledge

## Controls

- **Menu**: Media → Convert/Save (Ctrl+R)
- **Show more options**: Enable to set start/stop times
- **Profile selection**: Choose or customize audio profile
- **Codec configuration**: Set MP3 parameters

## Notes

This task simulates creating a custom phone notification from a video clip. Real-world use case: extracting a guitar riff, movie quote, or sound effect for use as a text message alert.