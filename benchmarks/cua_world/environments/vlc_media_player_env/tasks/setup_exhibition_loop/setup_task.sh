#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Exhibition Loop Task ==="

# Kill any existing VLC instances
kill_vlc ga

sleep 1

# Paths
USER_HOME="/home/ga"
VIDEOS_DIR="${USER_HOME}/Videos"
VLC_CONFIG_DIR="${USER_HOME}/.config/vlc"
VIDEO_FILE="${VIDEOS_DIR}/gallery_promo.mp4"

# Ensure VLC config directory exists
mkdir -p "${VLC_CONFIG_DIR}"
chown -R ga:ga "${VLC_CONFIG_DIR}"

# Create promotional video if it doesn't exist
if [ ! -f "$VIDEO_FILE" ]; then
    echo "Creating promotional video..."
    
    # Create a 30-second video with text overlay
    su - ga -c "ffmpeg -f lavfi -i testsrc=duration=30:size=1280x720:rate=25 \
           -f lavfi -i sine=frequency=440:duration=30 \
           -vf \"drawtext=text='GALLERY OPENING TOMORROW':fontsize=48:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2-50:box=1:boxcolor=black@0.7:boxborderw=10, \
                drawtext=text='Contemporary Art Exhibition':fontsize=32:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2+30:box=1:boxcolor=black@0.7:boxborderw=10\" \
           -c:v libx264 -preset fast -pix_fmt yuv420p \
           -c:a aac -b:a 128k \
           -y '$VIDEO_FILE' 2>/tmp/ffmpeg_promo.log"
    
    echo "✅ Promotional video created: $VIDEO_FILE"
else
    echo "✅ Promotional video already exists: $VIDEO_FILE"
fi

# Verify video exists and is valid
if [ ! -f "$VIDEO_FILE" ]; then
    echo "ERROR: Failed to create promotional video"
    exit 1
fi

# Reset VLC configuration to default state (no loop, no fullscreen, normal interface)
VLC_RC="${VLC_CONFIG_DIR}/vlcrc"

if [ -f "$VLC_RC" ]; then
    echo "Resetting VLC configuration to defaults..."
    
    # Backup existing config
    cp "$VLC_RC" "${VLC_RC}.backup.$(date +%s)" 2>/dev/null || true
    
    # Remove exhibition-related settings to ensure clean state
    sed -i '/^repeat=/d' "$VLC_RC"
    sed -i '/^loop=/d' "$VLC_RC"
    sed -i '/^fullscreen=/d' "$VLC_RC"
    sed -i '/^qt-minimal-view=/d' "$VLC_RC"
    sed -i '/^qt-fullscreen-screennumber=/d' "$VLC_RC"
    sed -i '/^no-qt-fs-controller=/d' "$VLC_RC"
    sed -i '/^qt-fs-controller=/d' "$VLC_RC"
    sed -i '/^video-title-show=/d' "$VLC_RC"
    sed -i '/^qt-notification=/d' "$VLC_RC"
    sed -i '/^qt-privacy-ask=/d' "$VLC_RC"
    sed -i '/^qt-system-tray=/d' "$VLC_RC"
    
    echo "✅ VLC configuration reset to defaults"
else
    echo "Creating new VLC configuration file..."
    # Create minimal vlcrc with default values
    cat > "$VLC_RC" <<EOF
# VLC configuration file
# Generated for exhibition loop task

[core]
# Default settings (no loop, no fullscreen)
EOF
    chown ga:ga "$VLC_RC"
fi

# Create expected state file for verifier reference
mkdir -p /tmp/task_state
cat > /tmp/task_state/exhibition_loop_expected.json <<EOF
{
  "video_file": "${VIDEO_FILE}",
  "video_exists": true,
  "video_duration": 30.0,
  "initial_state": "default_no_loop_no_fullscreen",
  "expected_loop_enabled": true,
  "expected_fullscreen": true,
  "expected_minimal_interface": true,
  "task_type": "configuration"
}
EOF

echo "✅ Task state file created"

# DO NOT launch VLC - let the agent do it as part of the task
# The agent needs to configure VLC settings through the preferences

echo ""
echo "=== Exhibition Loop Task Setup Complete ==="
echo ""
echo "📝 Instructions for Agent:"
echo "=========================================="
echo "You need to configure VLC Media Player for unattended exhibition display."
echo ""
echo "Video file: ${VIDEO_FILE}"
echo ""
echo "Requirements:"
echo "  1. Enable continuous looping (video plays over and over)"
echo "     → Tools → Preferences → Show settings: All"
echo "     → Playlist → Set 'Repeat all' or 'Loop' option"
echo ""
echo "  2. Enable fullscreen mode by default"
echo "     → Tools → Preferences → Video"
echo "     → Check 'Fullscreen' option"
echo ""
echo "  3. Hide interface elements (controls, menus)"
echo "     → Tools → Preferences → Interface"
echo "     → Configure minimal view or hide controller in fullscreen"
echo ""
echo "  4. Disable video title overlay (optional but recommended)"
echo "     → Tools → Preferences → Show settings: All"
echo "     → Video → Uncheck 'Show media title on video'"
echo ""
echo "  5. Disable notifications (optional but recommended)"
echo "     → Tools → Preferences → Interface"
echo "     → Configure notification settings"
echo ""
echo "IMPORTANT: You must open VLC and configure these settings through"
echo "           the preferences menu. Settings must be saved (they auto-save"
echo "           when you close preferences with 'Save' button)."
echo ""
echo "Test your configuration by opening the video and verifying it loops"
echo "and displays in fullscreen without visible controls."
echo "=========================================="