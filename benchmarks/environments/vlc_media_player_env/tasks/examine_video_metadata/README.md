# Examine Video Metadata Task

**Difficulty**: 🟡 Medium  
**Skills**: Media information dialog, metadata extraction, documentation  
**Duration**: 180 seconds  
**Steps**: ~40

## Objective

Extract technical metadata from a video file using VLC's Media Information dialog and document the findings in a structured report.

## Task Description

The agent must:
1. Open a video file in VLC
2. Access the Media Information dialog (Tools → Media Information or Ctrl+I)
3. Navigate through tabs to find technical specifications
4. Extract and document metadata fields:
   - Video codec
   - Resolution (width × height)
   - Frame rate (fps)
   - Bitrate
   - Creation date (if present)
5. Save findings to `/home/ga/Documents/metadata_report.txt`

## Expected Results

- Report file created with extracted metadata
- At least 4 out of 5 required fields documented
- Values match ground truth within acceptable tolerances

## Verification Criteria

1. ✅ **Report File Exists**: `/home/ga/Documents/metadata_report.txt` created
2. ✅ **Codec Identified**: Correct video codec extracted
3. ✅ **Resolution Documented**: Correct resolution within ±10px
4. ✅ **Frame Rate Documented**: Correct fps within ±2fps
5. ✅ **Completeness**: At least 4/5 fields correctly extracted

**Pass Threshold**: 80% (4/5 criteria)

## Skills Tested

- Media Information dialog navigation
- Tab switching in dialogs
- Technical specification reading
- Data extraction and documentation
- Understanding video metadata concepts

## Controls

- **Menu**: Tools → Media Information
- **Keyboard**: `Ctrl+I` - Open Media Information
- **Tabs**: General, Codec Information, Metadata, Statistics