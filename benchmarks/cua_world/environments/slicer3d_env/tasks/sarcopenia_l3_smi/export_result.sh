#!/bin/bash
echo "=== Exporting L3 Sarcopenia Assessment Results ==="

source /workspace/scripts/task_utils.sh

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Get the case ID used
if [ -f /tmp/amos_case_id ]; then
    CASE_ID=$(cat /tmp/amos_case_id)
else
    CASE_ID="amos_0001"
fi

OUTPUT_SEG="$AMOS_DIR/l3_muscle_segmentation.nii.gz"
OUTPUT_REPORT="$AMOS_DIR/sarcopenia_report.json"

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/task_final_state.png ga
sleep 1

# Get task timing info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Check if Slicer is still running
SLICER_RUNNING="false"
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
fi

# Check for agent's segmentation file
SEG_EXISTS="false"
SEG_PATH=""
SEG_SIZE="0"
SEG_MTIME="0"
FILE_CREATED_DURING_TASK="false"

# Check multiple possible locations
POSSIBLE_SEG_PATHS=(
    "$OUTPUT_SEG"
    "$AMOS_DIR/l3_muscle_segmentation.nii"
    "$AMOS_DIR/Segmentation.nii.gz"
    "$AMOS_DIR/segmentation.nii.gz"
    "$AMOS_DIR/muscle_segmentation.nii.gz"
    "/home/ga/Documents/l3_muscle_segmentation.nii.gz"
    "/home/ga/l3_muscle_segmentation.nii.gz"
)

for path in "${POSSIBLE_SEG_PATHS[@]}"; do
    if [ -f "$path" ]; then
        SEG_EXISTS="true"
        SEG_PATH="$path"
        SEG_SIZE=$(stat -c %s "$path" 2>/dev/null || echo "0")
        SEG_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        
        # Check if file was created during task
        if [ "$SEG_MTIME" -gt "$TASK_START" ]; then
            FILE_CREATED_DURING_TASK="true"
        fi
        
        echo "Found segmentation at: $path (size: $SEG_SIZE bytes)"
        
        # Copy to expected location if different
        if [ "$path" != "$OUTPUT_SEG" ]; then
            cp "$path" "$OUTPUT_SEG" 2>/dev/null || true
        fi
        break
    fi
done

# Check for agent's report file
REPORT_EXISTS="false"
REPORT_PATH=""
REPORTED_L3_SLICE=""
REPORTED_SMA=""
REPORTED_SMI=""
REPORTED_CLASSIFICATION=""

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$AMOS_DIR/sarcopenia_report.json"
    "$AMOS_DIR/report.json"
    "$AMOS_DIR/l3_report.json"
    "/home/ga/Documents/sarcopenia_report.json"
    "/home/ga/sarcopenia_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_PATH="$path"
        echo "Found report at: $path"
        
        # Copy to expected location if different
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        
        # Extract report fields
        REPORTED_L3_SLICE=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('l3_slice_index', ''))" 2>/dev/null || echo "")
        REPORTED_SMA=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('skeletal_muscle_area_cm2', ''))" 2>/dev/null || echo "")
        REPORTED_SMI=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('smi_cm2_m2', ''))" 2>/dev/null || echo "")
        REPORTED_CLASSIFICATION=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('sarcopenia_classification', ''))" 2>/dev/null || echo "")
        
        echo "  L3 slice: $REPORTED_L3_SLICE"
        echo "  SMA: $REPORTED_SMA cm²"
        echo "  SMI: $REPORTED_SMI cm²/m²"
        echo "  Classification: $REPORTED_CLASSIFICATION"
        break
    fi
done

# Analyze agent's segmentation to extract metrics
AGENT_L3_SLICE=""
AGENT_SMA=""
AGENT_PIXEL_COUNT=""

if [ "$SEG_EXISTS" = "true" ] && [ -f "$OUTPUT_SEG" ]; then
    echo "Analyzing agent's segmentation..."
    python3 << 'PYEOF'
import os
import sys
import json
import numpy as np

try:
    import nibabel as nib
except ImportError:
    print("nibabel not available")
    sys.exit(0)

seg_path = "/home/ga/Documents/SlicerData/AMOS/l3_muscle_segmentation.nii.gz"
if not os.path.exists(seg_path):
    print("Segmentation not found")
    sys.exit(0)

try:
    seg_nii = nib.load(seg_path)
    seg_data = seg_nii.get_fdata()
    spacing = seg_nii.header.get_zooms()[:3]
    
    # Find which slice(s) have segmentation
    slices_with_data = []
    for z in range(seg_data.shape[2]):
        count = np.sum(seg_data[:, :, z] > 0)
        if count > 0:
            slices_with_data.append((z, count))
    
    if slices_with_data:
        # Use slice with most content
        slices_with_data.sort(key=lambda x: x[1], reverse=True)
        primary_slice = slices_with_data[0][0]
        pixel_count = slices_with_data[0][1]
        
        # Calculate area in cm²
        pixel_area_cm2 = (spacing[0] * spacing[1]) / 100.0
        sma_cm2 = pixel_count * pixel_area_cm2
        
        # Save analysis results
        analysis = {
            "agent_l3_slice": int(primary_slice),
            "agent_pixel_count": int(pixel_count),
            "agent_sma_cm2": float(round(sma_cm2, 2)),
            "slices_with_data": len(slices_with_data),
            "spacing_mm": [float(s) for s in spacing]
        }
        
        with open("/tmp/agent_seg_analysis.json", "w") as f:
            json.dump(analysis, f, indent=2)
        
        print(f"Agent L3 slice: {primary_slice}")
        print(f"Agent pixel count: {pixel_count}")
        print(f"Agent SMA: {sma_cm2:.2f} cm²")
    else:
        print("No segmentation data found in file")
        with open("/tmp/agent_seg_analysis.json", "w") as f:
            json.dump({"error": "empty_segmentation"}, f)
            
except Exception as e:
    print(f"Error analyzing segmentation: {e}")
    with open("/tmp/agent_seg_analysis.json", "w") as f:
        json.dump({"error": str(e)}, f)
PYEOF

    # Read analysis results
    if [ -f /tmp/agent_seg_analysis.json ]; then
        AGENT_L3_SLICE=$(python3 -c "import json; d=json.load(open('/tmp/agent_seg_analysis.json')); print(d.get('agent_l3_slice', ''))" 2>/dev/null || echo "")
        AGENT_SMA=$(python3 -c "import json; d=json.load(open('/tmp/agent_seg_analysis.json')); print(d.get('agent_sma_cm2', ''))" 2>/dev/null || echo "")
        AGENT_PIXEL_COUNT=$(python3 -c "import json; d=json.load(open('/tmp/agent_seg_analysis.json')); print(d.get('agent_pixel_count', ''))" 2>/dev/null || echo "")
    fi
fi

# Copy files for verification
echo "Copying files for verification..."

# Copy agent segmentation to /tmp
if [ -f "$OUTPUT_SEG" ]; then
    cp "$OUTPUT_SEG" /tmp/agent_l3_segmentation.nii.gz 2>/dev/null || true
    chmod 644 /tmp/agent_l3_segmentation.nii.gz 2>/dev/null || true
fi

# Copy agent report to /tmp
if [ -f "$OUTPUT_REPORT" ]; then
    cp "$OUTPUT_REPORT" /tmp/agent_sarcopenia_report.json 2>/dev/null || true
    chmod 644 /tmp/agent_sarcopenia_report.json 2>/dev/null || true
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
    "segmentation_size_bytes": $SEG_SIZE,
    "segmentation_mtime": $SEG_MTIME,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "report_exists": $REPORT_EXISTS,
    "report_path": "$REPORT_PATH",
    "reported_l3_slice": "$REPORTED_L3_SLICE",
    "reported_sma_cm2": "$REPORTED_SMA",
    "reported_smi_cm2_m2": "$REPORTED_SMI",
    "reported_classification": "$REPORTED_CLASSIFICATION",
    "agent_l3_slice": "$AGENT_L3_SLICE",
    "agent_sma_cm2": "$AGENT_SMA",
    "agent_pixel_count": "$AGENT_PIXEL_COUNT",
    "case_id": "$CASE_ID",
    "screenshot_exists": $([ -f "/tmp/task_final_state.png" ] && echo "true" || echo "false"),
    "ground_truth_available": $([ -f "/tmp/sarcopenia_ground_truth.json" ] && echo "true" || echo "false"),
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/sarcopenia_task_result.json 2>/dev/null || sudo rm -f /tmp/sarcopenia_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/sarcopenia_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/sarcopenia_task_result.json
chmod 666 /tmp/sarcopenia_task_result.json 2>/dev/null || sudo chmod 666 /tmp/sarcopenia_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result ==="
cat /tmp/sarcopenia_task_result.json
echo ""
echo "=== Export Complete ==="