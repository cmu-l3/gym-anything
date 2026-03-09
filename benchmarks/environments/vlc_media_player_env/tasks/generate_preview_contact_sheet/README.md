# Generate Preview Contact Sheet Task

**Difficulty**: 🟡 Medium  
**Skills**: Batch processing, seeking, snapshot capture, file organization  
**Duration**: 5 minutes  
**Steps**: ~60

## Objective

Generate preview snapshots from multiple unlabeled video files to quickly identify their contents without full playback.

## Task Description

You have three mystery video files with generic names in `/home/ga/Videos/mystery_files/`. Without watching each video completely, you need to generate preview snapshots to identify what each contains.

The agent must:
1. Process three video files: `unknown_01.mp4`, `unknown_02.mp4`, `unknown_03.mp4`
2. For each video, capture 5 preview snapshots at: 10%, 30%, 50%, 70%, 90% through the video
3. Save snapshots to `/home/ga/Pictures/contact_sheets/`
4. Use clear filenames indicating source video and position (e.g., `unknown_01_preview_10pct.png`)

## Expected Results

- 15 preview images total (5 per video)
- PNG format, minimum 200x100 pixels
- Filenames clearly identify source and position
- All snapshots have reasonable quality (>5 KB)

## Verification Criteria

1. ✅ **Snapshot Count**: At least 12/15 snapshots found
2. ✅ **Valid Images**: At least 12 snapshots are valid PNG files
3. ✅ **All Videos Processed**: All 3 videos have preview snapshots

**Pass Threshold**: 75%

## Skills Tested

- Batch video processing workflow
- Video duration analysis
- Precise seeking to calculated positions
- Snapshot capture at specific timestamps
- File naming and organization
- Working with multiple files systematically

## Approach Suggestions

**CLI Approach (Recommended):**