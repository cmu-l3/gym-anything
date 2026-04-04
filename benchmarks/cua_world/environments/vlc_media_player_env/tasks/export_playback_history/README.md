# Export Playback History Task

**Difficulty**: 🟡 Medium  
**Skills**: File system navigation, data parsing, format conversion  
**Duration**: 180 seconds  
**Steps**: ~40

## Objective

Locate and export VLC's playback history to a structured CSV file for parental monitoring or content auditing purposes.

## Task Description

**Scenario**: A parent wants to monitor what video content their child has been watching. They need a readable list of recently played media files with timestamps.

The agent must:
1. Locate VLC's playback history (typically in `~/.local/share/vlc/` or `~/.config/vlc/`)
2. Parse the history data (XSPF, config files, or other formats)
3. Extract: filename, full path, timestamp, play count
4. Create a CSV file at `/home/ga/Documents/playback_history.csv`
5. Ensure CSV has proper headers and human-readable format

## Expected Results

- CSV file created at `/home/ga/Documents/playback_history.csv`
- File contains at least 3 media entries
- Each entry includes filename and timestamp information
- Proper CSV format with headers
- Human-readable timestamps (not just Unix epoch)

## Verification Criteria

1. ✅ **File Exists**: CSV file found at expected location
2. ✅ **Valid Format**: Proper CSV structure with headers
3. ✅ **Has Headers**: Contains expected column names (filename/path/timestamp)
4. ✅ **Sufficient Entries**: At least 3 media file entries
5. ✅ **Valid Filenames**: Entries have media file extensions
6. ✅ **Timestamp Present**: Each entry has timestamp/date information
7. ✅ **Human Readable**: Timestamps or filenames properly formatted

**Pass Threshold**: 70% (5/7 criteria)

## Skills Tested

- File system navigation (hidden directories)
- VLC data structure understanding
- XML/config file parsing
- Data transformation (to CSV)
- Path handling and decoding
- CSV creation and formatting

## Expected Approach

1. Explore `~/.local/share/vlc/` for media library files (ml.xspf)
2. Or check `~/.config/vlc/vlc-qt-interface.conf` for recent items
3. Parse the file format (XSPF XML or INI-style config)
4. Extract media file paths and metadata
5. Format as CSV with readable column names
6. Save to `/home/ga/Documents/playback_history.csv`

## Notes

- VLC stores history in multiple possible locations
- XSPF is an XML playlist format
- Config files may use INI-style or custom formats
- File paths may be encoded as file:// URIs
- Timestamps might be in Unix epoch format (requires conversion)