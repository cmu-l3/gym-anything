#!/bin/bash
echo "=== Exporting Flat-Field Correction Result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Directories
RESULTS_DIR="/home/ga/Fiji_Data/results/flatfield"

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Helper function to get file info
get_file_info() {
    local fpath="$1"
    if [ -f "$fpath" ]; then
        local mtime=$(stat -c %Y "$fpath")
        local size=$(stat -c %s "$fpath")
        local created="false"
        if [ "$mtime" -gt "$TASK_START" ]; then created="true"; fi
        echo "{\"exists\": true, \"size\": $size, \"created_during_task\": $created}"
    else
        echo "{\"exists\": false, \"size\": 0, \"created_during_task\": false}"
    fi
}

# Analyze images using Python to verify correction quality
# We calculate the metrics INDEPENDENTLY of what the agent reported
echo "Analyzing output images..."
ANALYSIS_JSON=$(python3 << 'PYEOF'
import json
import os
import numpy as np
from PIL import Image

results_dir = "/home/ga/Fiji_Data/results/flatfield"
corr_path = os.path.join(results_dir, "corrected_image.tif")
ref_path = os.path.join(results_dir, "flatfield_reference.tif")
csv_path = os.path.join(results_dir, "uniformity_report.csv")
txt_path = os.path.join(results_dir, "correction_summary.txt")

metrics = {
    "corrected_image_valid": False,
    "reference_image_smooth": False,
    "ratio_improved": False,
    "cv_improved": False,
    "measured_ratio": 0.0,
    "measured_cv": 0.0,
    "csv_parsed": False,
    "txt_parsed": False,
    "csv_has_headers": False
}

try:
    # 1. Analyze Corrected Image
    if os.path.exists(corr_path):
        img = Image.open(corr_path)
        arr = np.array(img)
        metrics["corrected_image_valid"] = True
        
        # Calculate uniformity
        h, w = arr.shape
        center_roi = arr[int(h*0.4):int(h*0.6), int(w*0.4):int(w*0.6)]
        
        # Corners
        c_tl = arr[0:int(h*0.2), 0:int(w*0.2)]
        c_tr = arr[0:int(h*0.2), int(w*0.8):]
        c_bl = arr[int(h*0.8):, 0:int(w*0.2)]
        c_br = arr[int(h*0.8):, int(w*0.8):]
        
        mean_center = np.mean(center_roi)
        mean_corners = np.mean([np.mean(c_tl), np.mean(c_tr), np.mean(c_bl), np.mean(c_br)])
        
        if mean_center > 0:
            ratio = mean_corners / mean_center
            metrics["measured_ratio"] = float(ratio)
        
        metrics["measured_cv"] = float(np.std(arr) / np.mean(arr) * 100) if np.mean(arr) > 0 else 0

        # Load initial metrics to compare
        try:
            with open("/tmp/initial_metrics.txt") as f:
                for line in f:
                    if "initial_ratio" in line:
                        init_ratio = float(line.split("=")[1])
                        # Improvement: Ratio should be closer to 1.0 than initial
                        if abs(1.0 - ratio) < abs(1.0 - init_ratio):
                            metrics["ratio_improved"] = True
                    if "initial_cv" in line:
                        init_cv = float(line.split("=")[1])
                        # Improvement: CV should be lower
                        if metrics["measured_cv"] < init_cv:
                            metrics["cv_improved"] = True
        except:
            pass

    # 2. Analyze Flat-Field Reference (Check if it's blurred/smooth)
    if os.path.exists(ref_path):
        ref = Image.open(ref_path)
        ref_arr = np.array(ref)
        
        # Check local variance vs global variance
        # A heavily blurred image has low high-frequency content
        # Simple check: Compare std dev of difference between adjacent pixels vs global std
        diff_y = np.diff(ref_arr, axis=0)
        diff_x = np.diff(ref_arr, axis=1)
        mean_diff = (np.mean(np.abs(diff_y)) + np.mean(np.abs(diff_x))) / 2
        global_std = np.std(ref_arr)
        
        # If mean_diff is very small compared to range, it's smooth
        if mean_diff < (global_std * 0.2): # Heuristic for "smooth"
            metrics["reference_image_smooth"] = True

    # 3. Check CSV
    if os.path.exists(csv_path):
        with open(csv_path) as f:
            lines = f.readlines()
            if len(lines) >= 2 and "," in lines[0]:
                metrics["csv_parsed"] = True
                header = lines[0].lower()
                if "quadrant" in header or "center" in header:
                    metrics["csv_has_headers"] = True

    # 4. Check Text Summary
    if os.path.exists(txt_path):
        with open(txt_path) as f:
            content = f.read().lower()
            if "improvement" in content and ("yes" in content or "true" in content):
                metrics["txt_parsed"] = True

except Exception as e:
    metrics["error"] = str(e)

print(json.dumps(metrics))
PYEOF
)

# Construct final JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "corrected_image": $(get_file_info "$RESULTS_DIR/corrected_image.tif"),
    "flatfield_reference": $(get_file_info "$RESULTS_DIR/flatfield_reference.tif"),
    "uniformity_report": $(get_file_info "$RESULTS_DIR/uniformity_report.csv"),
    "correction_summary": $(get_file_info "$RESULTS_DIR/correction_summary.txt"),
    "analysis": $ANALYSIS_JSON
}
EOF

# Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="