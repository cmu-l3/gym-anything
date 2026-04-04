# Concatenate Split Recordings Task

**Difficulty**: 🟡 Medium  
**Skills**: Media concatenation, Convert/Save interface, file management  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Combine multiple video clips (representing parts of a split recording) into a single continuous video file using VLC's Convert/Save functionality.

## Task Description

The agent must:
1. VLC launches in idle state
2. Navigate to Media → Convert/Save (Ctrl+R)
3. Add three video files in correct chronological order:
   - `recording_part1.mp4`
   - `recording_part2.mp4`
   - `recording_part3.mp4`
4. Configure output to `/home/ga/Videos/complete_recording.mp4`
5. Start conversion to concatenate the files

## Real-World Context

Cameras, dash cams, and phones often split long recordings into multiple files due to:
- FAT32 file system 4GB limit
- Preventing data loss in case of crashes
- Hardware/software limitations

Users need to merge these split recordings back into one continuous file for:
- Easier sharing and uploading
- Simpler editing workflows
- Better archival organization
- Continuous viewing experience

## Expected Results

- Output file created at `/home/ga/Videos/complete_recording.mp4`
- Video duration ≈ 60 seconds (sum of 3x ~20s parts)
- Resolution: 1280x720 (matching source)
- Codec: h264 or similar
- Playable without gaps or corruption

## Verification Criteria

1. ✅ **Output Exists**: Concatenated video file found
2. ✅ **Duration Correct**: Total duration matches sum of parts (±3s)
3. ✅ **Content Complete**: Duration is at least 80% of expected
4. ✅ **Quality Preserved**: Resolution and codec are correct
5. ✅ **Playable**: File can be analyzed and would play correctly

**Pass Threshold**: 80% (4/5 criteria)

## Skills Tested

- Advanced menu navigation (Media → Convert/Save)
- Complex dialog interaction (multi-step Convert dialog)
- Multiple file selection and ordering
- Understanding file concatenation concepts
- Output path specification
- Progress monitoring and patience

## Controls

- **Menu**: Media → Convert/Save (or Ctrl+R)
- **Dialog**: Add files, select profile, set destination
- **File Browser**: Navigate to split recording directory

## Common Pitfalls

- Adding files in wrong order (3, 1, 2 instead of 1, 2, 3)
- Missing one or more files
- Wrong output path or filename
- Canceling conversion prematurely
- Choosing wrong conversion profile

## Notes

The Convert/Save dialog in VLC is complex and non-intuitive. This task tests the agent's ability to navigate multi-step workflows with delayed feedback (conversion takes time).

Source files are in: `/home/ga/Videos/split_recording/`
Output should be: `/home/ga/Videos/complete_recording.mp4`