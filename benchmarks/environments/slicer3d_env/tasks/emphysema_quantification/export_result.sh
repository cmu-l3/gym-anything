#!/bin/bash
echo "=== Exporting Emphysema Quantification Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

LIDC_DIR="/home/ga/Documents/SlicerData/LIDC"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || true
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
fi
echo "Slicer running: $SLICER_RUNNING"

# Get task timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Check for segmentation file
SEGMENTATION_FILE="$LIDC_DIR/lung_segmentation.nii.gz"
SEGMENTATION_EXISTS="false"
SEGMENTATION_VALID="false"
SEGMENTATION_SIZE=0
SEGMENTATION_MTIME=0

# Check multiple possible locations
POSSIBLE_SEG_PATHS=(
    "$LIDC_DIR/lung_segmentation.nii.gz"
    "$LIDC_DIR/lung_segmentation.nii"
    "$LIDC_DIR/Segmentation.nii.gz"
    "$LIDC_DIR/Lungs.nii.gz"
    "/home/ga/Documents/lung_segmentation.nii.gz"
    "/home/ga/lung_segmentation.nii.gz"
)

for path in "${POSSIBLE_SEG_PATHS[@]}"; do
    if [ -f "$path" ]; then
        SEGMENTATION_EXISTS="true"
        SEGMENTATION_SIZE=$(stat -c%s "$path" 2>/dev/null || echo "0")
        SEGMENTATION_MTIME=$(stat -c%Y "$path" 2>/dev/null || echo "0")
        
        # Copy to expected location if different
        if [ "$path" != "$SEGMENTATION_FILE" ]; then
            cp "$path" "$SEGMENTATION_FILE" 2>/dev/null || true
        fi
        
        # Check if created after task start
        if [ "$SEGMENTATION_MTIME" -gt "$TASK_START" ] && [ "$SEGMENTATION_SIZE" -gt 1000 ]; then
            SEGMENTATION_VALID="true"
        fi
        
        echo "Found segmentation: $path (size: $SEGMENTATION_SIZE, valid: $SEGMENTATION_VALID)"
        break
    fi
done

# Check for report file
REPORT_FILE="$LIDC_DIR/emphysema_report.json"
REPORT_EXISTS="false"

POSSIBLE_REPORT_PATHS=(
    "$LIDC_DIR/emphysema_report.json"
    "$LIDC_DIR/report.json"
    "$LIDC_DIR/emphysema.json"
    "/home/ga/Documents/emphysema_report.json"
    "/home/ga/emphysema_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        # Copy to expected location if different
        if [ "$path" != "$REPORT_FILE" ]; then
            cp "$path" "$REPORT_FILE" 2>/dev/null || true
        fi
        echo "Found report: $path"
        break
    fi
done

# Read agent's report values if exists
AGENT_LAA950=""
AGENT_VOLUME=""
AGENT_CLASSIFICATION=""
AGENT_MEAN_DENSITY=""
AGENT_PERC15=""

if [ -f "$REPORT_FILE" ]; then
    echo "Parsing agent report..."
    
    AGENT_LAA950=$(python3 -c "
import json
try:
    with open('$REPORT_FILE', 'r') as f:
        d = json.load(f)
    v = d.get('laa_950_percent', d.get('laa950', d.get('LAA_950', d.get('laa_950', ''))))
    if v != '': print(float(v))
except Exception as e:
    pass
" 2>/dev/null || echo "")
    
    AGENT_VOLUME=$(python3 -c "
import json
try:
    with open('$REPORT_FILE', 'r') as f:
        d = json.load(f)
    v = d.get('total_lung_volume_ml', d.get('lung_volume_ml', d.get('volume_ml', d.get('lung_volume', ''))))
    if v != '': print(float(v))
except Exception as e:
    pass
" 2>/dev/null || echo "")
    
    AGENT_CLASSIFICATION=$(python3 -c "
import json
try:
    with open('$REPORT_FILE', 'r') as f:
        d = json.load(f)
    print(d.get('severity_classification', d.get('classification', d.get('severity', ''))))
except Exception as e:
    pass
" 2>/dev/null || echo "")
    
    AGENT_MEAN_DENSITY=$(python3 -c "
import json
try:
    with open('$REPORT_FILE', 'r') as f:
        d = json.load(f)
    v = d.get('mean_lung_density_hu', d.get('mean_density', d.get('mld', '')))
    if v != '': print(float(v))
except Exception as e:
    pass
" 2>/dev/null || echo "")
    
    AGENT_PERC15=$(python3 -c "
import json
try:
    with open('$REPORT_FILE', 'r') as f:
        d = json.load(f)
    v = d.get('perc15_density_hu', d.get('perc15', d.get('p15', '')))
    if v != '': print(float(v))
except Exception as e:
    pass
" 2>/dev/null || echo "")
    
    echo "  LAA-950: $AGENT_LAA950"
    echo "  Volume: $AGENT_VOLUME"
    echo "  Classification: $AGENT_CLASSIFICATION"
    echo "  Mean Density: $AGENT_MEAN_DENSITY"
    echo "  Perc15: $AGENT_PERC15"
fi

# Read ground truth values
GT_LAA950=""
GT_VOLUME=""
GT_CLASSIFICATION=""
GT_MEAN_DENSITY=""
GT_PERC15=""

if [ -f "$GROUND_TRUTH_DIR/emphysema_gt.json" ]; then
    echo "Reading ground truth..."
    
    GT_LAA950=$(python3 -c "
import json
with open('$GROUND_TRUTH_DIR/emphysema_gt.json', 'r') as f:
    d = json.load(f)
print(d.get('laa_950_percent', ''))
" 2>/dev/null || echo "")
    
    GT_VOLUME=$(python3 -c "
import json
with open('$GROUND_TRUTH_DIR/emphysema_gt.json', 'r') as f:
    d = json.load(f)
print(d.get('total_lung_volume_ml', ''))
" 2>/dev/null || echo "")
    
    GT_CLASSIFICATION=$(python3 -c "
import json
with open('$GROUND_TRUTH_DIR/emphysema_gt.json', 'r') as f:
    d = json.load(f)
print(d.get('severity_classification', ''))
" 2>/dev/null || echo "")
    
    GT_MEAN_DENSITY=$(python3 -c "
import json
with open('$GROUND_TRUTH_DIR/emphysema_gt.json', 'r') as f:
    d = json.load(f)
print(d.get('mean_lung_density_hu', ''))
" 2>/dev/null || echo "")
    
    GT_PERC15=$(python3 -c "
import json
with open('$GROUND_TRUTH_DIR/emphysema_gt.json', 'r') as f:
    d = json.load(f)
print(d.get('perc15_density_hu', ''))
" 2>/dev/null || echo "")
fi

# Calculate Dice coefficient if both segmentations exist
DICE_SCORE="-1"
if [ "$SEGMENTATION_VALID" = "true" ] && [ -f "$GROUND_TRUTH_DIR/lung_mask_gt.nii.gz" ]; then
    echo "Calculating Dice coefficient..."
    DICE_SCORE=$(python3 << 'PYEOF'
import sys
try:
    import nibabel as nib
    import numpy as np
    
    agent_seg = nib.load("/home/ga/Documents/SlicerData/LIDC/lung_segmentation.nii.gz").get_fdata()
    gt_seg = nib.load("/var/lib/slicer/ground_truth/lung_mask_gt.nii.gz").get_fdata()
    
    # Binarize
    agent_binary = (agent_seg > 0).astype(bool)
    gt_binary = (gt_seg > 0).astype(bool)
    
    # Handle shape mismatch by checking minimum overlap region
    if agent_binary.shape != gt_binary.shape:
        print("-1")
        sys.exit(0)
    
    intersection = np.sum(agent_binary & gt_binary)
    sum_vols = np.sum(agent_binary) + np.sum(gt_binary)
    
    if sum_vols == 0:
        dice = 0.0
    else:
        dice = 2.0 * intersection / sum_vols
    
    print(f"{dice:.4f}")
except Exception as e:
    print(f"-1", file=sys.stderr)
    print("-1")
PYEOF
    )
    echo "Dice coefficient: $DICE_SCORE"
fi

# Check for screenshot evidence
SCREENSHOT_EXISTS="false"
if [ -f /tmp/task_final_state.png ]; then
    SCREENSHOT_EXISTS="true"
fi

# Copy files for verification
echo "Preparing files for verification..."
cp "$GROUND_TRUTH_DIR/emphysema_gt.json" /tmp/emphysema_ground_truth.json 2>/dev/null || true
cp "$GROUND_TRUTH_DIR/lung_mask_gt.nii.gz" /tmp/lung_mask_gt.nii.gz 2>/dev/null || true

if [ -f "$SEGMENTATION_FILE" ]; then
    cp "$SEGMENTATION_FILE" /tmp/agent_lung_segmentation.nii.gz 2>/dev/null || true
fi

if [ -f "$REPORT_FILE" ]; then
    cp "$REPORT_FILE" /tmp/agent_emphysema_report.json 2>/dev/null || true
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/emphysema_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
  "task_id": "emphysema_quantification@1",
  "task_start_time": $TASK_START,
  "task_end_time": $TASK_END,
  "slicer_was_running": $SLICER_RUNNING,
  "segmentation_exists": $SEGMENTATION_EXISTS,
  "segmentation_valid": $SEGMENTATION_VALID,
  "segmentation_size_bytes": $SEGMENTATION_SIZE,
  "report_exists": $REPORT_EXISTS,
  "screenshot_exists": $SCREENSHOT_EXISTS,
  "dice_coefficient": "$DICE_SCORE",
  "agent_results": {
    "laa_950_percent": "$AGENT_LAA950",
    "total_lung_volume_ml": "$AGENT_VOLUME",
    "severity_classification": "$AGENT_CLASSIFICATION",
    "mean_lung_density_hu": "$AGENT_MEAN_DENSITY",
    "perc15_density_hu": "$AGENT_PERC15"
  },
  "ground_truth": {
    "laa_950_percent": "$GT_LAA950",
    "total_lung_volume_ml": "$GT_VOLUME",
    "severity_classification": "$GT_CLASSIFICATION",
    "mean_lung_density_hu": "$GT_MEAN_DENSITY",
    "perc15_density_hu": "$GT_PERC15"
  },
  "files": {
    "segmentation": "$SEGMENTATION_FILE",
    "report": "$REPORT_FILE",
    "ground_truth_json": "$GROUND_TRUTH_DIR/emphysema_gt.json",
    "ground_truth_mask": "$GROUND_TRUTH_DIR/lung_mask_gt.nii.gz"
  }
}
EOF

# Move to final location
rm -f /tmp/emphysema_task_result.json 2>/dev/null || sudo rm -f /tmp/emphysema_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/emphysema_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/emphysema_task_result.json
chmod 666 /tmp/emphysema_task_result.json 2>/dev/null || sudo chmod 666 /tmp/emphysema_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Complete ==="
echo "Results exported to: /tmp/emphysema_task_result.json"
cat /tmp/emphysema_task_result.json