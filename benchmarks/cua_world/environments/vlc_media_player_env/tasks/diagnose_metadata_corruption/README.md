# Diagnose Metadata Corruption Task

**Difficulty**: 🟡 Medium  
**Skills**: Media diagnostics, file integrity analysis, documentation  
**Duration**: 90-120 seconds  
**Steps**: ~30

## Objective

Diagnose a video file with corrupted duration metadata and document the discrepancy between reported and actual duration.

## Scenario

*"I'm digitizing my family's old VHS tapes from the 1990s. One video file—my daughter's first birthday party—seems corrupted. When I open it in VLC, the timeline shows it's only 47 seconds long, but the video keeps playing for several minutes! I can't seek properly because the progress bar thinks it ends at 0:47. I need to find out how long the video ACTUALLY is so I know if it's worth re-encoding, and I want to document what the file claims vs. what it actually contains."*

## Task Description

The agent must:
1. Open and analyze the corrupted video file at `/home/ga/Videos/corrupted/birthday_1995.avi`
2. Determine the TRUE playable duration (not the metadata duration)
3. Document findings in a diagnostic report
4. Save report to `/home/ga/Documents/media_diagnostics.txt`

## Expected Results

- Diagnostic report created at `/home/ga/Documents/media_diagnostics.txt`
- Report contains:
  - Claimed duration from metadata (~47 seconds)
  - Actual duration measured (~270 seconds / 4:30)
  - Explicit mention of the discrepancy
  - Verification method used

## Verification Criteria

1. ✅ **Report Exists**: Diagnostic report file found
2. ✅ **Actual Duration Accurate**: Within ±5 seconds of 270s
3. ✅ **Discrepancy Documented**: Report mentions mismatch
4. ✅ **Verification Method**: Method described

**Pass Threshold**: 75%

## Skills Tested

- Media file diagnostics
- Understanding metadata vs actual content
- Tool usage (VLC, ffprobe, mediainfo)
- Technical documentation
- Critical thinking (recognizing unreliable data)

## Available Tools

- **VLC Media Player**: Visual playback and observation
- **ffprobe**: Command-line media analysis
- **mediainfo**: Alternative media information tool
- Text editor for report creation

## Sample Report Format
