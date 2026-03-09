#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Quick Language Preset Result ==="

# Check for presets file
PRESETS_FILE="/home/ga/Videos/language_presets.txt"

if [ -f "$PRESETS_FILE" ]; then
    echo "✅ Presets file found: $PRESETS_FILE"
    cp "$PRESETS_FILE" /tmp/vlc_language_presets.txt
    echo "--- Presets File Content ---"
    cat "$PRESETS_FILE"
    echo "--- End of Presets File ---"
    
    # Count how many presets were documented
    PRESET_COUNT=$(grep -i "preset" "$PRESETS_FILE" | wc -l)
    echo "Number of presets found: $PRESET_COUNT"
else
    echo "⚠️ Presets file not found at expected location: $PRESETS_FILE"
    
    # Look for any text files in Videos directory that might be the presets
    RECENT_TXT=$(find /home/ga/Videos -name "*.txt" -type f -mmin -10 2>/dev/null | grep -v README | head -1)
    
    if [ -n "$RECENT_TXT" ]; then
        echo "Found recent text file: $RECENT_TXT"
        cp "$RECENT_TXT" /tmp/vlc_language_presets.txt
    else
        # Create empty file to avoid verification errors
        echo "No presets documented" > /tmp/vlc_language_presets.txt
    fi
fi

# Close VLC
if is_vlc_running; then
    echo "Closing VLC..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_preset_completed.txt
echo "Quick language preset task completed" >> /tmp/vlc_preset_completed.txt

# Capture VLC logs if available
if [ -f /tmp/vlc_preset_task.log ]; then
    cp /tmp/vlc_preset_task.log /tmp/vlc_preset_result.log 2>/dev/null || true
fi

echo "=== Export Complete ==="