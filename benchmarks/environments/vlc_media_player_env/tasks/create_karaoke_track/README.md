# Create Karaoke Track Task

**Difficulty**: 🟡 Medium  
**Skills**: Audio filter configuration, media conversion, audio effects  
**Duration**: 90-120 seconds  
**Steps**: ~40

## Objective

Create a karaoke version of a song by reducing center-channel vocals using VLC's audio filters and exporting the result.

## Scenario

Maya is preparing for an open mic night and needs to create a karaoke version of her practice song. She wants to reduce the original vocals so she can hear herself better when practicing.

## Task Description

The agent must:
1. Open the music file at `/home/ga/Music/practice_song.mp3`
2. Apply audio filtering to reduce center-channel content (where vocals typically reside)
3. Convert and save the filtered audio to `/home/ga/Music/karaoke_version.mp3`
4. The output should have noticeably reduced vocal presence

## Expected Results

- Karaoke version created at `/home/ga/Music/karaoke_version.mp3`
- File is valid MP3 audio with similar duration to input (~30 seconds)
- File maintains stereo format (2 channels)
- Output file size indicates actual audio content (>50 KB)

## Verification Criteria

1. ✅ **File Exists**: Karaoke version file found (30%)
2. ✅ **Valid Audio**: File has correct codec and format (30%)
3. ✅ **Duration Match**: Duration approximately matches input (20%)
4. ✅ **Stereo Output**: Maintains 2 channels (20%)

**Pass Threshold**: 80%

## Skills Tested

- Audio effects menu navigation (Tools → Effects and Filters)
- Understanding of stereo audio concepts (center channel)
- Media conversion workflow (Media → Convert/Save)
- Audio filter configuration
- File format selection

## How to Complete

### Method 1: Using Effects + Conversion
1. Open VLC Media Player
2. Open `/home/ga/Music/practice_song.mp3`
3. Go to Tools → Effects and Filters (Ctrl+E)
4. Navigate to Audio Effects → Spatializer
5. Enable "Headphone virtualization" or use Channel Mixer to invert/combine channels
6. Go to Media → Convert/Save (Ctrl+R)
7. Add the practice_song.mp3
8. Select audio profile (e.g., Audio - MP3)
9. Set destination to `/home/ga/Music/karaoke_version.mp3`
10. Start conversion

### Method 2: Using Convert/Save with Filters
1. Go to Media → Convert/Save (Ctrl+R)
2. Add `/home/ga/Music/practice_song.mp3`
3. Click "Convert/Save" button
4. In profile settings, edit to include audio filters
5. Set destination to `/home/ga/Music/karaoke_version.mp3`
6. Start conversion

## Technical Notes

**Vocal Removal Theory**:
- In stereo mixes, lead vocals are typically centered (identical in L+R channels)
- Instruments are often panned (different in L+R channels)
- Subtracting L-R or phase manipulation can reduce center content
- VLC's headphone spatializer or channel mixer can achieve this

**VLC Audio Filters**:
- Headphone virtualization with specific settings
- Channel mixer with custom pan values
- Stereo widener

## Controls

- `Ctrl+E`: Open Effects and Filters
- `Ctrl+R`: Open Convert/Save dialog
- `Ctrl+O`: Open media file