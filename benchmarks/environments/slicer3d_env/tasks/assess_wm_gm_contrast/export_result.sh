#!/bin/bash
echo "=== Exporting WM/GM Contrast Assessment Result ==="

source /workspace/scripts/task_utils.sh

# Get sample ID
SAMPLE_ID="BraTS2021_00000"
if [ -f /tmp/wm_gm_sample_id.txt ]; then
    SAMPLE_ID=$(cat /tmp/wm_gm_sample_id.txt)
fi

EXPORTS_DIR="/home/ga/Documents/SlicerData/Exports"
OUTPUT_FILE="$EXPORTS_DIR/wm_gm_contrast.json"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/wm_gm_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to extract fiducial data from Slicer
    echo "Extracting markup data from Slicer..."
    cat > /tmp/export_wm_gm_markups.py << 'PYEOF'
import slicer
import os
import json

output_dir = "/home/ga/Documents/SlicerData/Exports"
os.makedirs(output_dir, exist_ok=True)

# Find all fiducial markups
fiducial_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsFiducialNode")
print(f"Found {len(fiducial_nodes)} fiducial markup node(s)")

# Get volume node for intensity sampling
volume_nodes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
volume_node = None
if volume_nodes:
    volume_node = volume_nodes[0]
    print(f"Using volume: {volume_node.GetName()}")

fiducials_data = []
wm_data = None
gm_data = None

for node in fiducial_nodes:
    n_points = node.GetNumberOfControlPoints()
    node_name = node.GetName().lower()
    print(f"Processing markup '{node.GetName()}' with {n_points} point(s)")
    
    for i in range(n_points):
        pos = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(i, pos)
        label = node.GetNthControlPointLabel(i)
        
        # Sample intensity at this location if volume is available
        intensity = 0.0
        if volume_node:
            # Convert RAS to IJK
            rasToIjk = slicer.vtkMatrix4x4()
            volume_node.GetRASToIJKMatrix(rasToIjk)
            ijk = [0, 0, 0, 1]
            rasToIjk.MultiplyPoint([pos[0], pos[1], pos[2], 1], ijk)
            
            # Get intensity
            imageData = volume_node.GetImageData()
            if imageData:
                dims = imageData.GetDimensions()
                ix, iy, iz = int(round(ijk[0])), int(round(ijk[1])), int(round(ijk[2]))
                if 0 <= ix < dims[0] and 0 <= iy < dims[1] and 0 <= iz < dims[2]:
                    intensity = imageData.GetScalarComponentAsDouble(ix, iy, iz, 0)
        
        point_data = {
            "name": node.GetName(),
            "label": label,
            "position_ras": pos,
            "intensity": intensity
        }
        fiducials_data.append(point_data)
        print(f"  Point '{label}': RAS={pos}, intensity={intensity:.1f}")
        
        # Identify WM and GM samples
        label_lower = label.lower() if label else ""
        name_lower = node_name
        
        if "wm" in label_lower or "white" in label_lower or "wm" in name_lower or "white" in name_lower:
            wm_data = point_data
            print(f"    -> Identified as WHITE MATTER sample")
        elif "gm" in label_lower or "gray" in label_lower or "grey" in label_lower or "gm" in name_lower or "gray" in name_lower or "grey" in name_lower:
            gm_data = point_data
            print(f"    -> Identified as GRAY MATTER sample")

# Save extracted data
extracted_path = os.path.join(output_dir, "extracted_fiducials.json")
with open(extracted_path, "w") as f:
    json.dump({
        "fiducials": fiducials_data,
        "wm_sample": wm_data,
        "gm_sample": gm_data,
        "volume_name": volume_node.GetName() if volume_node else None
    }, f, indent=2)

print(f"\nExtracted data saved to {extracted_path}")
if wm_data and gm_data:
    ratio = wm_data["intensity"] / gm_data["intensity"] if gm_data["intensity"] > 0 else 0
    print(f"WM intensity: {wm_data['intensity']:.1f}")
    print(f"GM intensity: {gm_data['intensity']:.1f}")
    print(f"WM/GM ratio: {ratio:.3f}")
PYEOF

    # Run export script in Slicer
    timeout 30 sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_wm_gm_markups.py --no-main-window > /tmp/slicer_export_wm_gm.log 2>&1 || true
    sleep 3
fi

# Check for user's output file
OUTPUT_EXISTS="false"
OUTPUT_SIZE=0
OUTPUT_MTIME=0
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    echo "Found output file: $OUTPUT_FILE (${OUTPUT_SIZE} bytes)"
fi

# Try to parse user's output file
WM_INTENSITY=""
GM_INTENSITY=""
WM_GM_RATIO=""
QUALITY_ASSESSMENT=""
WM_POSITION=""
GM_POSITION=""
JSON_VALID="false"

if [ "$OUTPUT_EXISTS" = "true" ]; then
    # Validate and extract JSON content
    PARSE_RESULT=$(python3 << PYEOF
import json
import sys

try:
    with open("$OUTPUT_FILE") as f:
        data = json.load(f)
    
    result = {
        "json_valid": True,
        "wm_intensity": data.get("wm_intensity", ""),
        "gm_intensity": data.get("gm_intensity", ""),
        "wm_gm_ratio": data.get("wm_gm_ratio", ""),
        "quality_assessment": data.get("quality_assessment", ""),
        "wm_position": data.get("wm_position_ras", []),
        "gm_position": data.get("gm_position_ras", []),
        "has_required_fields": all(k in data for k in ["wm_intensity", "gm_intensity", "wm_gm_ratio"])
    }
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({"json_valid": False, "error": str(e)}))
PYEOF
)
    
    JSON_VALID=$(echo "$PARSE_RESULT" | python3 -c "import json,sys; print(str(json.load(sys.stdin).get('json_valid', False)).lower())" 2>/dev/null || echo "false")
    
    if [ "$JSON_VALID" = "true" ]; then
        WM_INTENSITY=$(echo "$PARSE_RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('wm_intensity', ''))" 2>/dev/null || echo "")
        GM_INTENSITY=$(echo "$PARSE_RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('gm_intensity', ''))" 2>/dev/null || echo "")
        WM_GM_RATIO=$(echo "$PARSE_RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('wm_gm_ratio', ''))" 2>/dev/null || echo "")
        QUALITY_ASSESSMENT=$(echo "$PARSE_RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('quality_assessment', ''))" 2>/dev/null || echo "")
        echo "Parsed: WM=$WM_INTENSITY, GM=$GM_INTENSITY, Ratio=$WM_GM_RATIO"
    fi
fi

# Also check for extracted fiducial data (if user didn't create JSON but placed fiducials)
EXTRACTED_FILE="$EXPORTS_DIR/extracted_fiducials.json"
EXTRACTED_WM_INTENSITY=""
EXTRACTED_GM_INTENSITY=""
FIDUCIALS_FOUND=0

if [ -f "$EXTRACTED_FILE" ]; then
    EXTRACTED_DATA=$(python3 << PYEOF
import json
try:
    with open("$EXTRACTED_FILE") as f:
        data = json.load(f)
    
    wm = data.get("wm_sample", {})
    gm = data.get("gm_sample", {})
    fiducials = data.get("fiducials", [])
    
    result = {
        "wm_intensity": wm.get("intensity", "") if wm else "",
        "gm_intensity": gm.get("intensity", "") if gm else "",
        "fiducials_count": len(fiducials),
        "wm_position": wm.get("position_ras", []) if wm else [],
        "gm_position": gm.get("position_ras", []) if gm else []
    }
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({"error": str(e)}))
PYEOF
)
    
    EXTRACTED_WM_INTENSITY=$(echo "$EXTRACTED_DATA" | python3 -c "import json,sys; print(json.load(sys.stdin).get('wm_intensity', ''))" 2>/dev/null || echo "")
    EXTRACTED_GM_INTENSITY=$(echo "$EXTRACTED_DATA" | python3 -c "import json,sys; print(json.load(sys.stdin).get('gm_intensity', ''))" 2>/dev/null || echo "")
    FIDUCIALS_FOUND=$(echo "$EXTRACTED_DATA" | python3 -c "import json,sys; print(json.load(sys.stdin).get('fiducials_count', 0))" 2>/dev/null || echo "0")
    echo "Extracted from Slicer: WM=$EXTRACTED_WM_INTENSITY, GM=$EXTRACTED_GM_INTENSITY, Fiducials=$FIDUCIALS_FOUND"
fi

# Load reference data
REF_FILE="$GROUND_TRUTH_DIR/${SAMPLE_ID}_wm_gm_reference.json"
REF_WM=""
REF_GM=""
REF_RATIO=""

if [ -f "$REF_FILE" ]; then
    REF_WM=$(python3 -c "import json; print(json.load(open('$REF_FILE')).get('estimated_wm_intensity', ''))" 2>/dev/null || echo "")
    REF_GM=$(python3 -c "import json; print(json.load(open('$REF_FILE')).get('estimated_gm_intensity', ''))" 2>/dev/null || echo "")
    REF_RATIO=$(python3 -c "import json; print(json.load(open('$REF_FILE')).get('estimated_wm_gm_ratio', ''))" 2>/dev/null || echo "")
fi

# Copy reference file for verifier
cp "$REF_FILE" /tmp/wm_gm_reference.json 2>/dev/null || true

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
    "json_valid": $JSON_VALID,
    "reported_wm_intensity": "$WM_INTENSITY",
    "reported_gm_intensity": "$GM_INTENSITY",
    "reported_wm_gm_ratio": "$WM_GM_RATIO",
    "reported_quality_assessment": "$QUALITY_ASSESSMENT",
    "extracted_wm_intensity": "$EXTRACTED_WM_INTENSITY",
    "extracted_gm_intensity": "$EXTRACTED_GM_INTENSITY",
    "fiducials_found": $FIDUCIALS_FOUND,
    "reference_wm_intensity": "$REF_WM",
    "reference_gm_intensity": "$REF_GM",
    "reference_ratio": "$REF_RATIO",
    "sample_id": "$SAMPLE_ID",
    "screenshot_path": "/tmp/wm_gm_final.png"
}
EOF

# Move to final location
rm -f /tmp/wm_gm_task_result.json 2>/dev/null || sudo rm -f /tmp/wm_gm_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/wm_gm_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/wm_gm_task_result.json
chmod 666 /tmp/wm_gm_task_result.json 2>/dev/null || sudo chmod 666 /tmp/wm_gm_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result saved to /tmp/wm_gm_task_result.json"
cat /tmp/wm_gm_task_result.json
echo ""
echo "=== Export Complete ==="