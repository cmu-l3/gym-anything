#!/bin/bash
echo "=== Exporting CT Tissue Calibration Verification Result ==="

source /workspace/scripts/task_utils.sh

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Get case ID
CASE_ID="amos_0001"
if [ -f /tmp/ct_case_id.txt ]; then
    CASE_ID=$(cat /tmp/ct_case_id.txt)
fi

CT_FILE="$AMOS_DIR/${CASE_ID}.nii.gz"

# Record task timing
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    sudo -u ga DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if Slicer is running
SLICER_RUNNING="false"
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
fi

# Export fiducials and sample intensities using Slicer Python
cat > /tmp/export_fiducials.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/AMOS"
os.makedirs(output_dir, exist_ok=True)

# Get the loaded volume
volumes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
volume = volumes[0] if volumes else None

# Get fiducial/point markup nodes
fiducial_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsFiducialNode")
point_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsPointListNode")

all_fiducial_nodes = list(fiducial_nodes) + list(point_nodes)
print(f"Found {len(all_fiducial_nodes)} fiducial/point list node(s)")

fiducials_data = []
fiducial_count = 0

for node in all_fiducial_nodes:
    n_points = node.GetNumberOfControlPoints()
    print(f"  Node '{node.GetName()}' has {n_points} point(s)")
    
    for i in range(n_points):
        fiducial_count += 1
        pos = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(i, pos)
        
        label = node.GetNthControlPointLabel(i)
        if not label:
            label = node.GetName()
        
        # Sample intensity at this position from the volume
        intensity = None
        if volume:
            # Convert RAS to IJK
            ras_to_ijk = slicer.vtkMRMLTransformNode()
            volume.GetRASToIJKMatrix(ras_to_ijk)
            
            # Manual matrix application
            matrix = slicer.util.arrayFromVTKMatrix(volume.GetRASToIJKMatrix())
            ras_h = [pos[0], pos[1], pos[2], 1.0]
            ijk_h = matrix.dot(ras_h)
            ijk = [int(round(ijk_h[0])), int(round(ijk_h[1])), int(round(ijk_h[2]))]
            
            # Get image data
            image_data = volume.GetImageData()
            if image_data:
                dims = image_data.GetDimensions()
                # Check bounds
                if (0 <= ijk[0] < dims[0] and 
                    0 <= ijk[1] < dims[1] and 
                    0 <= ijk[2] < dims[2]):
                    intensity = image_data.GetScalarComponentAsDouble(ijk[0], ijk[1], ijk[2], 0)
                    print(f"    Point '{label}' at RAS {pos} -> IJK {ijk} -> Intensity: {intensity:.1f}")
                else:
                    print(f"    Point '{label}' at RAS {pos} -> IJK {ijk} OUT OF BOUNDS")
            else:
                print(f"    No image data available")
        
        fiducial_info = {
            "label": label,
            "node_name": node.GetName(),
            "position_ras": pos,
            "intensity": intensity,
            "index": i
        }
        fiducials_data.append(fiducial_info)

# Save fiducials data
output_path = os.path.join(output_dir, "sampled_fiducials.json")
with open(output_path, "w") as f:
    json.dump({
        "fiducials": fiducials_data,
        "total_count": fiducial_count,
        "volume_loaded": volume is not None,
        "volume_name": volume.GetName() if volume else None
    }, f, indent=2)

print(f"\nExported {fiducial_count} fiducial(s) to {output_path}")

# Also save the markup nodes themselves
for node in all_fiducial_nodes:
    safe_name = node.GetName().replace(" ", "_").replace("/", "_")
    mrk_path = os.path.join(output_dir, f"{safe_name}.mrk.json")
    try:
        slicer.util.saveNode(node, mrk_path)
        print(f"Saved markup to {mrk_path}")
    except Exception as e:
        print(f"Could not save markup: {e}")

print("\nExport complete")
PYEOF

if [ "$SLICER_RUNNING" = "true" ]; then
    echo "Extracting fiducials from Slicer..."
    # Run export script in running Slicer
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --no-splash --no-main-window --python-script /tmp/export_fiducials.py > /tmp/slicer_export.log 2>&1 &
    EXPORT_PID=$!
    
    # Wait for export with timeout
    for i in $(seq 1 30); do
        if [ -f "$AMOS_DIR/sampled_fiducials.json" ]; then
            echo "Fiducials exported successfully"
            break
        fi
        sleep 1
    done
    
    kill $EXPORT_PID 2>/dev/null || true
    sleep 2
fi

# Read exported fiducials data
FIDUCIALS_FILE="$AMOS_DIR/sampled_fiducials.json"
FIDUCIAL_COUNT=0
AIR_FOUND="false"
FAT_FOUND="false"
LIVER_FOUND="false"
BONE_FOUND="false"
AIR_HU=""
FAT_HU=""
LIVER_HU=""
BONE_HU=""

if [ -f "$FIDUCIALS_FILE" ]; then
    echo "Parsing fiducials data..."
    
    FIDUCIAL_COUNT=$(python3 -c "
import json
with open('$FIDUCIALS_FILE') as f:
    data = json.load(f)
print(data.get('total_count', 0))
" 2>/dev/null || echo "0")
    
    # Parse each fiducial to identify tissue types
    python3 << 'PARSEPY' > /tmp/parsed_fiducials.txt
import json
import sys

with open("$AMOS_DIR/sampled_fiducials.json") as f:
    data = json.load(f)

fiducials = data.get("fiducials", [])

results = {
    "air": {"found": False, "hu": None, "position": None},
    "fat": {"found": False, "hu": None, "position": None},
    "liver": {"found": False, "hu": None, "position": None},
    "bone": {"found": False, "hu": None, "position": None}
}

for fid in fiducials:
    label = (fid.get("label", "") + " " + fid.get("node_name", "")).lower()
    intensity = fid.get("intensity")
    position = fid.get("position_ras")
    
    if "air" in label:
        results["air"] = {"found": True, "hu": intensity, "position": position}
    elif "fat" in label:
        results["fat"] = {"found": True, "hu": intensity, "position": position}
    elif "liver" in label or "hepat" in label:
        results["liver"] = {"found": True, "hu": intensity, "position": position}
    elif "bone" in label or "spine" in label or "vertebr" in label:
        results["bone"] = {"found": True, "hu": intensity, "position": position}

# Output for bash parsing
for tissue, data in results.items():
    found = "true" if data["found"] else "false"
    hu = data["hu"] if data["hu"] is not None else ""
    print(f"{tissue}_found={found}")
    print(f"{tissue}_hu={hu}")
PARSEPY

    # Source the parsed values
    if [ -f /tmp/parsed_fiducials.txt ]; then
        while IFS='=' read -r key value; do
            case "$key" in
                air_found) AIR_FOUND="$value" ;;
                air_hu) AIR_HU="$value" ;;
                fat_found) FAT_FOUND="$value" ;;
                fat_hu) FAT_HU="$value" ;;
                liver_found) LIVER_FOUND="$value" ;;
                liver_hu) LIVER_HU="$value" ;;
                bone_found) BONE_FOUND="$value" ;;
                bone_hu) BONE_HU="$value" ;;
            esac
        done < /tmp/parsed_fiducials.txt
    fi
fi

# Check screenshot
SCREENSHOT_EXISTS="false"
SCREENSHOT_SIZE=0
if [ -f /tmp/task_final.png ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final.png 2>/dev/null || echo "0")
fi

# Copy sampled fiducials JSON for verifier
if [ -f "$FIDUCIALS_FILE" ]; then
    cp "$FIDUCIALS_FILE" /tmp/sampled_fiducials.json 2>/dev/null || true
    chmod 666 /tmp/sampled_fiducials.json 2>/dev/null || true
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "ct_file": "$CT_FILE",
    "case_id": "$CASE_ID",
    "fiducial_count": $FIDUCIAL_COUNT,
    "air_found": $AIR_FOUND,
    "air_hu": "$AIR_HU",
    "fat_found": $FAT_FOUND,
    "fat_hu": "$FAT_HU",
    "liver_found": $LIVER_FOUND,
    "liver_hu": "$LIVER_HU",
    "bone_found": $BONE_FOUND,
    "bone_hu": "$BONE_HU",
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_size": $SCREENSHOT_SIZE,
    "fiducials_file": "$FIDUCIALS_FILE"
}
EOF

# Move to final location
rm -f /tmp/ct_calibration_result.json 2>/dev/null || sudo rm -f /tmp/ct_calibration_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/ct_calibration_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/ct_calibration_result.json
chmod 666 /tmp/ct_calibration_result.json 2>/dev/null || sudo chmod 666 /tmp/ct_calibration_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Summary ==="
echo "Fiducials found: $FIDUCIAL_COUNT"
echo "Air sample: $AIR_FOUND (HU: $AIR_HU)"
echo "Fat sample: $FAT_FOUND (HU: $FAT_HU)"
echo "Liver sample: $LIVER_FOUND (HU: $LIVER_HU)"
echo "Bone sample: $BONE_FOUND (HU: $BONE_HU)"
echo ""
echo "Result saved to /tmp/ct_calibration_result.json"
cat /tmp/ct_calibration_result.json
echo ""
echo "=== Export Complete ==="