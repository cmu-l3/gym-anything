# Isolate Dialogue Track Task

**Difficulty**: 🟡 Medium  
**Skills**: Audio filter configuration, understanding spatial audio  
**Duration**: 90 seconds  
**Steps**: ~35

## Objective

Configure VLC to isolate the center channel (dialogue) from a movie clip with background music, using audio filters to extract or emphasize center-channel content while suppressing stereo-positioned music and effects.

## Task Description

The agent must:
1. VLC launches with a movie clip containing dialogue with background music
2. Navigate to audio effects/filters menu
3. Enable audio filter for center channel extraction
4. Configure settings to emphasize dialogue over music
5. Settings persist in VLC configuration

## Expected Results

- Audio filter enabled in VLC config
- Center channel extraction or related filter configured
- Settings saved to vlcrc configuration file

## Verification Criteria

1. ✅ **Config Accessible**: VLC config file parsed successfully
2. ✅ **Audio Filter Enabled**: Audio effects filter is active
3. ✅ **Center Extraction Configured**: Settings indicate center channel emphasis

**Pass Threshold**: 70%

## Skills Tested

- Audio effects menu navigation
- Understanding of spatial audio concepts (center channel)
- Audio filter configuration
- Settings persistence
- Real-world audio problem solving

## Controls

- **Menu**: Tools → Effects and Filters (Ctrl+E) → Audio Effects tab
- **Filters**: 
  - Headphone effect with "Dolby Surround" mode
  - Spatializer with center extraction
  - Channel mixer settings

## Notes

In professional audio mixes, dialogue/vocals are typically placed in the center channel (phantom center between left and right speakers). Extracting content common to both channels isolates this center content while suppressing stereo-positioned music and effects.

This technique is useful for:
- Voice actors studying performances
- Language learners focusing on dialogue
- Karaoke (vocal removal)
- Accessibility (emphasizing speech)