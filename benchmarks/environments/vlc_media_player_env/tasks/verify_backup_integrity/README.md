# Verify Backup Integrity Task

**Difficulty**: 🟡 Medium  
**Skills**: File verification, metadata analysis, data safety  
**Duration**: 180 seconds  
**Steps**: ~20

## Objective

Verify that a backup copy of an important video file is complete, uncorrupted, and safe to rely on before deleting the original. This tests critical data preservation and verification skills.

## Task Description

The agent must:
1. Locate original video at `/home/ga/Videos/original/important_recording.mp4`
2. Locate backup copy at `/home/ga/Videos/backup/important_recording.mp4`
3. Compare file sizes, metadata, and playback integrity
4. Use VLC to verify both files play correctly
5. Use command-line tools (ffprobe) to compare technical properties
6. Create a verification report documenting the findings
7. Provide a clear recommendation (SAFE or NOT SAFE to delete original)

## Expected Results

- Verification report created at `/home/ga/Documents/backup_verification_report.txt`
- Report contains file size comparison
- Report contains metadata comparison (duration, resolution, codec)
- Report includes playback verification status
- Report has clear final assessment (SAFE TO DELETE ORIGINAL or NOT VERIFIED)

## Verification Criteria

1. ✅ **Report Exists**: Verification report file created
2. ✅ **Report Has Content**: Report contains meaningful analysis
3. ✅ **Metadata Comparison**: Report mentions key properties (size, duration, codec)
4. ✅ **Clear Assessment**: Report includes explicit PASS/FAIL or SAFE/NOT SAFE statement
5. ✅ **Backup Valid**: Independent verification confirms backup is playable
6. ✅ **Size Comparison**: Report mentions file size comparison
7. ✅ **Playback Tested**: Report indicates playback was verified
8. ✅ **End-to-End Check**: Report confirms file plays to completion

**Pass Threshold**: 88% (requires 7/8 criteria)

## Skills Tested

- File system navigation
- VLC playback verification
- Command-line tool usage (ffprobe, mediainfo)
- Metadata analysis and comparison
- Risk assessment and decision-making
- Technical report writing
- Data integrity verification

## Real-World Context

This task represents the critical verification step when:
- Moving large media files to external storage
- Backing up irreplaceable recordings (weddings, graduations, etc.)
- Archiving important work presentations or lectures
- Preparing to free up disk space

**Common disaster scenario:** "I copied my daughter's graduation video to an external drive and deleted the original. Six months later, the file won't play past 2 minutes. I've lost it forever."

## Recommended Verification Steps

1. **File Size Check**: