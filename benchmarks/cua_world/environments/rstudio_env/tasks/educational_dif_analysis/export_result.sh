#!/bin/bash
echo "=== Exporting educational_dif_analysis result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
CSV_PATH="/home/ga/RProjects/output/dif_flagged_items.csv"
PLOT_PATH="/home/ga/RProjects/output/dif_plot.png"
SCRIPT_PATH="/home/ga/RProjects/dif_analysis.R"

# 1. Check CSV
CSV_EXISTS="false"
CSV_IS_NEW="false"
CSV_CONTAINS_S6="false"

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        CSV_IS_NEW="true"
    fi
    
    # Check if 'S6' or 's6' is in the CSV (the known biased item)
    if grep -qi "s6" "$CSV_PATH"; then
        CSV_CONTAINS_S6="true"
    fi
fi

# 2. Check Plot
PLOT_EXISTS="false"
PLOT_IS_NEW="false"
PLOT_SIZE_BYTES="0"

if [ -f "$PLOT_PATH" ]; then
    PLOT_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$PLOT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        PLOT_IS_NEW="true"
    fi
    PLOT_SIZE_BYTES=$(stat -c %s "$PLOT_PATH" 2>/dev/null || echo "0")
fi

# 3. Check Script
SCRIPT_EXISTS="false"
SCRIPT_MODIFIED="false"
SCRIPT_HAS_DIFR="false"
SCRIPT_HAS_DIFMH="false"
SCRIPT_HAS_PURIFY="false"

if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$SCRIPT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        SCRIPT_MODIFIED="true"
    fi
    
    # Ignore comments for script checks
    CODE_ONLY=$(grep -v '^\s*#' "$SCRIPT_PATH")
    
    if echo "$CODE_ONLY" | grep -qi "difR"; then
        SCRIPT_HAS_DIFR="true"
    fi
    if echo "$CODE_ONLY" | grep -qi "difMH"; then
        SCRIPT_HAS_DIFMH="true"
    fi
    if echo "$CODE_ONLY" | grep -qi "purify\s*=\s*T\|purify\s*=\s*TRUE"; then
        SCRIPT_HAS_PURIFY="true"
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "csv_is_new": $CSV_IS_NEW,
    "csv_contains_s6": $CSV_CONTAINS_S6,
    "plot_exists": $PLOT_EXISTS,
    "plot_is_new": $PLOT_IS_NEW,
    "plot_size_bytes": $PLOT_SIZE_BYTES,
    "script_exists": $SCRIPT_EXISTS,
    "script_modified": $SCRIPT_MODIFIED,
    "script_has_difr": $SCRIPT_HAS_DIFR,
    "script_has_difmh": $SCRIPT_HAS_DIFMH,
    "script_has_purify": $SCRIPT_HAS_PURIFY
}
EOF

# Move to final location safely
rm -f /tmp/dif_task_result.json 2>/dev/null || sudo rm -f /tmp/dif_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/dif_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/dif_task_result.json
chmod 666 /tmp/dif_task_result.json 2>/dev/null || sudo chmod 666 /tmp/dif_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/dif_task_result.json"
cat /tmp/dif_task_result.json
echo "=== Export complete ==="