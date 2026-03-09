#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Configure Classroom Playback Task ==="

kill_vlc ga
sleep 1

# Backup existing VLC config if it exists
VLC_CONFIG_DIR="/home/ga/.config/vlc"
VLC_RC="$VLC_CONFIG_DIR/vlcrc"

if [ -f "$VLC_RC" ]; then
    echo "Backing up existing vlcrc..."
    cp "$VLC_RC" "$VLC_RC.backup.$(date +%s)"
fi

# Reset VLC configuration to defaults for this task
echo "Resetting VLC configuration to defaults..."
cat > "$VLC_RC" <<'EOF'
# VLC media player configuration - Default for classroom task

[core]
# Reset to defaults - agent must configure these

# Subtitle settings (defaults - need to be changed)
[subtitle]
freetype-fontsize=0
sub-text-scale=100
freetype-bold=0

# Audio settings (defaults - need to be changed)
[audio]
audio-gain=0.0
audio-replay-gain-mode=none
norm-max-level=0.0

# Video settings (defaults - need to be changed)
[video]
avcodec-hw=any

# Other
qt-privacy-ask=0
EOF

chown ga:ga "$VLC_RC"
chmod 644 "$VLC_RC"

echo "✅ VLC config reset to defaults"

# Generate sample educational documentary video with subtitles
echo "Generating sample educational video..."
SAMPLE_VIDEO="/home/ga/Videos/classroom_documentary.mp4"

if [ ! -f "$SAMPLE_VIDEO" ]; then
    # Create 60-second video with educational content appearance
    su - ga -c "ffmpeg -y -f lavfi -i testsrc=duration=60:size=1920x1080:rate=30 \
        -f lavfi -i sine=frequency=440:duration=60 \
        -vf \"drawtext=text='Educational Documentary':fontsize=48:fontcolor=white:x=(w-text_w)/2:y=50:box=1:boxcolor=black@0.5:boxborderw=5, \
             drawtext=text='Sample narration with important educational content':fontsize=24:fontcolor=white:x=(w-text_w)/2:y=(h-100):box=1:boxcolor=black@0.5:boxborderw=5\" \
        -c:v libx264 -preset ultrafast -c:a aac \
        '$SAMPLE_VIDEO' > /tmp/ffmpeg_classroom_video.log 2>&1" || {
        echo "ERROR: Failed to generate video"
        cat /tmp/ffmpeg_classroom_video.log
        exit 1
    }
fi

# Generate subtitle file
SUBTITLE_FILE="/home/ga/Videos/classroom_documentary.srt"
cat > "$SUBTITLE_FILE" <<'EOF'
1
00:00:02,000 --> 00:00:05,000
Welcome to this educational documentary.

2
00:00:05,500 --> 00:00:09,000
Students in the back row need to read these subtitles.

3
00:00:10,000 --> 00:00:14,000
Audio clarity is essential in noisy classroom environments.

4
00:00:15,000 --> 00:00:19,000
This content requires proper configuration for group viewing.

5
00:00:20,000 --> 00:00:24,000
Projector displays have different requirements than monitors.
EOF

chown ga:ga "$SUBTITLE_FILE"

echo "✅ Sample video and subtitles created"

# Launch VLC with the educational video
echo "Launching VLC with sample documentary..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --no-video-title-show --loop --sub-file='$SUBTITLE_FILE' '$SAMPLE_VIDEO' > /tmp/vlc_classroom_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_classroom_task.log
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    exit 1
fi

# Click on center of the screen to select current desktop (should be done in all tasks)
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Pause the video so agent can work on settings
echo "Pausing video for configuration..."
sleep 2
su - ga -c "DISPLAY=:1 xdotool key space" || true

echo "=== Configure Classroom Playback Task Setup Complete ==="
echo ""
echo "📝 Instructions:"
echo "  You are a teacher preparing to show this documentary to 30 students"
echo "  in a classroom with a projector and older computer."
echo ""
echo "  Configure VLC for optimal group viewing:"
echo ""
echo "  1. Open Preferences (Tools → Preferences or Ctrl+P)"
echo ""
echo "  2. SUBTITLE SETTINGS:"
echo "     - Navigate to: Subtitle / OSD section"
echo "     - Increase font size to ≥24 points (for back-row students)"
echo "     - OR increase text scaling to ≥150%"
echo "     - Enable BOLD rendering (for projector contrast)"
echo ""
echo "  3. AUDIO SETTINGS:"
echo "     - Navigate to: Audio section"
echo "     - Enable audio normalization OR volume normalization"
echo "     - Increase audio gain to ≥3dB (for weak classroom speakers)"
echo ""
echo "  4. PERFORMANCE SETTINGS:"
echo "     - Navigate to: Input / Codecs section"
echo "     - Disable hardware acceleration (prevents stuttering on old PC)"
echo "     - Set to 'Disable' or 'None' or select software decoder"
echo ""
echo "  5. SAVE settings and close preferences"
echo ""
echo "  Settings will be saved to ~/.config/vlc/vlcrc"
echo ""