#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Clear Playback History Result ==="

# Export VLC config file
VLC_RC="/home/ga/.config/vlc/vlcrc"
if [ -f "$VLC_RC" ]; then
    cp "$VLC_RC" /tmp/vlc_history_vlcrc.txt
    echo "✅ VLC config exported"
    
    # Debug: show recent-items lines
    echo "Recent-items lines in config:"
    grep -i "recent" "$VLC_RC" || echo "  (none found)"
else
    echo "⚠️ VLC config not found"
    touch /tmp/vlc_history_vlcrc.txt
fi

# Export Media Library file
ML_FILE="/home/ga/.local/share/vlc/ml.xspf"
if [ -f "$ML_FILE" ]; then
    cp "$ML_FILE" /tmp/vlc_history_ml.xspf
    echo "✅ Media Library exported"
    
    # Debug: count tracks
    TRACK_COUNT=$(grep -c "<track>" "$ML_FILE" || echo "0")
    echo "Media Library track count: $TRACK_COUNT"
else
    echo "⚠️ Media Library file not found (this may be OK if cleared)"
    echo '<?xml version="1.0" encoding="UTF-8"?><playlist xmlns="http://xspf.org/ns/0/" version="1"><title>Media Library</title><trackList></trackList></playlist>' > /tmp/vlc_history_ml.xspf
fi

# Close VLC gracefully
if is_vlc_running; then
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    echo "Closing VLC..."
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
fi

# Create summary JSON for easier parsing
cat > /tmp/vlc_history_summary.json <<EOF
{
    "config_exists": $([ -f "$VLC_RC" ] && echo "true" || echo "false"),
    "ml_exists": $([ -f "$ML_FILE" ] && echo "true" || echo "false"),
    "config_size": $(stat -c%s "$VLC_RC" 2>/dev/null || echo "0"),
    "ml_size": $(stat -c%s "$ML_FILE" 2>/dev/null || echo "0")
}
EOF

echo "✅ Summary exported to /tmp/vlc_history_summary.json"
cat /tmp/vlc_history_summary.json

# Create completion marker
echo "$(date)" > /tmp/vlc_history_completed.txt
echo "Clear playback history task completed" >> /tmp/vlc_history_completed.txt

echo "=== Export Complete ==="