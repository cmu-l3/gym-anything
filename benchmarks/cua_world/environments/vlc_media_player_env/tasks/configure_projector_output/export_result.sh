#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Configure Projector Output Result ==="

TASK_NAME="configure_projector_output"
EXPORT_DIR="${EXPORT_DIR:-/tmp}"

# Export VLC configuration file
VLC_CONFIG="/home/ga/.config/vlc/vlcrc"

if [ -f "$VLC_CONFIG" ]; then
    cp "$VLC_CONFIG" "$EXPORT_DIR/vlc_projector_config.vlcrc"
    echo "[$TASK_NAME] ✅ Exported VLC config to $EXPORT_DIR/vlc_projector_config.vlcrc"
    
    # Show relevant configuration lines for debugging
    echo "[$TASK_NAME] Configuration excerpt (resolution-related settings):"
    grep -E "(width|height|video|vout|resolution)" "$VLC_CONFIG" || echo "  (no resolution settings found)"
else
    echo "[$TASK_NAME] ⚠️  VLC config not found at $VLC_CONFIG"
    touch "$EXPORT_DIR/vlc_projector_config.missing"
fi

# Export task metadata
cat > "$EXPORT_DIR/vlc_projector_task_metadata.json" << EOF
{
  "task_id": "$TASK_NAME",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "target_resolution": {
    "width": 1280,
    "height": 800,
    "description": "WXGA projector native resolution"
  },
  "source_video": {
    "path": "/home/ga/Videos/presentation_video.mp4",
    "expected_resolution": "1920x1080"
  }
}
EOF

echo "[$TASK_NAME] ✅ Exported task metadata"

# Close VLC if still running
if is_vlc_running; then
    echo "[$TASK_NAME] Closing VLC..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
    
    # Force kill if still running
    if is_vlc_running; then
        echo "[$TASK_NAME] Force killing VLC..."
        kill_vlc ga
    fi
fi

# Create completion marker
echo "$(date)" > "$EXPORT_DIR/vlc_projector_config_completed.txt"
echo "[$TASK_NAME] ✅ Created completion marker"

echo "=== Export Complete ==="
ls -lh "$EXPORT_DIR"/vlc_projector_*