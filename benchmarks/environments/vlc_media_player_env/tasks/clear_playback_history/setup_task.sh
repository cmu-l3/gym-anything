#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Clear Playback History Task ==="

# Kill any existing VLC instances
kill_vlc ga

sleep 1

# Ensure VLC directories exist
mkdir -p /home/ga/.config/vlc
mkdir -p /home/ga/.local/share/vlc
mkdir -p /home/ga/Videos
mkdir -p /home/ga/Music
mkdir -p /home/ga/Downloads

# Ensure sample media files exist (they should from env setup, but create if missing)
if [ ! -f /home/ga/Videos/sample_video.mp4 ]; then
    touch /home/ga/Videos/sample_video.mp4
fi

if [ ! -f /home/ga/Videos/color_test.mp4 ]; then
    touch /home/ga/Videos/color_test.mp4
fi

if [ ! -f /home/ga/Music/sample_audio.mp3 ]; then
    mkdir -p /home/ga/Music
    touch /home/ga/Music/sample_audio.mp3
fi

# Create "embarrassing" filename for realism
touch /home/ga/Downloads/video_personal.mkv

# Backup existing vlcrc if it exists
VLC_RC="/home/ga/.config/vlc/vlcrc"
if [ -f "$VLC_RC" ]; then
    cp "$VLC_RC" "${VLC_RC}.backup"
fi

# Populate VLC recent files history in config
# This simulates the user having watched these files
echo "Populating VLC playback history..."

# Ensure vlcrc exists with basic structure
if [ ! -f "$VLC_RC" ]; then
    cat > "$VLC_RC" << 'EOF'
[qt]
qt-privacy-ask=0

[core]
EOF
fi

# Add recent items to vlcrc (append to end of file)
cat >> "$VLC_RC" << 'EOF'

# Recent Media
recent-items=file:///home/ga/Videos/sample_video.mp4,file:///home/ga/Videos/color_test.mp4,file:///home/ga/Music/sample_audio.mp3,file:///home/ga/Downloads/video_personal.mkv
list-of-recent=4
EOF

echo "✓ Recent files added to VLC config"

# Create Media Library with history
ML_FILE="/home/ga/.local/share/vlc/ml.xspf"
cat > "$ML_FILE" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<playlist xmlns="http://xspf.org/ns/0/" xmlns:vlc="http://www.videolan.org/vlc/playlist/ns/0/" version="1">
  <title>Media Library</title>
  <trackList>
    <track>
      <location>file:///home/ga/Videos/sample_video.mp4</location>
      <title>sample_video.mp4</title>
      <duration>30000</duration>
      <extension application="http://www.videolan.org/vlc/playlist/0">
        <vlc:id>0</vlc:id>
      </extension>
    </track>
    <track>
      <location>file:///home/ga/Videos/color_test.mp4</location>
      <title>color_test.mp4</title>
      <duration>5000</duration>
      <extension application="http://www.videolan.org/vlc/playlist/0">
        <vlc:id>1</vlc:id>
      </extension>
    </track>
    <track>
      <location>file:///home/ga/Music/sample_audio.mp3</location>
      <title>sample_audio.mp3</title>
      <duration>180000</duration>
      <extension application="http://www.videolan.org/vlc/playlist/0">
        <vlc:id>2</vlc:id>
      </extension>
    </track>
    <track>
      <location>file:///home/ga/Downloads/video_personal.mkv</location>
      <title>video_personal.mkv</title>
      <duration>12000</duration>
      <extension application="http://www.videolan.org/vlc/playlist/0">
        <vlc:id>3</vlc:id>
      </extension>
    </track>
  </trackList>
</playlist>
EOF

echo "✓ Media Library populated with history"

# Set proper ownership
chown -R ga:ga /home/ga/.config/vlc
chown -R ga:ga /home/ga/.local/share/vlc
chown -R ga:ga /home/ga/Videos
chown -R ga:ga /home/ga/Music
chown -R ga:ga /home/ga/Downloads

# Verify history was populated
RECENT_COUNT=$(grep -c "file://" "$VLC_RC" || echo "0")
ML_TRACK_COUNT=$(grep -c "<track>" "$ML_FILE" || echo "0")

echo "✓ VLC history setup complete:"
echo "  - Recent files in config: $RECENT_COUNT"
echo "  - Media Library tracks: $ML_TRACK_COUNT"

# Launch VLC so agent can interact with it
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_history_task.log 2>&1 &"

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

echo "=== Clear Playback History Task Setup Complete ==="
echo ""
echo "📝 Instructions:"
echo "  VLC has been used to watch several files. Recent history shows:"
echo "    • sample_video.mp4"
echo "    • color_test.mp4"
echo "    • sample_audio.mp3"
echo "    • video_personal.mkv (embarrassing!)"
echo ""
echo "  Your task: Clear ALL playback history"
echo ""
echo "  Methods to clear:"
echo "    1. GUI: Media menu → Open Recent Media → Clear (at bottom)"
echo "    2. Media Library: Media → Media Library → Clear/Delete items"
echo "    3. Config: Edit ~/.config/vlc/vlcrc directly (advanced)"
echo ""
echo "  Both recent files AND media library must be cleared!"