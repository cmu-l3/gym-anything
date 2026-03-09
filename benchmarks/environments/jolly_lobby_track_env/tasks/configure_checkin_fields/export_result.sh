#!/bin/bash
set -e
echo "=== Exporting configure_checkin_fields result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot for VLM verification
take_screenshot /tmp/task_final.png

# 1. Check if application is still running
APP_RUNNING="false"
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "lobby\|jolly\|visitor\|track" > /dev/null 2>&1; then
    APP_RUNNING="true"
fi

# 2. Check for configuration file modifications (evidence of saving)
CONFIG_MODIFIED="false"
LOBBYTRACK_DIRS=(
    "/home/ga/.wine/drive_c/ProgramData/Jolly Technologies"
    "/home/ga/.wine/drive_c/users/ga/Application Data/Jolly Technologies"
    "/home/ga/.wine/drive_c/Program Files/Jolly Technologies"
)

rm -f /tmp/config_files_after.txt
touch /tmp/config_files_after.txt

for dir in "${LOBBYTRACK_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        find "$dir" -type f \( -iname "*.config" -o -iname "*.xml" -o -iname "*.sdf" -o -iname "*.ini" \) -exec stat --format='%n %Y %s' {} \; >> /tmp/config_files_after.txt 2>/dev/null || true
    fi
done

# Compare before and after
if [ -s /tmp/config_files_before.txt ] && [ -s /tmp/config_files_after.txt ]; then
    # diff returns 1 if files differ (which is good here, implies change)
    if ! diff -q /tmp/config_files_before.txt /tmp/config_files_after.txt > /dev/null 2>&1; then
        CONFIG_MODIFIED="true"
        echo "Configuration files were modified."
    else
        echo "No configuration file changes detected."
    fi
else
    # Fallback if we couldn't find config files initially
    echo "Warning: Could not compare config files (missing initial or final state)."
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "app_running": $APP_RUNNING,
    "config_files_modified": $CONFIG_MODIFIED,
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="