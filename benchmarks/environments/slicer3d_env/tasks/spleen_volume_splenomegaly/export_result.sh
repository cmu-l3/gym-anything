#!/bin/bash
echo "=== Exporting Spleen Volume Task Results ==="

source /workspace/scripts/task_utils.sh

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
RESULT_FILE="/tmp/task_result.json"

# Get task timing info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Get case ID
CASE_ID=$(cat /tmp/amos_case_id 2>/dev/null || echo "amos_0001")

# Take final screenshot first
echo "Capturing final screenshot..."
take_screenshot /tmp/task_final.png ga
sleep 1

# ================================================================
# CHECK SLICER STATE
# ================================================================
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    echo "Slicer is running"
    
    # Try to export any segmentations from Slicer before checking files
    cat > /tmp/export_spleen_seg.py << 'PYEOF'
import slicer
import os
import json

output_dir = "/home/ga/Documents/SlicerData/AMOS"
os.makedirs(output_dir, exist_ok=True)

print("Exporting segmentations from Slicer...")

# Find all segmentation nodes
seg_nodes = slicer.util.getNodesByClass("vtkMRMLSegmentationNode")
print(f"Found {len(seg_nodes)} segmentation node(s)")

exported = False
for seg_node in seg_nodes:
    seg_name = seg_node.GetName()
    print(f"Processing segmentation: {seg_name}")
    
    # Export to labelmap then save as NIfTI
    labelmapNode = slicer.mrmlScene.AddNewNodeByClass("vtkMRMLLabelMapVolumeNode")
    slicer.modules.segmentations.logic().ExportAllSegmentsToLabelmapNode(seg_node, labelmapNode)
    
    output_path = os.path.join(output_dir, "spleen_segmentation.nii.gz")
    success = slicer.util.saveNode(labelmapNode, output_path)
    
    if success:
        print(f"Exported segmentation to {output_path}")
        exported = True
    
    slicer.mrmlScene.RemoveNode(labelmapNode)

# Also try to get segment statistics if available
try:
    import SegmentStatistics
    for seg_node in seg_nodes:
        stats_logic = SegmentStatistics.SegmentStatisticsLogic()
        stats_logic.getParameterNode().SetParameter("Segmentation", seg_node.GetID())
        stats_logic.computeStatistics()
        stats = stats_logic.getStatistics()
        
        for segmentId in stats.get("SegmentIDs", []):
            volume_mm3 = stats.get(f"{segmentId}.LabelmapSegmentStatisticsPlugin.volume_mm3", 0)
            volume_ml = volume_mm3 / 1000.0
            print(f"Segment {segmentId} volume: {volume_ml:.2f} mL")
except Exception as e:
    print(f"Could not compute statistics: {e}")

print("Export complete")
PYEOF

    # Run export script (with timeout)
    timeout 30 sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --no-splash --python-script /tmp/export_spleen_seg.py > /tmp/slicer_export.log 2>&1 &
    EXPORT_PID=$!
    sleep 15
    kill $EXPORT_PID 2>/dev/null || true
fi

# ================================================================
# CHECK FOR SEGMENTATION FILE
# ================================================================
SEGMENTATION_EXISTS="false"
SEGMENTATION_PATH=""
SEGMENTATION_SIZE=0
SEGMENTATION_CREATED_DURING_TASK="false"

# Check multiple possible locations
POSSIBLE_SEG_PATHS=(
    "$AMOS_DIR/spleen_segmentation.nii.gz"
    "$AMOS_DIR/spleen_segmentation.nii"
    "$AMOS_DIR/Segmentation.nii.gz"
    "$AMOS_DIR/Spleen.nii.gz"
    "/home/ga/Documents/spleen_segmentation.nii.gz"
    "/home/ga/spleen_segmentation.nii.gz"
)

for path in "${POSSIBLE_SEG_PATHS[@]}"; do
    if [ -f "$path" ]; then
        SEGMENTATION_EXISTS="true"
        SEGMENTATION_PATH="$path"
        SEGMENTATION_SIZE=$(stat -c %s "$path" 2>/dev/null || echo "0")
        
        # Check if file was created during the task (anti-gaming)
        FILE_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
            SEGMENTATION_CREATED_DURING_TASK="true"
        fi
        
        echo "Found segmentation at: $path (size: $SEGMENTATION_SIZE bytes)"
        
        # Copy to expected location if not there
        if [ "$path" != "$AMOS_DIR/spleen_segmentation.nii.gz" ]; then
            cp "$path" "$AMOS_DIR/spleen_segmentation.nii.gz" 2>/dev/null || true
        fi
        break
    fi
done

# ================================================================
# CHECK FOR REPORT FILE
# ================================================================
REPORT_EXISTS="false"
REPORT_PATH=""
AGENT_VOLUME_ML=""
AGENT_CLASSIFICATION=""

POSSIBLE_REPORT_PATHS=(
    "$AMOS_DIR/spleen_report.json"
    "$AMOS_DIR/report.json"
    "/home/ga/Documents/spleen_report.json"
    "/home/ga/spleen_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_PATH="$path"
        echo "Found report at: $path"
        
        # Parse report contents
        AGENT_VOLUME_ML=$(python3 -c "
import json
try:
    with open('$path', 'r') as f:
        data = json.load(f)
    vol = data.get('volume_ml', data.get('volume', data.get('spleen_volume', data.get('spleen_volume_ml', 0))))
    print(float(vol))
except Exception as e:
    print(0)
" 2>/dev/null || echo "0")

        AGENT_CLASSIFICATION=$(python3 -c "
import json
try:
    with open('$path', 'r') as f:
        data = json.load(f)
    cls = data.get('classification', data.get('clinical_classification', data.get('assessment', '')))
    print(cls)
except:
    print('')
" 2>/dev/null || echo "")
        
        echo "Reported volume: $AGENT_VOLUME_ML mL"
        echo "Reported classification: $AGENT_CLASSIFICATION"
        
        # Copy to expected location
        if [ "$path" != "$AMOS_DIR/spleen_report.json" ]; then
            cp "$path" "$AMOS_DIR/spleen_report.json" 2>/dev/null || true
        fi
        break
    fi
done

# ================================================================
# COMPUTE VERIFICATION METRICS
# ================================================================
echo "Computing verification metrics..."

DICE_SCORE="0"
VOLUME_ACCURACY="0"
AGENT_COMPUTED_VOLUME="0"
GT_VOLUME="0"
CORRECT_LOCATION="false"
FALSE_POSITIVE_RATE="1"

if [ "$SEGMENTATION_EXISTS" = "true" ] && [ "$SEGMENTATION_SIZE" -gt 1000 ]; then
    # Run verification computation
    python3 << PYEOF > /tmp/verification_metrics.json 2>/tmp/verification_error.log
import os
import sys
import json
import numpy as np

try:
    import nibabel as nib
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
    import nibabel as nib

agent_seg_path = "$AMOS_DIR/spleen_segmentation.nii.gz"
gt_labels_path = "$GROUND_TRUTH_DIR/${CASE_ID}_labels.nii.gz"
gt_json_path = "$GROUND_TRUTH_DIR/${CASE_ID}_spleen_gt.json"

results = {
    "dice_score": 0,
    "volume_accuracy": 0,
    "agent_volume_ml": 0,
    "gt_volume_ml": 0,
    "correct_location": False,
    "false_positive_rate": 1.0,
    "error_message": None
}

try:
    # Load agent segmentation
    agent_nii = nib.load(agent_seg_path)
    agent_data = agent_nii.get_fdata()
    agent_binary = (agent_data > 0).astype(np.uint8)
    
    # Calculate voxel volume
    voxel_dims = agent_nii.header.get_zooms()[:3]
    voxel_vol_mm3 = float(np.prod(voxel_dims))
    
    # Agent's segmented volume
    agent_vol_voxels = np.sum(agent_binary)
    agent_vol_ml = agent_vol_voxels * voxel_vol_mm3 / 1000.0
    results["agent_volume_ml"] = round(agent_vol_ml, 2)
    
    # Sanity check - volume should be physiologically plausible (50-2000 mL)
    if agent_vol_ml < 50 or agent_vol_ml > 2000:
        results["error_message"] = f"Volume {agent_vol_ml:.1f} mL outside physiological range"
    
    # Check anatomical location (spleen in left upper quadrant)
    if agent_vol_voxels > 0:
        coords = np.argwhere(agent_binary > 0)
        centroid = coords.mean(axis=0)
        
        # Get image center
        center_x = agent_data.shape[0] / 2
        center_y = agent_data.shape[1] / 2
        center_z = agent_data.shape[2] / 2
        
        # Spleen should be:
        # - Left side (higher x in standard orientation)
        # - Upper abdomen (higher z)
        # This is approximate - depends on image orientation
        x_offset = (centroid[0] - center_x) / center_x
        z_offset = (centroid[2] - center_z) / center_z
        
        # Check if generally in correct region (left and upper)
        results["correct_location"] = bool(x_offset > -0.3 and z_offset > 0)
        results["centroid_offset"] = {"x": float(x_offset), "z": float(z_offset)}
    
    # Load ground truth if available
    gt_spleen = None
    if os.path.exists(gt_labels_path):
        gt_nii = nib.load(gt_labels_path)
        gt_data = gt_nii.get_fdata()
        gt_spleen = (gt_data == 1).astype(np.uint8)  # Spleen is label 1
        
        gt_vol_voxels = np.sum(gt_spleen)
        gt_vol_ml = gt_vol_voxels * voxel_vol_mm3 / 1000.0
        results["gt_volume_ml"] = round(gt_vol_ml, 2)
        
        if gt_vol_voxels > 0:
            # Dice coefficient
            intersection = np.sum(agent_binary & gt_spleen)
            dice = 2 * intersection / (np.sum(agent_binary) + np.sum(gt_spleen))
            results["dice_score"] = round(float(dice), 4)
            
            # Volume accuracy
            if gt_vol_ml > 0:
                vol_error = abs(agent_vol_ml - gt_vol_ml) / gt_vol_ml
                results["volume_accuracy"] = round(max(0, 1.0 - vol_error), 4)
            
            # False positive rate
            false_positives = np.sum(agent_binary & ~gt_spleen)
            if np.sum(agent_binary) > 0:
                results["false_positive_rate"] = round(false_positives / np.sum(agent_binary), 4)
    
    elif os.path.exists(gt_json_path):
        # Use JSON ground truth (for synthetic data)
        with open(gt_json_path, 'r') as f:
            gt_info = json.load(f)
        gt_vol_ml = gt_info.get('spleen_volume_ml', 0)
        results["gt_volume_ml"] = gt_vol_ml
        
        if gt_vol_ml > 0:
            vol_error = abs(agent_vol_ml - gt_vol_ml) / gt_vol_ml
            results["volume_accuracy"] = round(max(0, 1.0 - vol_error), 4)
            # Can't compute dice without voxel-wise GT
            results["dice_score"] = results["volume_accuracy"] * 0.7  # Rough estimate

except Exception as e:
    results["error_message"] = str(e)

print(json.dumps(results, indent=2))
PYEOF

    # Read computed metrics
    if [ -f /tmp/verification_metrics.json ]; then
        DICE_SCORE=$(python3 -c "import json; print(json.load(open('/tmp/verification_metrics.json'))['dice_score'])" 2>/dev/null || echo "0")
        VOLUME_ACCURACY=$(python3 -c "import json; print(json.load(open('/tmp/verification_metrics.json'))['volume_accuracy'])" 2>/dev/null || echo "0")
        AGENT_COMPUTED_VOLUME=$(python3 -c "import json; print(json.load(open('/tmp/verification_metrics.json'))['agent_volume_ml'])" 2>/dev/null || echo "0")
        GT_VOLUME=$(python3 -c "import json; print(json.load(open('/tmp/verification_metrics.json'))['gt_volume_ml'])" 2>/dev/null || echo "0")
        CORRECT_LOCATION=$(python3 -c "import json; print(str(json.load(open('/tmp/verification_metrics.json'))['correct_location']).lower())" 2>/dev/null || echo "false")
        FALSE_POSITIVE_RATE=$(python3 -c "import json; print(json.load(open('/tmp/verification_metrics.json'))['false_positive_rate'])" 2>/dev/null || echo "1")
        
        echo "Verification metrics computed:"
        cat /tmp/verification_metrics.json
    fi
fi

# ================================================================
# DETERMINE EXPECTED CLASSIFICATION
# ================================================================
EXPECTED_CLASSIFICATION=""
if [ -n "$GT_VOLUME" ] && [ "$GT_VOLUME" != "0" ]; then
    GT_VOL_INT=$(python3 -c "print(int(float('$GT_VOLUME')))" 2>/dev/null || echo "0")
    if [ "$GT_VOL_INT" -lt 200 ]; then
        EXPECTED_CLASSIFICATION="Normal"
    elif [ "$GT_VOL_INT" -lt 400 ]; then
        EXPECTED_CLASSIFICATION="Mild Splenomegaly"
    elif [ "$GT_VOL_INT" -lt 800 ]; then
        EXPECTED_CLASSIFICATION="Moderate Splenomegaly"
    else
        EXPECTED_CLASSIFICATION="Massive Splenomegaly"
    fi
fi

# Check classification correctness
CLASSIFICATION_CORRECT="false"
if [ -n "$AGENT_CLASSIFICATION" ] && [ -n "$EXPECTED_CLASSIFICATION" ]; then
    AGENT_LOWER=$(echo "$AGENT_CLASSIFICATION" | tr '[:upper:]' '[:lower:]')
    EXPECTED_LOWER=$(echo "$EXPECTED_CLASSIFICATION" | tr '[:upper:]' '[:lower:]')
    
    # Check for matching keywords
    if echo "$AGENT_LOWER" | grep -qi "normal" && echo "$EXPECTED_LOWER" | grep -qi "normal"; then
        CLASSIFICATION_CORRECT="true"
    elif echo "$AGENT_LOWER" | grep -qi "mild" && echo "$EXPECTED_LOWER" | grep -qi "mild"; then
        CLASSIFICATION_CORRECT="true"
    elif echo "$AGENT_LOWER" | grep -qi "moderate" && echo "$EXPECTED_LOWER" | grep -qi "moderate"; then
        CLASSIFICATION_CORRECT="true"
    elif echo "$AGENT_LOWER" | grep -qi "massive" && echo "$EXPECTED_LOWER" | grep -qi "massive"; then
        CLASSIFICATION_CORRECT="true"
    fi
fi

# ================================================================
# COPY FILES FOR VERIFIER
# ================================================================
echo "Preparing files for verifier..."

# Copy segmentation
if [ -f "$AMOS_DIR/spleen_segmentation.nii.gz" ]; then
    cp "$AMOS_DIR/spleen_segmentation.nii.gz" /tmp/agent_spleen_seg.nii.gz 2>/dev/null || true
    chmod 644 /tmp/agent_spleen_seg.nii.gz 2>/dev/null || true
fi

# Copy ground truth
if [ -f "$GROUND_TRUTH_DIR/${CASE_ID}_labels.nii.gz" ]; then
    cp "$GROUND_TRUTH_DIR/${CASE_ID}_labels.nii.gz" /tmp/gt_labels.nii.gz 2>/dev/null || true
    chmod 644 /tmp/gt_labels.nii.gz 2>/dev/null || true
fi

if [ -f "$GROUND_TRUTH_DIR/${CASE_ID}_spleen_gt.json" ]; then
    cp "$GROUND_TRUTH_DIR/${CASE_ID}_spleen_gt.json" /tmp/gt_spleen.json 2>/dev/null || true
    chmod 644 /tmp/gt_spleen.json 2>/dev/null || true
fi

# ================================================================
# CREATE RESULT JSON
# ================================================================
echo "Creating result JSON..."

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "case_id": "$CASE_ID",
    "slicer_was_running": $SLICER_RUNNING,
    "segmentation_exists": $SEGMENTATION_EXISTS,
    "segmentation_path": "$SEGMENTATION_PATH",
    "segmentation_size_bytes": $SEGMENTATION_SIZE,
    "segmentation_created_during_task": $SEGMENTATION_CREATED_DURING_TASK,
    "report_exists": $REPORT_EXISTS,
    "report_path": "$REPORT_PATH",
    "agent_reported_volume_ml": "$AGENT_VOLUME_ML",
    "agent_reported_classification": "$AGENT_CLASSIFICATION",
    "agent_computed_volume_ml": $AGENT_COMPUTED_VOLUME,
    "gt_volume_ml": $GT_VOLUME,
    "expected_classification": "$EXPECTED_CLASSIFICATION",
    "classification_correct": $CLASSIFICATION_CORRECT,
    "dice_score": $DICE_SCORE,
    "volume_accuracy": $VOLUME_ACCURACY,
    "correct_location": $CORRECT_LOCATION,
    "false_positive_rate": $FALSE_POSITIVE_RATE,
    "screenshot_exists": $([ -f "/tmp/task_final.png" ] && echo "true" || echo "false"),
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f "$RESULT_FILE" 2>/dev/null || sudo rm -f "$RESULT_FILE" 2>/dev/null || true
cp "$TEMP_JSON" "$RESULT_FILE" 2>/dev/null || sudo cp "$TEMP_JSON" "$RESULT_FILE"
chmod 666 "$RESULT_FILE" 2>/dev/null || sudo chmod 666 "$RESULT_FILE" 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result ==="
cat "$RESULT_FILE"
echo ""
echo "=== Export Complete ==="