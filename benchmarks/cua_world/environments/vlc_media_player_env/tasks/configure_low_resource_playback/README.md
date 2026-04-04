# Configure Low Resource Playback Task

**Difficulty**: 🟡 Medium  
**Skills**: Performance optimization, settings navigation, hardware understanding  
**Duration**: 300 seconds  
**Steps**: ~40

## Objective

Configure VLC Media Player settings to enable smooth playback of high-quality video (1080p) on resource-constrained hardware by optimizing performance-related settings.

## Task Description

The agent must:
1. Open VLC with a 1080p test video
2. Navigate to advanced preferences (Tools → Preferences → Show All)
3. Enable hardware-accelerated decoding
4. Configure frame skipping to prevent stuttering
5. Select lightweight video output module
6. Adjust cache settings to reduce memory usage
7. Disable video filters that consume CPU
8. Save preferences

## Expected Results

- Hardware acceleration enabled (most critical)
- Frame skipping configured
- Lightweight video output selected
- Cache settings optimized
- Video filters disabled
- Settings persisted to VLC config file

## Verification Criteria

1. ✅ **Hardware Acceleration**: Enabled (avcodec-hw=any/auto)
2. ✅ **Frame Skipping**: Enabled (skip-frames=1)
3. ✅ **Video Output**: Lightweight module selected
4. ✅ **Cache Reduced**: File caching < 500ms
5. ✅ **Filters Disabled**: No active video filters
6. ✅ **Skip Late Frames**: Enabled
7. ✅ **Deinterlacing**: Disabled

**Pass Threshold**: 70% (weighted scoring, need ~5/7 criteria)

## Skills Tested

- Advanced preferences navigation
- Understanding of hardware acceleration
- Performance optimization knowledge
- Settings persistence understanding
- Trade-off decision making (quality vs. performance)

## Controls

- **Menu**: Tools → Preferences (Ctrl+P)
- **Show All**: Click "All" radio button at bottom left
- **Navigate**: Click through Input/Codecs, Video sections
- **Save**: Click "Save" button

## Real-World Context

User trying to watch high-quality video on older laptop. Video stutters and drops frames. Need to configure VLC to prioritize smooth playback over maximum quality. Common for students with budget laptops or users with older hardware.

## Notes

Hardware acceleration options vary by platform:
- Linux: VA-API, VDPAU
- Windows: DXVA2, D3D11
- macOS: VideoToolbox

Setting to "Automatic" or "any" works across platforms.