# Correct Lens Distortion Task

**Difficulty**: 🟡 Medium  
**Skills**: Video geometry filters, distortion correction, snapshot capture  
**Duration**: 90-120 seconds  
**Steps**: ~40

## Objective

Apply VLC's geometry transformation filters to correct barrel/fisheye distortion from wide-angle action camera footage, then capture a snapshot to verify the correction.

## Task Description

The agent must:
1. VLC launches with a video exhibiting severe barrel distortion
2. Navigate to Effects and Filters menu
3. Enable geometry/transform filters to correct the distortion
4. Adjust parameters so straight lines appear straight
5. Capture a snapshot of the corrected video

## Expected Results

- Geometry/transform filter enabled in VLC config
- Snapshot captured at `/home/ga/Pictures/vlc/corrected_view.png`
- Snapshot shows corrected video output

## Verification Criteria

1. ✅ **Filter Enabled**: Geometry/transform filter active in VLC config
2. ✅ **Snapshot Captured**: Corrected snapshot file exists
3. ✅ **Snapshot Quality**: Image has reasonable size/quality

**Pass Threshold**: 80%

## Skills Tested

- Effects and Filters menu navigation
- Understanding video geometry transformations
- Filter parameter adjustment
- Snapshot capture at specific moment
- Settings persistence

## Controls

- **Menu**: Tools → Effects and Filters (Ctrl+E)
- **Geometry Tab**: Video Effects → Geometry
- **Transform filter**: Enable and configure
- **Snapshot**: Video → Take Snapshot (Shift+S)

## Real-World Context

Action cameras (GoPro, DJI drones) use ultra-wide lenses (120-170° FOV) that introduce barrel/fisheye distortion. Users often preview corrected footage in VLC before committing to full video processing in editing software.