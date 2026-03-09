#!/bin/bash
echo "=== Exporting Clean Segmentation Islands Task Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

DATA_DIR="/home/ga/Documents/SlicerData/ChestCT"
EXPORT_DIR="/home/ga/Documents/SlicerData/Exports"
OUTPUT_FILE="$EXPORT_DIR/lungs_cleaned.seg.nrrd"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/islands_final.png 2>/dev/null || true
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
    echo "3D Slicer is running"
    
    # Try to export segmentation from Slicer if not already saved
    cat > /tmp/export_seg.py << 'EXPORTPY'
import slicer
import os

export_dir = "/home/ga/Documents/SlicerData/Exports"
os.makedirs(export_dir, exist_ok=True)

# Find segmentation node
seg_nodes = slicer.util.getNodesByClass("vtkMRMLSegmentationNode")
print(f"Found {len(seg_nodes)} segmentation node(s)")

for seg_node in seg_nodes:
    name = seg_node.GetName()
    print(f"  Segmentation: {name}")
    
    # Export as segmentation file
    output_path = os.path.join(export_dir, "lungs_cleaned.seg.nrrd")
    
    # Check if file already exists
    if not os.path.exists(output_path):
        print(f"Exporting to {output_path}...")
        slicer.util.saveNode(seg_node, output_path)
        print("Export complete")
    else:
        print(f"Output file already exists: {output_path}")

print("Export script finished")
EXPORTPY

    # Run export script
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_seg.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    EXPORT_PID=$!
    sleep 10
    kill $EXPORT_PID 2>/dev/null || true
fi

# ============================================================
# Check for output file
# ============================================================
OUTPUT_EXISTS="false"
OUTPUT_SIZE=0
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c%Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    echo "Output file found: $OUTPUT_FILE ($OUTPUT_SIZE bytes)"
else
    echo "Output file NOT found at $OUTPUT_FILE"
    
    # Search for alternative locations
    echo "Searching for segmentation files..."
    FOUND_FILES=$(find /home/ga -name "*.seg.nrrd" -o -name "*cleaned*.nrrd" -o -name "*lungs*.nrrd" 2>/dev/null | head -5)
    if [ -n "$FOUND_FILES" ]; then
        echo "Found alternative files:"
        echo "$FOUND_FILES"
        # Use the first found file
        ALT_FILE=$(echo "$FOUND_FILES" | head -1)
        if [ -f "$ALT_FILE" ]; then
            OUTPUT_EXISTS="true"
            OUTPUT_FILE="$ALT_FILE"
            OUTPUT_SIZE=$(stat -c%s "$ALT_FILE" 2>/dev/null || echo "0")
        fi
    fi
fi

# ============================================================
# Analyze the cleaned segmentation
# ============================================================
CLEANED_ISLAND_COUNT=0
CLEANED_TOTAL_VOXELS=0
VOLUME_RETAINED_FRACTION=0

if [ "$OUTPUT_EXISTS" = "true" ]; then
    echo "Analyzing cleaned segmentation..."
    
    python3 << ANALYSISPY
import os
import sys
import json
import numpy as np

try:
    import nibabel as nib
except ImportError:
    print("nibabel not available")
    sys.exit(1)

from scipy.ndimage import label as scipy_label

output_file = "$OUTPUT_FILE"
gt_file = "$GROUND_TRUTH_DIR/islands_ground_truth.json"

# Load ground truth
gt_data = {}
if os.path.exists(gt_file):
    with open(gt_file) as f:
        gt_data = json.load(f)

original_total = gt_data.get('total_voxels', 0)
original_islands = gt_data.get('original_island_count', 0)
expected_main = gt_data.get('main_component_count', 2)

print(f"Original: {original_islands} islands, {original_total} voxels")

# Load cleaned segmentation
try:
    # Try to load as NIfTI first
    cleaned_nii = nib.load(output_file)
    cleaned_data = cleaned_nii.get_fdata()
except Exception as e:
    print(f"Error loading NIfTI: {e}")
    # Try as NRRD
    try:
        import nrrd
        cleaned_data, _ = nrrd.read(output_file)
    except:
        print("Failed to load segmentation file")
        cleaned_data = None

if cleaned_data is not None:
    # Binarize (in case of labelmap)
    cleaned_binary = cleaned_data > 0
    
    # Count islands
    labeled, num_islands = scipy_label(cleaned_binary)
    cleaned_total = np.sum(cleaned_binary)
    
    print(f"Cleaned: {num_islands} islands, {cleaned_total} voxels")
    
    # Calculate volume retention
    if original_total > 0:
        retention = cleaned_total / original_total
        print(f"Volume retained: {retention:.2%}")
    else:
        retention = 0
    
    # Get component sizes
    component_sizes = []
    for i in range(1, num_islands + 1):
        size = np.sum(labeled == i)
        component_sizes.append(size)
    component_sizes.sort(reverse=True)
    
    # Check if main structures preserved
    main_preserved = False
    if original_total > 0:
        largest_sum = sum(component_sizes[:2]) if len(component_sizes) >= 2 else (component_sizes[0] if component_sizes else 0)
        if largest_sum >= 0.8 * gt_data.get('main_structure_voxels', original_total * 0.9):
            main_preserved = True
    
    # Save analysis results
    analysis = {
        "cleaned_island_count": int(num_islands),
        "cleaned_total_voxels": int(cleaned_total),
        "volume_retained_fraction": float(retention),
        "component_sizes": [int(s) for s in component_sizes[:10]],
        "main_structures_preserved": main_preserved,
        "islands_removed": int(original_islands - num_islands) if original_islands > 0 else 0
    }
    
    with open("/tmp/cleaned_analysis.json", "w") as f:
        json.dump(analysis, f, indent=2)
    
    print(f"\nAnalysis saved to /tmp/cleaned_analysis.json")
else:
    print("Could not analyze segmentation")
    with open("/tmp/cleaned_analysis.json", "w") as f:
        json.dump({"error": "Could not load segmentation"}, f)
ANALYSISPY
fi

# Load analysis results
CLEANED_ANALYSIS="{}"
if [ -f /tmp/cleaned_analysis.json ]; then
    CLEANED_ANALYSIS=$(cat /tmp/cleaned_analysis.json)
    CLEANED_ISLAND_COUNT=$(echo "$CLEANED_ANALYSIS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('cleaned_island_count', 0))" 2>/dev/null || echo "0")
    CLEANED_TOTAL_VOXELS=$(echo "$CLEANED_ANALYSIS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('cleaned_total_voxels', 0))" 2>/dev/null || echo "0")
    VOLUME_RETAINED=$(echo "$CLEANED_ANALYSIS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('volume_retained_fraction', 0))" 2>/dev/null || echo "0")
    MAIN_PRESERVED=$(echo "$CLEANED_ANALYSIS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('main_structures_preserved', False))" 2>/dev/null || echo "false")
    ISLANDS_REMOVED=$(echo "$CLEANED_ANALYSIS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('islands_removed', 0))" 2>/dev/null || echo "0")
fi

# Load ground truth
GT_DATA="{}"
if [ -f "$GROUND_TRUTH_DIR/islands_ground_truth.json" ]; then
    GT_DATA=$(cat "$GROUND_TRUTH_DIR/islands_ground_truth.json")
    ORIGINAL_ISLAND_COUNT=$(echo "$GT_DATA" | python3 -c "import json,sys; print(json.load(sys.stdin).get('original_island_count', 0))" 2>/dev/null || echo "0")
    ORIGINAL_TOTAL_VOXELS=$(echo "$GT_DATA" | python3 -c "import json,sys; print(json.load(sys.stdin).get('total_voxels', 0))" 2>/dev/null || echo "0")
fi

# ============================================================
# Create result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "output_exists": $OUTPUT_EXISTS,
    "output_file": "$OUTPUT_FILE",
    "output_size_bytes": $OUTPUT_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "original_island_count": $ORIGINAL_ISLAND_COUNT,
    "cleaned_island_count": $CLEANED_ISLAND_COUNT,
    "islands_removed": $ISLANDS_REMOVED,
    "original_total_voxels": $ORIGINAL_TOTAL_VOXELS,
    "cleaned_total_voxels": $CLEANED_TOTAL_VOXELS,
    "volume_retained_fraction": $VOLUME_RETAINED,
    "main_structures_preserved": $MAIN_PRESERVED,
    "screenshot_path": "/tmp/islands_final.png"
}
EOF

# Move to final location
rm -f /tmp/islands_task_result.json 2>/dev/null || sudo rm -f /tmp/islands_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/islands_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/islands_task_result.json
chmod 666 /tmp/islands_task_result.json 2>/dev/null || sudo chmod 666 /tmp/islands_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Complete ==="
echo "Result saved to /tmp/islands_task_result.json"
cat /tmp/islands_task_result.json