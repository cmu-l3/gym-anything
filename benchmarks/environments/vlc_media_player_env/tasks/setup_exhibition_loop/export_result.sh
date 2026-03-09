#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Exhibition Loop Configuration ==="

# Paths
VLC_CONFIG_DIR="/home/ga/.config/vlc"
VLC_RC="${VLC_CONFIG_DIR}/vlcrc"
EXPORT_DIR="/tmp/task_export"

# Ensure export directory exists
mkdir -p "${EXPORT_DIR}"

# Export VLC config file (main artifact to verify)
if [ -f "$VLC_RC" ]; then
    echo "Copying VLC configuration file..."
    cp "$VLC_RC" /tmp/vlc_exhibition_config.txt
    cp "$VLC_RC" "${EXPORT_DIR}/vlcrc_configured"
    
    echo "✅ VLC configuration exported"
    
    # Extract relevant settings for quick inspection
    echo "=== Exhibition-Related Settings ===" > "${EXPORT_DIR}/config_excerpt.txt"
    echo "" >> "${EXPORT_DIR}/config_excerpt.txt"
    
    grep -E "^(repeat|loop|fullscreen|qt-minimal|qt-fullscreen|no-qt-fs|qt-fs-controller|video-title|qt-notification|qt-privacy|qt-system-tray)=" "$VLC_RC" >> "${EXPORT_DIR}/config_excerpt.txt" 2>/dev/null || echo "No exhibition settings found" >> "${EXPORT_DIR}/config_excerpt.txt"
    
    echo "" >> "${EXPORT_DIR}/config_excerpt.txt"
    echo "Full config line count: $(wc -l < "$VLC_RC")" >> "${EXPORT_DIR}/config_excerpt.txt"
    
    cat "${EXPORT_DIR}/config_excerpt.txt"
else
    echo "⚠️ VLC config file not found: $VLC_RC"
    echo "VLC may not have been configured or launched"
    echo "error: config_not_found" > /tmp/vlc_exhibition_config.txt
fi

# Check if VLC is running and close it gracefully
if is_vlc_running; then
    echo "VLC is running, attempting to close..."
    
    # Try to focus and close gracefully
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
        sleep 0.5
    fi
    
    # Send quit command
    safe_xdotool ga :1 key --delay 200 ctrl+q || true
    sleep 2
    
    # Force kill if still running
    if is_vlc_running; then
        echo "Force closing VLC..."
        kill_vlc ga
        sleep 1
    fi
    
    echo "✅ VLC closed"
else
    echo "ℹ️ VLC not running"
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_exhibition_completed.txt
echo "Exhibition loop configuration task completed" >> /tmp/vlc_exhibition_completed.txt
echo "Config file: ${VLC_RC}" >> /tmp/vlc_exhibition_completed.txt

# Save configuration summary for verifier
if [ -f "$VLC_RC" ]; then
    cat > /tmp/vlc_exhibition_summary.json <<EOF
{
    "config_file_exists": true,
    "config_file_path": "${VLC_RC}",
    "config_file_size": $(stat -c%s "$VLC_RC" 2>/dev/null || echo 0),
    "config_line_count": $(wc -l < "$VLC_RC" 2>/dev/null || echo 0),
    "export_timestamp": "$(date -Iseconds)"
}
EOF
else
    cat > /tmp/vlc_exhibition_summary.json <<EOF
{
    "config_file_exists": false,
    "config_file_path": "${VLC_RC}",
    "error": "VLC configuration file not found"
}
EOF
fi

echo "✅ Configuration summary saved"
cat /tmp/vlc_exhibition_summary.json

echo ""
echo "=== Export Complete ==="
echo "Exported files:"
ls -lh "${EXPORT_DIR}/" 2>/dev/null || echo "Export directory empty"