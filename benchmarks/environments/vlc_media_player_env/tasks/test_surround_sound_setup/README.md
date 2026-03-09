# VLC Surround Sound Speaker Test Task (`test_surround_sound_setup@1`)

**Difficulty**: 🟡 Medium  
**Skills**: Audio configuration, multi-channel setup, system testing, documentation  
**Duration**: 180 seconds  
**Steps**: ~40

## Objective

Configure VLC Media Player's audio output for 5.1 surround sound, play a multi-channel test file to verify speaker configuration, and document the setup in a report.

## Task Description

The agent must:
1. VLC launches with default (stereo) audio settings
2. Navigate to advanced audio preferences
3. Configure audio output for 5.1 surround (6 channels)
4. Select appropriate audio output module
5. Open and play the 5.1 test audio file
6. Create a configuration report documenting the setup

## Expected Results

- VLC configured for 6-channel (5.1) audio output
- Audio output module explicitly set (ALSA, PulseAudio, etc.)
- Test file `/home/ga/Music/test/surround_test_5.1.wav` played
- Configuration report created at `/home/ga/Documents/audio_config_report.txt`
- Report contains channel information and configuration details

## Verification Criteria

1. ✅ **Multi-Channel Config** (25%): VLC audio channels set to 6+ or surround mode
2. ✅ **Output Module** (20%): Audio output module explicitly configured
3. ✅ **Test Played** (15%): Evidence of test file playback
4. ✅ **Report Exists** (25%): Configuration report file created
5. ✅ **Report Complete** (15%): Report contains channel and config details

**Pass Threshold**: 60%

## Skills Tested

- Deep preference menu navigation
- Audio terminology understanding  
- Multi-channel configuration concepts
- System settings modification
- File creation and technical documentation
- Testing methodology

## Controls

- **Menu**: Tools → Preferences (Ctrl+P) → Show settings: All
- **Audio Section**: Audio → Output modules
- **Settings**: Audio channels, output module selection
- **File Menu**: Media → Open File to play test audio

## Notes

This task simulates real-world home theater setup troubleshooting. Users often struggle to verify their 5.1 speaker systems are correctly configured. The task requires both technical configuration and documentation skills.