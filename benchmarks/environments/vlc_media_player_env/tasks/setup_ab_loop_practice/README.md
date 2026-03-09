# Setup A-B Loop Practice Task

**Difficulty**: 🟡 Medium  
**Skills**: A-B loop configuration, precise navigation, keyboard shortcuts  
**Duration**: 60 seconds  
**Steps**: ~25

## Objective

Configure VLC's A-B repeat loop feature to continuously repeat a specific 7-second dialogue segment (42-49 seconds) for practice purposes. This simulates a professional workflow for voice actors, musicians, or language learners who need to repeatedly practice a short segment.

## Task Description

The agent must:
1. Read task instructions from `/home/ga/dialogue_segment.txt`
2. Navigate to approximately 42 seconds in the video
3. Set the A (loop start) point
4. Navigate to approximately 49 seconds
5. Set the B (loop end) point
6. Verify the loop is active and continuously repeating

## Expected Results

- A-B loop markers set at approximately 42s and 49s (±2s tolerance)
- Loop duration of 5-9 seconds (target: ~7 seconds)
- VLC continuously repeating only the specified segment
- Confirmation file documenting loop parameters

## Verification Criteria

1. ✅ **Loop Confirmation Created**: Agent documented loop parameters
2. ✅ **Loop Boundaries Correct**: Start and end times within tolerance
3. ✅ **Loop Duration Valid**: Duration between 5-9 seconds
4. ✅ **Task Completed**: Completion marker present

**Pass Threshold**: 75% (3/4 criteria)

## Skills Tested

- Reading and following external task specifications
- Precise timeline navigation
- VLC A-B loop functionality (advanced feature)
- Keyboard shortcut mastery (Shift+L)
- Configuration verification and documentation

## Controls

### Primary Method (Recommended)
- **Shift+L**: Set A-B loop points (first press sets A, second sets B)

### Alternative Methods
- **Playback menu → A→B Loop**: Access via menu
- **Advanced Controls**: Enable advanced controls for loop button

### Navigation
- **Click timeline**: Direct seeking
- **Shift+Right**: Jump forward 5 seconds
- **Shift+Left**: Jump backward 5 seconds
- **Ctrl+T**: Jump to specific time

## Real-World Context

Voice actors, musicians, and performers frequently need to practice short segments repeatedly. VLC's A-B loop eliminates the tedious manual rewinding, allowing focused practice without breaking concentration.

## Notes

- The video has a visible timestamp overlay to help with navigation
- Loop indicators appear on VLC's timeline when A-B loop is active
- Agent should create `/tmp/ab_loop_confirmation.txt` with loop parameters for verification
- The segment contains the phrase "The answer lies in the details" (visible on screen)