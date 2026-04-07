#!/bin/bash
set -euo pipefail

echo "=== Exporting lunar_dsn_ephemeris_generation results ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

OEM_PATH="/home/ga/GMAT_output/lunar_dsn.oem"
SPK_PATH="/home/ga/GMAT_output/lunar_science.bsp"
SCRIPT_PATH="/home/ga/Documents/missions/lunar_dsn.script"

# Capture final state screenshot
take_screenshot /tmp/task_final.png

# Helper function to get file stats
get_file_stats() {
    local fpath="$1"
    if [ -f "$fpath" ]; then
        local mtime=$(stat -c %Y "$fpath")
        local size=$(stat -c %s "$fpath")
        local created_during=$([ "$mtime" -ge "$TASK_START" ] && echo "true" || echo "false")
        echo "{\"exists\": true, \"size\": $size, \"created_during_task\": $created_during}"
    else
        echo "{\"exists\": false, \"size\": 0, \"created_during_task\": false}"
    fi
}

OEM_STATS=$(get_file_stats "$OEM_PATH")
SPK_STATS=$(get_file_stats "$SPK_PATH")
SCRIPT_STATS=$(get_file_stats "$SCRIPT_PATH")

# Parse OEM data lightly in bash to avoid transferring multi-megabyte files unnecessarily
OEM_DATA_POINTS="0"
OEM_FIRST_TIME=""
OEM_SECOND_TIME=""
OEM_LAST_TIME=""
OEM_HAS_HEADER="false"

if [ -f "$OEM_PATH" ]; then
    # Check for CCSDS header
    grep -q "CCSDS_OEM_VERS" "$OEM_PATH" 2>/dev/null && OEM_HAS_HEADER="true" || true
    
    # Extract timestamps (format: YYYY-MM-DDTHH:MM:SS.sss)
    # Exclude headers and metadata by looking for lines starting with '2026-'
    OEM_DATA_POINTS=$(grep -c "^2026-" "$OEM_PATH" 2>/dev/null || echo "0")
    
    if [ "$OEM_DATA_POINTS" -ge 2 ]; then
        OEM_FIRST_TIME=$(grep "^2026-" "$OEM_PATH" | head -1 | awk '{print $1}' || echo "")
        OEM_SECOND_TIME=$(grep "^2026-" "$OEM_PATH" | head -2 | tail -1 | awk '{print $1}' || echo "")
        OEM_LAST_TIME=$(grep "^2026-" "$OEM_PATH" | tail -1 | awk '{print $1}' || echo "")
    fi
fi

# Check if SPK file is a valid binary DAF/SPK file
SPK_IS_BINARY="false"
if [ -f "$SPK_PATH" ]; then
    # SPK files start with 'DAF' signature
    head -c 3 "$SPK_PATH" | grep -q "DAF" 2>/dev/null && SPK_IS_BINARY="true" || true
fi

APP_RUNNING=$(pgrep -f "GMAT" > /dev/null && echo "true" || echo "false")

# Copy the script file securely to a tmp location so the verifier can inspect it
rm -f /tmp/lunar_dsn.script 2>/dev/null || true
if [ -f "$SCRIPT_PATH" ]; then
    cp "$SCRIPT_PATH" /tmp/lunar_dsn.script
    chmod 666 /tmp/lunar_dsn.script
fi

# Write results
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "script_file": $SCRIPT_STATS,
    "oem_file": $OEM_STATS,
    "spk_file": $SPK_STATS,
    "oem_has_header": $OEM_HAS_HEADER,
    "oem_data_points": $OEM_DATA_POINTS,
    "oem_first_time": "$OEM_FIRST_TIME",
    "oem_second_time": "$OEM_SECOND_TIME",
    "oem_last_time": "$OEM_LAST_TIME",
    "spk_is_binary": $SPK_IS_BINARY
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete."
cat /tmp/task_result.json
echo "=== Export Done ==="