#!/bin/bash
# Do NOT use set -e
echo "=== Exporting meteorite_mass_analysis task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Take final screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/meteorite_task_end.png" 2>/dev/null || true

SCRIPT_FILE="/home/ga/Documents/meteorite_analyzer.py"
OUTPUT_FILE="/home/ga/Documents/top_10_meteorites.txt"
TASK_START=$(cat /tmp/meteorite_analysis_start_ts 2>/dev/null || echo "0")

SCRIPT_EXISTS="false"
SCRIPT_SIZE=0
SCRIPT_MODIFIED="false"
SCRIPT_CONTENT=""

OUTPUT_EXISTS="false"
OUTPUT_SIZE=0
OUTPUT_MODIFIED="false"
OUTPUT_CONTENT=""

# Check Script File
if [ -f "$SCRIPT_FILE" ]; then
    SCRIPT_EXISTS="true"
    SCRIPT_SIZE=$(stat --format=%s "$SCRIPT_FILE" 2>/dev/null || echo "0")
    SCRIPT_MTIME=$(stat --format=%Y "$SCRIPT_FILE" 2>/dev/null || echo "0")
    if [ "$SCRIPT_MTIME" -gt "$TASK_START" ]; then
        SCRIPT_MODIFIED="true"
    fi
    # Read up to 4KB of the script securely
    SCRIPT_CONTENT=$(head -c 4096 "$SCRIPT_FILE" | jq -Rs . 2>/dev/null || echo '""')
else
    SCRIPT_CONTENT='""'
fi

# Check Output File
if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat --format=%s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat --format=%Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        OUTPUT_MODIFIED="true"
    fi
    # Read up to 4KB of the output securely
    OUTPUT_CONTENT=$(head -c 4096 "$OUTPUT_FILE" | jq -Rs . 2>/dev/null || echo '""')
else
    OUTPUT_CONTENT='""'
fi

# Build JSON Result safely
cat > /tmp/meteorite_result.json << EOF
{
    "script_exists": $SCRIPT_EXISTS,
    "script_size": $SCRIPT_SIZE,
    "script_modified": $SCRIPT_MODIFIED,
    "script_content": $SCRIPT_CONTENT,
    "output_exists": $OUTPUT_EXISTS,
    "output_size": $OUTPUT_SIZE,
    "output_modified": $OUTPUT_MODIFIED,
    "output_content": $OUTPUT_CONTENT
}
EOF

chmod 666 /tmp/meteorite_result.json
echo "Result saved to /tmp/meteorite_result.json"
echo "=== Export complete ==="