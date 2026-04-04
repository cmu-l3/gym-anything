# Rotate Phone Video Task

**Difficulty**: 🟡 Medium  
**Skills**: Video transform filters, geometric transformations  
**Duration**: 90-120 seconds  
**Steps**: ~40

## Objective

Rotate a sideways phone video to the correct orientation using VLC's transform/rotation filters.

## Task Description

The agent must:
1. Open a video file that is rotated 90° clockwise (sideways)
2. Navigate to VLC's video effects menu
3. Apply transform/rotation filter
4. Rotate the video 90° counter-clockwise to correct orientation

## Real-World Context

This is one of the most common frustrations with smartphone videos - someone records a video with their phone rotated incorrectly, and the video plays sideways or upside-down. VLC's transform filters allow viewing in the correct orientation without re-encoding.

## Expected Results

- Transform filter enabled in VLC configuration
- Rotation angle set to 90° counter-clockwise (or 270° clockwise)
- Video displays in correct, upright orientation

## Verification Criteria

1. ✅ **Transform Filter Enabled**: Video filter contains 'transform'
2. ✅ **Correct Rotation**: Rotation angle is 90° or 270°
3. ✅ **Config Persisted**: Settings saved in VLC configuration

**Pass Threshold**: 100% (all criteria must be met)

## Skills Tested

- Video effects menu navigation
- Transform/geometry filter usage
- Understanding geometric transformations
- Settings persistence
- Distinguishing between transform and crop/aspect ratio

## Controls

- **Menu**: Tools → Effects and Filters (Ctrl+E)
- **Video Effects tab**: Geometry sub-tab
- **Transform checkbox**: Enable rotation
- **Dropdown**: Select rotation angle

## Common Pitfalls

- Using crop instead of transform
- Applying wrong rotation angle (180° or opposite direction)
- Not enabling the transform checkbox
- Confusing aspect ratio with rotation

## Notes

This task tests the ability to apply geometric transformations to video playback. The transform is applied during playback only (non-destructive) and doesn't modify the original file.