# Assess Digitization Quality Task

**Difficulty**: 🟡 Medium  
**Skills**: Quality assessment, media diagnostics, systematic analysis  
**Duration**: 180 seconds  
**Steps**: ~60

## Objective

Systematically assess a digitized home video file for common digitization problems and create a diagnostic report recommending next steps.

## Human Context

You've received a digitized family video file from a conversion service. The file plays, but something looks "off." Before deciding whether to request re-digitization (expensive), attempt repairs yourself (risky), or accept the file as-is, you need to identify what's actually wrong.

## Task Description

The agent must:
1. Open the digitized video file (`/home/ga/Videos/family_recording.avi`) in VLC
2. Systematically assess THREE common digitization issues:
   - **Color Standard Mismatch**: Abnormal color saturation or tinting?
   - **Aspect Ratio Distortion**: Are faces/objects stretched or squished?
   - **Audio Sync Drift**: Does audio gradually fall out of sync with video?
3. Create assessment report at `/home/ga/Documents/digitization_report.txt`

## Expected Report Format
