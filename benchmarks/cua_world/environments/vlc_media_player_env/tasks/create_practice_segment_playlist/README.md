# 🕺 Create Practice Segment Playlist Task

**Difficulty**: 🟡 Medium  
**Skills**: Playlist management, time range specification, file operations  
**Duration**: 8-12 minutes  
**Steps**: ~50

## Objective

Create a VLC playlist that combines specific time segments from multiple instructional videos into a seamless practice sequence for teaching purposes.

## Task Description

The agent must:
1. VLC launches with empty playlist
2. Create a playlist with 4 video segments from different source files
3. Each segment must specify start and end times
4. Save playlist to disk with time range information
5. Playlist should loop for continuous practice

## Real-World Context

A dance/fitness instructor has multiple tutorial videos but wants to create a custom practice sequence by extracting and combining specific segments from each video. They need a playlist file that automatically plays only the relevant portions in the correct order.

## Expected Results

- Playlist file created at `/home/ga/Videos/playlists/practice_sequence.xspf` or `.m3u8`
- Playlist contains exactly 4 entries in correct order
- Each entry specifies time ranges for the segments
- Total playback duration approximately 3 minutes 25 seconds (205 seconds)

## Required Segments

1. **tutorial_01_basics.mp4**: 2:15 - 2:45 (body isolation)
2. **tutorial_02_intermediate.mp4**: 4:30 - 5:00 (footwork combo)
3. **tutorial_03_arms.mp4**: 1:00 - 1:40 (arm movements)
4. **tutorial_04_cooldown.mp4**: 8:00 - 9:30 (stretching)

## Verification Criteria

1. ✅ **Playlist Exists**: Playlist file found and parseable (15%)
2. ✅ **Format Valid**: Successfully parsed as XSPF or M3U (10%)
3. ✅ **Correct Entry Count**: Exactly 4 entries (15%)
4. ✅ **Segment Accuracy**: Each segment correctly specified (40%)
   - Correct source video referenced
   - Start time within ±5s tolerance
   - Duration within ±5s tolerance
5. ✅ **Total Duration**: Sum approximately 205 seconds (15%)
6. ✅ **Loop Configured**: Playlist set to repeat (10% bonus)

**Pass Threshold**: 70%

## Skills Tested

- VLC playlist file formats (XSPF, M3U8)
- Time range specification with VLC options
- File creation and management
- Understanding of media playlist concepts
- Workflow optimization for content curation

## Approach Strategies

### Method 1: M3U8 with VLC Options (Recommended)
Create a text file with VLC-specific time options:
