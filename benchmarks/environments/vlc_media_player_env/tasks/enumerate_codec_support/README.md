# Enumerate Codec Support Task

**Difficulty**: 🟡 Medium  
**Skills**: System introspection, CLI/GUI navigation, documentation  
**Duration**: 90 seconds  
**Steps**: ~35

## Objective

Extract and document VLC Media Player's complete codec support information by generating a comprehensive list of supported audio and video codecs.

## Task Description

The agent must:
1. Access VLC's codec/plugin information
2. Extract the list of supported decoders and codecs
3. Save the information to a text file at `/home/ga/Documents/vlc_info/codecs_supported.txt`
4. Ensure the file contains both audio and video codec identifiers

## Expected Results

- File created at `/home/ga/Documents/vlc_info/codecs_supported.txt`
- File contains comprehensive codec list (minimum 20 entries)
- File includes both audio codecs (mp3, aac, vorbis, etc.) and video codecs (h264, hevc, vp8, etc.)
- File has structured format (list-like, not prose)

## Verification Criteria

1. ✅ **File Exists**: Output file found at expected location
2. ✅ **Sufficient Content**: File size > 500 bytes
3. ✅ **Video Codecs Present**: At least 3 distinct video codec identifiers
4. ✅ **Audio Codecs Present**: At least 3 distinct audio codec identifiers
5. ✅ **Structured Format**: Multiple lines showing list structure
6. ✅ **VLC-specific Content**: Contains VLC-related keywords

**Pass Threshold**: 67% (4/6 criteria)

## Skills Tested

- CLI command usage (vlc --list, --longhelp)
- GUI navigation (Help → About, Tools → Plugins)
- System file inspection (/usr/lib/.../vlc/plugins/)
- Output redirection and file operations
- Understanding of codec architecture

## Solution Approaches

### Approach 1: Command Line (Recommended)