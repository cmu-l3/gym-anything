# Normalize Podcast Audio Task

**Difficulty**: 🟡 Medium  
**Skills**: Audio normalization, batch processing, command-line or conversion tools  
**Duration**: 90-120 seconds  
**Steps**: ~40

## Objective

Normalize three podcast audio segments with inconsistent volume levels to create files with uniform peak levels, using VLC's audio normalization capabilities.

## Task Description

You're a podcast producer who recorded a 3-segment interview remotely. Each segment has different audio levels:
- `segment_intro.mp3` (too quiet, -6 dB)
- `segment_interview.mp3` (reference level, -3 dB)  
- `segment_outro.mp3` (too loud, 0 dB)

You must normalize all three files so they have consistent volume levels before editing.

## Expected Results

- Three normalized files created in `/home/ga/podcast_project/normalized/`
- Files named: `normalized_segment_intro.mp3`, `normalized_segment_interview.mp3`, `normalized_segment_outro.mp3`
- All files have peak levels within ±0.5 dB of each other
- No clipping occurs (peaks stay below 0 dB)
- Files maintain MP3 format

## Verification Criteria

1. ✅ **All Files Present**: Three normalized files exist with correct names
2. ✅ **Consistent Levels**: Peak levels are within ±0.5 dB of each other
3. ✅ **No Clipping**: All peaks stay below 0 dB (no distortion)
4. ✅ **Format Maintained**: Files are valid MP3 format

**Pass Threshold**: 75%

## Skills Tested

- Audio file conversion and processing
- VLC command-line usage or GUI conversion
- Understanding of audio normalization concepts
- Batch processing workflow
- Quality control verification

## Solution Approaches

### Approach 1: VLC Command Line (Recommended)
Use terminal with `cvlc` commands for each file: