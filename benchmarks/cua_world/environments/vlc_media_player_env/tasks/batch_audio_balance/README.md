# Batch Audio Balance Task

**Difficulty**: 🟡 Medium  
**Skills**: Audio analysis, batch processing, volume adjustment, non-destructive editing  
**Duration**: 120 seconds  
**Steps**: ~45

## Objective

Balance volume levels across multiple podcast audio segments by identifying files with inappropriate loudness and adjusting them to achieve consistent perceived volume across the batch.

## Task Description

**Real-world scenario**: A podcast editor receives interview segments recorded on different equipment (Zoom call, phone recording, studio mic) with wildly varying volumes. The segments need balancing before stitching into a final episode.

The agent must:
1. Listen to/analyze multiple audio files in `/home/ga/Music/podcast_raw/`
2. Identify which files have inappropriate volume levels (too quiet or too loud)
3. Adjust problematic files using VLC's audio effects or conversion features
4. Export balanced versions to `/home/ga/Music/podcast_balanced/`
5. Preserve original files (non-destructive workflow)

## Input Files

Four audio segments in `/home/ga/Music/podcast_raw/`:
- `segment_a.mp3` - Reference level (normal volume)
- `segment_b.mp3` - Too quiet (needs boosting)
- `segment_c.mp3` - Too loud (needs reduction)
- `segment_d.mp3` - Normal volume (already balanced)

## Expected Results

- `/home/ga/Music/podcast_balanced/` directory contains adjusted audio files
- At minimum: `segment_b.mp3` and `segment_c.mp3` (the problematic files)
- All output files have similar perceived loudness
- Original files in `podcast_raw/` remain unmodified
- Audio quality preserved (no corruption)

## Verification Criteria

1. ✅ **Output Directory Exists**: Balanced audio directory created with files
2. ✅ **Problematic Files Adjusted**: At least the too-quiet and too-loud files are present
3. ✅ **Loudness Consistency**: Standard deviation of loudness ≤ 3 LUFS across outputs
4. ✅ **Target Range**: Each output file within [-21, -15] LUFS (typical podcast range)
5. ✅ **Originals Preserved**: Files in podcast_raw/ unchanged
6. ✅ **Audio Integrity**: No corruption, duration matches originals

**Pass Threshold**: 75%

## Skills Tested

- Comparative audio analysis across multiple files
- VLC audio effects (volume, gain, compression)
- Media conversion/export functionality
- File management (separate input/output directories)
- Non-destructive editing workflow
- Quality assessment mindset

## VLC Methods for Volume Adjustment

### Method 1: Audio Effects + Convert
1. Open file in VLC
2. Tools → Effects and Filters (Ctrl+E)
3. Audio Effects → Compressor or use volume slider
4. Media → Convert/Save to export

### Method 2: Conversion with Audio Codec Settings
1. Media → Convert/Save (Ctrl+R)
2. Add source file
3. Edit Profile → Audio codec settings
4. Adjust volume/gain in audio settings
5. Convert and save to destination

### Method 3: Command-line (cvlc)