# 📻 Prepare Mono Broadcast Audio (`prepare_mono_broadcast@1`)

## Task Overview

Convert a stereo audio file to mono format suitable for AM radio broadcast.

**Difficulty**: 🟡 Easy-Medium  
**Category**: Audio Conversion & Processing  
**Estimated Time**: 3-5 minutes  
**Skills**: Audio format understanding, VLC conversion, broadcast standards

## Real-World Context

You're a volunteer at a community radio station preparing the "Local Voices" segment. A listener submitted a beautiful acoustic guitar recording in stereo, but your AM transmitter only supports mono audio. Stereo broadcasts cause phase cancellation issues that make audio sound terrible on air. You need to convert this to proper mono before it can be broadcast.

## Task Description

**Input**: 
- Stereo audio file: `/home/ga/Music/submissions/listener_recording.wav`
- 2 channels (stereo), 44.1kHz, ~30 seconds

**Goal**: 
Convert the stereo audio to mono and save as: `/home/ga/Music/broadcast_ready/listener_recording_mono.wav`

**Requirements**:
- Output must be 1 channel (mono), not 2 channels (stereo)
- Audio quality should be preserved
- Output format should be WAV

## Why This Matters

- **AM Radio**: AM transmission is inherently mono - stereo information is lost/distorted
- **Phase Issues**: Improper stereo-to-mono conversion can cause cancellation
- **Bandwidth**: Mono files use half the bandwidth of stereo for streaming
- **Standards**: Professional broadcast requires format compliance

## Approach Hints

### Using VLC GUI:
1. Open VLC Media Player
2. Go to Media → Convert/Save (Ctrl+R)
3. Click "Add" button to add the input file
4. Browse to `/home/ga/Music/submissions/listener_recording.wav`
5. Click "Convert/Save" button at bottom
6. In the profile dropdown, select a profile or create custom profile:
   - Click the wrench icon to edit profile
   - Go to "Audio codec" tab
   - Set Channels: 1 (mono)
   - Codec: PCM/WAV
7. Set destination file: `/home/ga/Music/broadcast_ready/listener_recording_mono.wav`
8. Click "Start" to begin conversion

### Using VLC CLI (Advanced):