# Verify True Duration Task

**Difficulty**: 🟡 Medium  
**Skills**: Technical diagnostics, media information analysis, troubleshooting  
**Duration**: 5 minutes  
**Steps**: ~40

## Objective

Determine the ACTUAL playable duration of a video file whose metadata claims a longer duration than the real content - a common problem with interrupted downloads and corrupted files.

## Task Description

The agent must:
1. Investigate a video file that claims to be 10 minutes long
2. Verify the actual playable duration (which is shorter due to file truncation)
3. Document findings in a structured report
4. Explain the verification method used

## Expected Results

- Report file created at `/home/ga/Documents/duration_report.txt`
- Report contains:
  - METADATA_DURATION: [seconds from media info]
  - ACTUAL_DURATION: [actual playable seconds determined]
  - VERIFICATION_METHOD: [brief description of how verified]
- Accurate identification of true duration (within ±5 seconds)

## Verification Criteria

1. ✅ **Report Exists**: Duration report file created with correct format
2. ✅ **Metadata Identified**: Correct identification of metadata duration
3. ✅ **Actual Duration Found**: Accurate determination of true playable duration
4. ✅ **Method Documented**: Verification method explained

**Pass Threshold**: 70%

## Skills Tested

- Media information analysis (Tools → Media Information)
- Seeking and playback verification
- Understanding video metadata vs actual content
- File integrity troubleshooting
- Technical documentation

## Real-World Context

This scenario is extremely common when:
- Downloads are interrupted
- Screen recordings are force-stopped
- Streaming recordings fail mid-capture
- Files are poorly transcoded
- Cloud transfers are incomplete

Users waste time seeking to non-existent positions, encounter frozen frames, and face editing complications.

## Controls

- **Media Information**: Tools → Media Information (Ctrl+I)
- **Seeking**: Progress bar, Shift+Right/Left
- **Playback**: Space to pause/play

## Hints

- Don't trust what VLC's timeline initially shows
- Try seeking to near the reported end time
- Watch for freezing, errors, or unexpected jumps
- Compare metadata vs actual playback behavior