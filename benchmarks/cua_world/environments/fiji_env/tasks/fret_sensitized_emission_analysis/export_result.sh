#!/bin/bash
echo "=== Exporting FRET Analysis Results ==="

# Result paths
RESULTS_DIR="/home/ga/Fiji_Data/results/fret"
RESULT_IMAGE="$RESULTS_DIR/corrected_fret.tif"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check file existence and metadata
FILE_EXISTS="false"
FILE_SIZE=0
FILE_CREATED_DURING_TASK="false"

if [ -f "$RESULT_IMAGE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$RESULT_IMAGE")
    FILE_MTIME=$(stat -c%Y "$RESULT_IMAGE")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Run analysis python script INSIDE container to verify pixel values
# This avoids dependency issues on the host verifier
cat << 'PYEOF' > /tmp/analyze_fret_result.py
import numpy as np
from PIL import Image
import json
import sys
import os

result_path = "/home/ga/Fiji_Data/results/fret/corrected_fret.tif"
output_json = "/tmp/fret_analysis_metrics.json"

metrics = {
    "valid_image": False,
    "donor_bleed_mean": 999.0,
    "acceptor_bleed_mean": 999.0,
    "fret_signal_mean": 0.0,
    "is_float": False
}

if os.path.exists(result_path):
    try:
        # Load image
        img = Image.open(result_path)
        arr = np.array(img)
        metrics["valid_image"] = True
        
        # Check if float (Fiji 32-bit float saves as TIFF float)
        if arr.dtype == np.float32 or arr.dtype == np.float64:
            metrics["is_float"] = True
        
        # Define ROIs (matching generation script)
        # y_slice, x_slice
        # Donor Blob Center: 125, 125. Radius 60.
        # Acceptor Blob Center: 387, 125. Radius 60.
        # FRET Blob Center: 256, 387. Radius 60.
        
        # We sample central 20x20 pixels of each blob to be safe
        roi_donor_bleed = arr[115:135, 115:135]
        roi_acceptor_bleed = arr[115:135, 377:397]
        roi_fret = arr[377:397, 246:266]
        
        metrics["donor_bleed_mean"] = float(np.mean(roi_donor_bleed))
        metrics["acceptor_bleed_mean"] = float(np.mean(roi_acceptor_bleed))
        metrics["fret_signal_mean"] = float(np.mean(roi_fret))
        
    except Exception as e:
        metrics["error"] = str(e)

with open(output_json, 'w') as f:
    json.dump(metrics, f)
PYEOF

# Execute analysis
python3 /tmp/analyze_fret_result.py

# Combine into final JSON
cat << EOF > /tmp/task_result.json
{
    "task_start": $TASK_START,
    "output_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "screenshot_path": "/tmp/task_final.png",
    "metrics": $(cat /tmp/fret_analysis_metrics.json 2>/dev/null || echo "{}")
}
EOF

# Set permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json