#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Quick Language Preset Task ==="

kill_vlc ga
sleep 1

# Ensure Videos directory exists
mkdir -p /home/ga/Videos
chown ga:ga /home/ga/Videos

# Create multi-audio, multi-subtitle video file
echo "Creating multilingual test video..."

# Create a 10-second test video with visual indicators
ffmpeg -f lavfi -i testsrc=duration=10:size=640x480:rate=30 \
  -vf "drawtext=text='Family Movie Night':fontsize=40:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2" \
  -pix_fmt yuv420p -y /tmp/base_video.mp4 2>/dev/null

# Create audio tracks with different frequencies (for testing/debugging)
# English: 440 Hz, Spanish: 550 Hz, Portuguese: 660 Hz, French: 770 Hz
ffmpeg -f lavfi -i sine=frequency=440:duration=10 -ac 2 -y /tmp/audio_english.aac 2>/dev/null
ffmpeg -f lavfi -i sine=frequency=550:duration=10 -ac 2 -y /tmp/audio_spanish.aac 2>/dev/null
ffmpeg -f lavfi -i sine=frequency=660:duration=10 -ac 2 -y /tmp/audio_portuguese.aac 2>/dev/null
ffmpeg -f lavfi -i sine=frequency=770:duration=10 -ac 2 -y /tmp/audio_french.aac 2>/dev/null

# Combine video with multiple audio tracks
ffmpeg -i /tmp/base_video.mp4 \
  -i /tmp/audio_english.aac \
  -i /tmp/audio_spanish.aac \
  -i /tmp/audio_portuguese.aac \
  -i /tmp/audio_french.aac \
  -map 0:v -map 1:a -map 2:a -map 3:a -map 4:a \
  -c:v copy -c:a copy \
  -metadata:s:a:0 language=eng -metadata:s:a:0 title="English" \
  -metadata:s:a:1 language=spa -metadata:s:a:1 title="Spanish" \
  -metadata:s:a:2 language=por -metadata:s:a:2 title="Portuguese" \
  -metadata:s:a:3 language=fra -metadata:s:a:3 title="French" \
  -y /tmp/video_multi_audio.mp4 2>/dev/null

# Create subtitle files
cat > /tmp/english.srt << 'EOF'
1
00:00:00,000 --> 00:00:10,000
English subtitles - Family movie night!
EOF

cat > /tmp/spanish.srt << 'EOF'
1
00:00:00,000 --> 00:00:10,000
Subtítulos en español - ¡Noche de película familiar!
EOF

cat > /tmp/portuguese.srt << 'EOF'
1
00:00:00,000 --> 00:00:10,000
Legendas em português - Noite de cinema em família!
EOF

cat > /tmp/french.srt << 'EOF'
1
00:00:00,000 --> 00:00:10,000
Sous-titres français - Soirée cinéma en famille!
EOF

# Embed subtitles into video using MKV format (better subtitle support)
ffmpeg -i /tmp/video_multi_audio.mp4 \
  -i /tmp/english.srt -i /tmp/spanish.srt -i /tmp/portuguese.srt -i /tmp/french.srt \
  -map 0:v -map 0:a:0 -map 0:a:1 -map 0:a:2 -map 0:a:3 \
  -map 1:s -map 2:s -map 3:s -map 4:s \
  -c:v libx264 -c:a aac -c:s srt \
  -metadata:s:s:0 language=eng -metadata:s:s:0 title="English" \
  -metadata:s:s:1 language=spa -metadata:s:s:1 title="Spanish" \
  -metadata:s:s:2 language=por -metadata:s:s:2 title="Portuguese" \
  -metadata:s:s:3 language=fra -metadata:s:s:3 title="French" \
  -y /home/ga/Videos/family_movie.mkv 2>/dev/null

# Create README explaining the tracks
cat > /home/ga/Videos/README.txt << 'EOF'
=== Family Movie - Available Tracks ===

Audio Tracks:
- Track 1: English (440 Hz test tone)
- Track 2: Spanish (550 Hz test tone)
- Track 3: Portuguese (660 Hz test tone)
- Track 4: French (770 Hz test tone)

Subtitle Tracks:
- Track 1: English
- Track 2: Spanish
- Track 3: Portuguese
- Track 4: French

Task: Create quick-switch presets for:
- Preset A (Grandparents): Spanish audio (track 2), no subtitles
- Preset B (Children): English audio (track 1), Spanish subtitles (track 2)
- Preset C (Parents): English audio (track 1), no subtitles

Save your preset documentation to:
/home/ga/Videos/language_presets.txt
EOF

# Set permissions
chown -R ga:ga /home/ga/Videos/

# Cleanup temp files
rm -f /tmp/base_video.mp4 /tmp/video_multi_audio.mp4
rm -f /tmp/audio_*.aac
rm -f /tmp/english.srt /tmp/spanish.srt /tmp/portuguese.srt /tmp/french.srt

echo "Video file created successfully at /home/ga/Videos/family_movie.mkv"

# Launch VLC with the multilingual video
echo "Launching VLC with multilingual video..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --loop /home/ga/Videos/family_movie.mkv > /tmp/vlc_preset_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    exit 1
fi

# Click on center of the screen to select current desktop (should be done in all tasks), and then focus window.
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

echo "=== Quick Language Preset Task Setup Complete ==="
echo ""
echo "📝 Task Instructions:"
echo "================================================"
echo ""
echo "SCENARIO: Maria's trilingual household needs language presets"
echo ""
echo "Create three quick-switch presets:"
echo ""
echo "  Preset A (Grandparents):"
echo "    - Spanish audio (track 2)"
echo "    - No subtitles (track -1 or disabled)"
echo ""
echo "  Preset B (Children):"
echo "    - English audio (track 1)"
echo "    - Spanish subtitles (track 2)"
echo ""
echo "  Preset C (Parents):"
echo "    - English audio (track 1)"
echo "    - No subtitles (track -1 or disabled)"
echo ""
echo "STEPS:"
echo "  1. Explore available audio tracks: Audio → Audio Track"
echo "  2. Explore available subtitle tracks: Subtitle → Subtitle Track"
echo "  3. Test switching between different configurations"
echo "  4. Document your presets in: /home/ga/Videos/language_presets.txt"
echo ""
echo "REQUIRED FORMAT:"
echo "  Preset A: audio_track=2, subtitle_track=-1"
echo "  Preset B: audio_track=1, subtitle_track=2"
echo "  Preset C: audio_track=1, subtitle_track=-1"
echo ""
echo "TIPS:"
echo "  - Keyboard shortcuts: 'b' cycles audio, 'v' cycles subtitles"
echo "  - Subtitle track -1 or 0 means disabled"
echo "  - Test each preset to ensure it works!"
echo ""
echo "================================================"