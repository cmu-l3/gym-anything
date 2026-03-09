# Create Timed Subtitles Task

**Difficulty**: 🟡 Medium  
**Skills**: Subtitle timing, SRT format, content creation  
**Duration**: 180 seconds  
**Steps**: ~50

## Objective

Create a properly-formatted and accurately-timed SRT subtitle file for a tutorial video by watching the video and manually noting when each line of dialogue is spoken.

## Task Description

The agent must:
1. Review the provided script text containing dialogue
2. Play the video and note timestamps for each line
3. Create an SRT format subtitle file with proper timing
4. Save the subtitle file to the specified location

## Expected Results

- Subtitle file created at `/home/ga/Videos/python_tutorial.srt`
- Valid SRT format with proper timecode structure
- At least 5 subtitle segments covering the dialogue
- Reasonable timing (subtitles synchronized to speech)
- No empty subtitle segments

## Verification Criteria

1. ✅ **File Exists**: Subtitle file created and parseable
2. ✅ **Valid Format**: Proper SRT structure (numbering, timecodes, text)
3. ✅ **Sufficient Segments**: At least 5 subtitle entries
4. ✅ **Valid Timing**: Timecodes within video duration and chronological
5. ✅ **Has Content**: Each subtitle segment contains actual text

**Pass Threshold**: 75%

## Skills Tested

- Video playback and observation
- Timestamp notation and tracking
- SRT subtitle format understanding
- Text file creation
- Attention to detail and timing precision
- Content creation workflow

## SRT Format Reference
