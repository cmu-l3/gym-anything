#!/bin/bash
echo "=== Exporting bmt_competing_risks result ==="

source /workspace/scripts/task_utils.sh

# Record task end
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
take_screenshot /tmp/task_end.png

# Target paths
OUT_DIR="/home/ga/RProjects/output"
CIF_CSV="$OUT_DIR/relapse_cif_estimates.csv"
MODEL_CSV="$OUT_DIR/fine_gray_model.csv"
PLOT_PNG="$OUT_DIR/cif_relapse_plot.png"
SCRIPT="/home/ga/RProjects/bmt_analysis.R"

# Copy files to /tmp to make them accessible to verifier's copy_from_env
[ -f "$CIF_CSV" ] && cp "$CIF_CSV" /tmp/cif_csv.csv
[ -f "$MODEL_CSV" ] && cp "$MODEL_CSV" /tmp/model_csv.csv
[ -f "$SCRIPT" ] && cp "$SCRIPT" /tmp/script.R
[ -f "$PLOT_PNG" ] && cp "$PLOT_PNG" /tmp/plot.png
chmod 666 /tmp/cif_csv.csv /tmp/model_csv.csv /tmp/script.R /tmp/plot.png 2>/dev/null || true

# Function to get file metadata
check_file() {
    if [ -f "$1" ]; then
        local mtime=$(stat -c %Y "$1" 2>/dev/null || echo "0")
        local is_new="false"
        if [ "$mtime" -gt "$TASK_START" ]; then
            is_new="true"
        fi
        local size=$(stat -c %s "$1" 2>/dev/null || echo "0")
        echo "{\"exists\": true, \"is_new\": $is_new, \"size\": $size}"
    else
        echo "{\"exists\": false, \"is_new\": false, \"size\": 0}"
    fi
}

# Create JSON summary
TEMP_JSON=$(mktemp)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "cif_csv": $(check_file "$CIF_CSV"),
    "model_csv": $(check_file "$MODEL_CSV"),
    "plot_png": $(check_file "$PLOT_PNG"),
    "script": $(check_file "$SCRIPT")
}
EOF

# Safely copy to standard result location
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="