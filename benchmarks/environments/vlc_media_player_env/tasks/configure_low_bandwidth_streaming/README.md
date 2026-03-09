# Configure Low-Bandwidth Streaming Task

**Difficulty**: 🟡 Medium  
**Skills**: Advanced preferences navigation, network configuration, performance optimization  
**Duration**: 180 seconds  
**Steps**: ~40

## Objective

Configure VLC Media Player to handle streaming video on slow/unstable internet connections by increasing the network cache buffer to at least 5 seconds (5000ms).

## Real-World Scenario

You're staying at a rural cabin with poor internet connectivity (1-2 Mbps). You want to watch streaming video, but with default VLC settings, the video buffers constantly every 5-10 seconds. You need to configure VLC's network caching settings to build up a larger buffer before playback starts, allowing smoother viewing despite the slow connection.

## Task Description

The agent must:
1. Open VLC's advanced preferences
2. Navigate to network caching settings
3. Increase the network cache from default (1000ms) to ≥5000ms
4. Save the configuration

## Expected Results

- Network cache set to ≥5000 milliseconds in VLC config
- Settings persisted to `~/.config/vlc/vlcrc`
- Configuration parameter `network-caching` ≥ 5000

## Verification Criteria

1. ✅ **Config Accessible**: VLC config file parsed successfully
2. ✅ **Cache Increased**: network-caching parameter ≥ 5000ms
3. ✅ **Settings Saved**: Changes persisted to config file

**Pass Threshold**: 70%

## Skills Tested

- Advanced preferences navigation (switching from Simple to All mode)
- Menu system understanding
- Network performance concepts
- Settings persistence understanding
- Problem-solving for real-world connectivity issues

## Navigation Path

1. **Open Preferences**: Tools → Preferences (or Ctrl+P)
2. **Switch to Advanced**: Click "All" button at bottom-left
3. **Navigate to Network**: Input / Codecs → Network (in left sidebar)
4. **Modify Cache**: Find "Network caching (ms)" field, change to 5000+
5. **Save**: Click "Save" button at bottom

## Alternative Approaches

- **Direct config edit**: Edit `~/.config/vlc/vlcrc` and add/modify `network-caching=5000`
- **Command-line test**: Launch VLC with `--network-caching=5000` flag (temporary)

## Notes

- Default network-caching is typically 1000ms
- Values are in milliseconds
- Higher values = more buffering before playback = smoother playback on slow connections
- Trade-off: Higher cache = longer initial buffering time