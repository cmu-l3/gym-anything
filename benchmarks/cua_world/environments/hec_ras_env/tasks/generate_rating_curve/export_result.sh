#!/bin/bash
echo "=== Exporting task results ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Configuration
RESULTS_DIR="/home/ga/Documents/hec_ras_results"
PROJECT_DIR="/home/ga/Documents/hec_ras_projects/Muncie"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# --- Helper function to check file stats ---
check_file() {
    local filepath="$1"
    local min_size="${2:-1}"
    
    if [ -f "$filepath" ]; then
        local mtime=$(stat -c %Y "$filepath" 2>/dev/null || echo "0")
        local size=$(stat -c %s "$filepath" 2>/dev/null || echo "0")
        
        # Check if modified/created during task
        if [ "$mtime" -gt "$TASK_START" ]; then
            echo "{\"exists\": true, \"created_during_task\": true, \"size\": $size}"
        else
            echo "{\"exists\": true, \"created_during_task\": false, \"size\": $size}"
        fi
    else
        echo "{\"exists\": false, \"created_during_task\": false, \"size\": 0}"
    fi
}

# --- Gather File Status ---

# 1. Simulation Output (HDF)
HDF_FILE="$PROJECT_DIR/Muncie.p04.hdf"
HDF_STATUS=$(check_file "$HDF_FILE" 1000)

# 2. Generated CSV
CSV_FILE="$RESULTS_DIR/rating_curve_data.csv"
CSV_STATUS=$(check_file "$CSV_FILE" 50)

# 3. Generated Plot
PLOT_FILE="$RESULTS_DIR/rating_curve.png"
PLOT_STATUS=$(check_file "$PLOT_FILE" 1000)

# 4. Generated Report
REPORT_FILE="$RESULTS_DIR/rating_curve_report.txt"
REPORT_STATUS=$(check_file "$REPORT_FILE" 10)

# 5. XS List
XSLIST_FILE="$RESULTS_DIR/cross_sections.txt"
XSLIST_STATUS=$(check_file "$XSLIST_FILE" 10)

# --- Prepare files for extraction ---
# Copy critical text files to /tmp for easy copy_from_env access
cp "$CSV_FILE" /tmp/agent_csv_data.csv 2>/dev/null || true
cp "$REPORT_FILE" /tmp/agent_report.txt 2>/dev/null || true
cp "$XSLIST_FILE" /tmp/agent_xs_list.txt 2>/dev/null || true
chmod 644 /tmp/agent_*.{csv,txt} 2>/dev/null || true

# --- Create Result JSON ---
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "simulation_output": $HDF_STATUS,
    "csv_file": $CSV_STATUS,
    "plot_file": $PLOT_STATUS,
    "report_file": $REPORT_STATUS,
    "xs_list_file": $XSLIST_STATUS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="