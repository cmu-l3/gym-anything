# Validate Subtitle Sync Task

**Difficulty**: 🟡 Medium  
**Skills**: Subtitle loading, timeline navigation, quality assurance, documentation  
**Duration**: 90-120 seconds  
**Steps**: ~50

## Objective

Validate that a subtitle file properly matches and synchronizes with a video file by checking sync at multiple checkpoints (beginning, middle, end) and creating a validation report.

## Real-World Scenario

You've downloaded a foreign film (`foreign_film.mp4`) and a separate subtitle file (`foreign_film.srt`) from different sources. Before committing to a 2-hour viewing session, you need to verify that the subtitles actually match this video version and are properly synchronized throughout.

## Task Description

The agent must:
1. Open the video file in VLC
2. Load the subtitle file (`/home/ga/Videos/foreign_film.srt`)
3. Check subtitle synchronization at three checkpoints:
   - **Beginning**: Around 0:30-0:40
   - **Middle**: Around 1:30 (halfway point)
   - **End**: Around 2:50 (near end)
4. Create a validation report documenting findings

## Expected Results

- Validation report created at `/home/ga/subtitle_validation_report.txt`
- Report contains checkpoint assessments (PASS/FAIL)
- Report includes overall verdict
- Subtitles were actually loaded in VLC

## Verification Criteria

1. ✅ **Report Exists**: Validation report file found and parseable
2. ✅ **Subtitles Loaded Status**: Report documents whether subtitles loaded
3. ✅ **Duration Documented**: Video duration is recorded
4. ✅ **Three Checkpoints**: All three checkpoints are assessed
5. ✅ **Overall Verdict**: Final verdict present and correct
6. ✅ **Notes Included**: Additional observations documented

**Pass Threshold**: 70%

## Skills Tested

- External subtitle file loading
- Precise timeline seeking to specific timestamps
- Visual verification of subtitle synchronization
- Structured report writing
- Quality assurance methodology

## Controls

- **Subtitle loading**: Subtitle → Add Subtitle File... (or Ctrl+Shift+O on some systems)
- **Seeking**: Click on progress bar or use keyboard shortcuts
- **Pause/Play**: Space bar

## Report Format
