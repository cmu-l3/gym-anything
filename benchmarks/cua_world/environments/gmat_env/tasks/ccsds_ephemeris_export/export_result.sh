#!/bin/bash
set -euo pipefail

echo "=== Exporting ccsds_ephemeris_export results ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

SCRIPT_PATH="/home/ga/Documents/missions/magsat2_ephemeris.script"
OEM_PATH="/home/ga/GMAT_output/magsat2_predicts.oem"
SPK_PATH="/home/ga/GMAT_output/magsat2_predicts.bsp"

take_screenshot /tmp/task_final.png

check_file() {
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

SCRIPT_STATS=$(check_file "$SCRIPT_PATH")
OEM_STATS=$(check_file "$OEM_PATH")
SPK_STATS=$(check_file "$SPK_PATH")

APP_RUNNING=$(pgrep -f "GMAT" > /dev/null && echo "true" || echo "false")

SPK_MAGIC=""
if [ -f "$SPK_PATH" ]; then
    # Grab the first 8 bytes and strip any nulls/newlines for clean JSON output
    SPK_MAGIC=$(head -c 8 "$SPK_PATH" | tr -d '\0' | tr -d '\n' || echo "")
fi

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "script_file": $SCRIPT_STATS,
    "oem_file": $OEM_STATS,
    "spk_file": $SPK_STATS,
    "spk_magic": "$SPK_MAGIC",
    "script_path": "$SCRIPT_PATH",
    "oem_path": "$OEM_PATH",
    "spk_path": "$SPK_PATH"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete."
cat /tmp/task_result.json
echo "=== Export Done ==="