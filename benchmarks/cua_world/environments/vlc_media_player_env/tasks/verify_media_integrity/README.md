# Verify Media Integrity Task

**Difficulty**: 🟡 Medium  
**Skills**: Media information analysis, quality assurance, documentation  
**Duration**: 90 seconds  
**Steps**: ~35

## Objective

Verify that a video file matches its claimed technical specifications by using VLC's Media Information tools to inspect actual properties and document findings in a verification report.

## Task Description

The agent must:
1. Open the test video file in VLC
2. Access Media Information dialog (Tools → Media Information or Ctrl+I)
3. Inspect technical specifications (resolution, codec, duration)
4. Compare against expected specifications
5. Create a verification report documenting findings
6. Make pass/fail determination based on comparison

## Scenario

You're organizing your film club's media library. A member contributed a video labeled as "1080p HD lecture recording" but the file size seems suspicious. Before adding it to the shared collection, you need to verify the actual specifications match what's claimed.

## Expected Specifications

The file `/home/ga/Videos/verification/expected_specs.txt` contains:
- Resolution: 1920x1080 (1080p)
- Duration: 60 seconds (±5 seconds)
- Video Codec: H.264
- File Size: >50 MB

## Expected Results

- Verification report created at `/home/ga/Documents/verification_report.txt`
- Report contains actual resolution, codec, and duration
- Pass/fail determination based on spec comparison
- Documentation is clear and structured

## Verification Criteria

1. ✅ **Report Created** (15 points): Verification report file exists and is non-empty
2. ✅ **Resolution Documented** (25 points): Report contains actual video resolution
3. ✅ **Codec Documented** (20 points): Report contains video codec information
4. ✅ **Duration Documented** (20 points): Report contains video duration
5. ✅ **Correct Determination** (20 points): Pass/fail status matches actual spec comparison

**Pass Threshold**: 70% (requires report + at least 3 specs documented accurately)

## Skills Tested

- VLC Media Information dialog navigation
- Understanding technical video specifications
- Comparing expected vs actual properties
- Creating structured documentation
- Making quality assurance decisions
- Identifying specification mismatches

## Controls

- **Menu**: Tools → Media Information (or Ctrl+I)
- **Tabs**: General, Codec Information, Statistics
- **Report**: Text file at `/home/ga/Documents/verification_report.txt`

## Notes

The test video intentionally has mismatched specifications to simulate a real-world scenario where files don't match their claimed properties. The agent must correctly identify this and mark the verification as "FAIL".