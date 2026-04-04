#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Remove Vocals for Karaoke Task ==="

kill_vlc ga
sleep 1

# Generate sample music video with stereo audio (vocals in center channel)
MUSIC_VIDEO="/home/ga/Videos/favorite_song.mp4"

if [ ! -f "$MUSIC_VIDEO" ]; then
    echo "Generating sample music video with stereo audio..."
    
    # Create a 30-second music-like audio with stereo mix
    # Left/Right channels have instruments, Center channel has "vocal-like" content
    ffmpeg -y -f lavfi -i "sine=frequency=440:duration=30" \
        -f lavfi -i "sine=frequency=880:duration=30" \
        -f lavfi -i "sine=frequency=660:duration=30" \
        -filter_complex \
        "[0:a]volume=0.6,aformat=channel_layouts=mono[left]; \
         [1:a]volume=0.6,aformat=channel_layouts=mono[right]; \
         [2:a]volume=0.8,aformat=channel_layouts=mono[center]; \
         [left][right]amerge=inputs=2[lr]; \
         [lr][center]amix=inputs=2:duration=first:dropout_transition=2[stereo]" \
        -map "[stereo]" \
        -f lavfi -i "color=c=blue:size=640x480:duration=30,format=yuv420p" \
        -map 1:v -map 0:a \
        -c:v libx264 -preset ultrafast -c:a aac -b:a 128k \
        -t 30 /tmp/favorite_song_temp.mp4 2>/dev/null || {
        
        # Fallback: simpler stereo audio
        echo "Fallback: creating simpler stereo audio..."
        ffmpeg -y -f lavfi -i "sine=frequency=440:duration=30" \
            -f lavfi -i "color=c=blue:size=640x480:duration=30,format=yuv420p" \
            -c:v libx264 -preset ultrafast -c:a aac -b:a 128k \
            -shortest /tmp/favorite_song_temp.mp4 2>/dev/null
    }
    
    mv /tmp/favorite_song_temp.mp4 "$MUSIC_VIDEO"
    chown ga:ga "$MUSIC_VIDEO"
    echo "✅ Music video created: $MUSIC_VIDEO"
else
    echo "Music video already exists: $MUSIC_VIDEO"
fi

# Reset VLC audio effects to defaults
VLC_RC="/home/ga/.config/vlc/vlcrc"
if [ -f "$VLC_RC" ]; then
    echo "Resetting audio filters in VLC config..."
    
    # Remove all audio filter settings
    sed -i '/^audio-filter=/d' "$VLC_RC"
    sed -i '/^spatializer/d' "$VLC_RC"
    sed -i '/^stereo-widener/d' "$VLC_RC"
    sed -i '/^equalizer/d' "$VLC_RC"
    sed -i '/^karaoke/d' "$VLC_RC"
    sed -i '/^param-eq/d' "$VLC_RC"
    
    echo "Audio filters reset to default"
else
    echo "VLC config not found, will be created on first launch"
fi

# Launch VLC with the music video
echo "Launching VLC with music video..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --loop '$MUSIC_VIDEO' > /tmp/vlc_karaoke_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_karaoke_task.log
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

# Let video play briefly to initialize
sleep 2

echo "=== Remove Vocals for Karaoke Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. VLC is playing favorite_song.mp4 (music with vocals)"
echo "  2. Open Effects and Filters: Tools → Effects and Filters (Ctrl+E)"
echo "  3. Go to Audio Effects tab"
echo "  4. Enable one of these filters for vocal removal:"
echo "     - Spatializer (recommended)"
echo "     - Stereo Widener (adjust mix to reduce center)"
echo "     - Equalizer (reduce mid-frequencies 200Hz-5kHz)"
echo "     - Karaoke filter (if available)"
echo "  5. Close dialog to apply settings"
echo "  6. Settings will be saved to VLC config"