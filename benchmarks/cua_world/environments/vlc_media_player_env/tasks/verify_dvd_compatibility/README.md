# Verify DVD Compatibility Task

**Difficulty**: 🟡 Medium  
**Skills**: Technical analysis, media standards, report writing  
**Duration**: 180 seconds  
**Steps**: ~25

## Objective

Analyze a video file's technical specifications and create a detailed DVD compatibility report identifying whether the file meets DVD-Video standard requirements.

## Task Description

The agent must:
1. VLC launches with a video file loaded
2. Access Media Information (Tools → Media Information or Ctrl+I)
3. Analyze video properties (resolution, frame rate, codec, aspect ratio)
4. Analyze audio properties (codec, channels, bitrate)
5. Check duration fits DVD capacity
6. Write structured compatibility report to `/home/ga/Documents/dvd_compatibility_report.txt`
7. Include pass/fail for each parameter and overall assessment
8. Provide specific conversion recommendations if incompatible

## Expected Results

- Report file created with structured format
- Accurate technical specifications reported
- Correct pass/fail assessments based on DVD-Video standards
- Actionable conversion recommendations if needed

## DVD-Video Standards

**Video:**
- Resolution: 720×480 (NTSC) or 720×576 (PAL)
- Frame Rate: 29.97 fps (NTSC) or 25 fps (PAL)
- Codec: MPEG-2

**Audio:**
- Codec: AC3 (Dolby Digital), MP2, or LPCM
- Channels: Stereo or 5.1
- Bitrate: AC3 ≤448 kbps, MP2 ≤384 kbps

**Capacity:**
- Single-layer: ~120 minutes
- Dual-layer: ~240 minutes

## Verification Criteria

1. ✅ **Report Created**: File exists with 200+ characters
2. ✅ **Structure Present**: Contains VIDEO, AUDIO, DURATION, OVERALL sections
3. ✅ **Accurate Resolution**: Reports actual resolution within ±5 pixels
4. ✅ **Accurate Codec**: Reports actual video/audio codecs correctly
5. ✅ **Accurate Duration**: Reports duration within ±5 seconds
6. ✅ **Correct Assessment**: Pass/fail decisions match actual properties
7. ✅ **Valid Recommendations**: Provides specific conversion steps if incompatible

**Pass Threshold**: 70% (5/7 criteria)

## Skills Tested

- Media Information dialog navigation
- Technical specification interpretation
- DVD standard knowledge
- Systematic analysis
- Report writing
- Problem diagnosis

## Controls

- **Ctrl+I**: Open Media Information dialog
- **Codec Information tab**: View technical details
- **Text editor**: Write report (gedit, nano, etc.)