# Recover Damaged Download Task

**Difficulty**: 🟡 Medium  
**Skills**: Media recovery, file conversion, error handling, VLC transcoding  
**Duration**: 120 seconds  
**Steps**: ~40

## Objective

Recover the playable portion from a partially corrupted/incomplete video file (simulating an interrupted download) and save it as a clean, working video file.

## Real-World Scenario

A graduate student downloaded a 120-minute lecture recording overnight, but the campus internet cut out at 85% completion. Re-downloading would take 4+ hours, but they have an exam tomorrow and need to watch whatever content is available NOW.

**Problem**: 
- The file shows errors when playing in VLC
- Unknown how much is actually watchable
- Need to extract working portion to avoid crashes
- Time-sensitive situation

## Task Description

The agent must:
1. Open the damaged file at `/home/ga/Videos/damaged/lecture_recording.mp4`
2. Use VLC's conversion feature to extract the playable portion
3. Save recovered video to `/home/ga/Videos/recovered/lecture_recovered.mp4`
4. Ensure output is clean and fully playable

## Expected Results

- Recovered file exists at target location
- File is valid and fully playable (no errors)
- Duration is 60-115 minutes (proving partial recovery)
- Video and audio streams both functional
- Reasonable file size (200+ MB for 60+ min video)

## Verification Criteria

1. ✅ **File Exists**: Recovered file found at correct path
2. ✅ **Valid Format**: Has proper video codec and properties
3. ✅ **Correct Duration**: Between 60-115 minutes (partial, not full)
4. ✅ **Fully Playable**: No corruption, passes playback test
5. ✅ **Reasonable Size**: At least 200 MB

**Pass Threshold**: 75%

## Skills Tested

- Working with corrupted/problematic media
- Media → Convert/Save navigation
- Understanding video file structure
- Troubleshooting playback issues
- File format conversion
- Progress monitoring

## Solution Approach

### Method 1: VLC Convert/Save (Recommended)
1. Open VLC
2. Media → Convert/Save (Ctrl+R)
3. Add source: `/home/ga/Videos/damaged/lecture_recording.mp4`
4. Click "Convert/Save"
5. Choose profile (e.g., Video - H.264 + MP3 (MP4))
6. Set destination: `/home/ga/Videos/recovered/lecture_recovered.mp4`
7. Start conversion - VLC will automatically stop at corruption

### Method 2: Direct Play + Record (Alternative)
1. Open damaged file in VLC
2. Use Tools → Effects and Filters → Record
3. Play until it stops at corruption
4. Stop recording, save output

## Controls

- **Media → Convert/Save**: Open conversion dialog (Ctrl+R)
- **Add**: Select source file
- **Convert/Save**: Start conversion process
- **Profile dropdown**: Choose output format

## Notes

- Conversion stops automatically when hitting corrupted data
- The damaged file is intentionally truncated at 85% to simulate interrupted download
- Expected recovered duration: ~80-100 minutes (about 70-85% of 120 min original)
- VLC handles corruption gracefully during conversion