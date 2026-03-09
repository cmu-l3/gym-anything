#!/bin/bash
echo "=== Exporting Tumor Necrosis Pattern Result ==="

source /workspace/scripts/task_utils.sh

# Get the sample ID used
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
OUTPUT_SEG="$BRATS_DIR/enhancement_segmentation.nii.gz"
OUTPUT_REPORT="$BRATS_DIR/necrosis_report.json"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/necrosis_final.png ga
sleep 1

# Get task timing info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export any segmentation from Slicer before checking files
    cat > /tmp/export_necrosis_seg.py << 'PYEOF'
import slicer
import os
import json

output_dir = "/home/ga/Documents/SlicerData/BraTS"
os.makedirs(output_dir, exist_ok=True)

print("Checking for segmentation nodes in scene...")

# Find segmentation nodes
seg_nodes = slicer.util.getNodesByClass("vtkMRMLSegmentationNode")
print(f"Found {len(seg_nodes)} segmentation node(s)")

for seg_node in seg_nodes:
    seg_name = seg_node.GetName()
    print(f"  Processing: {seg_name}")
    
    # Get segment IDs
    segmentation = seg_node.GetSegmentation()
    num_segments = segmentation.GetNumberOfSegments()
    print(f"    Contains {num_segments} segment(s)")
    
    if num_segments > 0:
        # Export as labelmap
        labelmap_node = slicer.mrmlScene.AddNewNodeByClass("vtkMRMLLabelMapVolumeNode")
        slicer.modules.segmentations.logic().ExportAllSegmentsToLabelmapNode(
            seg_node, labelmap_node
        )
        
        # Save to NIfTI
        output_path = os.path.join(output_dir, "enhancement_segmentation.nii.gz")
        success = slicer.util.saveNode(labelmap_node, output_path)
        
        if success:
            print(f"    Saved segmentation to: {output_path}")
        else:
            print(f"    Failed to save segmentation")
        
        # Clean up
        slicer.mrmlScene.RemoveNode(labelmap_node)
        
        # List segment names
        for i in range(num_segments):
            segment = segmentation.GetNthSegment(i)
            print(f"    - Segment {i}: {segment.GetName()}")

print("Export check complete")
PYEOF

    # Run export in Slicer (with timeout)
    timeout 30 sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_necrosis_seg.py --no-main-window > /tmp/slicer_export.log 2>&1 || true
    sleep 2
fi

# Check if agent saved a segmentation file
AGENT_SEG_EXISTS="false"
AGENT_SEG_PATH=""
SEG_SIZE_BYTES=0
SEG_MTIME=0
SEG_CREATED_DURING_TASK="false"
SEG_LABEL_COUNT=0

# Check multiple possible locations
POSSIBLE_SEG_PATHS=(
    "$OUTPUT_SEG"
    "$BRATS_DIR/enhancement_segmentation.nii"
    "$BRATS_DIR/Segmentation.nii.gz"
    "$BRATS_DIR/segmentation.nii.gz"
    "$BRATS_DIR/necrosis_segmentation.nii.gz"
    "/home/ga/Documents/enhancement_segmentation.nii.gz"
    "/home/ga/enhancement_segmentation.nii.gz"
)

for path in "${POSSIBLE_SEG_PATHS[@]}"; do
    if [ -f "$path" ]; then
        AGENT_SEG_EXISTS="true"
        AGENT_SEG_PATH="$path"
        SEG_SIZE_BYTES=$(stat -c %s "$path" 2>/dev/null || echo "0")
        SEG_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        
        # Check if created during task
        if [ "$SEG_MTIME" -gt "$TASK_START" ]; then
            SEG_CREATED_DURING_TASK="true"
        fi
        
        echo "Found agent segmentation at: $path (size: $SEG_SIZE_BYTES bytes)"
        
        # Copy to expected location if different
        if [ "$path" != "$OUTPUT_SEG" ]; then
            cp "$path" "$OUTPUT_SEG" 2>/dev/null || true
        fi
        
        # Count labels in segmentation
        SEG_LABEL_COUNT=$(python3 << PYEOF
import sys
try:
    import nibabel as nib
    import numpy as np
    seg = nib.load("$path")
    data = seg.get_fdata()
    labels = np.unique(data[data > 0])
    print(len(labels))
except Exception as e:
    print(0)
PYEOF
)
        echo "Segmentation has $SEG_LABEL_COUNT non-zero label(s)"
        break
    fi
done

# Check if agent created a report
REPORT_EXISTS="false"
REPORT_PATH=""
REPORT_VALID="false"
REPORT_MTIME=0
REPORT_CREATED_DURING_TASK="false"
REPORTED_ENHANCING=""
REPORTED_NECROTIC=""
REPORTED_RATIO=""
REPORTED_PATTERN=""
REPORT_FIELDS_COUNT=0

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$BRATS_DIR/necrosis_report.json"
    "$BRATS_DIR/report.json"
    "$BRATS_DIR/enhancement_report.json"
    "/home/ga/Documents/necrosis_report.json"
    "/home/ga/necrosis_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_PATH="$path"
        REPORT_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        
        # Check if created during task
        if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
            REPORT_CREATED_DURING_TASK="true"
        fi
        
        echo "Found report at: $path"
        
        # Copy to expected location if different
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        
        # Parse report fields
        REPORT_PARSE=$(python3 << PYEOF
import json
import sys

try:
    with open("$path", 'r') as f:
        data = json.load(f)
    
    required = ['enhancing_volume_ml', 'necrotic_volume_ml', 'necrosis_ratio', 'enhancement_pattern']
    present = sum(1 for k in required if k in data)
    
    enhancing = data.get('enhancing_volume_ml', data.get('enhancing_ml', ''))
    necrotic = data.get('necrotic_volume_ml', data.get('necrotic_ml', ''))
    ratio = data.get('necrosis_ratio', data.get('ratio', ''))
    pattern = data.get('enhancement_pattern', data.get('pattern', ''))
    
    valid = "true" if present >= 4 else "false"
    
    print(f"{valid}|{present}|{enhancing}|{necrotic}|{ratio}|{pattern}")
except Exception as e:
    print(f"false|0||||")
PYEOF
)
        
        REPORT_VALID=$(echo "$REPORT_PARSE" | cut -d'|' -f1)
        REPORT_FIELDS_COUNT=$(echo "$REPORT_PARSE" | cut -d'|' -f2)
        REPORTED_ENHANCING=$(echo "$REPORT_PARSE" | cut -d'|' -f3)
        REPORTED_NECROTIC=$(echo "$REPORT_PARSE" | cut -d'|' -f4)
        REPORTED_RATIO=$(echo "$REPORT_PARSE" | cut -d'|' -f5)
        REPORTED_PATTERN=$(echo "$REPORT_PARSE" | cut -d'|' -f6)
        
        echo "Report valid: $REPORT_VALID, fields: $REPORT_FIELDS_COUNT"
        echo "Reported enhancing: $REPORTED_ENHANCING mL"
        echo "Reported necrotic: $REPORTED_NECROTIC mL"
        echo "Reported ratio: $REPORTED_RATIO"
        echo "Reported pattern: $REPORTED_PATTERN"
        break
    fi
done

# Copy ground truth files for verification
echo "Preparing ground truth files for verification..."
cp "$GROUND_TRUTH_DIR/${SAMPLE_ID}_seg.nii.gz" /tmp/ground_truth_seg.nii.gz 2>/dev/null || true
cp "$GROUND_TRUTH_DIR/${SAMPLE_ID}_necrosis_stats.json" /tmp/ground_truth_necrosis_stats.json 2>/dev/null || true
chmod 644 /tmp/ground_truth_seg.nii.gz /tmp/ground_truth_necrosis_stats.json 2>/dev/null || true

if [ -f "$OUTPUT_SEG" ]; then
    cp "$OUTPUT_SEG" /tmp/agent_segmentation.nii.gz 2>/dev/null || true
    chmod 644 /tmp/agent_segmentation.nii.gz 2>/dev/null || true
fi

if [ -f "$OUTPUT_REPORT" ]; then
    cp "$OUTPUT_REPORT" /tmp/agent_necrosis_report.json 2>/dev/null || true
    chmod 644 /tmp/agent_necrosis_report.json 2>/dev/null || true
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "sample_id": "$SAMPLE_ID",
    "segmentation": {
        "exists": $AGENT_SEG_EXISTS,
        "path": "$AGENT_SEG_PATH",
        "size_bytes": $SEG_SIZE_BYTES,
        "mtime": $SEG_MTIME,
        "created_during_task": $SEG_CREATED_DURING_TASK,
        "label_count": $SEG_LABEL_COUNT
    },
    "report": {
        "exists": $REPORT_EXISTS,
        "path": "$REPORT_PATH",
        "mtime": $REPORT_MTIME,
        "created_during_task": $REPORT_CREATED_DURING_TASK,
        "valid": $REPORT_VALID,
        "fields_count": $REPORT_FIELDS_COUNT,
        "enhancing_volume_ml": "$REPORTED_ENHANCING",
        "necrotic_volume_ml": "$REPORTED_NECROTIC",
        "necrosis_ratio": "$REPORTED_RATIO",
        "enhancement_pattern": "$REPORTED_PATTERN"
    },
    "ground_truth_available": $([ -f "/tmp/ground_truth_necrosis_stats.json" ] && echo "true" || echo "false"),
    "screenshot_exists": $([ -f "/tmp/necrosis_final.png" ] && echo "true" || echo "false")
}
EOF

# Save result with permission handling
rm -f /tmp/necrosis_task_result.json 2>/dev/null || sudo rm -f /tmp/necrosis_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/necrosis_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/necrosis_task_result.json
chmod 666 /tmp/necrosis_task_result.json 2>/dev/null || sudo chmod 666 /tmp/necrosis_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/necrosis_task_result.json
echo ""
echo "=== Export Complete ==="