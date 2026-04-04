# Extract Embedded Subtitles Task

**Difficulty**: 🟡 Medium  
**Skills**: Stream identification, media conversion, subtitle extraction  
**Duration**: 180 seconds  
**Steps**: ~50

## Objective

Extract an embedded English subtitle track from a multi-language video container (MKV) and save it as a standalone SRT file.

## Task Description

The agent must:
1. Open video file with multiple embedded subtitle tracks
2. Navigate to Media Information to identify subtitle streams
3. Use VLC's Convert/Save functionality to extract English subtitle track
4. Save extracted subtitle as `/home/ga/Videos/subtitles/extracted_english.srt`

## Expected Results

- Extracted subtitle file created at specified location
- File is valid SRT format with proper structure
- Contains actual subtitle content (≥10 entries)
- Properly encoded in UTF-8

## Verification Criteria

1. ✅ **File Exists**: Extracted subtitle file found
2. ✅ **Valid SRT Format**: Proper SRT structure with timestamps
3. ✅ **Sufficient Content**: Contains ≥10 subtitle entries
4. ✅ **Proper Encoding**: UTF-8 encoded text

**Pass Threshold**: 75%

## Skills Tested

- Media Information navigation (Tools → Media Information)
- Stream identification and metadata reading
- Convert/Save dialog usage
- Subtitle format understanding
- File save operations

## Controls

- **Ctrl+I**: Media Information dialog
- **Ctrl+R**: Convert/Save dialog
- **Menu**: Media → Convert/Save

## Notes

The source video contains three embedded subtitle tracks (English, Spanish, French). The task requires extracting specifically the English track. Understanding stream indices and language metadata is crucial.