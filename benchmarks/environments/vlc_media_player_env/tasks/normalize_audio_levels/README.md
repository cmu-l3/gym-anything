# Volume Normalization Task

**Difficulty**: 🟡 Medium  
**Skills**: Audio effects, configuration persistence, problem-solving  
**Duration**: 180 seconds  
**Steps**: ~40

## Objective

Enable VLC's audio normalization or dynamic range compression to handle videos with drastically different volume levels consistently.

## Real-World Scenario

You've downloaded two educational video lectures from different sources. The first video has extremely quiet audio (requires volume at 180% to hear clearly), while the second video is much louder (comfortable at 80% volume). You're constantly frustrated by having to frantically adjust volume between videos.

**Your goal**: Configure VLC's audio settings to enable volume normalization so both videos play at consistent, comfortable volume levels without manual adjustment.

## Task Description

The agent must:
1. Launch VLC and understand the volume inconsistency problem
2. Navigate to audio effects/filters settings
3. Enable audio normalization or dynamic range compression
4. Ensure settings persist to VLC configuration file

## Expected Results

- VLC config shows audio filter enabled (e.g., `compressor`, `normvol`)
- Settings persisted to `~/.config/vlc/vlcrc`
- Audio normalization/compression is active

## Verification Criteria

1. ✅ **Config Accessible**: VLC config file parsed successfully
2. ✅ **Audio Filter Enabled**: Relevant audio filter present in config
3. ✅ **Valid Configuration**: Filter settings are properly configured

**Pass Threshold**: 70%

## Skills Tested

- Advanced menu navigation (Tools → Effects and Filters)
- Understanding audio concepts (normalization, compression, dynamic range)
- Configuration persistence knowledge
- Real-world problem diagnosis and solution
- Feature discovery in complex software

## Solution Approaches

### Approach 1: Audio Compressor
1. Open **Tools → Effects and Filters** (Ctrl+E)
2. Go to **Audio Effects** tab
3. Enable **Compressor** checkbox
4. Adjust settings (ratio, threshold, etc.)
5. Ensure settings save to preferences

### Approach 2: Volume Normalizer
1. Open **Tools → Preferences** (Ctrl+P)
2. Switch to **All** settings (bottom left)
3. Navigate to **Audio → Filters**
4. Enable **Volume normalizer**
5. Configure max level
6. Save preferences

### Approach 3: Preferences-Based
1. Open **Tools → Preferences**
2. Go to **Audio** section
3. Look for normalization or compression options
4. Enable and configure

## Controls

- **Menu**: Tools → Effects and Filters (Ctrl+E)
- **Menu**: Tools → Preferences (Ctrl+P)
- **Audio Effects**: Compressor, Normalizer panels
- **Keyboard**: Navigate with Tab, Enter, Arrow keys

## Test Videos

- `/home/ga/Videos/lectures/lecture_quiet.mp4` - Very quiet audio (-18dB)
- `/home/ga/Videos/lectures/lecture_normal.mp4` - Normal audio (0dB)

## Notes

The task tests whether the agent can discover and configure advanced audio features that aren't immediately obvious. Multiple solutions are acceptable as long as audio normalization/compression is properly enabled and persisted.