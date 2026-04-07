#!/bin/bash
echo "=== Exporting patient summary result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# 1. Check for newly downloaded files in the Downloads directory
NEW_DOWNLOADS_COUNT=$(find /home/ga/Downloads -type f -newer /tmp/task_start_marker 2>/dev/null | wc -l)

DOWNLOADED_FILES=""
if [ "$NEW_DOWNLOADS_COUNT" -gt 0 ]; then
    DOWNLOADED_FILES=$(find /home/ga/Downloads -type f -newer /tmp/task_start_marker 2>/dev/null | xargs basename -a | tr '\n' ',' | sed 's/,$//')
fi

# 2. Get active window titles to check if a new print tab/window was opened
# Look specifically for Firefox windows
WINDOW_TITLES=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | cut -d' ' -f5- || echo "")
WINDOW_TITLES_ESC=$(echo "$WINDOW_TITLES" | sed 's/"/\\"/g' | tr '\n' '|')

# 3. Create JSON output
TEMP_JSON=$(mktemp /tmp/patient_summary_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "new_downloads_count": $NEW_DOWNLOADS_COUNT,
    "downloaded_files": "$DOWNLOADED_FILES",
    "window_titles": "$WINDOW_TITLES_ESC",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
rm -f /tmp/patient_summary_result.json 2>/dev/null || sudo rm -f /tmp/patient_summary_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/patient_summary_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/patient_summary_result.json
chmod 666 /tmp/patient_summary_result.json 2>/dev/null || sudo chmod 666 /tmp/patient_summary_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/patient_summary_result.json"
cat /tmp/patient_summary_result.json
echo "=== Export complete ==="