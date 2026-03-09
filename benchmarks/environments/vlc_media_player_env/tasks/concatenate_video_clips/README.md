# Concatenate Video Clips Task

**Difficulty**: 🟡 Medium  
**Skills**: Video concatenation, conversion workflow, format handling  
**Duration**: 180 seconds  
**Steps**: ~50

## Objective

Merge multiple separate video files into a single continuous output file using VLC's conversion functionality.

## Task Description

The agent must:
1. Open VLC's Media → Convert/Save dialog
2. Add 4 video clip files in sequence
3. Configure conversion settings (H.264 codec, MP4 container)
4. Save merged output to `/home/ga/Videos/merged_output.mp4`
5. Wait for conversion to complete

## Real-World Context

**Scenario**: A skateboarding tutorial creator filmed 4 separate takes of the same trick from their afternoon practice session. Each clip is 10 seconds long. They need to merge these into one continuous tutorial video for their YouTube channel, with upload scheduled for tonight. Their editing software crashed and they need a quick solution using VLC.

## Expected Results

- Merged video file created at `/home/ga/Videos/merged_output.mp4`
- Video duration approximately 40 seconds (4 clips × 10 seconds)
- Video maintains quality and resolution (1280×720)
- All clips present in sequence

## Verification Criteria

1. ✅ **Output Exists**: Merged video file found
2. ✅ **Correct Duration**: Video is ~40 seconds (±3s tolerance)
3. ✅ **Valid Properties**: Correct resolution, codec, and file size
4. ✅ **Playable**: Video can be analyzed by ffprobe

**Pass Threshold**: 75%

## Skills Tested

- Media → Convert/Save dialog navigation
- Multiple file selection
- Conversion profile configuration
- Output path specification
- Process monitoring and completion

## Controls

- **Menu**: Media → Convert/Save (Ctrl+R)
- **Add button**: Select source files
- **Convert/Save button**: Start conversion
- **Browse button**: Set output destination

## Notes

- Source clips located in: `/home/ga/Videos/concat_clips/`
- Clips are named: `clip_01.mp4`, `clip_02.mp4`, `clip_03.mp4`, `clip_04.mp4`
- Each clip is 10 seconds, 1280×720, H.264 codec
- Conversion may take 20-60 seconds depending on system
- Alternative: Can use command-line `cvlc` with concatenation demuxer