# Embed Video Metadata Task

**Difficulty**: 🟡 Medium  
**Skills**: Media Information dialog, metadata editing, file metadata understanding  
**Duration**: 90 seconds  
**Steps**: ~40

## Objective

Edit and embed metadata (title, artist, description, copyright) into a video file using VLC's Media Information editor.

## Task Description

The agent must:
1. Open VLC Media Player
2. Open the target video file at `/home/ga/Videos/metadata_test/documentary.mp4`
3. Access the Media Information dialog (Tools → Media Information or Ctrl+I)
4. Edit metadata fields with specific values
5. Save the metadata to the file (not just VLC's cache)
6. Verify changes persist

## Expected Results

- Video file at `/home/ga/Videos/metadata_test/documentary.mp4` has embedded metadata:
  - **Title:** "Urban Wildlife Behavior Study"
  - **Artist:** "Dr. Emily Chen"
  - **Description:** "Observational study of raccoon populations in metropolitan areas, filmed 2023-2024"
  - **Copyright:** "Creative Commons BY-SA 4.0"
- Metadata is written to file (not just displayed in VLC)
- Changes persist after reopening file

## Verification Criteria

1. ✅ **Metadata Extracted**: Metadata successfully read from file
2. ✅ **Title Correct**: Title matches expected value
3. ✅ **Artist Correct**: Artist matches expected value
4. ✅ **Description Correct**: Description matches expected value
5. ✅ **Copyright Correct**: Copyright matches expected value

**Pass Threshold**: 80% (4/5 criteria)

## Skills Tested

- Tools menu navigation
- Media Information dialog interaction
- Text field editing
- Understanding metadata vs. filenames
- Save operation (clicking "Save Metadata" button)
- File-level metadata embedding

## Controls

- **Menu**: Tools → Media Information (or Ctrl+I)
- **Dialog**: Edit text fields, click "Save Metadata" button
- **File**: Media → Open File (Ctrl+O) to open the video

## Notes

This task requires understanding that:
1. Metadata is stored IN the video file, not just in VLC's library
2. The "Save Metadata" button must be clicked to write changes
3. Metadata fields must match exactly (case-insensitive, whitespace-normalized)
4. This is different from renaming the file or creating playlists

## Common Pitfalls

- Forgetting to click "Save Metadata" button
- Editing the wrong file
- Typos in metadata fields
- Confusing Media Information with File Information