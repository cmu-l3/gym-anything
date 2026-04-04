# Configure Network Cache Task

**Difficulty**: 🟡 Medium  
**Skills**: Advanced preferences navigation, performance optimization, buffer configuration  
**Duration**: 180 seconds  
**Steps**: ~40

## Objective

Configure VLC Media Player's network cache buffer settings to eliminate stuttering when playing high-bitrate media from network drives or NAS storage.

## Task Description

The agent must:
1. VLC launches with default (low) cache settings
2. Navigate to VLC's advanced preferences (not simple preferences)
3. Locate network caching settings in Input/Codecs section
4. Increase network-caching value from 300ms to 1500-3000ms (optimal range)
5. Save settings to persist configuration

## Expected Results

- VLC config file (`vlcrc`) contains increased network-caching value
- Value is within recommended range (1000-5000ms)
- Optimal range is 1500-3000ms for best balance

## Verification Criteria

1. ✅ **Config Accessible**: VLC config file parsed successfully
2. ✅ **Cache Increased**: network-caching value > 300ms (default)
3. ✅ **Optimal Range**: Value in recommended range for smooth playback

**Pass Threshold**: 70%

## Skills Tested

- Advanced preferences navigation (switching from Simple to All settings)
- Understanding of nested preference categories
- Knowledge of cache/buffer concepts
- Numeric value input and validation
- Settings persistence verification

## Controls

- **Menu**: Tools → Preferences (Ctrl+P)
- **Settings Mode**: Click "All" at bottom left to show advanced settings
- **Navigation**: Input / Codecs → Advanced
- **Parameter**: "Network caching (ms)" or "Caching value for network resources"

## Real-World Context

Users with NAS drives or high-bitrate 4K content often experience stuttering during playback because VLC's default 300ms cache is insufficient. Increasing to 1500-3000ms provides smooth playback without excessive initial buffering delay.

## Notes

- Different VLC versions may use slightly different key names (network-caching, network-cache)
- Values are in milliseconds (1000ms = 1 second)
- Too high values (>10000ms) cause long initial loading times
- This setting affects all network file playback (SMB, NFS, HTTP streams)