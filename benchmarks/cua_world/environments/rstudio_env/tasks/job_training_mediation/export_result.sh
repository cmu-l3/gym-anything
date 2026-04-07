#!/bin/bash
echo "=== Exporting job_training_mediation result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
take_screenshot /tmp/task_end.png

OUTPUT_DIR="/home/ga/RProjects/output"
CSV_PATH="$OUTPUT_DIR/mediation_effects.csv"
PLOT_PATH="$OUTPUT_DIR/mediation_plot.png"
SENS_PATH="$OUTPUT_DIR/sensitivity_summary.txt"
SCRIPT_PATH="/home/ga/RProjects/mediation_analysis.R"

# Function to check file status
check_file() {
    local path=$1
    local exists=false
    local is_new=false
    local size=0
    
    if [ -f "$path" ]; then
        exists=true
        size=$(stat -c %s "$path")
        local mtime=$(stat -c %Y "$path")
        if [ "$mtime" -gt "$TASK_START" ]; then
            is_new=true
        fi
    fi
    echo "$exists|$is_new|$size"
}

# Check all deliverables
IFS='|' read CSV_EXISTS CSV_NEW CSV_SIZE <<< $(check_file "$CSV_PATH")
IFS='|' read PLOT_EXISTS PLOT_NEW PLOT_SIZE <<< $(check_file "$PLOT_PATH")
IFS='|' read SENS_EXISTS SENS_NEW SENS_SIZE <<< $(check_file "$SENS_PATH")
IFS='|' read SCRIPT_EXISTS SCRIPT_NEW SCRIPT_SIZE <<< $(check_file "$SCRIPT_PATH")

# Check if mediation package was installed (by checking user library)
PKG_INSTALLED=false
if [ -d "/home/ga/R/library/mediation" ]; then
    PKG_INSTALLED=true
fi

# Prepare temp directory for files to be copied by verifier
mkdir -p /tmp/export_data
if [ "$CSV_EXISTS" = "true" ]; then cp "$CSV_PATH" /tmp/export_data/mediation_effects.csv; fi
if [ "$PLOT_EXISTS" = "true" ]; then cp "$PLOT_PATH" /tmp/export_data/mediation_plot.png; fi
if [ "$SENS_EXISTS" = "true" ]; then cp "$SENS_PATH" /tmp/export_data/sensitivity_summary.txt; fi
chmod -R 644 /tmp/export_data/* 2>/dev/null || true

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "pkg_installed": $PKG_INSTALLED,
    "csv": {
        "exists": $CSV_EXISTS,
        "is_new": $CSV_NEW,
        "size": $CSV_SIZE,
        "path": "/tmp/export_data/mediation_effects.csv"
    },
    "plot": {
        "exists": $PLOT_EXISTS,
        "is_new": $PLOT_NEW,
        "size": $PLOT_SIZE,
        "path": "/tmp/export_data/mediation_plot.png"
    },
    "sensitivity": {
        "exists": $SENS_EXISTS,
        "is_new": $SENS_NEW,
        "size": $SENS_SIZE,
        "path": "/tmp/export_data/sensitivity_summary.txt"
    },
    "script": {
        "exists": $SCRIPT_EXISTS,
        "is_new": $SCRIPT_NEW
    },
    "screenshot_path": "/tmp/task_end.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"