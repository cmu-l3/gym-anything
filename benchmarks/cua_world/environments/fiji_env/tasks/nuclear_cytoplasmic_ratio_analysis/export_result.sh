#!/bin/bash
echo "=== Exporting Nuclear-Cytoplasmic Ratio Results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

REPORT_PATH="/home/ga/Fiji_Data/results/translocation/ratio_report.txt"
ROIS_PATH="/home/ga/Fiji_Data/results/translocation/rois.zip"
DAPI_PATH="/home/ga/Fiji_Data/raw/translocation/cell_dapi.tif"
SIGNAL_PATH="/home/ga/Fiji_Data/raw/translocation/cell_signal.tif"

# 1. Check Files
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_CREATED_DURING="false"
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_PATH")
    F_TIME=$(stat -c %Y "$REPORT_PATH")
    if [ "$F_TIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING="true"
    fi
fi

ROIS_EXISTS="false"
if [ -f "$ROIS_PATH" ]; then
    ROIS_EXISTS="true"
fi

# 2. Calculate Ground Truth using Python
# We replicate the intended analysis programmatically to verify the agent's math.
# Logic: Otsu threshold DAPI -> Nucleus Mask. Dilate (15px) -> XOR -> Cyto Mask. Measure Signal.
echo "Calculating ground truth..."
python3 << PYEOF > /tmp/gt_calculation.json
import numpy as np
import json
import os
from PIL import Image
from skimage.filters import threshold_otsu
from skimage.morphology import dilation, disk

try:
    # Load images
    dapi = np.array(Image.open("$DAPI_PATH"))
    signal = np.array(Image.open("$SIGNAL_PATH"))

    # 1. Segment Nucleus (Otsu)
    thresh = threshold_otsu(dapi)
    nuc_mask = dapi > thresh

    # 2. Create Cytoplasm (Donut)
    # Task says "Enlarge by 15 pixels"
    # Dilation with disk(15) approximates this
    struct = disk(15)
    dilated = dilation(nuc_mask.astype(np.uint8), struct)
    
    # Cyto = Dilated AND NOT Nucleus
    cyto_mask = (dilated.astype(bool)) & (~nuc_mask)

    # 3. Measure Intensities
    # Handle case where mask might be empty (unlikely with this data)
    if np.sum(nuc_mask) == 0:
        nuc_mean = 0
    else:
        nuc_mean = np.mean(signal[nuc_mask])

    if np.sum(cyto_mask) == 0:
        cyto_mean = 0
    else:
        cyto_mean = np.mean(signal[cyto_mask])

    # 4. Calculate Ratio
    if cyto_mean > 0:
        ratio = nuc_mean / cyto_mean
    else:
        ratio = 0.0

    print(json.dumps({
        "gt_nuc_mean": float(nuc_mean),
        "gt_cyto_mean": float(cyto_mean),
        "gt_ratio": float(ratio),
        "success": True
    }))

except Exception as e:
    print(json.dumps({
        "success": False,
        "error": str(e),
        "gt_ratio": 0.0
    }))
PYEOF

# 3. Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 4. Compile JSON
GT_DATA=$(cat /tmp/gt_calculation.json)

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_created_during": $REPORT_CREATED_DURING,
    "report_content": "$REPORT_CONTENT",
    "rois_exists": $ROIS_EXISTS,
    "ground_truth": $GT_DATA,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json