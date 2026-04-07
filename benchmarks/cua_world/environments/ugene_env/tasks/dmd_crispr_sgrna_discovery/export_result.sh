#!/bin/bash
echo "=== Exporting dmd_crispr_sgrna_discovery task result ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/dmd_crispr_task_start_time 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

RESULTS_DIR="/home/ga/UGENE_Data/crispr/results"
GB_FILE="$RESULTS_DIR/dmd_targets.gb"
TXT_FILE="$RESULTS_DIR/sgrna_candidates.txt"

# Copy outputs to /tmp/ so verifier.py can safely copy_from_env them without permission issues
rm -f /tmp/dmd_targets.gb /tmp/sgrna_candidates.txt 2>/dev/null || true

GB_EXISTS="false"
GB_SIZE=0
if [ -f "$GB_FILE" ]; then
    GB_EXISTS="true"
    GB_SIZE=$(stat -c%s "$GB_FILE" 2>/dev/null || echo "0")
    cp "$GB_FILE" /tmp/dmd_targets.gb 2>/dev/null
    chmod 666 /tmp/dmd_targets.gb 2>/dev/null || true
fi

TXT_EXISTS="false"
TXT_SIZE=0
if [ -f "$TXT_FILE" ]; then
    TXT_EXISTS="true"
    TXT_SIZE=$(stat -c%s "$TXT_FILE" 2>/dev/null || echo "0")
    cp "$TXT_FILE" /tmp/sgrna_candidates.txt 2>/dev/null
    chmod 666 /tmp/sgrna_candidates.txt 2>/dev/null || true
fi

APP_RUNNING=$(pgrep -f "ugene" > /dev/null && echo "true" || echo "false")

# Create JSON summary
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "gb_exists": $GB_EXISTS,
    "gb_size": $GB_SIZE,
    "txt_exists": $TXT_EXISTS,
    "txt_size": $TXT_SIZE,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

mv "$TEMP_JSON" /tmp/dmd_crispr_task_result.json
chmod 666 /tmp/dmd_crispr_task_result.json

echo "Export complete. Result JSON:"
cat /tmp/dmd_crispr_task_result.json