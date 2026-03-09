# Configure Buffer for Network Storage Task

**Difficulty**: 🟡 Medium  
**Skills**: VLC preferences navigation, buffering configuration, network troubleshooting  
**Duration**: 120 seconds  
**Steps**: ~40

## Objective

Configure VLC's file caching buffer to enable smooth playback of large video files stored on network storage (NAS, cloud mounts, SMB shares). The default 300ms cache causes stuttering with high-bitrate files over network.

## Task Description

The agent must:
1. VLC launches with default cache settings (300ms file caching)
2. Navigate to VLC preferences
3. Increase file caching to at least 3000ms (3 seconds)
4. Save configuration

## Expected Results

- VLC config file (`vlcrc`) updated with new cache value
- file-caching set to 3000ms or higher (up to 60000ms)
- Configuration persists after closing VLC

## Verification Criteria

1. ✅ **Config Accessible**: VLC config file parsed successfully
2. ✅ **Cache Increased**: file-caching value changed from default (300ms)
3. ✅ **Appropriate Value**: Cache set between 3000-60000ms

**Pass Threshold**: 65%

## Real-World Context

This task simulates a freelance video editor working with 4K footage stored on company NAS over WiFi. Default VLC settings cause constant stuttering. Increasing the file cache creates a buffer that absorbs network slowdowns.

## Skills Tested

- Advanced preferences navigation (Show All settings)
- Understanding of buffering/caching concepts
- File I/O optimization knowledge
- Configuration file management

## Controls

### GUI Approach
1. **Tools → Preferences** (or `Ctrl+P`)
2. **Show settings: All** (bottom-left button)
3. **Input / Codecs → Advanced**
4. Find **File caching (ms)**
5. Change from 300 to 3000 or higher
6. Click **Save**

### Config File Approach
1. Edit `~/.config/vlc/vlcrc`
2. Find or add: `file-caching=3000`
3. Save and close VLC to persist

## Notes

- VLC cache range: 0-65535ms
- Default file-caching: 300ms (suitable for local SSD)
- Network storage recommended: 3000-10000ms
- Very large files or slow networks: 10000-60000ms
- Changes require VLC restart to take effect