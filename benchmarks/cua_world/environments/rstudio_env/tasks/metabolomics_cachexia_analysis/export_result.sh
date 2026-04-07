#!/bin/bash
echo "=== Exporting metabolomics_cachexia_analysis result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/metabolomics_task_start_ts 2>/dev/null || echo "0")
take_screenshot /tmp/metabolomics_task_end.png

CSV_PATH="/home/ga/RProjects/output/metabolomics_results.csv"
PLOT_PATH="/home/ga/RProjects/output/volcano_plot.png"
SCRIPT_PATH="/home/ga/RProjects/cachexia_analysis.R"

# Initialize variables
CSV_EXISTS="false"
CSV_IS_NEW="false"
CSV_SIZE="0"
PLOT_EXISTS="false"
PLOT_IS_NEW="false"
PLOT_SIZE="0"
SCRIPT_MODIFIED="false"

# Check CSV
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c %s "$CSV_PATH" 2>/dev/null || echo "0")
    CSV_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_IS_NEW="true"
    fi
    # Stage the file in tmp for robust extraction
    cp "$CSV_PATH" /tmp/agent_results.csv 2>/dev/null || true
    chmod 666 /tmp/agent_results.csv 2>/dev/null || true
fi

# Check Plot
if [ -f "$PLOT_PATH" ]; then
    PLOT_EXISTS="true"
    PLOT_SIZE=$(stat -c %s "$PLOT_PATH" 2>/dev/null || echo "0")
    PLOT_MTIME=$(stat -c %Y "$PLOT_PATH" 2>/dev/null || echo "0")
    if [ "$PLOT_MTIME" -gt "$TASK_START" ]; then
        PLOT_IS_NEW="true"
    fi
    # Stage the plot
    cp "$PLOT_PATH" /tmp/agent_volcano.png 2>/dev/null || true
    chmod 666 /tmp/agent_volcano.png 2>/dev/null || true
fi

# Check Script
if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_MTIME=$(stat -c %Y "$SCRIPT_PATH" 2>/dev/null || echo "0")
    if [ "$SCRIPT_MTIME" -gt "$TASK_START" ]; then
        SCRIPT_MODIFIED="true"
    fi
fi

# Stage original dataset for ground-truth calculation by verifier
cp "/home/ga/RProjects/datasets/human_cachexia.csv" "/tmp/original_data.csv" 2>/dev/null || true
chmod 666 "/tmp/original_data.csv" 2>/dev/null || true

# Build export JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "csv_is_new": $CSV_IS_NEW,
    "csv_size_bytes": $CSV_SIZE,
    "plot_exists": $PLOT_EXISTS,
    "plot_is_new": $PLOT_IS_NEW,
    "plot_size_bytes": $PLOT_SIZE,
    "script_modified": $SCRIPT_MODIFIED,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Safe move
rm -f /tmp/metabolomics_result.json 2>/dev/null || sudo rm -f /tmp/metabolomics_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/metabolomics_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/metabolomics_result.json
chmod 666 /tmp/metabolomics_result.json 2>/dev/null || sudo chmod 666 /tmp/metabolomics_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="