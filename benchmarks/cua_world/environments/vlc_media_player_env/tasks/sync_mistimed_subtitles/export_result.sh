#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Sync Mistimed Subtitles Result ==="

EXPORT_DIR="/tmp/subtitle_sync_export"
mkdir -p "${EXPORT_DIR}"

# Export VLC configuration file
VLC_CONFIG="/home/ga/.config/vlc/vlcrc"

if [ -f "${VLC_CONFIG}" ]; then
    cp "${VLC_CONFIG}" "${EXPORT_DIR}/vlcrc"
    echo "✅ Exported VLC configuration"
    
    # Extract and display subtitle-related settings
    echo ""
    echo "Subtitle settings found in config:"
    grep -i "sub\|spu" "${VLC_CONFIG}" | head -20 || echo "  (none found)"
    echo ""
else
    echo "⚠️ WARNING: VLC config not found at ${VLC_CONFIG}"
    touch "${EXPORT_DIR}/vlcrc"
fi

# Export VLC state directory (may contain recent subtitle settings)
VLC_STATE_DIR="/home/ga/.local/share/vlc"
if [ -d "${VLC_STATE_DIR}" ]; then
    cp -r "${VLC_STATE_DIR}" "${EXPORT_DIR}/vlc_state" 2>/dev/null || true
    echo "✅ Exported VLC state directory"
fi

# Copy VLC log file if it exists
if [ -f "/tmp/vlc_subtitle_sync_task.log" ]; then
    cp /tmp/vlc_subtitle_sync_task.log "${EXPORT_DIR}/vlc.log" 2>/dev/null || true
fi

# Extract subtitle delay value for summary
DELAY_VALUE="not_set"
DELAY_SECONDS="0.0"

if [ -f "${VLC_CONFIG}" ]; then
    # Check for various subtitle delay keys
    for key in spu-delay sub-delay audio-desync; do
        if grep -q "^${key}=" "${VLC_CONFIG}"; then
            DELAY_VALUE=$(grep "^${key}=" "${VLC_CONFIG}" | cut -d= -f2 | head -1)
            # Convert microseconds to seconds for display
            DELAY_SECONDS=$(echo "scale=3; ${DELAY_VALUE} / 1000000" | bc 2>/dev/null || echo "0.0")
            echo "Found ${key}=${DELAY_VALUE} (${DELAY_SECONDS}s)"
            break
        fi
    done
fi

# Create summary file
cat > "${EXPORT_DIR}/summary.txt" << EOF
Subtitle Synchronization Task Export
=====================================
Export time: $(date)
VLC config: ${VLC_CONFIG}
Task: sync_mistimed_subtitles@1

TASK DESCRIPTION:
Fix subtitles that appear 2.5 seconds too early by adjusting subtitle delay.

EXPECTED RESULT:
Subtitle delay set to approximately +2,500,000 microseconds (+2.5 seconds)
This compensates for subtitles appearing 2.5s too early.

ACTUAL RESULT:
Subtitle delay value: ${DELAY_VALUE} microseconds
Subtitle delay in seconds: ${DELAY_SECONDS}s

VERIFICATION:
Expected range: 2,200,000 to 2,800,000 microseconds (2.2s to 2.8s)
Delay direction: Positive (makes subtitles appear later)

FILES EXPORTED:
- vlcrc (VLC configuration file)
- vlc_state/ (VLC state directory)
- vlc.log (VLC output log)
- summary.txt (this file)
EOF

echo "✅ Summary file created"
cat "${EXPORT_DIR}/summary.txt"

# Copy export directory to standard location
cp -r "${EXPORT_DIR}"/* /tmp/ 2>/dev/null || true
cp "${EXPORT_DIR}/vlcrc" /tmp/vlc_subtitle_sync_config.txt 2>/dev/null || true

# Close VLC gracefully
if is_vlc_running; then
    echo "Closing VLC..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
    
    # Force kill if still running
    if is_vlc_running; then
        echo "Force killing VLC..."
        kill_vlc ga
    fi
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_subtitle_sync_completed.txt
echo "Subtitle synchronization task completed" >> /tmp/vlc_subtitle_sync_completed.txt
echo "Config exported to: ${EXPORT_DIR}" >> /tmp/vlc_subtitle_sync_completed.txt

echo ""
echo "=== Export Complete ==="
echo "Export directory: ${EXPORT_DIR}"
echo "Files exported:"
ls -lh "${EXPORT_DIR}/" 2>/dev/null || true