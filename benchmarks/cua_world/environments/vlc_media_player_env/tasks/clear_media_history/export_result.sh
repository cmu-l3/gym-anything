#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Clear Media History Result ==="

# Initialize result variables
RECENT_ITEMS_COUNT=0
CONFIG_MODIFIED="false"
RECENT_ITEMS_LIST=""

VLC_CONFIG_DIR="/home/ga/.config/vlc"
VLC_QT_CONF="$VLC_CONFIG_DIR/vlc-qt-interface.conf"
VLC_RC="$VLC_CONFIG_DIR/vlcrc"

# Close VLC to ensure config is flushed to disk
if is_vlc_running; then
    echo "Closing VLC to flush configuration..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
    
    # Force kill if still running
    if is_vlc_running; then
        kill_vlc ga
        sleep 1
    fi
fi

# Parse VLC Qt interface config for recent items
if [ -f "$VLC_QT_CONF" ]; then
    echo "Analyzing VLC Qt interface config..."
    
    # Copy config for analysis
    cp "$VLC_QT_CONF" /tmp/vlc_qt_interface_export.conf
    
    # Count recent items (file:// URLs in RecentsMRL section)
    RECENT_ITEMS_COUNT=$(grep -c "file://" "$VLC_QT_CONF" 2>/dev/null || echo "0")
    
    # Extract recent items list
    RECENT_ITEMS_LIST=$(grep "file://" "$VLC_QT_CONF" 2>/dev/null | head -5 || echo "")
    
    echo "Recent items count: $RECENT_ITEMS_COUNT"
    
    # Check if config was modified during task (compare timestamp)
    INITIAL_COUNT=$(cat /tmp/vlc_history_initial_count.txt 2>/dev/null || echo "999")
    if [ "$RECENT_ITEMS_COUNT" -lt "$INITIAL_COUNT" ]; then
        CONFIG_MODIFIED="true"
        echo "✅ Config was modified (count reduced from $INITIAL_COUNT to $RECENT_ITEMS_COUNT)"
    else
        echo "⚠️ Config may not have been modified (count: $INITIAL_COUNT → $RECENT_ITEMS_COUNT)"
    fi
else
    echo "⚠️ VLC Qt config not found: $VLC_QT_CONF"
fi

# Also copy vlcrc for additional analysis
if [ -f "$VLC_RC" ]; then
    cp "$VLC_RC" /tmp/vlcrc_export.conf
fi

# Create JSON result
cat > /tmp/vlc_history_result.json <<EOF
{
    "recent_items_count": $RECENT_ITEMS_COUNT,
    "config_modified": $CONFIG_MODIFIED,
    "config_file_exists": $([ -f "$VLC_QT_CONF" ] && echo "true" || echo "false"),
    "initial_count": $(cat /tmp/vlc_history_initial_count.txt 2>/dev/null || echo "0")
}
EOF

echo "✅ History result saved to /tmp/vlc_history_result.json"
cat /tmp/vlc_history_result.json

# Save recent items details for verifier
if [ -n "$RECENT_ITEMS_LIST" ]; then
    echo "$RECENT_ITEMS_LIST" > /tmp/vlc_recent_items_list.txt
else
    echo "" > /tmp/vlc_recent_items_list.txt
fi

echo "$(date)" > /tmp/vlc_history_completed.txt
echo "Clear media history task completed" >> /tmp/vlc_history_completed.txt

echo "=== Export Complete ==="