#!/bin/bash
echo "=== Exporting Segmentation Margin Expansion Result ==="

source /workspace/scripts/task_utils.sh

# Get the sample ID used
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
OUTPUT_SEG="$BRATS_DIR/treatment_volumes.seg.nrrd"
OUTPUT_REPORT="$BRATS_DIR/treatment_volumes_report.json"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/margin_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export segmentation from Slicer
    cat > /tmp/export_segments.py << 'PYEOF'
import slicer
import os
import json

brats_dir = "/home/ga/Documents/SlicerData/BraTS"
output_seg = os.path.join(brats_dir, "treatment_volumes.seg.nrrd")
output_report = os.path.join(brats_dir, "treatment_volumes_report.json")

print("Exporting segmentation data...")

# Find the segmentation node
seg_nodes = slicer.util.getNodesByClass("vtkMRMLSegmentationNode")

if not seg_nodes:
    print("No segmentation nodes found!")
else:
    # Use the first segmentation node (should be TreatmentVolumes)
    seg_node = seg_nodes[0]
    print(f"Found segmentation: {seg_node.GetName()}")
    
    segmentation = seg_node.GetSegmentation()
    n_segments = segmentation.GetNumberOfSegments()
    print(f"Number of segments: {n_segments}")
    
    # List all segments
    segment_info = {}
    for i in range(n_segments):
        seg_id = segmentation.GetNthSegmentID(i)
        segment = segmentation.GetSegment(seg_id)
        seg_name = segment.GetName()
        print(f"  Segment {i}: {seg_name} (ID: {seg_id})")
        
        # Get segment statistics
        import SegmentStatistics
        stats_logic = SegmentStatistics.SegmentStatisticsLogic()
        stats_logic.getParameterNode().SetParameter("Segmentation", seg_node.GetID())
        stats_logic.getParameterNode().SetParameter("ScalarVolume", "")
        stats_logic.computeStatistics()
        stats = stats_logic.getStatistics()
        
        # Find volume for this segment
        volume_mm3 = 0
        for stat_key in stats.keys():
            if seg_id in stat_key and "volume_mm3" in stat_key.lower():
                volume_mm3 = stats[stat_key]
                break
        
        volume_ml = volume_mm3 / 1000.0 if volume_mm3 else 0
        segment_info[seg_name.lower()] = {
            "name": seg_name,
            "id": seg_id,
            "volume_ml": volume_ml
        }
        print(f"    Volume: {volume_ml:.2f} mL")
    
    # Save segmentation
    print(f"Saving segmentation to: {output_seg}")
    slicer.util.saveNode(seg_node, output_seg)
    
    # Create report
    report = {
        "gtv_volume_ml": segment_info.get("gtv", {}).get("volume_ml", 0),
        "ctv_volume_ml": segment_info.get("ctv", {}).get("volume_ml", 0),
        "ptv_volume_ml": segment_info.get("ptv", {}).get("volume_ml", 0),
        "ctv_margin_mm": 5,
        "ptv_margin_mm": 8,
        "segments_found": list(segment_info.keys()),
        "segment_details": segment_info
    }
    
    # Check if report already exists (agent may have created one)
    if not os.path.exists(output_report):
        print(f"Creating report: {output_report}")
        with open(output_report, 'w') as f:
            json.dump(report, f, indent=2)
    else:
        print(f"Report already exists at: {output_report}")
    
    print("Export complete!")
PYEOF
    
    # Run export in Slicer's Python environment
    # Use a timeout to avoid hanging
    timeout 30 sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_segments.py --no-main-window > /tmp/slicer_export.log 2>&1 || true
    sleep 5
fi

# Check for output files
SEG_EXISTS="false"
SEG_PATH=""
SEG_SIZE=0
SEG_MTIME=0

POSSIBLE_SEG_PATHS=(
    "$OUTPUT_SEG"
    "$BRATS_DIR/treatment_volumes.seg.nrrd"
    "$BRATS_DIR/Segmentation.seg.nrrd"
    "$BRATS_DIR/TreatmentVolumes.seg.nrrd"
    "/home/ga/Documents/treatment_volumes.seg.nrrd"
)

for path in "${POSSIBLE_SEG_PATHS[@]}"; do
    if [ -f "$path" ]; then
        SEG_EXISTS="true"
        SEG_PATH="$path"
        SEG_SIZE=$(stat -c %s "$path" 2>/dev/null || echo "0")
        SEG_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        echo "Found segmentation at: $path (${SEG_SIZE} bytes)"
        if [ "$path" != "$OUTPUT_SEG" ]; then
            cp "$path" "$OUTPUT_SEG" 2>/dev/null || true
        fi
        break
    fi
done

# Check if segmentation was created during task
SEG_CREATED_DURING_TASK="false"
if [ "$SEG_EXISTS" = "true" ] && [ "$SEG_MTIME" -gt "$TASK_START" ]; then
    SEG_CREATED_DURING_TASK="true"
fi

# Check for report
REPORT_EXISTS="false"
REPORT_PATH=""

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$BRATS_DIR/treatment_volumes_report.json"
    "$BRATS_DIR/report.json"
    "$BRATS_DIR/volumes_report.json"
    "/home/ga/Documents/treatment_volumes_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_PATH="$path"
        echo "Found report at: $path"
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        break
    fi
done

# Parse report if exists
REPORTED_GTV_VOL=""
REPORTED_CTV_VOL=""
REPORTED_PTV_VOL=""

if [ "$REPORT_EXISTS" = "true" ] && [ -f "$OUTPUT_REPORT" ]; then
    REPORTED_GTV_VOL=$(python3 -c "import json; d=json.load(open('$OUTPUT_REPORT')); print(d.get('gtv_volume_ml', ''))" 2>/dev/null || echo "")
    REPORTED_CTV_VOL=$(python3 -c "import json; d=json.load(open('$OUTPUT_REPORT')); print(d.get('ctv_volume_ml', ''))" 2>/dev/null || echo "")
    REPORTED_PTV_VOL=$(python3 -c "import json; d=json.load(open('$OUTPUT_REPORT')); print(d.get('ptv_volume_ml', ''))" 2>/dev/null || echo "")
fi

# Analyze segmentation content
SEGMENTS_FOUND=""
GTV_FOUND="false"
CTV_FOUND="false"
PTV_FOUND="false"

if [ "$SEG_EXISTS" = "true" ] && [ -f "$OUTPUT_SEG" ]; then
    # Try to analyze the segmentation file
    python3 << PYEOF > /tmp/segment_analysis.json 2>/dev/null || echo "{}"
import json
import os
import sys

output_seg = "$OUTPUT_SEG"
gt_dir = "$GROUND_TRUTH_DIR"

try:
    import nibabel as nib
    import numpy as np
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel", "numpy"])
    import nibabel as nib
    import numpy as np

# Load ground truth info
gt_info_path = os.path.join(gt_dir, "margin_task_ground_truth.json")
gt_info = {}
if os.path.exists(gt_info_path):
    with open(gt_info_path) as f:
        gt_info = json.load(f)

# Load the segmentation (NRRD format)
# For .seg.nrrd, we need to parse the NRRD header to find segment info
# This is complex, so we'll do basic analysis

result = {
    "analyzed": False,
    "gt_info": gt_info,
    "error": None
}

try:
    # Try to read as NRRD using nibabel's streamlines loader or direct parsing
    # For complex seg.nrrd files, we may need pynrrd
    try:
        import nrrd
    except ImportError:
        import subprocess
        subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "pynrrd"])
        import nrrd
    
    data, header = nrrd.read(output_seg)
    
    result["analyzed"] = True
    result["shape"] = list(data.shape)
    result["dtype"] = str(data.dtype)
    
    # Check for segment information in header
    segment_names = []
    for key, value in header.items():
        if "Segment" in key and "Name" in key:
            segment_names.append(value)
    
    result["segment_names_from_header"] = segment_names
    
    # Analyze unique values
    unique_vals = np.unique(data)
    result["unique_values"] = [int(v) for v in unique_vals]
    result["n_nonzero_voxels"] = int(np.sum(data > 0))
    
    # If we have multiple labels, analyze each
    if len(unique_vals) > 2:  # More than just 0 and 1
        label_info = {}
        for val in unique_vals:
            if val > 0:
                count = int(np.sum(data == val))
                label_info[int(val)] = count
        result["label_voxel_counts"] = label_info
    
except Exception as e:
    result["error"] = str(e)

print(json.dumps(result, indent=2))
PYEOF
    
    if [ -f /tmp/segment_analysis.json ]; then
        SEGMENTS_FOUND=$(python3 -c "import json; d=json.load(open('/tmp/segment_analysis.json')); print(','.join(d.get('segment_names_from_header', [])))" 2>/dev/null || echo "")
    fi
fi

# Copy files for verification
echo "Preparing files for verification..."
cp "$GROUND_TRUTH_DIR/margin_task_ground_truth.json" /tmp/margin_ground_truth.json 2>/dev/null || true
chmod 644 /tmp/margin_ground_truth.json 2>/dev/null || true

if [ -f "$OUTPUT_SEG" ]; then
    cp "$OUTPUT_SEG" /tmp/agent_segmentation.seg.nrrd 2>/dev/null || true
    chmod 644 /tmp/agent_segmentation.seg.nrrd 2>/dev/null || true
fi

if [ -f "$OUTPUT_REPORT" ]; then
    cp "$OUTPUT_REPORT" /tmp/agent_report.json 2>/dev/null || true
    chmod 644 /tmp/agent_report.json 2>/dev/null || true
fi

if [ -f /tmp/segment_analysis.json ]; then
    chmod 644 /tmp/segment_analysis.json 2>/dev/null || true
fi

# Close Slicer
echo "Closing Slicer..."
close_slicer

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
    "report_exists": $REPORT_EXISTS,
    "report_path": "$REPORT_PATH",
    "reported_gtv_volume_ml": "$REPORTED_GTV_VOL",
    "reported_ctv_volume_ml": "$REPORTED_CTV_VOL",
    "reported_ptv_volume_ml": "$REPORTED_PTV_VOL",
    "segments_found": "$SEGMENTS_FOUND",
    "sample_id": "$SAMPLE_ID",
    "screenshot_exists": $([ -f "/tmp/margin_final.png" ] && echo "true" || echo "false"),
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/margin_task_result.json 2>/dev/null || sudo rm -f /tmp/margin_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/margin_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/margin_task_result.json
chmod 666 /tmp/margin_task_result.json 2>/dev/null || sudo chmod 666 /tmp/margin_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/margin_task_result.json
echo ""
echo "=== Export Complete ==="