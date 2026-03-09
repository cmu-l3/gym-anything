# Verify Recording Settings Task

**Difficulty**: 🟡 Easy-Medium  
**Skills**: Media analysis, codec information, technical verification, report generation  
**Duration**: 3-5 minutes  
**Steps**: ~40

## Objective

Verify that a test video file was recorded with specific camera settings before an important shoot by checking its technical specifications using VLC Media Player.

## Human Context

**Scenario**: Marcus is a wedding videographer who just upgraded to a new camera. He recorded a test clip at what he thought were the correct settings (4K 60fps H.264) for tomorrow's wedding. The client specifically requested these specs, and Marcus needs to verify his camera is configured correctly before the event.

**Why VLC**: Marcus is on location without his editing suite, and needs to quickly check the codec information to confirm the camera settings worked as expected.

## Task Description

The agent must:
1. Open the test video `/home/ga/Videos/camera_test.mp4` in VLC
2. Access the video's technical specifications (Tools → Media Information → Codec Details)
3. Verify each specification against expected values:
   - **Resolution**: 3840x2160 (4K)
   - **Frame Rate**: 60 fps
   - **Video Codec**: H.264
   - **Bitrate**: ≥80 Mbps
4. Create a verification report at `/home/ga/Documents/recording_verification.txt` with:
   - Each specification with actual vs. expected values
   - Status indicators (✓/✗) for each specification
   - Overall verdict: "PASS" or "FAIL"

## Expected Results

- Verification report created with structured format
- All four specifications documented
- Clear pass/fail indicators for each spec
- Overall verdict based on all checks

## Verification Criteria

1. ✅ **Report Exists**: Verification report file created
2. ✅ **Specifications Documented**: All 4 specs mentioned in report
3. ✅ **Status Indicators**: Clear ✓/✗ or PASS/FAIL markers present
4. ✅ **Verdict Accuracy**: Overall verdict matches actual video specs

**Pass Threshold**: 70%

## Skills Tested

- Media Information menu navigation
- Codec Details panel interpretation
- Technical specification understanding
- Text file creation and formatting
- Quality control workflow

## Controls

- **Menu**: Tools → Media Information (Ctrl+I)
- **Tab**: Codec Details tab
- **File Manager**: Create text file with report

## Example Report Format
