# Verify Recording Framerate Task

**Difficulty**: 🟡 Medium  
**Skills**: Media analysis, diagnostic tools, frame rate verification  
**Duration**: 120 seconds  
**Steps**: ~25

## Objective

Analyze a recorded gameplay video to verify its frame rate consistency using VLC Media Player's diagnostic and codec information features.

## Task Description

The agent must:
1. Open the gameplay recording in VLC Media Player
2. Access VLC's codec information or diagnostic messages
3. Extract frame rate data from VLC's technical information
4. Export/save diagnostic information showing:
   - The video's frame rate (should be 60 FPS)
   - Codec details and stream information
   - Frame rate consistency data (constant vs variable)
5. Save analysis to a text file for documentation

## Expected Results

- Analysis file created (e.g., `recording_analysis.txt`)
- File contains frame rate information (60 FPS)
- File contains codec or stream technical details
- Evidence of VLC's diagnostic tools being used

## Verification Criteria

1. ✅ **Analysis File Exists**: Text/log file with diagnostic info found
2. ✅ **Frame Rate Mentioned**: Analysis contains frame rate data
3. ✅ **Correct FPS Value**: Mentions 60 FPS (±1 FPS tolerance)
4. ✅ **Diagnostic Data**: Contains codec info or technical details

**Pass Threshold**: 70%

## Skills Tested

- VLC diagnostic tools navigation (Tools → Codec Information, Tools → Messages)
- Understanding of video technical properties
- Information extraction and documentation
- Frame rate analysis concepts

## Common Approaches

### Approach 1: Codec Information
1. Open video in VLC
2. Go to `Tools → Media Information` (Ctrl+I)
3. Click "Codec Details" tab
4. Copy frame rate, codec, resolution info
5. Save to text file

### Approach 2: VLC Messages
1. Open video in VLC
2. Go to `Tools → Messages` (Ctrl+M)
3. Set verbosity to "Debug" (level 2)
4. Let video play briefly
5. Save message log showing stream info

### Approach 3: CLI Analysis
1. Use `ffprobe` or `mediainfo` CLI tools
2. Extract technical specs
3. Document findings

## Controls

- **Ctrl+I**: Media Information
- **Ctrl+M**: Messages (debug log)
- **Tools menu**: Access diagnostic features

## Notes

This task simulates a real content creator workflow: verifying recording quality before investing time in editing. Frame drops or variable frame rate can ruin hours of editing work.