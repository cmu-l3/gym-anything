#!/bin/bash
echo "=== Exporting coastal_flood_evd results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
take_screenshot /tmp/task_final.png

OUTPUT_DIR="/home/ga/RProjects/output"
PARAMS_CSV="$OUTPUT_DIR/gev_params.csv"
LEVELS_CSV="$OUTPUT_DIR/return_levels.csv"
DIAG_PNG="$OUTPUT_DIR/evd_diagnostics.png"
SCRIPT="$OUTPUT_DIR/../flood_analysis.R"

# Initialize JSON fields
PARAMS_EXISTS="false"
PARAMS_NEW="false"
LEVELS_EXISTS="false"
LEVELS_NEW="false"
DIAG_EXISTS="false"
DIAG_NEW="false"
SCRIPT_EXISTS="false"
SCRIPT_MODIFIED="false"
PACKAGE_INSTALLED="false"

# Check Params CSV
if [ -f "$PARAMS_CSV" ]; then
    PARAMS_EXISTS="true"
    MTIME=$(stat -c %Y "$PARAMS_CSV")
    [ "$MTIME" -gt "$TASK_START" ] && PARAMS_NEW="true"
fi

# Check Levels CSV
if [ -f "$LEVELS_CSV" ]; then
    LEVELS_EXISTS="true"
    MTIME=$(stat -c %Y "$LEVELS_CSV")
    [ "$MTIME" -gt "$TASK_START" ] && LEVELS_NEW="true"
fi

# Check Diagnostics PNG
if [ -f "$DIAG_PNG" ]; then
    DIAG_EXISTS="true"
    MTIME=$(stat -c %Y "$DIAG_PNG")
    [ "$MTIME" -gt "$TASK_START" ] && DIAG_NEW="true"
    DIAG_SIZE=$(stat -c %s "$DIAG_PNG")
else
    DIAG_SIZE=0
fi

# Check Script
if [ -f "$SCRIPT" ]; then
    SCRIPT_EXISTS="true"
    MTIME=$(stat -c %Y "$SCRIPT")
    [ "$MTIME" -gt "$TASK_START" ] && SCRIPT_MODIFIED="true"
fi

# Check if evd package is installed
if R --vanilla --slave -e "quit(status=!requireNamespace('evd', quietly=TRUE))"; then
    PACKAGE_INSTALLED="true"
fi

# Read CSV content for verifier (handle formatting safely)
PARAMS_CONTENT=""
if [ "$PARAMS_EXISTS" = "true" ]; then
    # Read first data row (assuming header)
    PARAMS_CONTENT=$(awk 'NR==2 {print $0}' "$PARAMS_CSV" | tr -d '\r')
fi

LEVELS_CONTENT=""
if [ "$LEVELS_EXISTS" = "true" ]; then
    # Read whole file
    LEVELS_CONTENT=$(cat "$LEVELS_CSV" | tr -d '\r' | base64 -w 0)
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "params_exists": $PARAMS_EXISTS,
    "params_new": $PARAMS_NEW,
    "params_content": "$PARAMS_CONTENT",
    "levels_exists": $LEVELS_EXISTS,
    "levels_new": $LEVELS_NEW,
    "levels_content_b64": "$LEVELS_CONTENT",
    "diag_exists": $DIAG_EXISTS,
    "diag_new": $DIAG_NEW,
    "diag_size": $DIAG_SIZE,
    "script_exists": $SCRIPT_EXISTS,
    "script_modified": $SCRIPT_MODIFIED,
    "package_installed": $PACKAGE_INSTALLED,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="