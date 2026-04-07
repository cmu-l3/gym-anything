#!/bin/bash
echo "=== Exporting Agricultural Split-Plot Result ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# Paths
ANOVA_CSV="/home/ga/RProjects/output/oats_anova_results.csv"
PLOT_PNG="/home/ga/RProjects/output/oats_interaction_plot.png"

# 1. Check ANOVA CSV
CSV_EXISTS="false"
CSV_NEW="false"
CSV_SIZE="0"
if [ -f "$ANOVA_CSV" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c %s "$ANOVA_CSV" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$ANOVA_CSV" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        CSV_NEW="true"
    fi
fi

# 2. Check Plot PNG
PLOT_EXISTS="false"
PLOT_NEW="false"
PLOT_SIZE="0"
if [ -f "$PLOT_PNG" ]; then
    PLOT_EXISTS="true"
    PLOT_SIZE=$(stat -c %s "$PLOT_PNG" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$PLOT_PNG" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        PLOT_NEW="true"
    fi
fi

# 3. Check if RStudio is still running
APP_RUNNING=$(pgrep -f "rstudio" > /dev/null && echo "true" || echo "false")

# 4. Take final screenshot
take_screenshot /tmp/task_final.png

# 5. Prepare results for Python verifier
# We copy the result files to a temporary location that copy_from_env can access safely
# if permissions are tricky, but copy_from_env usually handles standard paths fine.
# We will create a JSON summary.

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $CURRENT_TIME,
    "csv_exists": $CSV_EXISTS,
    "csv_is_new": $CSV_NEW,
    "csv_size_bytes": $CSV_SIZE,
    "plot_exists": $PLOT_EXISTS,
    "plot_is_new": $PLOT_NEW,
    "plot_size_bytes": $PLOT_SIZE,
    "app_running": $APP_RUNNING,
    "csv_path": "$ANOVA_CSV",
    "plot_path": "$PLOT_PNG"
}
EOF

# Move JSON to standardized path
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="