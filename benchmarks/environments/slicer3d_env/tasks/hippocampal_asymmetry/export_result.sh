#!/bin/bash
echo "=== Exporting Hippocampal Asymmetry Assessment Result ==="

source /workspace/scripts/task_utils.sh

# Get the sample ID used
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
OUTPUT_SEG="$BRATS_DIR/hippocampal_segmentation.nii.gz"
OUTPUT_REPORT="$BRATS_DIR/hippocampal_report.json"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Get task start time for timestamp verification
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/hippocampal_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export segmentation from Slicer
    cat > /tmp/export_hippocampal_seg.py << 'PYEOF'
import slicer
import os
import json

output_dir = "/home/ga/Documents/SlicerData/BraTS"
os.makedirs(output_dir, exist_ok=True)

# Look for segmentation nodes
seg_nodes = slicer.util.getNodesByClass("vtkMRMLSegmentationNode")
print(f"Found {len(seg_nodes)} segmentation node(s)")

segments_found = {}
left_volume = 0
right_volume = 0

for seg_node in seg_nodes:
    seg = seg_node.GetSegmentation()
    num_segments = seg.GetNumberOfSegments()
    print(f"  Segmentation '{seg_node.GetName()}' has {num_segments} segments")
    
    for i in range(num_segments):
        segment = seg.GetNthSegment(i)
        seg_id = seg.GetNthSegmentID(i)
        seg_name = segment.GetName()
        print(f"    Segment {i}: '{seg_name}' (ID: {seg_id})")
        
        # Check for hippocampus segments by name
        name_lower = seg_name.lower()
        if 'left' in name_lower and 'hippo' in name_lower:
            segments_found['left'] = {'name': seg_name, 'id': seg_id}
        elif 'right' in name_lower and 'hippo' in name_lower:
            segments_found['right'] = {'name': seg_name, 'id': seg_id}
        elif 'hippo' in name_lower:
            # Generic hippocampus - check position later
            if 'left' not in segments_found:
                segments_found['left'] = {'name': seg_name, 'id': seg_id}
            elif 'right' not in segments_found:
                segments_found['right'] = {'name': seg_name, 'id': seg_id}

# Try to compute segment statistics
if seg_nodes:
    try:
        import SegmentStatistics
        segStatLogic = SegmentStatistics.SegmentStatisticsLogic()
        segStatLogic.getParameterNode().SetParameter("Segmentation", seg_nodes[0].GetID())
        
        # Find a reference volume
        vol_nodes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
        if vol_nodes:
            segStatLogic.getParameterNode().SetParameter("ScalarVolume", vol_nodes[0].GetID())
        
        segStatLogic.computeStatistics()
        stats = segStatLogic.getStatistics()
        
        # Extract volumes
        for seg_id in stats.keys():
            if 'LabelmapSegmentStatisticsPlugin.volume_mm3' in stats[seg_id]:
                vol_mm3 = stats[seg_id]['LabelmapSegmentStatisticsPlugin.volume_mm3']
                vol_ml = vol_mm3 / 1000.0
                
                seg_name = stats[seg_id].get('SegmentID', seg_id)
                print(f"    {seg_name}: {vol_ml:.3f} mL")
                
                if 'left' in seg_id.lower() or 'left' in seg_name.lower():
                    left_volume = vol_ml
                elif 'right' in seg_id.lower() or 'right' in seg_name.lower():
                    right_volume = vol_ml
    except Exception as e:
        print(f"Could not compute statistics: {e}")

# Save segmentation
if seg_nodes:
    seg_path = os.path.join(output_dir, "hippocampal_segmentation.nii.gz")
    try:
        # Export as labelmap
        labelmapNode = slicer.mrmlScene.AddNewNodeByClass("vtkMRMLLabelMapVolumeNode")
        slicer.modules.segmentations.logic().ExportAllSegmentsToLabelmapNode(
            seg_nodes[0], labelmapNode)
        slicer.util.saveNode(labelmapNode, seg_path)
        slicer.mrmlScene.RemoveNode(labelmapNode)
        print(f"Saved segmentation to {seg_path}")
    except Exception as e:
        print(f"Could not save segmentation: {e}")

# Save info for export script
info = {
    'segments_found': segments_found,
    'left_volume_ml': left_volume,
    'right_volume_ml': right_volume
}
with open('/tmp/hippocampal_slicer_info.json', 'w') as f:
    json.dump(info, f)

print("Export from Slicer complete")
PYEOF

    # Run export script in Slicer
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_hippocampal_seg.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 15
    pkill -f "export_hippocampal_seg" 2>/dev/null || true
fi

# Check for segmentation file
SEG_EXISTS="false"
SEG_PATH=""
SEG_CREATED_DURING_TASK="false"
SEG_SIZE_BYTES=0

POSSIBLE_SEG_PATHS=(
    "$OUTPUT_SEG"
    "$BRATS_DIR/hippocampal_segmentation.nii"
    "$BRATS_DIR/segmentation.nii.gz"
    "$BRATS_DIR/Segmentation.nii.gz"
    "/home/ga/Documents/hippocampal_segmentation.nii.gz"
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

# Check for report file
REPORT_EXISTS="false"
REPORT_PATH=""
REPORTED_LEFT_VOL=""
REPORTED_RIGHT_VOL=""
REPORTED_HAI=""
REPORTED_CLASSIFICATION=""

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$BRATS_DIR/hippocampal_report.json"
    "$BRATS_DIR/report.json"
    "/home/ga/Documents/hippocampal_report.json"
    "/home/ga/hippocampal_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_PATH="$path"
        echo "Found report at: $path"
        
        # Extract values from report
        REPORTED_LEFT_VOL=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('left_volume_ml', d.get('left_hippocampus_volume_ml', '')))" 2>/dev/null || echo "")
        REPORTED_RIGHT_VOL=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('right_volume_ml', d.get('right_hippocampus_volume_ml', '')))" 2>/dev/null || echo "")
        REPORTED_HAI=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('asymmetry_index_percent', d.get('hai', d.get('asymmetry_index', ''))))" 2>/dev/null || echo "")
        REPORTED_CLASSIFICATION=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('classification', d.get('clinical_classification', '')))" 2>/dev/null || echo "")
        
        echo "  Left volume: $REPORTED_LEFT_VOL mL"
        echo "  Right volume: $REPORTED_RIGHT_VOL mL"
        echo "  HAI: $REPORTED_HAI %"
        echo "  Classification: $REPORTED_CLASSIFICATION"
        
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        break
    fi
done

# Get Slicer-extracted info if available
SLICER_LEFT_VOL=""
SLICER_RIGHT_VOL=""
if [ -f /tmp/hippocampal_slicer_info.json ]; then
    SLICER_LEFT_VOL=$(python3 -c "import json; d=json.load(open('/tmp/hippocampal_slicer_info.json')); print(d.get('left_volume_ml', ''))" 2>/dev/null || echo "")
    SLICER_RIGHT_VOL=$(python3 -c "import json; d=json.load(open('/tmp/hippocampal_slicer_info.json')); print(d.get('right_volume_ml', ''))" 2>/dev/null || echo "")
fi

# Use Slicer values if report values not available
if [ -z "$REPORTED_LEFT_VOL" ] && [ -n "$SLICER_LEFT_VOL" ]; then
    REPORTED_LEFT_VOL="$SLICER_LEFT_VOL"
fi
if [ -z "$REPORTED_RIGHT_VOL" ] && [ -n "$SLICER_RIGHT_VOL" ]; then
    REPORTED_RIGHT_VOL="$SLICER_RIGHT_VOL"
fi

# Analyze segmentation file if it exists
SEG_ANALYSIS=""
LEFT_CENTROID=""
RIGHT_CENTROID=""
LEFT_SEG_VOLUME=""
RIGHT_SEG_VOLUME=""
SEGMENTS_IN_SEG=""
MIDLINE_CROSSOVER="false"

if [ -f "$OUTPUT_SEG" ]; then
    echo "Analyzing segmentation file..."
    
    SEG_ANALYSIS=$(python3 << 'PYEOF'
import json
import sys

try:
    import numpy as np
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "numpy"])
    import numpy as np

try:
    import nibabel as nib
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
    import nibabel as nib

from scipy import ndimage

seg_path = "/home/ga/Documents/SlicerData/BraTS/hippocampal_segmentation.nii.gz"

try:
    seg_nii = nib.load(seg_path)
    seg_data = seg_nii.get_fdata().astype(np.int32)
    affine = seg_nii.affine
    voxel_dims = seg_nii.header.get_zooms()[:3]
    voxel_vol_mm3 = float(np.prod(voxel_dims))
    
    # Get unique labels
    unique_labels = np.unique(seg_data)
    unique_labels = unique_labels[unique_labels != 0]  # Exclude background
    
    result = {
        'shape': list(seg_data.shape),
        'voxel_dims_mm': [float(v) for v in voxel_dims],
        'unique_labels': [int(l) for l in unique_labels],
        'num_segments': len(unique_labels),
        'segments': []
    }
    
    # Image center for midline check
    img_center_x = seg_data.shape[0] / 2.0
    
    for label in unique_labels:
        mask = (seg_data == label)
        voxel_count = np.sum(mask)
        volume_ml = voxel_count * voxel_vol_mm3 / 1000.0
        
        # Get centroid
        coords = np.array(np.where(mask)).T
        if len(coords) > 0:
            centroid = coords.mean(axis=0)
            
            # Relative position in image
            rel_x = centroid[0] / seg_data.shape[0]
            rel_y = centroid[1] / seg_data.shape[1]
            rel_z = centroid[2] / seg_data.shape[2]
            
            # Determine side based on centroid
            side = "left" if centroid[0] < img_center_x else "right"
            
            # Check for connected components
            labeled, num_components = ndimage.label(mask)
            
            seg_info = {
                'label': int(label),
                'volume_ml': float(volume_ml),
                'voxel_count': int(voxel_count),
                'centroid_voxels': [float(c) for c in centroid],
                'relative_position': {'x': float(rel_x), 'y': float(rel_y), 'z': float(rel_z)},
                'side': side,
                'num_components': int(num_components)
            }
            result['segments'].append(seg_info)
    
    print(json.dumps(result))
    
except Exception as e:
    print(json.dumps({'error': str(e)}))
PYEOF
)
    
    echo "Segmentation analysis: $SEG_ANALYSIS"
    
    # Extract values from analysis
    if [ -n "$SEG_ANALYSIS" ]; then
        SEGMENTS_IN_SEG=$(echo "$SEG_ANALYSIS" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('num_segments', 0))" 2>/dev/null || echo "0")
        
        # Try to identify left and right segments
        LEFT_SEG_VOLUME=$(echo "$SEG_ANALYSIS" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for s in d.get('segments', []):
    if s.get('side') == 'left':
        print(f\"{s['volume_ml']:.4f}\")
        break
" 2>/dev/null || echo "")
        
        RIGHT_SEG_VOLUME=$(echo "$SEG_ANALYSIS" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for s in d.get('segments', []):
    if s.get('side') == 'right':
        print(f\"{s['volume_ml']:.4f}\")
        break
" 2>/dev/null || echo "")
        
        # Get centroids
        LEFT_CENTROID=$(echo "$SEG_ANALYSIS" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for s in d.get('segments', []):
    if s.get('side') == 'left':
        rp = s.get('relative_position', {})
        print(f\"{rp.get('x',0):.3f},{rp.get('y',0):.3f},{rp.get('z',0):.3f}\")
        break
" 2>/dev/null || echo "")
        
        RIGHT_CENTROID=$(echo "$SEG_ANALYSIS" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for s in d.get('segments', []):
    if s.get('side') == 'right':
        rp = s.get('relative_position', {})
        print(f\"{rp.get('x',0):.3f},{rp.get('y',0):.3f},{rp.get('z',0):.3f}\")
        break
" 2>/dev/null || echo "")
    fi
fi

# Close Slicer
echo "Closing 3D Slicer..."
close_slicer

# Copy files for verification
echo "Preparing files for verification..."
cp "$GROUND_TRUTH_DIR/hippocampal_reference.json" /tmp/hippocampal_reference.json 2>/dev/null || true
chmod 644 /tmp/hippocampal_reference.json 2>/dev/null || true

if [ -f "$OUTPUT_SEG" ]; then
    cp "$OUTPUT_SEG" /tmp/agent_hippocampal_seg.nii.gz 2>/dev/null || true
    chmod 644 /tmp/agent_hippocampal_seg.nii.gz 2>/dev/null || true
fi

if [ -f "$OUTPUT_REPORT" ]; then
    cp "$OUTPUT_REPORT" /tmp/agent_hippocampal_report.json 2>/dev/null || true
    chmod 644 /tmp/agent_hippocampal_report.json 2>/dev/null || true
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "segmentation_exists": $SEG_EXISTS,
    "segmentation_path": "$SEG_PATH",
    "segmentation_size_bytes": $SEG_SIZE_BYTES,
    "segmentation_created_during_task": $SEG_CREATED_DURING_TASK,
    "num_segments_in_file": $SEGMENTS_IN_SEG,
    "report_exists": $REPORT_EXISTS,
    "report_path": "$REPORT_PATH",
    "reported_left_volume_ml": "$REPORTED_LEFT_VOL",
    "reported_right_volume_ml": "$REPORTED_RIGHT_VOL",
    "reported_hai_percent": "$REPORTED_HAI",
    "reported_classification": "$REPORTED_CLASSIFICATION",
    "analyzed_left_volume_ml": "$LEFT_SEG_VOLUME",
    "analyzed_right_volume_ml": "$RIGHT_SEG_VOLUME",
    "left_centroid_relative": "$LEFT_CENTROID",
    "right_centroid_relative": "$RIGHT_CENTROID",
    "segmentation_analysis": $SEG_ANALYSIS,
    "screenshot_exists": $([ -f "/tmp/hippocampal_final.png" ] && echo "true" || echo "false"),
    "sample_id": "$SAMPLE_ID",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Handle empty segmentation analysis
if [ -z "$SEG_ANALYSIS" ]; then
    sed -i 's/"segmentation_analysis": ,/"segmentation_analysis": null,/' "$TEMP_JSON"
fi

# Save result
rm -f /tmp/hippocampal_task_result.json 2>/dev/null || sudo rm -f /tmp/hippocampal_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/hippocampal_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/hippocampal_task_result.json
chmod 666 /tmp/hippocampal_task_result.json 2>/dev/null || sudo chmod 666 /tmp/hippocampal_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/hippocampal_task_result.json
echo ""
echo "=== Export Complete ==="