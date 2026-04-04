#!/bin/bash
echo "=== Exporting GLCM Texture Task Results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Directories
RESULTS_DIR="/home/ga/Fiji_Data/results/texture"
ROIS_FILE="$RESULTS_DIR/rois.zip"
CSV_FILE="$RESULTS_DIR/glcm_measurements.csv"
IMG_FILE="$RESULTS_DIR/annotated_microstructure.png"
REPORT_FILE="$RESULTS_DIR/texture_report.txt"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Function to get file info
get_file_info() {
    local fpath=$1
    if [ -f "$fpath" ]; then
        local size=$(stat -c %s "$fpath" 2>/dev/null || echo "0")
        local mtime=$(stat -c %Y "$fpath" 2>/dev/null || echo "0")
        local created_during="false"
        if [ "$mtime" -gt "$TASK_START" ]; then
            created_during="true"
        fi
        echo "{\"exists\": true, \"size\": $size, \"mtime\": $mtime, \"created_during_task\": $created_during}"
    else
        echo "{\"exists\": false, \"size\": 0, \"mtime\": 0, \"created_during_task\": false}"
    fi
}

# Analyze CSV content using Python
CSV_ANALYSIS=$(python3 << EOF
import csv
import json
import os

csv_path = "$CSV_FILE"
result = {
    "row_count": 0,
    "has_header": False,
    "col_count": 0,
    "roi_names": [],
    "numeric_cols": 0,
    "phases_detected": []
}

if os.path.exists(csv_path):
    try:
        with open(csv_path, 'r') as f:
            reader = csv.reader(f)
            rows = list(reader)
            if len(rows) > 0:
                result["has_header"] = True
                result["col_count"] = len(rows[0])
                # Check for numeric columns in first data row
                if len(rows) > 1:
                    data_row = rows[1]
                    num_cnt = 0
                    for val in data_row[1:]: # Skip first col (usually name)
                        try:
                            float(val)
                            num_cnt += 1
                        except ValueError:
                            pass
                    result["numeric_cols"] = num_cnt
                
                result["row_count"] = len(rows) - 1 # Exclude header
                
                # Extract ROI names
                names = [r[0] for r in rows[1:] if r]
                result["roi_names"] = names
                
                # Check for Phase A/B naming
                has_a = any(x in n.lower() for n in names for x in ['phasea', 'phase_a', 'phase a'])
                has_b = any(x in n.lower() for n in names for x in ['phaseb', 'phase_b', 'phase b'])
                if has_a: result["phases_detected"].append("A")
                if has_b: result["phases_detected"].append("B")
    except Exception as e:
        result["error"] = str(e)

print(json.dumps(result))
EOF
)

# Analyze ZIP file (ROI count) using Python
ZIP_ANALYSIS=$(python3 << EOF
import zipfile
import json
import os

zip_path = "$ROIS_FILE"
result = {"roi_count": 0}

if os.path.exists(zip_path):
    try:
        with zipfile.ZipFile(zip_path, 'r') as zf:
            rois = [f for f in zf.namelist() if f.endswith('.roi')]
            result["roi_count"] = len(rois)
    except Exception:
        pass

print(json.dumps(result))
EOF
)

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "rois_file": $(get_file_info "$ROIS_FILE"),
    "csv_file": $(get_file_info "$CSV_FILE"),
    "img_file": $(get_file_info "$IMG_FILE"),
    "report_file": $(get_file_info "$REPORT_FILE"),
    "csv_analysis": $CSV_ANALYSIS,
    "zip_analysis": $ZIP_ANALYSIS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json