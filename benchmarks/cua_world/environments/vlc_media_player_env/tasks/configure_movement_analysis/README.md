# Configure Movement Analysis Task

**Difficulty**: 🟡 Medium  
**Skills**: Multi-setting orchestration, playback control, workflow configuration  
**Duration**: 180 seconds  
**Steps**: ~45

## Objective

Configure VLC Media Player for detailed movement analysis by setting up playback speed reduction, A-B repeat loops, and on-screen time display—a workflow used by martial artists, dancers, and coaches.

## Task Description

The agent must:
1. Open VLC with a training video
2. Adjust playback speed to 50-75% for detailed analysis
3. Configure A-B repeat loop on a movement segment (2-5 seconds)
4. Enable on-screen time display (OSD) for temporal reference
5. Verify the complete configuration works together

## Expected Results

- Playback speed reduced to 50-75% (0.5-0.75x rate)
- A-B loop configured and active
- Time display visible on video overlay
- Configuration suitable for movement analysis workflow

## Verification Criteria

1. ✅ **OSD Enabled**: Time display configured in VLC settings
2. ✅ **Speed Adjusted**: Playback speed in analysis range (0.5-0.75x)
3. ✅ **Workflow Coherent**: Settings work together for movement analysis

**Pass Threshold**: 70%

## Skills Tested

- Playback speed control navigation
- A-B loop point marking
- OSD/overlay configuration
- Multi-setting coordination
- Understanding professional VLC workflows
- Temporal precision

## Controls

- **Speed**: 
  - Menu: Playback → Speed → Slower/Faster
  - Keyboard: `]` to slow down, `[` to speed up
- **A-B Loop**:
  - Menu: Playback → A-B Loop (mark points A and B)
  - Keyboard: `Shift+L` to mark points
- **Time Display**:
  - Keyboard: `T` to toggle time display
  - Menu: Tools → Preferences → Interface → Show media time

## Real-World Context

This configuration is used by:
- Martial artists studying complex forms and techniques
- Dancers learning choreography
- Coaches analyzing athletic performance
- Physical therapists reviewing movement patterns
- Animation students studying reference footage

## Notes

- A-B loop is session-specific and won't persist after restart
- Playback speed may reset between videos
- OSD settings persist in VLC configuration
- Audio may distort at very slow speeds (<50%)