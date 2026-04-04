# Tag Media Metadata Task

**Difficulty**: 🟡 Medium  
**Skills**: Metadata editing, media library organization, file management  
**Duration**: 180 seconds  
**Steps**: ~50

## Objective

Add comprehensive metadata tags to a concert recording video file using VLC Media Player's Media Information editor to enable proper media library organization.

## Real-World Scenario

**Persona**: Alex, a concert enthusiast and live music collector

**Context**: Alex has been recording live concerts and has hundreds of video files with generic names that are impossible to search or organize. Alex is building a personal concert archive and needs to properly tag each video with artist name, concert location, date, and notes about the setlist. Without proper metadata, Alex can't use media library software to browse by artist, search by venue, or sort chronologically.

**Goal**: Use VLC's media information editor to add comprehensive metadata tags to a concert recording so it appears correctly in media library applications and is searchable.

## Task Description

You have a video file of a concert recording: `/home/ga/Videos/concert_recording.mp4`

This file currently has no metadata. Your task is to open it in VLC and add the following metadata tags using VLC's Media Information editor:

**Required metadata fields**:
- **Title**: "Live at The Roxy Theatre"
- **Artist**: "The Midnight Riders"
- **Album**: "2024 North American Tour"
- **Date**: "2024-03-15" (or "2024")
- **Genre**: "Rock"
- **Description**: "Opening night performance featuring extended guitar solos and two-song encore"
- **Copyright**: "Personal Recording - Non-Commercial Use"

## Instructions

1. Open VLC Media Player
2. Open the file `/home/ga/Videos/concert_recording.mp4`
3. Navigate to the Media Information dialog:
   - Menu: Tools → Media Information (or press Ctrl+I)
4. Navigate to the Metadata tab
5. Fill in all required metadata fields with the exact values specified above
6. Save the changes (may need to close dialog or save to file)
7. Close VLC to ensure changes are persisted

## Success Criteria

The task is successful if:
- ✅ The file exists with metadata embedded
- ✅ At least 6 out of 8 metadata fields correctly populated
- ✅ Metadata fields match expected values (case-insensitive)
- ✅ Changes persisted to the file

**Pass Threshold**: 75% (6/8 fields minimum)

## Skills Tested

- Menu navigation (Tools → Media Information)
- Tab navigation within dialogs
- Multi-field form completion
- Understanding of metadata concepts
- File metadata persistence

## Controls

- **Menu**: Tools → Media Information (Ctrl+I)
- **Tabs**: General Info, Metadata, Codec Details, Statistics
- **Save**: Close dialog to auto-save, or use Save Metadata button if available

## Notes

- VLC metadata editing works best with MP4 format
- Some metadata fields may have slightly different names (e.g., "Comment" vs "Description")
- Changes should be saved automatically when closing the Media Information dialog
- If metadata doesn't save, try: Media → Save or File → Save