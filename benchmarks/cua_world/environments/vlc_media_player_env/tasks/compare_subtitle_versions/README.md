# Compare Subtitle Versions Task

**Difficulty**: 🟡 Medium  
**Skills**: Subtitle management, quality assessment, file operations  
**Duration**: 120 seconds  
**Steps**: ~40

## Objective

Compare three different subtitle files for a foreign film and identify the best-synced, highest-quality version.

## Task Description

The agent must:
1. VLC launches with a German film video
2. Load each of the three subtitle files (v1, v2, v3)
3. Seek to timestamp 5:20 to check subtitle timing
4. Assess which subtitle has:
   - Correct timing (appears when dialogue is spoken)
   - Good translation quality
   - Clean formatting
5. Copy the selected subtitle to `/home/ga/Videos/selected_subtitle.srt`

## Expected Results

- Agent tests each subtitle file at timestamp 5:20
- Identifies v2 as the correctly-synced professional subtitle
- Copies v2 to `/home/ga/Videos/selected_subtitle.srt`

## Verification Criteria

1. ✅ **Subtitle Selected**: A subtitle file was copied to selected_subtitle.srt
2. ✅ **File Identified**: Selected file matches one of v1/v2/v3
3. ✅ **Correct Choice**: Selected file is v2 (professional DVD subtitle)

**Pass Threshold**: 65%

## Skills Tested

- Subtitle loading and switching
- Quality assessment (timing, translation)
- Systematic comparison workflow
- Timestamp seeking
- File management

## Subtitle Characteristics

- **v1**: Auto-translated, timing off by +2s, poor grammar
- **v2**: Professional DVD subtitle, perfect timing ⭐ CORRECT
- **v3**: Fan translation, timing off by -1s, okay quality

## Controls

- **Menu**: Subtitle → Add Subtitle File
- **Keyboard**: 
  - `V`: Cycle through subtitle tracks
  - `Ctrl+J`: Jump to specific time
  - `H` / `G`: Adjust subtitle delay

## Real-World Context

This simulates downloading a foreign film and finding multiple subtitle files online with cryptic labels. Users must manually test each to find properly-synced subtitles.