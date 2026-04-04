# Verify Audio Description Track Task

**Difficulty**: 🟡 Medium  
**Skills**: Audio track management, accessibility features, compliance testing  
**Duration**: 2-3 minutes  
**Steps**: ~40

## Objective

Verify that a video file's audio description (AD) track can be selected and plays correctly for accessibility compliance testing. This simulates a real-world quality control workflow used by streaming services and content distributors.

## Task Description

The agent must:
1. Open the test video file in VLC (`wildlife_doc.mp4`)
2. Navigate to the Audio menu to view available tracks
3. Identify and select the Audio Description track (Track 2)
4. Verify the AD track is playing alongside the main audio
5. Leave VLC in a state where AD track remains selected

## Expected Results

- Video opens and plays in VLC
- Audio Description track (Track 2) is identified
- AD track is explicitly selected (not just default)
- Both main audio and AD narration can be heard together
- Selection is reflected in VLC's runtime state

## Verification Criteria

1. ✅ **VLC Running**: VLC process is active with correct video
2. ✅ **Audio Track Selected**: Audio track setting shows Track 2 (AD)
3. ✅ **Explicit Selection**: Track was actively changed from default
4. ✅ **Task Completed**: Completion marker present

**Pass Threshold**: 70%

## Skills Tested

- Audio menu navigation (Audio → Audio Track)
- Multi-track audio understanding
- Accessibility feature awareness
- Track identification from labels
- Settings verification

## Controls

- **Menu**: Audio → Audio Track → Track 2 (Audio Description)
- **Right-click**: Context menu → Audio → Audio Track
- **Keyboard**: `B` to cycle through audio tracks

## Real-World Context

This task simulates accessibility compliance testing required by:
- **CVAA** (21st Century Communications and Video Accessibility Act) in the US
- **EN 301 549** accessibility standard in Europe
- **WCAG 2.1** (Web Content Accessibility Guidelines)

Accessibility consultants and QA testers perform this verification before content is approved for distribution to ensure visually impaired users can access descriptive audio.

## Notes

- The video has 2 audio tracks:
  - **Track 1**: Main Audio (ambient sounds, music)
  - **Track 2**: Audio Description (narrative descriptions for blind users)
- Both tracks should play simultaneously (mixed), not exclusively
- VLC track numbering may be 0-indexed or 1-indexed depending on version