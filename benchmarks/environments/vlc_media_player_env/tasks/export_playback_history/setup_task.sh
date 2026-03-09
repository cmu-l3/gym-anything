#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Export Playback History Task ==="

# Kill any existing VLC instances
kill_vlc ga
sleep 1

# Ensure VLC directories exist
mkdir -p /home/ga/.local/share/vlc
mkdir -p /home/ga/.config/vlc
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/.local/share/vlc
chown -R ga:ga /home/ga/.config/vlc
chown ga:ga /home/ga/Documents

# Clean up any existing history export
rm -f /home/ga/Documents/playback_history.csv

# Ensure sample video files exist
VIDEO_DIR="/home/ga/Videos"
AUDIO_DIR="/home/ga/Music"

if [ ! -d "$VIDEO_DIR" ]; then
    echo "ERROR: Videos directory not found"
    exit 1
fi

# Play multiple videos to populate history
echo "Populating VLC playback history..."

MEDIA_FILES=(
    "$VIDEO_DIR/sample_video.mp4"
    "$VIDEO_DIR/color_test.mp4"
    "$AUDIO_DIR/sample_audio.mp3"
)

# Add more files if they exist
if [ -f "$VIDEO_DIR/convert_source.mp4" ]; then
    MEDIA_FILES+=("$VIDEO_DIR/convert_source.mp4")
fi

# Play each file briefly to add to history
for media in "${MEDIA_FILES[@]}"; do
    if [ -f "$media" ]; then
        echo "Playing: $media"
        su - ga -c "DISPLAY=:1 cvlc --play-and-exit --run-time=3 '$media' > /dev/null 2>&1 &"
        sleep 4
        # Ensure VLC has closed
        if pgrep -f "cvlc.*$(basename "$media")" > /dev/null; then
            pkill -f "cvlc.*$(basename "$media")" || true
        fi
        sleep 1
    else
        echo "⚠️  Media file not found: $media"
    fi
done

# Give VLC time to write history files
sleep 2

# Kill any remaining VLC processes
kill_vlc ga
sleep 1

# Verify history files were created
echo "Checking for VLC history files..."

HISTORY_LOCATIONS=(
    "/home/ga/.local/share/vlc/ml.xspf"
    "/home/ga/.config/vlc/vlc-qt-interface.conf"
    "/home/ga/.local/share/recently-used.xbel"
)

FOUND_HISTORY=false
for history_file in "${HISTORY_LOCATIONS[@]}"; do
    if [ -f "$history_file" ]; then
        echo "✅ Found history file: $history_file"
        ls -lh "$history_file"
        FOUND_HISTORY=true
    fi
done

if [ "$FOUND_HISTORY" = false ]; then
    echo "⚠️  Warning: No VLC history files found, trying alternative method..."
    
    # Force create a media library file with recent items
    ML_FILE="/home/ga/.local/share/vlc/ml.xspf"
    cat > "$ML_FILE" <<'EOF'
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
        <vlc:option>start-time=0</vlc:option>
      </extension>
    </track>
    <track>
      <location>file:///home/ga/Videos/color_test.mp4</location>
      <title>color_test.mp4</title>
      <duration>10000</duration>
      <extension application="http://www.videolan.org/vlc/playlist/0">
        <vlc:id>1</vlc:id>
      </extension>
    </track>
    <track>
      <location>file:///home/ga/Music/sample_audio.mp3</location>
      <title>sample_audio.mp3</title>
      <duration>60000</duration>
      <extension application="http://www.videolan.org/vlc/playlist/0">
        <vlc:id>2</vlc:id>
      </extension>
    </track>
    <track>
      <location>file:///home/ga/Videos/convert_source.mp4</location>
      <title>convert_source.mp4</title>
      <duration>5000</duration>
      <extension application="http://www.videolan.org/vlc/playlist/0">
        <vlc:id>3</vlc:id>
      </extension>
    </track>
  </trackList>
</playlist>
EOF
    chown ga:ga "$ML_FILE"
    echo "✅ Created media library file: $ML_FILE"
fi

# Also add to recent items in Qt config
QT_CONFIG="/home/ga/.config/vlc/vlc-qt-interface.conf"
if [ ! -f "$QT_CONFIG" ]; then
    cat > "$QT_CONFIG" <<'EOF'
[RecentsMRL]
list=file:///home/ga/Videos/sample_video.mp4, file:///home/ga/Videos/color_test.mp4, file:///home/ga/Music/sample_audio.mp3, file:///home/ga/Videos/convert_source.mp4
times=1, 2, 1, 1
EOF
    chown ga:ga "$QT_CONFIG"
    echo "✅ Created Qt interface config with recent items"
else
    # Add recent items to existing config
    if ! grep -q "^\[RecentsMRL\]" "$QT_CONFIG"; then
        cat >> "$QT_CONFIG" <<'EOF'

[RecentsMRL]
list=file:///home/ga/Videos/sample_video.mp4, file:///home/ga/Videos/color_test.mp4, file:///home/ga/Music/sample_audio.mp3
times=1, 2, 1
EOF
        chown ga:ga "$QT_CONFIG"
        echo "✅ Added recent items to Qt interface config"
    fi
fi

echo "=== Export Playback History Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. VLC has been used to watch multiple videos"
echo "  2. Locate VLC's playback history files:"
echo "     - ~/.local/share/vlc/ml.xspf (Media Library)"
echo "     - ~/.config/vlc/vlc-qt-interface.conf (Recent items)"
echo "  3. Parse the history data"
echo "  4. Create a CSV file at: /home/ga/Documents/playback_history.csv"
echo "  5. Include columns: filename, full_path, last_played (or timestamp), play_count"
echo "  6. Ensure at least 3 media entries are present"
echo ""
echo "Hint: Use file manager, terminal, or text editor to explore VLC config directories"