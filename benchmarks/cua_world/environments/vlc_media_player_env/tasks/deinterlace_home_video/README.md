# Deinterlace Home Video Task

**Difficulty**: 🟡 Medium  
**Skills**: Video filters, deinterlacing, quality adjustment  
**Duration**: 75 seconds  
**Steps**: ~30

## Objective

Apply deinterlacing filter to eliminate visible combing artifacts from an old interlaced home video, making it watchable on modern progressive-scan displays.

## Task Description

The agent must:
1. VLC launches with an interlaced video showing motion artifacts
2. Enable deinterlacing filter using Video menu or keyboard
3. Select an appropriate deinterlacing mode
4. Verify deinterlacing is active and persists

## Scenario

David recently digitized his family's old DV camcorder tapes from the late 1990s. When playing them in VLC, he sees annoying "combing" effects (horizontal scan lines) during motion - classic interlacing artifacts from old NTSC cameras. He wants to enable deinterlacing to make the videos look smooth on modern displays before sharing them with family.

## Expected Results

- Deinterlacing enabled in VLC configuration
- Valid deinterlacing mode selected (e.g., yadif, linear, bob)
- Setting persists in VLC config files

## Verification Criteria

1. ✅ **Config Accessible**: VLC config files parsed successfully
2. ✅ **Deinterlacing Enabled**: Deinterlace setting is active
3. ✅ **Valid Mode Selected**: Appropriate deinterlacing algorithm chosen

**Pass Threshold**: 70%

## Skills Tested

- Video menu navigation
- Understanding of video quality issues
- Filter configuration
- Settings persistence
- Real-world video archival workflow

## Controls

- **Menu**: Video → Deinterlace → Select mode
- **Keyboard**: `D` key - Cycle through deinterlace modes
- **Preferences**: Tools → Preferences → Video → Filters

## Valid Deinterlacing Modes

- **Yadif** (recommended) - Best quality, most CPU intensive
- **Linear** - Good balance of quality and performance
- **Bob** - Doubles framerate, smooth motion
- **Blend** - Fast but softer
- **Discard**, **Mean**, **X**, **Phosphor**, **IVTC** - Other options

## Notes

Interlaced video has alternating scan lines from different time moments, causing "combing" during motion. This was common in old camcorders, VHS tapes, and broadcast TV. Deinterlacing reconstructs full progressive frames.