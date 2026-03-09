# Extract Research Frames Task

**Difficulty**: 🟡 Medium  
**Skills**: Precise timestamp seeking, snapshot configuration, batch frame extraction, file management  
**Duration**: 3-5 minutes  
**Steps**: ~40

## Objective

Extract multiple specific frames from a video at precise timestamps to create figures for scientific publication. Each frame must be saved as a high-quality PNG image with a descriptive filename.

## Task Description

The agent must:
1. Read target timestamps from instruction file
2. Open the research video in VLC
3. Configure snapshot settings (PNG format, correct output directory)
4. For each timestamp: seek precisely, capture snapshot, rename file
5. Verify all 5 frames extracted with correct filenames

## Expected Results

- 5 PNG frames extracted at specified timestamps
- Files named: `frame_position_01.png` through `frame_position_05.png`
- Each frame has resolution 1280x720 and file size > 50 KB
- All frames saved in `/home/ga/Pictures/research_frames/`

## Verification Criteria

1. ✅ **Frames Extracted**: All 5 target frames present
2. ✅ **Correct Filenames**: Files match specified naming convention
3. ✅ **Image Quality**: Each frame is valid PNG with correct resolution
4. ✅ **File Properties**: Reasonable file sizes indicating valid image data

**Pass Threshold**: 80% (4/5 frames valid)

## Skills Tested

- Reading and parsing instruction files
- Precise timestamp seeking (sub-second accuracy)
- VLC snapshot configuration
- Batch processing workflow
- File renaming and organization
- Quality verification

## Real-world Context

Scientists and researchers frequently extract specific frames from video footage for:
- Creating figures for papers and presentations
- Documenting experimental observations at key moments
- Comparing visual states across time points
- Annotating datasets for analysis

Manual extraction (seek → snapshot → rename) for multiple frames is tedious and error-prone.

## Controls

- **Seek**: `Ctrl+T` (Jump to Time) or timeline scrubbing
- **Snapshot**: `Shift+S` or Video → Take Snapshot
- **Pause**: `Space`
- **Frame step**: `E` (next frame), `Shift+E` (previous frame)