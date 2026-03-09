#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Correct Aspect Ratio Result ==="

# Create export directory
mkdir -p /tmp/task_export
chown ga:ga /tmp/task_export

# Copy VLC configuration files
VLC_CONFIG_DIR="/home/ga/.config/vlc"

if [ -f "$VLC_CONFIG_DIR/vlcrc" ]; then
    cp "$VLC_CONFIG_DIR/vlcrc" /tmp/task_export/vlcrc
    echo "✅ Exported vlcrc"
else
    echo "⚠️ vlcrc not found"
    touch /tmp/task_export/vlcrc
fi

# Check for Qt interface config (VLC might store aspect ratio here too)
if [ -f "$VLC_CONFIG_DIR/vlc-qt-interface.conf" ]; then
    cp "$VLC_CONFIG_DIR/vlc-qt-interface.conf" /tmp/task_export/vlc-qt-interface.conf
    echo "Exported vlc-qt-interface.conf"
fi

# Also check for media library that might store per-file settings
if [ -f /home/ga/.local/share/vlc/ml.xspf ]; then
    cp /home/ga/.local/share/vlc/ml.xspf /tmp/task_export/ml.xspf 2>/dev/null || true
fi

# Export video info for reference (to verify it's unchanged)
if command -v ffprobe &> /dev/null; then
    ffprobe -v error -select_streams v:0 \
        -show_entries stream=width,height,display_aspect_ratio,sample_aspect_ratio \
        -of json /home/ga/Videos/family_reunion_2005.avi > /tmp/task_export/video_info.json 2>&1 || true
    echo "Exported video metadata for verification"
fi

# Create a summary of config settings
echo "=== VLC Aspect Ratio Configuration ===" > /tmp/task_export/config_summary.txt
echo "Searching for aspect ratio settings..." >> /tmp/task_export/config_summary.txt
echo "" >> /tmp/task_export/config_summary.txt

if [ -f /tmp/task_export/vlcrc ]; then
    echo "From vlcrc:" >> /tmp/task_export/config_summary.txt
    grep -i "aspect" /tmp/task_export/vlcrc >> /tmp/task_export/config_summary.txt 2>&1 || echo "No aspect ratio settings found in vlcrc" >> /tmp/task_export/config_summary.txt
fi

if [ -f /tmp/task_export/vlc-qt-interface.conf ]; then
    echo "" >> /tmp/task_export/config_summary.txt
    echo "From vlc-qt-interface.conf:" >> /tmp/task_export/config_summary.txt
    grep -i "aspect" /tmp/task_export/vlc-qt-interface.conf >> /tmp/task_export/config_summary.txt 2>&1 || echo "No aspect ratio settings found in qt config" >> /tmp/task_export/config_summary.txt
fi

# Close VLC gracefully
if is_vlc_running; then
    echo "Closing VLC..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
fi

# Force kill if still running
if is_vlc_running; then
    echo "Force closing VLC..."
    kill_vlc ga
    sleep 1
fi

# Set permissions
chmod -R 755 /tmp/task_export
chown -R ga:ga /tmp/task_export

# Create completion marker
echo "$(date)" > /tmp/vlc_aspect_completed.txt
echo "Aspect ratio correction task completed" >> /tmp/vlc_aspect_completed.txt

echo "✅ Export complete. Configuration saved to /tmp/task_export/"
cat /tmp/task_export/config_summary.txt

echo "=== Export Complete ==="