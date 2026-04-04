#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Deinterlace Configuration ==="

# Create export directory
mkdir -p /tmp/task_export

# Query VLC RC interface for deinterlacing settings (runtime state)
DEINTERLACE_ENABLED="false"
DEINTERLACE_MODE=""
RUNTIME_CAPTURED="false"

if is_vlc_running; then
    echo "Querying VLC RC interface for deinterlacing status..."

    # Query deinterlace status from RC interface
    RC_OUTPUT=$(echo "deinterlace" | nc -w 2 localhost 9999 2>/dev/null || echo "")

    if [ -n "$RC_OUTPUT" ]; then
        echo "RC deinterlace output: $RC_OUTPUT"
        
        # VLC RC returns current deinterlace status
        # Might return "on" or "off" or mode name
        if echo "$RC_OUTPUT" | grep -qi "on\|enabled\|yadif\|linear\|bob\|blend\|mean\|discard"; then
            DEINTERLACE_ENABLED="true"
            RUNTIME_CAPTURED="true"
            
            # Try to extract mode
            if echo "$RC_OUTPUT" | grep -qi "yadif"; then
                DEINTERLACE_MODE="yadif"
            elif echo "$RC_OUTPUT" | grep -qi "linear"; then
                DEINTERLACE_MODE="linear"
            elif echo "$RC_OUTPUT" | grep -qi "bob"; then
                DEINTERLACE_MODE="bob"
            elif echo "$RC_OUTPUT" | grep -qi "blend"; then
                DEINTERLACE_MODE="blend"
            fi
            
            echo "✅ Runtime deinterlacing detected: $DEINTERLACE_MODE"
        fi
    fi

    # Also query status for more information
    STATUS_OUTPUT=$(echo "status" | nc -w 2 localhost 9999 2>/dev/null || echo "")
    if [ -n "$STATUS_OUTPUT" ]; then
        # Look for deinterlace in status output
        if echo "$STATUS_OUTPUT" | grep -qi "deinterlace"; then
            echo "Status mentions deinterlace: $(echo "$STATUS_OUTPUT" | grep -i deinterlace || true)"
        fi
    fi
fi

# Export VLC configuration files (persistent state)
VLC_CONFIG_DIR="/home/ga/.config/vlc"

# Export main VLC config (vlcrc)
if [ -f "$VLC_CONFIG_DIR/vlcrc" ]; then
    cp "$VLC_CONFIG_DIR/vlcrc" /tmp/task_export/vlcrc
    echo "✅ Exported vlcrc"
    
    # Show relevant deinterlace settings
    echo "Deinterlace settings in vlcrc:"
    grep -i "deinterlace" "$VLC_CONFIG_DIR/vlcrc" || echo "  (none found)"
else
    echo "⚠️ vlcrc not found"
fi

# Export Qt interface config (may have GUI state)
if [ -f "$VLC_CONFIG_DIR/vlc-qt-interface.conf" ]; then
    cp "$VLC_CONFIG_DIR/vlc-qt-interface.conf" /tmp/task_export/vlc-qt-interface.conf
    echo "✅ Exported Qt interface config"
    
    # Show relevant deinterlace settings
    echo "Deinterlace settings in Qt config:"
    grep -i "deinterlace" "$VLC_CONFIG_DIR/vlc-qt-interface.conf" || echo "  (none found)"
else
    echo "⚠️ Qt interface config not found"
fi

# Export all VLC config files for debugging
find "$VLC_CONFIG_DIR" -type f 2>/dev/null | while read -r file; do
    filename=$(basename "$file")
    if [ "$filename" != "vlcrc" ] && [ "$filename" != "vlc-qt-interface.conf" ]; then
        cp "$file" "/tmp/task_export/$filename" 2>/dev/null || true
    fi
done

# List all config files found
echo "All VLC config files:"
ls -la "$VLC_CONFIG_DIR" 2>/dev/null || echo "  (config dir not found)"

# Check VLC process status
ps aux | grep "[v]lc" > /tmp/task_export/vlc_process.txt || echo "VLC not running" > /tmp/task_export/vlc_process.txt
echo "VLC process status:"
cat /tmp/task_export/vlc_process.txt

# Check if video file is being played
if is_vlc_running && lsof -p $(pgrep vlc | head -1) 2>/dev/null | grep -q "family_vacation_1998"; then
    echo "✅ VLC is playing the home video"
    echo "true" > /tmp/task_export/video_loaded.txt
else
    echo "false" > /tmp/task_export/video_loaded.txt
fi

# Create runtime state file with captured info
cat > /tmp/task_export/runtime_state.json <<EOF
{
    "deinterlace_enabled": $DEINTERLACE_ENABLED,
    "deinterlace_mode": "$DEINTERLACE_MODE",
    "runtime_captured": $RUNTIME_CAPTURED,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "✅ Runtime state saved"
cat /tmp/task_export/runtime_state.json

# Close VLC gracefully
if is_vlc_running; then
    {
        wid=$(get_vlc_window_id)
        if [ -n "$wid" ]; then
            focus_window "$wid" || true
        fi
        echo "Closing VLC..."
        
        # Close via RC interface first (cleaner)
        echo "quit" | nc -w 1 localhost 9999 2>/dev/null || true
        sleep 1
        
        # Fallback to keyboard shortcut if still running
        if is_vlc_running; then
            safe_xdotool ga :1 key --delay 200 ctrl+q || true
            sleep 2
        fi
        
        # Final fallback: kill
        if is_vlc_running; then
            kill_vlc ga
        fi
    } || {
        echo "⚠️ Error closing VLC gracefully"
        kill_vlc ga || true
    }
fi

# Set proper permissions
chown -R ga:ga /tmp/task_export 2>/dev/null || true

# Create completion marker
echo "$(date -Iseconds)" > /tmp/vlc_deinterlace_completed.txt
echo "Deinterlacing configuration task completed" >> /tmp/vlc_deinterlace_completed.txt
echo "Runtime captured: $RUNTIME_CAPTURED" >> /tmp/vlc_deinterlace_completed.txt
echo "Deinterlace enabled: $DEINTERLACE_ENABLED" >> /tmp/vlc_deinterlace_completed.txt

echo "=== Export Complete ==="
echo "Files exported to /tmp/task_export:"
ls -la /tmp/task_export/ 2>/dev/null || echo "  (no files)"