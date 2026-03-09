# Stabilize Shaky Video Task

**Difficulty**: 🟡 Medium  
**Skills**: Video filters, effects navigation, real-time processing  
**Duration**: 90 seconds  
**Steps**: ~35

## Objective

Enable VLC's video stabilization filter to watch shaky smartphone footage with real-time motion smoothing.

## Real-World Context

A parent recorded their child's first steps but the video is extremely shaky from walking while filming. The family gets motion-sick watching it. Enable VLC's stabilization filter to smooth out the camera shake during playback without re-encoding.

## Task Description

The agent must:
1. VLC launches with a shaky video file
2. Navigate to Effects and Filters menu (Tools → Effects and Filters)
3. Enable video stabilization/transform filter
4. Verify filter is active and persisted in config

## Expected Results

- Video filter enabled in VLC config
- Filter includes stabilization (transform/stabilize/motion keywords)
- Configuration persists for future playback

## Verification Criteria

1. ✅ **Config Accessible**: VLC config file found and parsed
2. ✅ **Filter Present**: Video filter setting exists
3. ✅ **Stabilization Active**: Filter contains stabilization keywords

**Pass Threshold**: 70%

## Skills Tested

- Effects and Filters menu navigation (Tools → Effects and Filters)
- Video Effects tab understanding
- Geometry/Transform filter activation
- Persistent configuration understanding

## Controls

- **Menu**: Tools → Effects and Filters (Ctrl+E)
- **Video Effects tab**: Click "Geometry" sub-tab
- **Enable**: Check "Transform" or similar filter
- **Apply**: Changes persist automatically

## Notes

VLC can apply stabilization in real-time during playback without re-encoding. The filter setting is stored in `vlcrc` configuration file as `video-filter=transform` or similar.