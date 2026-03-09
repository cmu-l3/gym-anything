# Extract Lecture Highlights Task

**Difficulty**: 🟡 Medium  
**Skills**: Audio extraction, timestamp navigation, file management, media conversion  
**Duration**: 120 seconds  
**Steps**: ~50

## Objective

Extract 4 specific audio segments from a lecture video at precise timestamps and save them as separate MP3 files for study purposes.

## Scenario

A university student preparing for finals needs to extract audio highlights from a 45-minute recorded lecture. They mentally bookmarked 4 key explanations and want portable audio segments to review during their commute rather than re-watching the entire video.

## Task Description

The agent must:
1. Open the lecture video file (`/home/ga/Videos/lecture_video.mp4`)
2. Extract 4 audio segments at specific timestamps:
   - **Segment 1**: 3:15 - 3:50 (35 seconds) → `segment_1_concept_a.mp3`
   - **Segment 2**: 12:40 - 13:15 (35 seconds) → `segment_2_concept_b.mp3`
   - **Segment 3**: 28:05 - 28:40 (35 seconds) → `segment_3_concept_c.mp3`
   - **Segment 4**: 39:25 - 40:00 (35 seconds) → `segment_4_concept_d.mp3`
3. Save all segments to `/home/ga/Music/lecture_highlights/`

## Expected Results

- 4 MP3 files created with correct filenames
- Each file is 30-40 seconds long (±tolerance)
- Audio-only format (MP3), not video
- All files are playable and valid

## Verification Criteria

1. ✅ **All Files Exist**: 4 audio files with correct names
2. ✅ **Correct Duration**: Each file is 30-40 seconds
3. ✅ **Valid Audio**: Files are parseable MP3 format
4. ✅ **Correct Location**: Files saved in designated directory

**Pass Threshold**: 80%

## Skills Tested

- Media conversion (video to audio extraction)
- Precise timestamp navigation and seeking
- Segment selection and trimming
- File naming and organization
- Understanding VLC's Convert/Save workflow
- Batch processing (4 separate extractions)

## Methods

### GUI Method:
1. Open lecture video in VLC
2. For each segment:
   - Seek to start time
   - Media → Convert/Save (Ctrl+R)
   - Select "Convert" mode
   - Choose Audio - MP3 profile
   - Set destination filename
   - Advanced: Set start/stop time
   - Start conversion

### CLI Method (more efficient):