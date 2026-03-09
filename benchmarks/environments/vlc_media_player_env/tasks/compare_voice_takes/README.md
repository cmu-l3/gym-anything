# Compare Voice Takes Task

**Difficulty**: 🟡 Medium  
**Skills**: Comparative audio analysis, critical listening, decision-making  
**Duration**: 180 seconds  
**Steps**: ~40

## Objective

Review multiple voice recording takes of the same line, compare their audio quality and performance characteristics, and select the best take for final production use.

## Task Description

The agent must:
1. VLC is available with 4 audio takes in `/home/ga/VoiceRecordings/ProjectApollo/`
2. Play and review each of the 4 takes (line_042_take1.mp3 through take4.mp3)
3. Compare audio characteristics:
   - Volume levels and consistency
   - Presence of artifacts (clicks, pops, noise)
   - Pacing and delivery quality
   - Overall clarity and performance
4. Document findings in `/home/ga/VoiceRecordings/ProjectApollo/take_selection.txt`
5. Clearly identify take 3 as the best selection with reasoning

## Expected Results

- File `/home/ga/VoiceRecordings/ProjectApollo/take_selection.txt` created
- Contains evaluation of all 4 takes
- Clearly identifies take 3 as the selected/best take
- Provides quality reasoning (mentions volume, noise, pacing, or clarity)
- File has meaningful content (>100 bytes)

## Verification Criteria

1. ✅ **Selection File Exists**: take_selection.txt found at correct path
2. ✅ **Meaningful Content**: File has >100 bytes (not just "take 3")
3. ✅ **Correct Selection**: Identifies take 3 as best/selected take
4. ✅ **Complete Evaluation**: Mentions all 4 takes
5. ✅ **Quality Reasoning**: References at least 2 quality factors

**Bonus**: ⭐ Identifies the flaw in take 2 (mouth click/artifact)

**Pass Threshold**: 75% (requires 4/5 primary criteria)

## Skills Tested

- Audio playback and comparison
- Critical listening skills
- Qualitative assessment and decision-making
- Documentation and written communication
- Understanding of audio production workflows
- File navigation and text editing

## Take Characteristics

- **Take 1**: Decent quality but volume is reduced (-8dB, slightly quiet)
- **Take 2**: Good quality but has a mouth click/pop at 3 seconds
- **Take 3**: Excellent quality, clean, well-paced (**BEST TAKE**)
- **Take 4**: Too fast/rushed (1.3x speed), lacks appropriate pacing

## Real-World Context

This task simulates a voice actor's daily workflow: after recording multiple takes of a line, they must self-select the best version before submitting to producers. Missing audio flaws or selecting a suboptimal take can result in expensive re-recording sessions.

## Controls

- **Open Media**: Media → Open File (Ctrl+O)
- **Playback**: Space bar (play/pause)
- **Seek**: Shift+Right/Left (jump forward/backward)
- **Volume**: Ctrl+Up/Down (adjust for critical listening)
- **Repeat Section**: Playback → A→B Loop for isolating suspicious sections
- **Text Editor**: gedit, nano, or any editor to create selection document