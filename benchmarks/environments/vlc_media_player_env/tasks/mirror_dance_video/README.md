# Mirror Dance Video Task

**Difficulty**: 🟡 Medium  
**Skills**: Video transformation, geometry effects, conversion  
**Duration**: 3-5 minutes  
**Steps**: ~50

## Objective

Transform a dance instruction video by rotating it 90° clockwise and horizontally flipping it for mirror-following, then save the transformed result.

## Real-World Context

Dance instructors often record demonstrations for students to practice at home. However, unmodified videos create "mirror confusion"—when the instructor moves right, students instinctively mirror incorrectly. The solution is to horizontally flip the video so it appears as if students are looking in a mirror.

Additionally, phone recordings often have orientation issues that need correction before distribution.

## Task Description

The agent must:
1. Open the video file `/home/ga/Videos/dance_demo.mp4` (45 seconds, portrait orientation)
2. Apply video transformations:
   - Rotate 90° clockwise to fix orientation
   - Horizontally flip (mirror) for instruction use
3. Convert and save with transformations to `/home/ga/Videos/dance_demo_mirrored.mp4`

## Expected Results

- Output video file created at target location
- Video rotated from portrait to landscape orientation
- Video horizontally flipped
- Valid video properties (duration ~45s, resolution ~1280x720)

## Verification Criteria

1. ✅ **File Exists**: Output video file found
2. ✅ **Duration Correct**: Video duration matches original (~45s ±2s)
3. ✅ **Resolution Changed**: Video resolution indicates rotation (landscape ~1280x720)
4. ✅ **Valid Video**: Video has valid codec and properties

**Pass Threshold**: 70%

## Skills Tested

- Effects and Filters menu navigation
- Geometry transformations (rotate, flip/mirror)
- Video conversion with effects applied
- Understanding of video orientation
- Multi-step workflow execution

## Controls

- **Effects**: Tools → Effects and Filters (Ctrl+E) → Video Effects → Geometry
- **Rotate**: Transform dropdown or Rotate dial
- **Mirror**: Transform checkbox with mirror/flip option
- **Convert**: Media → Convert/Save (Ctrl+R)

## Workflow Steps

1. Open video in VLC (or VLC launches with it)
2. Open Tools → Effects and Filters (Ctrl+E)
3. Go to Video Effects → Geometry tab
4. Enable and apply:
   - Transform: Rotate by 90 degrees (clockwise)
   - Transform: Mirror or Flip horizontally
5. Close effects dialog
6. Open Media → Convert/Save (Ctrl+R)
7. Add source file (already open)
8. Choose profile (e.g., H.264 + MP3)
9. Set destination: `/home/ga/Videos/dance_demo_mirrored.mp4`
10. **Important**: Ensure effects are applied during conversion
11. Start conversion and wait for completion

## Notes

- The source video is in portrait orientation (720x1280)
- After 90° clockwise rotation, it should become landscape (~1280x720)
- Horizontal flip is applied for dance instruction purposes
- Conversion may take 30-60 seconds for a 45-second video