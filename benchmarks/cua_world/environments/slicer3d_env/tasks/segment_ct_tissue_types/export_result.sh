#!/bin/bash
echo "=== Exporting Multi-Tissue Segmentation Result ==="

source /workspace/scripts/task_utils.sh

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
EXPORTS_DIR="/home/ga/Documents/SlicerData/Exports"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
OUTPUT_SEG="$EXPORTS_DIR/tissue_segmentation.seg.nrrd"
CASE_ID="amos_0001"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

if [ -f /tmp/task_final.png ]; then
    SIZE=$(stat -c %s /tmp/task_final.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SIZE} bytes"
fi

# Check if Slicer is running
SLICER_RUNNING="false"
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
    echo "3D Slicer is running"
fi

# Try to export segmentation from Slicer if not already saved
if [ "$SLICER_RUNNING" = "true" ]; then
    echo "Attempting to export segmentation from Slicer..."
    
    cat > /tmp/export_segmentation.py << 'PYEOF'
import slicer
import os
import json

output_dir = "/home/ga/Documents/SlicerData/Exports"
os.makedirs(output_dir, exist_ok=True)

# Find segmentation nodes
seg_nodes = slicer.util.getNodesByClass("vtkMRMLSegmentationNode")
print(f"Found {len(seg_nodes)} segmentation node(s)")

segment_info = []

for seg_node in seg_nodes:
    seg = seg_node.GetSegmentation()
    num_segments = seg.GetNumberOfSegments()
    print(f"Segmentation '{seg_node.GetName()}' has {num_segments} segments")
    
    for i in range(num_segments):
        segment_id = seg.GetNthSegmentID(i)
        segment = seg.GetSegment(segment_id)
        segment_name = segment.GetName()
        
        # Get color
        color = segment.GetColor()
        
        segment_info.append({
            "id": segment_id,
            "name": segment_name,
            "color": [color[0], color[1], color[2]]
        })
        print(f"  Segment {i}: '{segment_name}'")
    
    # Save the segmentation
    if num_segments > 0:
        output_path = os.path.join(output_dir, "tissue_segmentation.seg.nrrd")
        success = slicer.util.saveNode(seg_node, output_path)
        print(f"Saved segmentation to {output_path}: {success}")
        
        # Also try alternative formats
        nrrd_path = os.path.join(output_dir, "tissue_segmentation.nrrd")
        try:
            slicer.util.saveNode(seg_node, nrrd_path)
        except:
            pass

# Save segment info
info_path = os.path.join(output_dir, "segment_info.json")
with open(info_path, "w") as f:
    json.dump({"segments": segment_info, "count": len(segment_info)}, f, indent=2)

print(f"Segment info saved to {info_path}")
PYEOF

    sudo -u ga DISPLAY=:1 timeout 30 /opt/Slicer/Slicer --python-script /tmp/export_segmentation.py --no-main-window > /tmp/slicer_export.log 2>&1 || true
    sleep 5
fi

# Search for segmentation files
echo "Searching for segmentation files..."
SEG_FILE=""
SEG_FILE_SIZE=0
FILE_CREATED_DURING_TASK="false"
FILE_MTIME=0

# Check primary output path
SEARCH_PATHS=(
    "$OUTPUT_SEG"
    "$EXPORTS_DIR/tissue_segmentation.nrrd"
    "$EXPORTS_DIR/Segmentation.seg.nrrd"
    "$EXPORTS_DIR/Segmentation.nrrd"
    "/home/ga/tissue_segmentation.seg.nrrd"
    "/home/ga/Documents/tissue_segmentation.seg.nrrd"
)

for path in "${SEARCH_PATHS[@]}"; do
    if [ -f "$path" ]; then
        SEG_FILE="$path"
        SEG_FILE_SIZE=$(stat -c %s "$path" 2>/dev/null || echo "0")
        FILE_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        
        if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
            FILE_CREATED_DURING_TASK="true"
        fi
        
        echo "Found segmentation file: $path"
        echo "  Size: $SEG_FILE_SIZE bytes"
        echo "  Modified: $FILE_MTIME"
        echo "  Created during task: $FILE_CREATED_DURING_TASK"
        break
    fi
done

# Also search for any .seg.nrrd or .nrrd files created during the task
if [ -z "$SEG_FILE" ]; then
    echo "Searching for any recently created segmentation files..."
    NEW_SEG=$(find /home/ga -name "*.seg.nrrd" -newer /tmp/task_start_time.txt 2>/dev/null | head -1)
    if [ -n "$NEW_SEG" ] && [ -f "$NEW_SEG" ]; then
        SEG_FILE="$NEW_SEG"
        SEG_FILE_SIZE=$(stat -c %s "$NEW_SEG" 2>/dev/null || echo "0")
        FILE_MTIME=$(stat -c %Y "$NEW_SEG" 2>/dev/null || echo "0")
        FILE_CREATED_DURING_TASK="true"
        echo "Found recently created file: $NEW_SEG"
    fi
fi

# Determine if output exists
OUTPUT_EXISTS="false"
if [ -n "$SEG_FILE" ] && [ -f "$SEG_FILE" ] && [ "$SEG_FILE_SIZE" -gt 1000 ]; then
    OUTPUT_EXISTS="true"
fi

# Analyze segmentation file if it exists
NUM_SEGMENTS=0
SEGMENT_NAMES=""
SEGMENT_VOXELS=""
HAS_BONE="false"
HAS_SOFT_TISSUE="false"
HAS_AIR="false"

if [ "$OUTPUT_EXISTS" = "true" ]; then
    echo "Analyzing segmentation file..."
    
    python3 << PYEOF
import os
import sys
import json
import numpy as np

seg_file = "$SEG_FILE"
gt_dir = "$GROUND_TRUTH_DIR"
case_id = "$CASE_ID"

try:
    import nibabel as nib
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
    import nibabel as nib

try:
    import nrrd
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "pynrrd"])
    import nrrd

results = {
    "num_segments": 0,
    "segment_names": [],
    "segment_voxels": {},
    "has_bone": False,
    "has_soft_tissue": False,
    "has_air": False,
    "analysis_success": False
}

try:
    # Try loading as NRRD first
    data, header = nrrd.read(seg_file)
    print(f"Loaded segmentation: shape {data.shape}, dtype {data.dtype}")
    
    # For multi-label segmentation, count unique labels
    unique_labels = np.unique(data)
    unique_labels = unique_labels[unique_labels > 0]  # Exclude background (0)
    
    results["num_segments"] = len(unique_labels)
    print(f"Found {len(unique_labels)} unique segment labels: {unique_labels}")
    
    # Count voxels per label
    for label in unique_labels:
        voxel_count = int(np.sum(data == label))
        results["segment_voxels"][str(int(label))] = voxel_count
        print(f"  Label {label}: {voxel_count:,} voxels")
    
    # Try to get segment names from header
    segment_names = []
    if 'Segment0_Name' in header:
        for i in range(10):
            key = f'Segment{i}_Name'
            if key in header:
                segment_names.append(header[key])
    
    results["segment_names"] = segment_names
    print(f"Segment names from header: {segment_names}")
    
    # Check for expected tissue types by name
    all_names_lower = ' '.join(segment_names).lower()
    results["has_bone"] = 'bone' in all_names_lower
    results["has_soft_tissue"] = 'soft' in all_names_lower or 'tissue' in all_names_lower
    results["has_air"] = 'air' in all_names_lower or 'lung' in all_names_lower
    
    results["analysis_success"] = True
    
except Exception as e:
    print(f"Error analyzing segmentation: {e}")
    results["error"] = str(e)

# Also check segment_info.json if available
info_path = "/home/ga/Documents/SlicerData/Exports/segment_info.json"
if os.path.exists(info_path):
    try:
        with open(info_path) as f:
            info = json.load(f)
        if info.get("segments"):
            results["segment_names"] = [s["name"] for s in info["segments"]]
            results["num_segments"] = len(info["segments"])
            
            all_names_lower = ' '.join(results["segment_names"]).lower()
            results["has_bone"] = 'bone' in all_names_lower
            results["has_soft_tissue"] = 'soft' in all_names_lower or 'tissue' in all_names_lower
            results["has_air"] = 'air' in all_names_lower or 'lung' in all_names_lower
            
            print(f"Updated from segment_info.json: {results['segment_names']}")
    except Exception as e:
        print(f"Could not read segment_info.json: {e}")

# Save analysis results
analysis_path = "/tmp/seg_analysis.json"
with open(analysis_path, "w") as f:
    json.dump(results, f, indent=2)

print(f"Analysis saved to {analysis_path}")
PYEOF

    # Read analysis results
    if [ -f /tmp/seg_analysis.json ]; then
        NUM_SEGMENTS=$(python3 -c "import json; print(json.load(open('/tmp/seg_analysis.json')).get('num_segments', 0))" 2>/dev/null || echo "0")
        SEGMENT_NAMES=$(python3 -c "import json; print(','.join(json.load(open('/tmp/seg_analysis.json')).get('segment_names', [])))" 2>/dev/null || echo "")
        HAS_BONE=$(python3 -c "import json; print('true' if json.load(open('/tmp/seg_analysis.json')).get('has_bone', False) else 'false')" 2>/dev/null || echo "false")
        HAS_SOFT_TISSUE=$(python3 -c "import json; print('true' if json.load(open('/tmp/seg_analysis.json')).get('has_soft_tissue', False) else 'false')" 2>/dev/null || echo "false")
        HAS_AIR=$(python3 -c "import json; print('true' if json.load(open('/tmp/seg_analysis.json')).get('has_air', False) else 'false')" 2>/dev/null || echo "false")
    fi
fi

# Create result JSON
echo "Creating result JSON..."
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_sec": $((TASK_END - TASK_START)),
    "slicer_was_running": $SLICER_RUNNING,
    "output_exists": $OUTPUT_EXISTS,
    "output_file": "$SEG_FILE",
    "output_size_bytes": $SEG_FILE_SIZE,
    "file_mtime": $FILE_MTIME,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "num_segments": $NUM_SEGMENTS,
    "segment_names": "$SEGMENT_NAMES",
    "has_bone_segment": $HAS_BONE,
    "has_soft_tissue_segment": $HAS_SOFT_TISSUE,
    "has_air_segment": $HAS_AIR,
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/tissue_seg_result.json 2>/dev/null || sudo rm -f /tmp/tissue_seg_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/tissue_seg_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/tissue_seg_result.json
chmod 666 /tmp/tissue_seg_result.json 2>/dev/null || sudo chmod 666 /tmp/tissue_seg_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

# Copy analysis results for verifier
if [ -f /tmp/seg_analysis.json ]; then
    cp /tmp/seg_analysis.json /tmp/tissue_seg_analysis.json 2>/dev/null || true
    chmod 666 /tmp/tissue_seg_analysis.json 2>/dev/null || true
fi

echo ""
echo "Result saved to /tmp/tissue_seg_result.json"
cat /tmp/tissue_seg_result.json
echo ""
echo "=== Export Complete ==="