# Batch Verify Raw Footage Task

**Difficulty**: 🟡 Medium  
**Skills**: Batch processing, QA workflow, media analysis, documentation  
**Duration**: 180 seconds  
**Steps**: ~50

## Objective

Systematically verify a batch of raw video files from a client shoot to identify any corrupted or defective files before starting editing work. Create a professional QA report documenting the results.

## Task Description

The agent must:
1. Analyze 5 video files in `/home/ga/Videos/wedding_raw/`
2. Check each file for:
   - Playability (file opens without errors)
   - Video and audio streams present
   - Correct resolution (1920x1080)
   - Correct codec (H.264)
   - Valid duration (>5 seconds)
3. Create a QA report at `/home/ga/Documents/qa_report.txt`
4. Flag any problematic files in the report

## Expected Results

- QA report created with all 5 files documented
- Problematic file (`ceremony_02.mp4` - missing audio) correctly identified
- Report includes technical specs for each file
- Summary section with pass/fail counts

## Verification Criteria

1. ✅ **Report Exists**: QA report file found at expected location
2. ✅ **All Files Documented**: All 5 files analyzed and present in report
3. ✅ **Problem Detection**: Defective file correctly flagged as FAIL/Issue
4. ✅ **Valid File Specs**: Valid files show correct resolution, codec, audio
5. ✅ **Summary Present**: Report includes summary with accurate counts

**Pass Threshold**: 80%

## Skills Tested

- Systematic workflow (batch processing)
- Media file analysis using ffprobe/VLC
- Professional QA documentation
- Problem detection and reporting
- Understanding video properties (codec, resolution, streams)

## Scenario

You're a freelance video editor who received 5 raw video clips from a wedding videographer. Before starting the edit, you must verify all files are playable and meet technical specifications. Last month you wasted 12 hours on a project only to discover a corrupted file at the end. Never again.

## Tools Available

- **VLC Media Player**: Open and inspect files
- **ffprobe**: Command-line media analysis (`ffprobe -v error -show_format -show_streams file.mp4`)
- **Python utils**: `vlc_verification_utils.py` with helper functions
- **Terminal**: Any command-line tools

## Report Format

The report should be structured text with sections for each file and a summary:
