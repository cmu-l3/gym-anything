# Extract Audio from Video Task

**Difficulty**: 🟡 Medium  
**Skills**: Media conversion, audio extraction, format understanding  
**Duration**: 180 seconds  
**Steps**: ~40

## Objective

Extract the audio track from a video file and save it as an MP3 file with specific quality settings (192 kbps bitrate).

## Task Description

The agent must:
1. Open VLC's Convert/Save dialog (Media → Convert/Save or Ctrl+R)
2. Add the source video file `/home/ga/Videos/band_practice.mp4`
3. Configure conversion to extract audio only as MP3
4. Set bitrate to 192 kbps
5. Save output to `/home/ga/Music/extracted/practice_audio.mp3`
6. Complete the conversion

## Real-World Scenario

🎸 You recorded your band's practice session on your phone. The video quality is poor (shaky camera, dim lighting), but the audio captured is surprisingly good. You want to extract just the audio track to share with bandmates on Discord and potentially upload to SoundCloud as a demo.

## Expected Results

- MP3 file created at `/home/ga/Music/extracted/practice_audio.mp3`
- Audio-only format (no video stream)
- Bitrate: 192 kbps (±10 kbps tolerance)
- Stereo audio (2 channels)
- Duration matches source video (~45 seconds)
- File is valid and playable

## Verification Criteria

1. ✅ **File Exists**: Output MP3 file found at correct path
2. ✅ **Audio Format**: Codec is MP3, no video stream present
3. ✅ **Bitrate Correct**: Audio bitrate within 180-204 kbps range
4. ✅ **Duration Match**: Duration matches source (±1 second)
5. ✅ **File Valid**: File is playable and not corrupted

**Pass Threshold**: 75%

## Skills Tested

- Media menu navigation (Convert/Save feature)
- File browser interaction (source and destination selection)
- Profile configuration (audio codec, bitrate settings)
- Understanding of audio formats and codecs
- Quality settings comprehension (bitrate implications)
- Multi-step workflow execution

## Controls

### GUI Method (Recommended):
1. **Media → Convert/Save** (or `Ctrl+R`)
2. **Add...** button to select source video
3. **Convert** from dropdown menu
4. **Browse** to set destination path
5. **Profile**: Select "Audio - MP3" or customize settings
6. **Start** to begin extraction

### Profile Customization:
- Click wrench icon (🔧) next to Profile dropdown
- Enable "Audio" codec tab
- Set Codec: MP3
- Set Bitrate: 192 kb/s
- Set Channels: 2 (Stereo)

## Notes

- Conversion time: ~10-30 seconds for a 45-second video
- Watch progress bar at bottom of VLC window
- Do NOT select video profiles - audio-only extraction required
- Output directory `/home/ga/Music/extracted/` will be created automatically
- Bitrate affects file size: 192 kbps ≈ 1 MB per minute of audio