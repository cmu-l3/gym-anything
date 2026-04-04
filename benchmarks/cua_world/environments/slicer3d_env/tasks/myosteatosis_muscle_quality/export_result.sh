#!/bin/bash
echo "=== Exporting Myosteatosis Assessment Result ==="

source /workspace/scripts/task_utils.sh

# Get the case ID used
if [ -f /tmp/amos_case_id ]; then
    CASE_ID=$(cat /tmp/amos_case_id)
else
    CASE_ID="amos_0001"
fi

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
OUTPUT_SEG="$AMOS_DIR/muscle_segmentation.nii.gz"
OUTPUT_REPORT="$AMOS_DIR/myosteatosis_report.json"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Get task timing
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/myosteatosis_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"

    # Try to export segmentation from Slicer
    cat > /tmp/export_muscle_seg.py << 'PYEOF'
import slicer
import os
import json
import numpy as np

output_dir = "/home/ga/Documents/SlicerData/AMOS"
os.makedirs(output_dir, exist_ok=True)

# Look for segmentation nodes
seg_nodes = slicer.util.getNodesByClass("vtkMRMLSegmentationNode")
print(f"Found {len(seg_nodes)} segmentation node(s)")

for seg_node in seg_nodes:
    seg_name = seg_node.GetName()
    print(f"Processing segmentation: {seg_name}")
    
    # Export as labelmap
    labelmap_node = slicer.mrmlScene.AddNewNodeByClass("vtkMRMLLabelMapVolumeNode")
    slicer.modules.segmentations.logic().ExportAllSegmentsToLabelmapNode(
        seg_node, labelmap_node, slicer.vtkSegmentation.EXTENT_REFERENCE_GEOMETRY)
    
    # Save as NIfTI
    output_path = os.path.join(output_dir, "muscle_segmentation.nii.gz")
    slicer.util.saveNode(labelmap_node, output_path)
    print(f"Exported segmentation to: {output_path}")
    
    # Calculate segment statistics if possible
    try:
        import SegmentStatistics
        segStatLogic = SegmentStatistics.SegmentStatisticsLogic()
        segStatLogic.getParameterNode().SetParameter("Segmentation", seg_node.GetID())
        
        # Find master volume
        volumes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
        if volumes:
            segStatLogic.getParameterNode().SetParameter("ScalarVolume", volumes[0].GetID())
            segStatLogic.computeStatistics()
            stats = segStatLogic.getStatistics()
            
            # Extract mean HU
            for segment_id in stats["SegmentIDs"]:
                mean_key = f"{segment_id}.ScalarVolumeSegmentStatisticsPlugin.mean"
                std_key = f"{segment_id}.ScalarVolumeSegmentStatisticsPlugin.stdev"
                area_key = f"{segment_id}.LabelmapSegmentStatisticsPlugin.volume_mm3"
                
                mean_hu = stats.get(mean_key, 0)
                std_hu = stats.get(std_key, 0)
                volume_mm3 = stats.get(area_key, 0)
                
                print(f"  Segment {segment_id}: Mean HU = {mean_hu:.1f}, Std = {std_hu:.1f}")
    except Exception as e:
        print(f"Could not compute segment statistics: {e}")
    
    # Clean up temp labelmap
    slicer.mrmlScene.RemoveNode(labelmap_node)
    break  # Only export first segmentation

print("Export complete")
PYEOF

    # Run the export script in Slicer
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_muscle_seg.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 10
    pkill -f "export_muscle_seg" 2>/dev/null || true
fi

# Check if agent saved segmentation file
SEG_EXISTS="false"
SEG_PATH=""
SEG_SIZE_BYTES=0
SEG_CREATED_DURING_TASK="false"

POSSIBLE_SEG_PATHS=(
    "$OUTPUT_SEG"
    "$AMOS_DIR/muscle_segmentation.nii"
    "$AMOS_DIR/Segmentation.nii.gz"
    "$AMOS_DIR/segmentation.nii.gz"
    "/home/ga/Documents/muscle_segmentation.nii.gz"
    "/home/ga/muscle_segmentation.nii.gz"
)

for path in "${POSSIBLE_SEG_PATHS[@]}"; do
    if [ -f "$path" ]; then
        SEG_EXISTS="true"
        SEG_PATH="$path"
        SEG_SIZE_BYTES=$(stat -c %s "$path" 2>/dev/null || echo "0")
        SEG_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$SEG_MTIME" -gt "$TASK_START" ]; then
            SEG_CREATED_DURING_TASK="true"
        fi
        echo "Found segmentation at: $path (size: $SEG_SIZE_BYTES bytes)"
        if [ "$path" != "$OUTPUT_SEG" ]; then
            cp "$path" "$OUTPUT_SEG" 2>/dev/null || true
        fi
        break
    fi
done

# Check if agent saved a report
REPORT_EXISTS="false"
REPORT_PATH=""
REPORTED_MEAN_HU=""
REPORTED_CLASSIFICATION=""
REPORTED_AREA=""

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$AMOS_DIR/myosteatosis_report.json"
    "$AMOS_DIR/report.json"
    "$AMOS_DIR/muscle_report.json"
    "/home/ga/Documents/myosteatosis_report.json"
    "/home/ga/myosteatosis_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_PATH="$path"
        echo "Found report at: $path"
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        # Extract report fields
        REPORTED_MEAN_HU=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('mean_hu', d.get('mean_HU', d.get('meanHU', ''))))" 2>/dev/null || echo "")
        REPORTED_CLASSIFICATION=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('classification', d.get('myosteatosis', '')))" 2>/dev/null || echo "")
        REPORTED_AREA=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('muscle_area_cm2', d.get('area_cm2', '')))" 2>/dev/null || echo "")
        echo "Reported mean HU: $REPORTED_MEAN_HU"
        echo "Reported classification: $REPORTED_CLASSIFICATION"
        break
    fi
done

# Get patient sex from setup
PATIENT_SEX=$(grep "Sex:" "$AMOS_DIR/patient_info.txt" 2>/dev/null | cut -d: -f2 | tr -d ' ' || echo "Unknown")

# Analyze agent's segmentation if it exists
AGENT_MEAN_HU=""
AGENT_STD_HU=""
AGENT_AREA_CM2=""
AGENT_VOXEL_COUNT="0"
AGENT_Z_CENTER=""

if [ "$SEG_EXISTS" = "true" ] && [ -f "$OUTPUT_SEG" ]; then
    python3 << PYEOF
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

seg_path = "$OUTPUT_SEG"
ct_path = "$AMOS_DIR/${CASE_ID}.nii.gz"
output_json = "/tmp/agent_seg_analysis.json"

try:
    seg_nii = nib.load(seg_path)
    seg_data = seg_nii.get_fdata()
    spacing = seg_nii.header.get_zooms()[:3]
    
    ct_nii = nib.load(ct_path)
    ct_data = ct_nii.get_fdata()
    
    # Find where segmentation exists
    seg_mask = seg_data > 0
    voxel_count = int(np.sum(seg_mask))
    
    if voxel_count > 0:
        # Get z-coordinate of segmentation center
        z_coords = np.where(np.any(np.any(seg_mask, axis=0), axis=0))[0]
        z_center = float(np.mean(z_coords)) if len(z_coords) > 0 else 0
        
        # Calculate area at center slice
        if len(z_coords) > 0:
            center_slice = int(np.median(z_coords))
            slice_mask = seg_mask[:, :, center_slice]
            area_mm2 = np.sum(slice_mask) * spacing[0] * spacing[1]
            area_cm2 = area_mm2 / 100.0
        else:
            area_cm2 = 0
        
        # Get HU values within segmentation
        hu_values = ct_data[seg_mask]
        mean_hu = float(np.mean(hu_values))
        std_hu = float(np.std(hu_values))
        
        analysis = {
            "voxel_count": voxel_count,
            "z_center": z_center,
            "z_range": [int(min(z_coords)), int(max(z_coords))] if len(z_coords) > 0 else [0, 0],
            "area_cm2": round(area_cm2, 2),
            "mean_hu": round(mean_hu, 2),
            "std_hu": round(std_hu, 2),
            "ct_shape": list(ct_data.shape),
        }
    else:
        analysis = {
            "voxel_count": 0,
            "error": "Empty segmentation"
        }
    
    with open(output_json, "w") as f:
        json.dump(analysis, f, indent=2)
    print(json.dumps(analysis, indent=2))
    
except Exception as e:
    error_result = {"error": str(e)}
    with open(output_json, "w") as f:
        json.dump(error_result, f)
    print(f"Error analyzing segmentation: {e}")
PYEOF

    # Read analysis results
    if [ -f /tmp/agent_seg_analysis.json ]; then
        AGENT_MEAN_HU=$(python3 -c "import json; print(json.load(open('/tmp/agent_seg_analysis.json')).get('mean_hu', ''))" 2>/dev/null || echo "")
        AGENT_STD_HU=$(python3 -c "import json; print(json.load(open('/tmp/agent_seg_analysis.json')).get('std_hu', ''))" 2>/dev/null || echo "")
        AGENT_AREA_CM2=$(python3 -c "import json; print(json.load(open('/tmp/agent_seg_analysis.json')).get('area_cm2', ''))" 2>/dev/null || echo "")
        AGENT_VOXEL_COUNT=$(python3 -c "import json; print(json.load(open('/tmp/agent_seg_analysis.json')).get('voxel_count', 0))" 2>/dev/null || echo "0")
        AGENT_Z_CENTER=$(python3 -c "import json; print(json.load(open('/tmp/agent_seg_analysis.json')).get('z_center', ''))" 2>/dev/null || echo "")
    fi
fi

# Close Slicer
echo "Closing 3D Slicer..."
close_slicer

# Copy ground truth for verification
echo "Preparing files for verification..."
cp "$GROUND_TRUTH_DIR/${CASE_ID}_muscle_gt.json" /tmp/muscle_ground_truth.json 2>/dev/null || true
cp "$GROUND_TRUTH_DIR/${CASE_ID}_muscle_gt.nii.gz" /tmp/ground_truth_muscle_seg.nii.gz 2>/dev/null || true
chmod 644 /tmp/muscle_ground_truth.json /tmp/ground_truth_muscle_seg.nii.gz 2>/dev/null || true

if [ -f "$OUTPUT_SEG" ]; then
    cp "$OUTPUT_SEG" /tmp/agent_muscle_seg.nii.gz 2>/dev/null || true
    chmod 644 /tmp/agent_muscle_seg.nii.gz 2>/dev/null || true
fi

if [ -f "$OUTPUT_REPORT" ]; then
    cp "$OUTPUT_REPORT" /tmp/agent_muscle_report.json 2>/dev/null || true
    chmod 644 /tmp/agent_muscle_report.json 2>/dev/null || true
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
    "segmentation_size_bytes": $SEG_SIZE_BYTES,
    "segmentation_created_during_task": $SEG_CREATED_DURING_TASK,
    "report_exists": $REPORT_EXISTS,
    "report_path": "$REPORT_PATH",
    "patient_sex": "$PATIENT_SEX",
    "reported_mean_hu": "$REPORTED_MEAN_HU",
    "reported_classification": "$REPORTED_CLASSIFICATION",
    "reported_area": "$REPORTED_AREA",
    "agent_measured_mean_hu": "$AGENT_MEAN_HU",
    "agent_measured_std_hu": "$AGENT_STD_HU",
    "agent_measured_area_cm2": "$AGENT_AREA_CM2",
    "agent_voxel_count": $AGENT_VOXEL_COUNT,
    "agent_z_center": "$AGENT_Z_CENTER",
    "screenshot_exists": $([ -f "/tmp/myosteatosis_final.png" ] && echo "true" || echo "false"),
    "ground_truth_available": $([ -f "/tmp/muscle_ground_truth.json" ] && echo "true" || echo "false"),
    "case_id": "$CASE_ID",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/myosteatosis_task_result.json 2>/dev/null || sudo rm -f /tmp/myosteatosis_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/myosteatosis_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/myosteatosis_task_result.json
chmod 666 /tmp/myosteatosis_task_result.json 2>/dev/null || sudo chmod 666 /tmp/myosteatosis_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/myosteatosis_task_result.json
echo ""
echo "=== Export Complete ==="