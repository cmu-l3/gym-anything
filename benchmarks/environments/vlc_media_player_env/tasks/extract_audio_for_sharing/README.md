# Extract Audio for Sharing Task

**Difficulty**: 🟡 Medium  
**Skills**: Audio extraction, format conversion, file management  
**Duration**: 120 seconds  
**Steps**: ~40

## Objective

Extract audio from a video recording and save it as a compressed MP3 file that's easy to share, suitable for situations where only the audio content matters (e.g., lectures, podcasts, interviews).

## Scenario

A university student recorded a 90-minute guest lecture with their phone camera. The video file is large (1.2GB) and most classmates only need to listen to the content. The student needs to extract just the audio track and save it as a compressed MP3 file that's:
- Small enough for easy sharing via email/messaging
- Playable on any device
- Suitable for listening during commute

## Task Description

The agent must:
1. Open VLC's conversion dialog
2. Load the lecture recording video file
3. Use VLC's conversion feature to extract ONLY the audio (not convert the entire video)
4. Save as MP3 format with reasonable quality (128-192 kbps)
5. Output file to `/home/ga/Music/lecture_audio.mp3`

## Expected Results

- Output file: `/home/ga/Music/lecture_audio.mp3`
- Audio-only (NO video stream)
- MP3 codec
- Duration matches source video (±3 seconds tolerance)
- Bitrate: 96-256 kbps (optimal for speech)
- File size: significantly smaller than original (less than 50%)

## Verification Criteria

1. ✅ **File Exists**: Output audio file found
2. ✅ **Audio-Only**: No video stream in output
3. ✅ **MP3 Format**: Codec is MP3
4. ✅ **Duration Match**: Duration approximately matches source
5. ✅ **Appropriate Bitrate**: 96-256 kbps range
6. ✅ **Size Reduction**: File size < 50% of source

**Pass Threshold**: 70%

## Skills Tested

- Media conversion dialog navigation
- Understanding audio extraction vs. video conversion
- Format/codec selection (MP3)
- File path specification
- Understanding of audio quality settings

## Controls

- **Media → Convert/Save** (Ctrl+R): Open conversion dialog
- **Add**: Select source file
- **Profile dropdown**: Choose audio profile (e.g., "Audio - MP3")
- **Destination**: Set output file path
- **Start**: Begin conversion

## Common Pitfalls

1. Converting entire video to MP4/AVI instead of extracting audio-only
2. Wrong codec - saving as OGG, FLAC, or WAV instead of MP3
3. Wrong save location - not using `/home/ga/Music/`
4. Bitrate too low - selecting extremely compressed profile
5. Not waiting for conversion to complete
6. Incorrect filename

## Notes

- The source video is a 90-second clip (simulated lecture recording)
- Conversion may take 10-30 seconds depending on system
- MP3 is chosen for maximum compatibility across devices
- Bitrate of 128-192 kbps provides good quality for speech while keeping file size manageable