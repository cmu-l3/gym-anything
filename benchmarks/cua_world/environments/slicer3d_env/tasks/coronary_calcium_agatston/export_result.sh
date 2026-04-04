#!/bin/bash
echo "=== Exporting Coronary Calcium Agatston Score Result ==="

source /workspace/scripts/task_utils.sh

CARDIAC_DIR="/home/ga/Documents/SlicerData/Cardiac"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
CASE_ID="cardiac_cac_001"
OUTPUT_SEG="$CARDIAC_DIR/calcium_segmentation.nii.gz"
OUTPUT_REPORT="$CARDIAC_DIR/agatston_report.json"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/calcium_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export any segmentations from Slicer
    cat > /tmp/export_calcium_seg.py << 'PYEOF'
import slicer
import os
import json

output_dir = "/home/ga/Documents/SlicerData/Cardiac"
os.makedirs(output_dir, exist_ok=True)

# Try to find and export segmentation nodes
seg_nodes = slicer.util.getNodesByClass("vtkMRMLSegmentationNode")
print(f"Found {len(seg_nodes)} segmentation node(s)")

for node in seg_nodes:
    print(f"  Segmentation: {node.GetName()}")
    # Export as labelmap
    output_path = os.path.join(output_dir, "calcium_segmentation.nii.gz")
    try:
        labelmapVolumeNode = slicer.mrmlScene.AddNewNodeByClass("vtkMRMLLabelMapVolumeNode")
        slicer.modules.segmentations.logic().ExportAllSegmentsToLabelmapNode(node, labelmapVolumeNode)
        slicer.util.saveNode(labelmapVolumeNode, output_path)
        slicer.mrmlScene.RemoveNode(labelmapVolumeNode)
        print(f"  Exported to: {output_path}")
    except Exception as e:
        print(f"  Error exporting: {e}")

# Also check for any labelmap volumes that might be the segmentation
labelmap_nodes = slicer.util.getNodesByClass("vtkMRMLLabelMapVolumeNode")
print(f"Found {len(labelmap_nodes)} labelmap node(s)")

for node in labelmap_nodes:
    name = node.GetName()
    if "calcium" in name.lower() or "seg" in name.lower():
        output_path = os.path.join(output_dir, "calcium_segmentation.nii.gz")
        try:
            slicer.util.saveNode(node, output_path)
            print(f"  Exported labelmap {name} to: {output_path}")
        except Exception as e:
            print(f"  Error: {e}")

print("Export script complete")
PYEOF

    # Run export script
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_calcium_seg.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 8
    pkill -f "export_calcium_seg" 2>/dev/null || true
fi

# Check for agent's segmentation file
SEG_EXISTS="false"
SEG_PATH=""
SEG_SIZE=0
SEG_CREATED_DURING_TASK="false"

POSSIBLE_SEG_PATHS=(
    "$OUTPUT_SEG"
    "$CARDIAC_DIR/Segmentation.nii.gz"
    "$CARDIAC_DIR/calcium.nii.gz"
    "/home/ga/Documents/calcium_segmentation.nii.gz"
)

for path in "${POSSIBLE_SEG_PATHS[@]}"; do
    if [ -f "$path" ]; then
        SEG_EXISTS="true"
        SEG_PATH="$path"
        SEG_SIZE=$(stat -c %s "$path" 2>/dev/null || echo "0")
        SEG_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$SEG_MTIME" -gt "$TASK_START" ]; then
            SEG_CREATED_DURING_TASK="true"
        fi
        if [ "$path" != "$OUTPUT_SEG" ]; then
            cp "$path" "$OUTPUT_SEG" 2>/dev/null || true
        fi
        echo "Found segmentation at: $path"
        break
    fi
done

# Check for agent's report file
REPORT_EXISTS="false"
REPORT_PATH=""
REPORTED_SCORE=""
REPORTED_CATEGORY=""
REPORTED_LESIONS=""
REPORT_CREATED_DURING_TASK="false"

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$CARDIAC_DIR/report.json"
    "$CARDIAC_DIR/calcium_report.json"
    "/home/ga/Documents/agatston_report.json"
    "/home/ga/agatston_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_PATH="$path"
        REPORT_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
            REPORT_CREATED_DURING_TASK="true"
        fi
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        echo "Found report at: $path"
        
        # Extract values from report
        REPORTED_SCORE=$(python3 -c "
import json
try:
    with open('$path') as f:
        d = json.load(f)
    score = d.get('total_agatston_score', d.get('agatston_score', d.get('total_score', d.get('score', ''))))
    print(score)
except:
    print('')
" 2>/dev/null || echo "")
        
        REPORTED_CATEGORY=$(python3 -c "
import json
try:
    with open('$path') as f:
        d = json.load(f)
    cat = d.get('risk_category', d.get('classification', d.get('risk', '')))
    print(cat)
except:
    print('')
" 2>/dev/null || echo "")
        
        REPORTED_LESIONS=$(python3 -c "
import json
try:
    with open('$path') as f:
        d = json.load(f)
    count = d.get('lesion_count', d.get('num_lesions', len(d.get('lesions', []))))
    print(count)
except:
    print('')
" 2>/dev/null || echo "")
        
        echo "Reported score: $REPORTED_SCORE"
        echo "Reported category: $REPORTED_CATEGORY"
        echo "Reported lesions: $REPORTED_LESIONS"
        break
    fi
done

# Analyze segmentation if it exists
SEG_VOXELS=0
SEG_VOLUME_MM3=0
SEG_MEAN_HU=0

if [ -f "$OUTPUT_SEG" ]; then
    python3 << PYEOF
import json
import numpy as np
try:
    import nibabel as nib
except ImportError:
    import subprocess, sys
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
    import nibabel as nib

try:
    seg = nib.load("$OUTPUT_SEG")
    seg_data = seg.get_fdata()
    spacing = seg.header.get_zooms()[:3]
    voxel_vol = float(np.prod(spacing))
    
    # Count non-zero voxels
    nonzero = np.sum(seg_data > 0)
    volume = nonzero * voxel_vol
    
    print(f"SEG_VOXELS={int(nonzero)}")
    print(f"SEG_VOLUME_MM3={volume:.2f}")
except Exception as e:
    print(f"# Error analyzing segmentation: {e}")
    print("SEG_VOXELS=0")
    print("SEG_VOLUME_MM3=0")
PYEOF
    SEG_ANALYSIS=$(python3 << 'PYEOF'
import json
import numpy as np
try:
    import nibabel as nib
    seg = nib.load("/home/ga/Documents/SlicerData/Cardiac/calcium_segmentation.nii.gz")
    seg_data = seg.get_fdata()
    spacing = seg.header.get_zooms()[:3]
    voxel_vol = float(np.prod(spacing))
    nonzero = int(np.sum(seg_data > 0))
    volume = nonzero * voxel_vol
    print(json.dumps({"voxels": nonzero, "volume_mm3": volume}))
except:
    print(json.dumps({"voxels": 0, "volume_mm3": 0}))
PYEOF
)
    SEG_VOXELS=$(echo "$SEG_ANALYSIS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('voxels', 0))" 2>/dev/null || echo "0")
    SEG_VOLUME_MM3=$(echo "$SEG_ANALYSIS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('volume_mm3', 0))" 2>/dev/null || echo "0")
fi

# Copy ground truth for verification
cp "$GROUND_TRUTH_DIR/${CASE_ID}_calcium_gt.json" /tmp/calcium_ground_truth.json 2>/dev/null || true
cp "$GROUND_TRUTH_DIR/${CASE_ID}_calcium_mask.nii.gz" /tmp/calcium_gt_mask.nii.gz 2>/dev/null || true
chmod 644 /tmp/calcium_ground_truth.json /tmp/calcium_gt_mask.nii.gz 2>/dev/null || true

# Copy agent outputs for verification
if [ -f "$OUTPUT_SEG" ]; then
    cp "$OUTPUT_SEG" /tmp/agent_calcium_seg.nii.gz 2>/dev/null || true
    chmod 644 /tmp/agent_calcium_seg.nii.gz 2>/dev/null || true
fi

if [ -f "$OUTPUT_REPORT" ]; then
    cp "$OUTPUT_REPORT" /tmp/agent_calcium_report.json 2>/dev/null || true
    chmod 644 /tmp/agent_calcium_report.json 2>/dev/null || true
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "segmentation_exists": $SEG_EXISTS,
    "segmentation_path": "$SEG_PATH",
    "segmentation_size_bytes": $SEG_SIZE,
    "segmentation_created_during_task": $SEG_CREATED_DURING_TASK,
    "segmentation_voxels": $SEG_VOXELS,
    "segmentation_volume_mm3": $SEG_VOLUME_MM3,
    "report_exists": $REPORT_EXISTS,
    "report_path": "$REPORT_PATH",
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "reported_agatston_score": "$REPORTED_SCORE",
    "reported_risk_category": "$REPORTED_CATEGORY",
    "reported_lesion_count": "$REPORTED_LESIONS",
    "screenshot_exists": $([ -f "/tmp/calcium_final.png" ] && echo "true" || echo "false"),
    "ground_truth_available": $([ -f "/tmp/calcium_ground_truth.json" ] && echo "true" || echo "false"),
    "case_id": "$CASE_ID",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/calcium_task_result.json 2>/dev/null || sudo rm -f /tmp/calcium_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/calcium_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/calcium_task_result.json
chmod 666 /tmp/calcium_task_result.json 2>/dev/null || sudo chmod 666 /tmp/calcium_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

# Close Slicer
echo "Closing 3D Slicer..."
close_slicer

echo ""
echo "Export result:"
cat /tmp/calcium_task_result.json
echo ""
echo "=== Export Complete ==="