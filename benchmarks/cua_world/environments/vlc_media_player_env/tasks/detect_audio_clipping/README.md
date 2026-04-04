# Detect Audio Clipping Task

**Difficulty**: 🟡 Medium  
**Skills**: Audio analysis, visualization, quality control, documentation  
**Duration**: 90 seconds  
**Steps**: ~35

## Objective

Analyze an audio recording to detect clipping/distortion using VLC's audio visualization features and document findings for quality control before mixing.

## Scenario

You're a bedroom music producer who just recorded a guitar track. Before spending hours mixing, you need to check if the input gain was too high, causing clipping (digital distortion). Use VLC to analyze the audio and determine if re-recording is needed.

## Task Description

The agent must:
1. Open the audio file `/home/ga/Music/recordings/guitar_take_01.wav` in VLC
2. Enable audio visualization features (spectrum, level meters, etc.)
3. Play through the file and observe if audio peaks reach 0 dBFS (clipping)
4. Document findings in `/home/ga/Music/recordings/guitar_take_01_analysis.txt` with:
   - Whether clipping was detected (YES/NO)
   - Approximate timestamps where clipping occurs
   - Peak level reached (e.g., "0 dBFS - CLIPPING" or "-3.2 dBFS - OK")
   - Recommendation: "SAFE TO MIX" or "NEEDS RE-RECORDING"

## Expected Results

- Analysis file created with correct clipping detection
- Clipping correctly identified in middle section (10-15 seconds)
- Recommendation matches severity (NEEDS RE-RECORDING for this file)

## Verification Criteria

1. ✅ **Analysis File Created**: File exists at expected location
2. ✅ **Clipping Detection Correct**: Agent correctly identifies clipping presence
3. ✅ **Timestamp Information**: Approximate timing of clipping provided
4. ✅ **Peak Level Mentioned**: Audio level information included
5. ✅ **Recommendation Provided**: Actionable advice given

**Pass Threshold**: 70%

## Skills Tested

- Audio visualization feature navigation
- Understanding of audio levels and clipping
- Waveform/spectrum analysis
- Quality control documentation
- Professional workflow understanding

## Controls

- **Menu**: Tools → Effects and Filters → Audio Effects → Visualizations
- **Menu**: View → Visualizations (various options)
- **Advanced Controls**: View → Advanced Controls (shows audio levels)
- **Keyboard**: `Space` - Play/Pause, `Shift+Right` - Jump forward 5s

## Notes

Clipping occurs when audio signal exceeds 0 dBFS (digital full scale), causing harsh distortion. Professional recordings maintain peak levels at -3 to -6 dBFS for headroom. This task tests both technical understanding and documentation skills essential for audio production workflows.