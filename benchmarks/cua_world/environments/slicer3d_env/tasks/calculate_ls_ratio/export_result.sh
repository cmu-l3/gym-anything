#!/bin/bash
echo "=== Exporting Liver-to-Spleen Ratio Measurement Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
EXPORTS_DIR="/home/ga/Documents/SlicerData/Exports"
OUTPUT_FILE="$EXPORTS_DIR/ls_ratio_result.json"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/ls_ratio_final.png 2>/dev/null || true
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
SLICER_PID=""
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
    SLICER_PID=$(pgrep -f "Slicer" | head -1)
    echo "Slicer is running (PID: $SLICER_PID)"
fi

# Check for output file
OUTPUT_EXISTS="false"
OUTPUT_SIZE="0"
OUTPUT_MTIME="0"
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    # Check if file was created/modified during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
        echo "Output file created during task"
    else
        echo "WARNING: Output file exists but was not created during task"
    fi
    
    echo "Output file: $OUTPUT_FILE ($OUTPUT_SIZE bytes)"
else
    echo "Output file not found at: $OUTPUT_FILE"
fi

# Parse output file content if it exists
LIVER_HU_MEAN=""
LIVER_HU_STD=""
SPLEEN_HU_MEAN=""
SPLEEN_HU_STD=""
LS_RATIO=""
INTERPRETATION=""
SLICE_NUMBER=""
VALID_JSON="false"

if [ "$OUTPUT_EXISTS" = "true" ]; then
    # Validate JSON and extract values
    PARSE_RESULT=$(python3 << PYEOF
import json
import sys

try:
    with open("$OUTPUT_FILE", "r") as f:
        data = json.load(f)
    
    # Extract required fields
    liver_hu = data.get("liver_roi_hu_mean", data.get("liver_hu_mean", ""))
    liver_std = data.get("liver_roi_hu_std", data.get("liver_hu_std", ""))
    spleen_hu = data.get("spleen_roi_hu_mean", data.get("spleen_hu_mean", ""))
    spleen_std = data.get("spleen_roi_hu_std", data.get("spleen_hu_std", ""))
    ls_ratio = data.get("ls_ratio", data.get("ratio", ""))
    interpretation = data.get("interpretation", data.get("classification", ""))
    slice_num = data.get("slice_number", data.get("slice", ""))
    
    # Output as pipe-separated values
    print(f"VALID|{liver_hu}|{liver_std}|{spleen_hu}|{spleen_std}|{ls_ratio}|{interpretation}|{slice_num}")
except json.JSONDecodeError as e:
    print(f"INVALID|JSON parse error: {e}")
except Exception as e:
    print(f"ERROR|{e}")
PYEOF
)
    
    if echo "$PARSE_RESULT" | grep -q "^VALID"; then
        VALID_JSON="true"
        IFS='|' read -r STATUS LIVER_HU_MEAN LIVER_HU_STD SPLEEN_HU_MEAN SPLEEN_HU_STD LS_RATIO INTERPRETATION SLICE_NUMBER <<< "$PARSE_RESULT"
        echo "Parsed output:"
        echo "  Liver HU: $LIVER_HU_MEAN ± $LIVER_HU_STD"
        echo "  Spleen HU: $SPLEEN_HU_MEAN ± $SPLEEN_HU_STD"
        echo "  L/S Ratio: $LS_RATIO"
        echo "  Interpretation: $INTERPRETATION"
        echo "  Slice: $SLICE_NUMBER"
    else
        echo "Failed to parse output file: $PARSE_RESULT"
    fi
fi

# Try to extract measurements from Slicer if output file is missing/invalid
if [ "$SLICER_RUNNING" = "true" ] && [ "$VALID_JSON" = "false" ]; then
    echo "Attempting to extract measurements from Slicer..."
    
    cat > /tmp/extract_ls_measurements.py << 'PYEOF'
import slicer
import json
import os
import numpy as np

output_dir = "/home/ga/Documents/SlicerData/Exports"
os.makedirs(output_dir, exist_ok=True)

measurements = {
    "extracted_from_slicer": True,
    "rois_found": []
}

# Look for segment statistics or markup ROIs
try:
    # Check for segments
    seg_nodes = slicer.util.getNodesByClass("vtkMRMLSegmentationNode")
    for seg_node in seg_nodes:
        seg = seg_node.GetSegmentation()
        if seg:
            for i in range(seg.GetNumberOfSegments()):
                segment = seg.GetNthSegment(i)
                name = segment.GetName().lower() if segment else ""
                measurements["rois_found"].append({
                    "type": "segment",
                    "name": name
                })
    
    # Check for closed curve markups (ROIs)
    curve_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsClosedCurveNode")
    for node in curve_nodes:
        name = node.GetName()
        measurements["rois_found"].append({
            "type": "closed_curve",
            "name": name
        })
    
    # Check for ROI nodes
    roi_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsROINode")
    for node in roi_nodes:
        name = node.GetName()
        measurements["rois_found"].append({
            "type": "roi",
            "name": name
        })

except Exception as e:
    measurements["error"] = str(e)

# Save extracted info
extract_path = os.path.join(output_dir, "slicer_extracted.json")
with open(extract_path, "w") as f:
    json.dump(measurements, f, indent=2)

print(f"Extraction complete: {len(measurements['rois_found'])} ROIs found")
PYEOF

    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/extract_ls_measurements.py --no-main-window > /tmp/slicer_extract.log 2>&1 &
    EXTRACT_PID=$!
    sleep 8
    kill $EXTRACT_PID 2>/dev/null || true
fi

# Load reference data for comparison
REF_LIVER_HU=""
REF_SPLEEN_HU=""
REF_LS_RATIO=""
REF_CLASSIFICATION=""

CASE_ID=$(cat /tmp/amos_case_id 2>/dev/null || echo "amos_0001")
REF_FILE="$GROUND_TRUTH_DIR/${CASE_ID}_ls_reference.json"

if [ -f "$REF_FILE" ]; then
    REF_DATA=$(python3 << PYEOF
import json
with open("$REF_FILE", "r") as f:
    data = json.load(f)
liver = data.get("liver_hu_mean", 0)
spleen = data.get("spleen_hu_mean", 0)
ratio = data.get("expected_ls_ratio", 0)
classification = data.get("expected_classification", "")
print(f"{liver}|{spleen}|{ratio}|{classification}")
PYEOF
)
    IFS='|' read -r REF_LIVER_HU REF_SPLEEN_HU REF_LS_RATIO REF_CLASSIFICATION <<< "$REF_DATA"
    echo "Reference values loaded:"
    echo "  Expected Liver HU: $REF_LIVER_HU"
    echo "  Expected Spleen HU: $REF_SPLEEN_HU"
    echo "  Expected L/S Ratio: $REF_LS_RATIO"
fi

# Verify ratio calculation if values are present
RATIO_CALCULATION_CORRECT="false"
if [ -n "$LIVER_HU_MEAN" ] && [ -n "$SPLEEN_HU_MEAN" ] && [ -n "$LS_RATIO" ]; then
    CALC_CHECK=$(python3 << PYEOF
liver = float("$LIVER_HU_MEAN") if "$LIVER_HU_MEAN" else 0
spleen = float("$SPLEEN_HU_MEAN") if "$SPLEEN_HU_MEAN" else 0
reported_ratio = float("$LS_RATIO") if "$LS_RATIO" else 0

if spleen > 0:
    expected_ratio = liver / spleen
    diff = abs(expected_ratio - reported_ratio)
    if diff < 0.02:
        print("CORRECT")
    else:
        print(f"WRONG|expected {expected_ratio:.4f}, got {reported_ratio}")
else:
    print("INVALID|spleen HU is zero")
PYEOF
)
    if echo "$CALC_CHECK" | grep -q "^CORRECT"; then
        RATIO_CALCULATION_CORRECT="true"
        echo "Ratio calculation verified: CORRECT"
    else
        echo "Ratio calculation: $CALC_CHECK"
    fi
fi

# Verify interpretation matches ratio
INTERPRETATION_CORRECT="false"
if [ -n "$LS_RATIO" ] && [ -n "$INTERPRETATION" ]; then
    INTERP_CHECK=$(python3 << PYEOF
ratio = float("$LS_RATIO") if "$LS_RATIO" else 0
reported = "$INTERPRETATION".strip()

if ratio >= 1.0:
    expected = "Normal"
elif ratio >= 0.8:
    expected = "Borderline"
else:
    expected = "Abnormal"

if reported.lower() == expected.lower():
    print("CORRECT")
else:
    print(f"WRONG|expected '{expected}' for ratio {ratio:.3f}, got '{reported}'")
PYEOF
)
    if echo "$INTERP_CHECK" | grep -q "^CORRECT"; then
        INTERPRETATION_CORRECT="true"
        echo "Interpretation verified: CORRECT"
    else
        echo "Interpretation: $INTERP_CHECK"
    fi
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "output_file_exists": $OUTPUT_EXISTS,
    "output_file_size": $OUTPUT_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "valid_json": $VALID_JSON,
    "liver_hu_mean": "$LIVER_HU_MEAN",
    "liver_hu_std": "$LIVER_HU_STD",
    "spleen_hu_mean": "$SPLEEN_HU_MEAN",
    "spleen_hu_std": "$SPLEEN_HU_STD",
    "ls_ratio": "$LS_RATIO",
    "interpretation": "$INTERPRETATION",
    "slice_number": "$SLICE_NUMBER",
    "ratio_calculation_correct": $RATIO_CALCULATION_CORRECT,
    "interpretation_correct": $INTERPRETATION_CORRECT,
    "ref_liver_hu": "$REF_LIVER_HU",
    "ref_spleen_hu": "$REF_SPLEEN_HU",
    "ref_ls_ratio": "$REF_LS_RATIO",
    "ref_classification": "$REF_CLASSIFICATION",
    "screenshot_path": "/tmp/ls_ratio_final.png"
}
EOF

# Move to final location
rm -f /tmp/ls_ratio_task_result.json 2>/dev/null || sudo rm -f /tmp/ls_ratio_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/ls_ratio_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/ls_ratio_task_result.json
chmod 666 /tmp/ls_ratio_task_result.json 2>/dev/null || sudo chmod 666 /tmp/ls_ratio_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result saved to /tmp/ls_ratio_task_result.json"
cat /tmp/ls_ratio_task_result.json
echo ""
echo "=== Export Complete ==="