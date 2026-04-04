#!/bin/bash
echo "=== Exporting Task Results ==="

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
RESULTS_DIR="/home/ga/Fiji_Data/results/polarity"
DATA_DIR="/home/ga/Fiji_Data/raw/BBBC005"

CSV_FILE="$RESULTS_DIR/displacement_metrics.csv"
IMG_FILE="$RESULTS_DIR/annotated_cell.png"
TARGET_W1_NAME=$(cat /tmp/target_image_w1.txt 2>/dev/null)
TARGET_W2_NAME="${TARGET_W1_NAME/w1/w2}"

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Calculate Ground Truth using Python (running inside the container)
# We calculate this NOW based on the file we expected them to use.
# This avoids needing complex image processing dependencies in the verifier.
echo "Calculating ground truth..."
python3 << EOF > /tmp/ground_truth.json
import json
import os
import numpy as np
import math
from skimage import io, filters, measure

data_dir = "$DATA_DIR"
w1_name = "$TARGET_W1_NAME"
w2_name = "$TARGET_W2_NAME"
scale = 0.65

result = {
    "ground_truth_calculated": False,
    "gt_displacement_um": 0.0,
    "gt_cell_x": 0.0,
    "gt_cell_y": 0.0,
    "gt_nuc_x": 0.0,
    "gt_nuc_y": 0.0
}

try:
    w1_path = os.path.join(data_dir, w1_name)
    w2_path = os.path.join(data_dir, w2_name)

    if os.path.exists(w1_path) and os.path.exists(w2_path):
        # Load images
        img_cell = io.imread(w1_path)
        img_nuc = io.imread(w2_path)

        # Simple Otsu thresholding for centroid detection
        # This mirrors what a standard "Analyze Particles" would do
        thresh_cell = filters.threshold_otsu(img_cell)
        binary_cell = img_cell > thresh_cell
        
        thresh_nuc = filters.threshold_otsu(img_nuc)
        binary_nuc = img_nuc > thresh_nuc

        # Calculate moments/centroids
        M_cell = measure.moments(binary_cell)
        cy_cell = M_cell[1, 0] / M_cell[0, 0]
        cx_cell = M_cell[0, 1] / M_cell[0, 0]

        M_nuc = measure.moments(binary_nuc)
        cy_nuc = M_nuc[1, 0] / M_nuc[0, 0]
        cx_nuc = M_nuc[0, 1] / M_nuc[0, 0]

        # Calculate distance
        dx = cx_cell - cx_nuc
        dy = cy_cell - cy_nuc
        dist_px = math.sqrt(dx*dx + dy*dy)
        dist_um = dist_px * scale

        result["ground_truth_calculated"] = True
        result["gt_displacement_um"] = float(dist_um)
        result["gt_cell_x"] = float(cx_cell)
        result["gt_cell_y"] = float(cy_cell)
        result["gt_nuc_x"] = float(cx_nuc)
        result["gt_nuc_y"] = float(cy_nuc)
    else:
        result["error"] = "Input files not found"

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
EOF

# 3. Analyze Agent Output (CSV)
CSV_EXISTS="false"
CSV_VALID="false"
AGENT_DISPLACEMENT=0
AGENT_CELL_X=0
AGENT_CELL_Y=0

if [ -f "$CSV_FILE" ]; then
    CSV_EXISTS="true"
    # Read CSV values using Python
    python3 << EOF > /tmp/agent_csv_data.json
import json
import csv

csv_file = "$CSV_FILE"
data = {
    "valid": False,
    "displacement": 0.0,
    "cell_x": 0.0,
    "cell_y": 0.0,
    "rows": 0
}

try:
    with open(csv_file, 'r') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
        data["rows"] = len(rows)
        if len(rows) > 0:
            row = rows[0]
            # Try to handle case-insensitive headers
            row = {k.lower().strip(): v for k, v in row.items()}
            
            # Extract displacement (flexible naming)
            disp_key = next((k for k in row if 'displacement' in k or 'dist' in k), None)
            if disp_key:
                data["displacement"] = float(row[disp_key])
                data["valid"] = True
            
            # Extract Coordinates
            cx_key = next((k for k in row if 'cell_x' in k), None)
            cy_key = next((k for k in row if 'cell_y' in k), None)
            if cx_key: data["cell_x"] = float(row[cx_key])
            if cy_key: data["cell_y"] = float(row[cy_key])
            
except Exception as e:
    data["error"] = str(e)

print(json.dumps(data))
EOF
fi

# 4. Analyze Agent Output (Image)
IMG_EXISTS="false"
IMG_ANNOTATED="false"
if [ -f "$IMG_FILE" ]; then
    IMG_EXISTS="true"
    IMG_MTIME=$(stat -c %Y "$IMG_FILE")
    # Check if image has "pure white" pixels (255,255,255) indicating annotation
    # Normal fluorescence data is rarely pure saturated white unless clipped, but annotations usually are.
    # We use python to check quickly.
    python3 << EOF > /tmp/image_check.json
import json
import numpy as np
from PIL import Image

try:
    img = Image.open("$IMG_FILE")
    img_arr = np.array(img)
    
    # Check if RGB
    is_rgb = len(img_arr.shape) == 3 and img_arr.shape[2] >= 3
    
    # Check for annotation (white pixels)
    # Looking for [255, 255, 255]
    has_annotation = False
    if is_rgb:
        # Check pixels that are exactly white or very close
        white_mask = np.all(img_arr[:,:,:3] > 250, axis=2)
        if np.sum(white_mask) > 10: # At least 10 pixels
            has_annotation = True
            
    print(json.dumps({"is_rgb": is_rgb, "has_annotation": has_annotation}))
except:
    print(json.dumps({"is_rgb": False, "has_annotation": False}))
EOF
fi

# 5. Compile Final JSON
cat << EOF > /tmp/task_result.json
{
    "task_start": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "image_exists": $IMG_EXISTS,
    "ground_truth": $(cat /tmp/ground_truth.json),
    "agent_csv": $(cat /tmp/agent_csv_data.json 2>/dev/null || echo "{}"),
    "agent_image": $(cat /tmp/image_check.json 2>/dev/null || echo "{}"),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json
echo "Export complete. Result:"
cat /tmp/task_result.json