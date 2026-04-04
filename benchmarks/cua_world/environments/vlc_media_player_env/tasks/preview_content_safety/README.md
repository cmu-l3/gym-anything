# Preview Content Safety Task

**Difficulty**: 🟡 Medium  
**Skills**: Content review, playback speed control, note-taking, professional workflow  
**Duration**: 90 seconds  
**Steps**: ~50

## Objective

Efficiently preview a 12-minute educational video at increased playback speed to identify and document potentially inappropriate content sections before showing to a middle school audience.

## Task Description

The agent must:
1. Open the educational video in VLC
2. Set playback speed to 1.5x-2.0x for efficient preview
3. Identify problematic sections (the video has visible warnings at specific timestamps)
4. Document findings in a text file with timestamps and descriptions
5. Provide an overall recommendation

## Expected Results

- Video previewed at faster playback speed
- Text file created: `/home/ga/Videos/content_review_notes.txt`
- File contains:
  - 2-3 flagged timestamps in MM:SS format
  - Brief descriptions of concerns
  - Overall recommendation (APPROVED / NEEDS EDITING / DO NOT USE)
- Playback speed setting persisted in VLC config

## Verification Criteria

1. ✅ **Review Notes Exist**: Text file created and parseable
2. ✅ **Timestamps Documented**: At least 2 timestamps present
3. ✅ **Timestamps Accurate**: Timestamps match problematic sections (2:45, 6:15, 10:45)
4. ✅ **Descriptions Present**: Content concerns described
5. ✅ **Recommendation Made**: Clear recommendation provided
6. ✅ **Speed Configured**: Playback speed set to 1.3x+ (bonus)

**Pass Threshold**: 70%

## Skills Tested

- Playback speed control (Playback → Speed menu or `[` / `]` keys)
- Timestamp observation and recording
- Content analysis and judgment
- Professional documentation
- Text file creation
- Multi-step workflow execution

## Real-world Context

Teachers and content reviewers frequently need to preview media quickly before showing it to students. This task simulates the real-world need to efficiently scan content for appropriateness while documenting specific concerns for decision-making.

## Controls

- **Speed Control**: 
  - Menu: Playback → Speed → Faster/Slower
  - Keyboard: `]` faster, `[` slower, `=` normal
- **Playback**: Space to pause/play
- **Note-taking**: Use text editor (gedit, nano, etc.) to create review file