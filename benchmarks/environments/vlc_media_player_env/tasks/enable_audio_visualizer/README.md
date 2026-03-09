# Enable Audio Visualizer Task

**Difficulty**: 🟡 Medium  
**Skills**: Interface discovery, audio visualization, feature activation  
**Duration**: 90 seconds  
**Steps**: ~25

## Objective

Enable VLC's audio visualization feature (spectrum analyzer or waveform) for an audio recording, navigate to a specific timestamp, and capture a screenshot proving the visualization is active.

## Task Description

The agent must:
1. Open an audio file in VLC
2. Navigate to VLC's visualization settings
3. Enable audio visualization (spectrum/waveform/scope)
4. Navigate to approximately 3:00 (3 minutes) in the audio
5. Capture a screenshot showing active visualization

## Expected Results

- Audio visualization enabled and visible in VLC window
- Screenshot captured showing visualization display
- Timestamp approximately at 3:00 mark
- Screenshot file size >100 KB (indicates actual visualization content)

## Verification Criteria

1. ✅ **Screenshot Exists**: Screenshot file found and valid
2. ✅ **Image Quality**: Screenshot has sufficient size/resolution
3. ✅ **Content Verification**: File size suggests visualization content

**Pass Threshold**: 70%

## Skills Tested

- Menu navigation (View → Visualizations or Audio menu)
- Feature discovery (finding non-obvious settings)
- Audio playback understanding
- Screenshot capture
- Timestamp navigation

## Human Context

You're an ornithologist who recorded audio in a wetland. To analyze a suspected rare bird call at the 3-minute mark, you need to visually examine the frequency spectrum. Bird calls create distinctive patterns in frequency visualizations.

## Controls

- **Menu**: View → Visualizations → Spectrum/Spectrometer/Scope
- **Alternative**: Tools → Effects and Filters → Audio Effects
- **Seek**: Click timeline or use Shift+Right/Left
- **Screenshot**: Shift+S or Video → Take Snapshot