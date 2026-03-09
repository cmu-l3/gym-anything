# Fix Subtitle Encoding Task

**Difficulty**: 🟡 Medium  
**Skills**: Subtitle troubleshooting, character encoding, VLC configuration, command-line tools  
**Duration**: 90 seconds  
**Steps**: ~35

## Objective

Fix garbled subtitle text caused by incorrect character encoding. The subtitle file contains Japanese text in Shift-JIS encoding, but VLC is trying to read it as UTF-8, resulting in mojibake (garbled characters).

## Task Description

The agent must:
1. Observe that subtitles appear garbled when loaded
2. Read the hint file explaining the encoding issue
3. Either:
   - **Option A**: Configure VLC to interpret subtitles as Shift-JIS encoding, OR
   - **Option B**: Convert the subtitle file to UTF-8 and reload it

## Expected Results

**Option A (VLC Configuration)**:
- VLC preferences updated with `subsdec-encoding=Shift-JIS`
- Subtitles display correctly as Japanese characters

**Option B (File Conversion)**:
- New UTF-8 encoded subtitle file created
- File contains valid Japanese characters
- Subtitle structure preserved (5 entries)

## Verification Criteria

1. ✅ **Encoding Fixed**: VLC config has Shift-JIS setting OR UTF-8 file exists
2. ✅ **Valid Content**: Japanese characters display correctly
3. ✅ **Structure Preserved**: Subtitle timing intact

**Pass Threshold**: 70%

## Skills Tested

- Character encoding troubleshooting
- VLC preferences navigation
- Command-line text processing (iconv)
- International text handling
- File format understanding

## Controls

**Option A - VLC Configuration**:
- Tools → Preferences (Ctrl+P)
- Show settings: All
- Input / Codecs → Subtitles/OSD → Text subtitles decoder
- Set "Subtitle text encoding" to "Shift-JIS"
- Save and restart

**Option B - Command Line Conversion**: