#!/bin/bash
echo "=== Exporting Surface Roughness Profiling Results ==="

# Get timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
RESULTS_DIR="/home/ga/Fiji_Data/results/surface"
JSON_OUT="/tmp/task_result.json"

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Helper to check file status
check_file() {
    local fpath="$1"
    if [ -f "$fpath" ]; then
        local mtime=$(stat -c %Y "$fpath")
        local size=$(stat -c %s "$fpath")
        local created_during="false"
        if [ "$mtime" -gt "$TASK_START" ]; then created_during="true"; fi
        echo "{\"exists\": true, \"size\": $size, \"created_during_task\": $created_during}"
    else
        echo "{\"exists\": false, \"size\": 0, \"created_during_task\": false}"
    fi
}

# 1. Gather File Status
HP_STATUS=$(check_file "$RESULTS_DIR/horizontal_profile.csv")
VP_STATUS=$(check_file "$RESULTS_DIR/vertical_profile.csv")
REPORT_STATUS=$(check_file "$RESULTS_DIR/roughness_report.txt")
PLOT_STATUS=$(check_file "$RESULTS_DIR/surface_plot_3d.png")
IMG_STATUS=$(check_file "$RESULTS_DIR/annotated_image.png")

# 2. Parse Roughness Report Content
REPORT_CONTENT="{}"
if [ -f "$RESULTS_DIR/roughness_report.txt" ]; then
    # Python script to parse the key-value pairs robustly
    REPORT_CONTENT=$(python3 -c "
import sys, json, re
try:
    with open('$RESULTS_DIR/roughness_report.txt', 'r') as f:
        text = f.read()
    data = {}
    # Find patterns like Ra=12.3 or Ra: 12.3
    for key in ['Ra', 'Rq', 'Rz', 'Mean_height', 'Median_height']:
        m = re.search(key + r'[^0-9\-]*([0-9\.]+)', text, re.IGNORECASE)
        if m:
            data[key] = float(m.group(1))
    print(json.dumps(data))
except:
    print('{}')
")
fi

# 3. Read Ground Truth (generated in setup)
GROUND_TRUTH="{}"
if [ -f "/tmp/ground_truth_stats.json" ]; then
    GROUND_TRUTH=$(cat /tmp/ground_truth_stats.json)
fi

# 4. Check CSV Content (Basic validity check)
CSV_VALIDITY=$(python3 -c "
import sys, json, os
hp = '$RESULTS_DIR/horizontal_profile.csv'
vp = '$RESULTS_DIR/vertical_profile.csv'
res = {'horizontal_rows': 0, 'vertical_rows': 0}
try:
    if os.path.exists(hp):
        with open(hp) as f: res['horizontal_rows'] = sum(1 for line in f if line.strip() and line[0].isdigit())
    if os.path.exists(vp):
        with open(vp) as f: res['vertical_rows'] = sum(1 for line in f if line.strip() and line[0].isdigit())
except: pass
print(json.dumps(res))
")

# 5. Construct Final JSON
cat > "$JSON_OUT" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "files": {
        "horizontal_profile": $HP_STATUS,
        "vertical_profile": $VP_STATUS,
        "roughness_report": $REPORT_STATUS,
        "surface_plot": $PLOT_STATUS,
        "annotated_image": $IMG_STATUS
    },
    "report_values": $REPORT_CONTENT,
    "ground_truth": $GROUND_TRUTH,
    "csv_stats": $CSV_VALIDITY,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 "$JSON_OUT"
echo "Export complete. Result saved to $JSON_OUT"