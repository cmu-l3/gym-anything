# Diagnose Playback Issue Task

**Difficulty**: 🟡 Medium  
**Skills**: Diagnostic tools, technical analysis, documentation  
**Duration**: 90 seconds  
**Steps**: ~35

## Objective

Diagnose a playback issue with a problematic video file using VLC's diagnostic tools and create a structured technical report.

## Task Description

The agent must:
1. VLC launches with a problematic video file
2. Use VLC's diagnostic tools to identify the issue
3. Access Codec Information (Tools → Codec Information or Ctrl+J)
4. Access Messages/Logs (Tools → Messages or Ctrl+M)
5. Extract technical specifications
6. Create a diagnostic report documenting findings

## Human Context

This simulates remote tech support: A non-technical user reports their video "isn't working right" but can't articulate the specific problem. You must systematically diagnose the issue using VLC's tools and document findings in a technical report they can share or use to find solutions.

## Expected Results

- Diagnostic report created at `/home/ga/Documents/diagnostic_report.txt`
- Report contains:
  - File reference and path
  - Container format information
  - Video codec, resolution, framerate
  - Audio codec and track information (or lack thereof)
  - Error messages or warnings
  - Problem description and recommendations

## Verification Criteria

1. ✅ **Report Exists**: Diagnostic report file found
2. ✅ **File Reference**: Report mentions the problem video file
3. ✅ **Container Format**: Report includes format information
4. ✅ **Video Codec**: Report includes video codec details
5. ✅ **Resolution**: Report includes resolution information
6. ✅ **Audio Issue**: Report identifies the audio problem (missing audio track)
7. ✅ **Recommendation**: Report includes problem description or recommendation

**Pass Threshold**: 70% (5/7 criteria or equivalent)

## Skills Tested

- VLC diagnostic tool navigation
- Technical information extraction
- Understanding of media specifications
- Systematic troubleshooting approach
- Technical documentation
- Problem identification

## Controls

- **Ctrl+J**: Open Codec Information
- **Ctrl+M**: Open Messages window
- **Tools → Codec Information**: View codec details
- **Tools → Messages**: View log messages

## Notes

The problem video has been created with NO audio track, simulating a common download/conversion issue. The agent should identify this through systematic use of VLC's diagnostic tools.