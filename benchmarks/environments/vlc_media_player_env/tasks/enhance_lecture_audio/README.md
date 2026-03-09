# Enhance Lecture Audio Task

**Difficulty**: 🟡 Medium  
**Skills**: Audio equalizer, frequency adjustment, audio enhancement  
**Duration**: 90 seconds  
**Steps**: ~35

## Objective

Use VLC's audio equalizer to enhance a poorly recorded lecture audio file by reducing low-frequency rumble and boosting speech frequencies for better intelligibility.

## Scenario

A graduate student recorded a professor's lecture on her phone at the back of a large auditorium. The recording has excessive low-frequency rumble from the HVAC system and the professor's voice lacks clarity. The student needs to enhance the audio for studying during her commute.

## Task Description

The agent must:
1. Open the lecture audio file in VLC
2. Enable the audio equalizer (Tools → Effects and Filters → Audio Effects → Equalizer)
3. Reduce low-frequency bands (60-170 Hz range) by at least 3-5 dB
4. Boost mid-range speech bands (1-4 kHz range) by at least 3-6 dB
5. Save equalizer settings so they persist

## Expected Results

- VLC equalizer is enabled
- Low frequency bands reduced (negative dB values)
- Mid-range speech bands boosted (positive dB values)
- Settings persisted in VLC configuration

## Verification Criteria

1. ✅ **Equalizer Enabled**: Audio equalizer is active
2. ✅ **Low Frequencies Reduced**: Bands 0-2 (60-310 Hz) reduced by ≥3 dB
3. ✅ **Mid Frequencies Boosted**: Bands 4-6 (1-6 kHz) boosted by ≥3 dB

**Pass Threshold**: 70%

## Skills Tested

- Audio effects menu navigation
- Understanding of frequency-based audio enhancement
- Equalizer band adjustment
- Settings persistence
- Audio problem diagnosis

## Controls

- **Menu**: Tools → Effects and Filters (Ctrl+E)
- **Audio Effects Tab**: Select Equalizer checkbox
- **Sliders**: Adjust 10 frequency bands
- **Save**: Equalizer settings auto-save to config

## Tips

- Human speech intelligibility is centered around 1-4 kHz
- Low frequency rumble is typically below 200 Hz
- Each band adjustment is in decibels (dB)
- Negative values reduce, positive values boost