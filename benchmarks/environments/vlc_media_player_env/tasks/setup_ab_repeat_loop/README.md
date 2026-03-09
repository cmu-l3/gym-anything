# Set Up A-B Repeat Loop Task

**Difficulty**: 🟡 Medium  
**Skills**: Advanced playback features, timeline navigation, A-B repeat configuration  
**Duration**: 90 seconds  
**Steps**: ~40

## Objective

Configure VLC Media Player's A-B repeat feature to continuously loop a specific 15-second segment of an interview recording, enabling efficient transcription work.

## Human Context & Scenario

**Persona**: Maya, a PhD student in sociology conducting qualitative research

**Situation**: Maya is transcribing a 60-second interview clip. At 15 seconds into the recording, the interviewee begins discussing a complex topic while speaking rapidly. Maya needs to listen to the 15-second segment (from 15s to 30s) repeatedly to capture every word accurately.

**Goal**: Set up VLC's A-B repeat feature to automatically loop just the segment from 15 to 30 seconds, allowing her to focus entirely on typing while the audio repeats seamlessly.

## Task Description

The agent must:
1. VLC launches with interview video playing
2. Navigate to timestamp 0:15 (15 seconds)
3. Set Point A (loop start) at 15 seconds
4. Navigate to timestamp 0:30 (30 seconds)
5. Set Point B (loop end) at 30 seconds
6. Activate A-B repeat mode so the segment loops continuously

## Expected Results

- VLC is playing the interview video
- A-B repeat mode is enabled
- Loop point A is set around 15 seconds (±2 second tolerance)
- Loop point B is set around 30 seconds (±2 second tolerance)
- Video segment is looping continuously

## Verification Criteria

1. ✅ **VLC Running**: VLC process is active
2. ✅ **Video Loaded**: Interview video is loaded
3. ✅ **Loop Active**: A-B repeat appears to be configured
4. ✅ **Loop Points**: Points are set within tolerance (if detectable)

**Pass Threshold**: 70%

## Skills Tested

- VLC advanced playback features
- Precise timeline navigation
- A-B repeat loop configuration
- Keyboard shortcuts or menu navigation
- Understanding of looping modes

## Controls

- **Keyboard**: `Shift+L` or `L` - Set A-B loop points (press once for A, again for B)
- **Menu**: Playback → A→B Loop
- **Seek**: Click timeline or use arrow keys to navigate
- **Clear Loop**: Press loop key again to disable

## Notes

Different VLC versions may use different shortcuts for A-B repeat. The most common are:
- `Shift+L` (Linux/Windows)
- `L` (some versions)
- Via menu: Playback → Loop → A→B (set point A, then set point B)

VLC will display markers on the timeline when A-B points are set.