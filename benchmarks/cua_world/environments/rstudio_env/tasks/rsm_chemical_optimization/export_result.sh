#!/bin/bash
echo "=== Exporting RSM Optimization Result ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Paths
OUTPUT_DIR="/home/ga/RProjects/output"
SCRIPT_PATH="/home/ga/RProjects/optimize_reaction.R"
CSV_PATH="$OUTPUT_DIR/optimization_results.csv"
CONTOUR_PATH="$OUTPUT_DIR/contour_yield.png"
SURFACE_PATH="$OUTPUT_DIR/surface_yield.png"

# Helper to check file status
check_file() {
    local fpath="$1"
    local exists="false"
    local created_during="false"
    local size=0
    
    if [ -f "$fpath" ]; then
        exists="true"
        size=$(stat -c %s "$fpath" 2>/dev/null || echo "0")
        local mtime=$(stat -c %Y "$fpath" 2>/dev/null || echo "0")
        if [ "$mtime" -gt "$TASK_START" ]; then
            created_during="true"
        fi
    fi
    echo "{\"exists\": $exists, \"created_during\": $created_during, \"size\": $size}"
}

# Check all expected files
SCRIPT_STATUS=$(check_file "$SCRIPT_PATH")
CSV_STATUS=$(check_file "$CSV_PATH")
CONTOUR_STATUS=$(check_file "$CONTOUR_PATH")
SURFACE_STATUS=$(check_file "$SURFACE_PATH")

# Extract CSV content safely using Python
CSV_CONTENT_JSON="{}"
if [ -f "$CSV_PATH" ]; then
    CSV_CONTENT_JSON=$(python3 -c "
import csv, json, sys
path = '$CSV_PATH'
result = {}
try:
    with open(path, 'r') as f:
        reader = csv.DictReader(f)
        row = next(reader, None)
        if row:
            # Normalize keys to lowercase for robust verification
            result = {k.lower().strip(): v.strip() for k, v in row.items()}
except Exception as e:
    result = {'error': str(e)}
print(json.dumps(result))
")
fi

# Check if 'rsm' package is actually installed
RSM_INSTALLED=$(R --vanilla --slave -e "cat(requireNamespace('rsm', quietly=TRUE))" 2>/dev/null || echo "FALSE")
if echo "$RSM_INSTALLED" | grep -q "TRUE"; then
    RSM_INSTALLED="true"
else
    RSM_INSTALLED="false"
fi

# Check script content for key functions
SCRIPT_ANALYSIS="{}"
if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_ANALYSIS=$(python3 -c "
import json
try:
    with open('$SCRIPT_PATH', 'r') as f:
        content = f.read()
    analysis = {
        'has_rsm_library': 'library(rsm)' in content or 'require(rsm)' in content,
        'has_so_function': 'SO(' in content,
        'has_contour': 'contour(' in content,
        'has_persp': 'persp(' in content,
        'has_canonical': 'canonical(' in content
    }
except:
    analysis = {}
print(json.dumps(analysis))
")
fi

# Create final JSON result
TEMP_JSON=$(mktemp /tmp/rsm_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "rsm_installed": $RSM_INSTALLED,
    "script": $SCRIPT_STATUS,
    "script_content_analysis": $SCRIPT_ANALYSIS,
    "results_csv": $CSV_STATUS,
    "csv_data": $CSV_CONTENT_JSON,
    "contour_plot": $CONTOUR_STATUS,
    "surface_plot": $SURFACE_STATUS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="