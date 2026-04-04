# Batch Verify Media Integrity Task

**Difficulty**: 🟡 Medium  
**Skills**: Quality control workflow, systematic testing, file organization  
**Duration**: 120 seconds  
**Steps**: ~60

## Objective

Test multiple video files for playback issues and organize the working files into a separate directory while documenting the results.

## Task Description

**Scenario**: You've downloaded 4 movies for your parents and need to verify they all work before putting them on a USB drive. One file may be corrupted from interrupted downloads.

The agent must:
1. Test each video file in `/home/ga/Videos/to_verify/` by playing it
2. Identify which files play correctly vs. which are corrupted
3. Copy/move only working files to `/home/ga/Videos/verified_good/`
4. Create a verification report documenting results

## Expected Results

- Directory `/home/ga/Videos/verified_good/` contains only working files (3 files)
- Corrupted file (`movie_3.avi`) is excluded from verified directory
- Verification report created at `/home/ga/Videos/verification_report.txt`

## Verification Criteria

1. ✅ **Verified Directory Exists** (10 points)
2. ✅ **Correct Files Copied** (50 points)
   - movie_1.mp4 present (15 pts)
   - movie_2.mkv present (15 pts)
   - movie_4.mp4 present (20 pts)
3. ✅ **Corrupted File Excluded** (20 points)
4. ✅ **Verification Report Created** (20 points)

**Pass Threshold**: 70%

## Skills Tested

- Systematic file testing workflow
- Media playback troubleshooting
- File organization and management
- Quality control processes
- Documentation and reporting

## Controls

- **VLC Playback**: Open each file and test
- **File Manager**: Copy/move files between directories
- **Text Editor**: Create verification report
- **Keyboard**: Ctrl+O (open file), Ctrl+Q (quit)

## Notes

This task simulates a real-world quality control workflow where you need to systematically test multiple files before distribution. The corrupted file (`movie_3.avi`) will show obvious playback issues.