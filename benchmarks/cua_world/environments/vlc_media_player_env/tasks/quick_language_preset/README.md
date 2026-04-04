# Quick Language Preset Task

**Difficulty**: 🟡 Medium  
**Skills**: Multi-language navigation, preset configuration, accessibility  
**Duration**: 90 seconds  
**Steps**: ~35

## Objective

Create quick-switch language presets for a multi-language household, allowing family members to easily switch between different audio/subtitle configurations.

## Task Description

The agent must:
1. Open a video with multiple audio and subtitle tracks
2. Create three language preset configurations:
   - **Preset A (Grandparents)**: Spanish audio, no subtitles
   - **Preset B (Children)**: English audio, Spanish subtitles
   - **Preset C (Parents)**: English audio, no subtitles
3. Document the presets in `/home/ga/Videos/language_presets.txt`
4. Test each preset configuration

## Expected Results

- Presets file created with all three configurations documented
- Clear documentation of audio and subtitle track settings
- Format: `Preset X: audio_track=N, subtitle_track=M`

## Verification Criteria

1. ✅ **Presets File Exists**: Documentation file created
2. ✅ **All Presets Documented**: Three presets (A, B, C) present
3. ✅ **Correct Configuration**: Track numbers match requirements

**Pass Threshold**: 70%

## Skills Tested

- Multi-track audio navigation
- Subtitle track management
- Configuration documentation
- Understanding of track indexing
- Real-world accessibility problem-solving

## Controls

- **Audio Menu**: Audio → Audio Track
- **Subtitle Menu**: Subtitle → Subtitle Track
- **Keyboard**:
  - `B`: Cycle audio tracks
  - `V`: Cycle subtitle tracks

## Scenario

Maria's trilingual household needs quick switching between:
- Spanish audio for visiting grandparents
- English audio + Spanish subtitles for children learning Spanish
- English audio without distractions for adults

This task simulates a real multilingual family's needs.