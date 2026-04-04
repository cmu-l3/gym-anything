# Navigate Chapter Markers Task

**Difficulty**: 🟡 Medium  
**Skills**: Chapter navigation, menu navigation, snapshot capture, metadata understanding  
**Duration**: 120 seconds  
**Steps**: ~50

## Objective

Efficiently navigate a long-form documentary video using embedded chapter markers to reach specific chapters and capture snapshots, simulating a research workflow where manual scrubbing would be inefficient.

## Task Description

**Scenario**: You're a graduate student preparing a presentation on renewable energy. You have a 90-minute documentary with chapter markers for different energy types. Your advisor needs screenshots specifically from the "Solar Power" and "Wind Energy" chapters by tomorrow morning.

The agent must:
1. Open the video file in VLC (`/home/ga/Videos/future_energy_documentary.mp4`)
2. Access the chapter navigation menu (Playback → Chapter)
3. Navigate to the "Solar Power" chapter (12:00-30:00)
4. Capture a snapshot and save as `/home/ga/Pictures/vlc/solar_power.png`
5. Navigate to the "Wind Energy" chapter (30:00-50:00)
6. Capture a snapshot and save as `/home/ga/Pictures/vlc/wind_energy.png`

## Expected Results

- Two snapshot files created:
  - `/home/ga/Pictures/vlc/solar_power.png` (from Solar Power chapter)
  - `/home/ga/Pictures/vlc/wind_energy.png` (from Wind Energy chapter)
- Snapshots show content matching their respective chapters
- Chapter navigation was used (not manual seeking)

## Verification Criteria

1. ✅ **Video Opened**: VLC opened with documentary (15 points)
2. ✅ **Solar Snapshot Valid**: Solar power snapshot exists with correct content (30 points)
3. ✅ **Wind Snapshot Valid**: Wind energy snapshot exists with correct content (30 points)
4. ✅ **Chapter Navigation Used**: Evidence of chapter menu access (15 points)
5. ✅ **Correct Time Ranges**: Snapshots from expected chapter time ranges (10 points)

**Pass Threshold**: 70%

## Skills Tested

- **Chapter marker discovery**: Finding chapter navigation feature
- **Menu navigation**: Playback → Chapter submenu
- **Precise navigation**: Jumping to specific chapters by name
- **Snapshot capture**: Taking and naming screenshots
- **Metadata understanding**: Recognizing chapter structure
- **Workflow efficiency**: Using chapters instead of manual scrubbing

## Controls

- **Menu**: Playback → Chapter → [Chapter Name]
- **Right-click**: Right-click → Playback → Chapter
- **Keyboard**: `[` (previous chapter), `]` (next chapter)
- **Snapshot**: `Shift+S` or Video → Take Snapshot

## Video Structure

The documentary has 6 chapters:
1. Introduction (0:00-12:00)
2. **Solar Power** (12:00-30:00) ← TARGET
3. **Wind Energy** (30:00-50:00) ← TARGET
4. Hydroelectric (50:00-65:00)
5. Nuclear Options (65:00-80:00)
6. Conclusion (80:00-90:00)

## Notes

This task tests the agent's ability to use structured navigation features for long-form content, which is much more efficient than manual scrubbing through a 90-minute video.