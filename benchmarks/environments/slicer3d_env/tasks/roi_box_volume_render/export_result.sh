#!/bin/bash
echo "=== Exporting ROI Box Volume Rendering Result ==="

source /workspace/scripts/task_utils.sh

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
EXPORTS_DIR="/home/ga/Documents/SlicerData/Exports"
OUTPUT_SCREENSHOT="$EXPORTS_DIR/roi_kidney_render.png"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot of Slicer state
echo "Capturing final screenshot..."
take_screenshot /tmp/roi_task_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    echo "Slicer is running"
fi

# Create export script to query Slicer state
EXPORT_SCRIPT="/tmp/export_roi_state.py"
cat > "$EXPORT_SCRIPT" << 'PYEOF'
import slicer
import json
import os
import math

result = {
    "roi_nodes": [],
    "volume_rendering_nodes": [],
    "roi_cropping_enabled": False,
    "roi_linked_to_vr": False,
    "linked_roi_info": None
}

# Find all ROI nodes
roi_class = "vtkMRMLMarkupsROINode"
roi_nodes = slicer.mrmlScene.GetNodesByClass(roi_class)
roi_nodes.UnRegister(None)

print(f"Found {roi_nodes.GetNumberOfItems()} ROI node(s)")

for i in range(roi_nodes.GetNumberOfItems()):
    node = roi_nodes.GetItemAsObject(i)
    
    # Get center
    center = [0.0, 0.0, 0.0]
    node.GetCenter(center)
    
    # Get size (radius in each direction)
    size = [0.0, 0.0, 0.0]
    node.GetSize(size)
    
    roi_info = {
        "name": node.GetName(),
        "id": node.GetID(),
        "center_ras": center,
        "size_mm": size,
        "visible": node.GetDisplayVisibility()
    }
    result["roi_nodes"].append(roi_info)
    print(f"  ROI '{node.GetName()}': center={center}, size={size}")

# Find volume rendering display nodes
vr_class = "vtkMRMLVolumeRenderingDisplayNode"
vr_nodes = slicer.mrmlScene.GetNodesByClass(vr_class)
vr_nodes.UnRegister(None)

print(f"Found {vr_nodes.GetNumberOfItems()} volume rendering node(s)")

for i in range(vr_nodes.GetNumberOfItems()):
    node = vr_nodes.GetItemAsObject(i)
    
    # Check if ROI is linked
    roi_node = node.GetROINode() if hasattr(node, 'GetROINode') else None
    cropping_enabled = node.GetCroppingEnabled() if hasattr(node, 'GetCroppingEnabled') else False
    
    vr_info = {
        "name": node.GetName(),
        "id": node.GetID(),
        "visible": node.GetVisibility(),
        "cropping_enabled": cropping_enabled,
        "roi_linked": roi_node is not None,
        "linked_roi_id": roi_node.GetID() if roi_node else None,
        "linked_roi_name": roi_node.GetName() if roi_node else None
    }
    result["volume_rendering_nodes"].append(vr_info)
    print(f"  VR '{node.GetName()}': visible={node.GetVisibility()}, cropping={cropping_enabled}")
    
    if cropping_enabled and roi_node:
        result["roi_cropping_enabled"] = True
        result["roi_linked_to_vr"] = True
        
        # Get the linked ROI details
        center = [0.0, 0.0, 0.0]
        roi_node.GetCenter(center)
        size = [0.0, 0.0, 0.0]
        roi_node.GetSize(size)
        
        result["linked_roi_info"] = {
            "name": roi_node.GetName(),
            "id": roi_node.GetID(),
            "center_ras": center,
            "size_mm": size
        }
        print(f"  Linked ROI: center={center}, size={size}")

# Check for volumes loaded
vol_nodes = slicer.mrmlScene.GetNodesByClass("vtkMRMLScalarVolumeNode")
vol_nodes.UnRegister(None)
result["volumes_loaded"] = vol_nodes.GetNumberOfItems()

# Save result
output_path = "/tmp/roi_slicer_state.json"
with open(output_path, "w") as f:
    json.dump(result, f, indent=2)

print(f"\nState exported to {output_path}")
PYEOF

chmod 644 "$EXPORT_SCRIPT"

# Run export script in Slicer
if [ "$SLICER_RUNNING" = "true" ]; then
    echo "Querying Slicer state..."
    
    # Use Slicer's Python to run the script
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --no-splash --python-script "$EXPORT_SCRIPT" > /tmp/slicer_export.log 2>&1 &
    EXPORT_PID=$!
    
    # Wait for export with timeout
    for i in $(seq 1 20); do
        if [ -f /tmp/roi_slicer_state.json ]; then
            echo "Slicer state exported"
            break
        fi
        sleep 1
    done
    
    kill $EXPORT_PID 2>/dev/null || true
fi

# Parse Slicer state
ROI_EXISTS="false"
ROI_COUNT=0
ROI_CENTER_R=""
ROI_CENTER_A=""
ROI_CENTER_S=""
ROI_SIZE_X=""
ROI_SIZE_Y=""
ROI_SIZE_Z=""
VR_ACTIVE="false"
ROI_CROPPING_ENABLED="false"
ROI_LINKED="false"

if [ -f /tmp/roi_slicer_state.json ]; then
    echo "Parsing Slicer state..."
    
    ROI_COUNT=$(python3 -c "import json; d=json.load(open('/tmp/roi_slicer_state.json')); print(len(d.get('roi_nodes', [])))" 2>/dev/null || echo "0")
    
    if [ "$ROI_COUNT" -gt 0 ]; then
        ROI_EXISTS="true"
        
        # Get first ROI's properties (or linked ROI if available)
        python3 << 'PYEOF'
import json
import os

with open('/tmp/roi_slicer_state.json') as f:
    data = json.load(f)

# Prefer linked ROI info if available
roi_info = data.get('linked_roi_info')
if not roi_info and data.get('roi_nodes'):
    roi_info = data['roi_nodes'][0]

if roi_info:
    center = roi_info.get('center_ras', [0, 0, 0])
    size = roi_info.get('size_mm', [0, 0, 0])
    
    # Write to temp files for bash to read
    with open('/tmp/roi_center_r', 'w') as f: f.write(str(center[0]))
    with open('/tmp/roi_center_a', 'w') as f: f.write(str(center[1]))
    with open('/tmp/roi_center_s', 'w') as f: f.write(str(center[2]))
    with open('/tmp/roi_size_x', 'w') as f: f.write(str(size[0]))
    with open('/tmp/roi_size_y', 'w') as f: f.write(str(size[1]))
    with open('/tmp/roi_size_z', 'w') as f: f.write(str(size[2]))

# VR and cropping status
with open('/tmp/vr_active', 'w') as f:
    vr_nodes = data.get('volume_rendering_nodes', [])
    active = any(v.get('visible', False) for v in vr_nodes)
    f.write('true' if active else 'false')

with open('/tmp/roi_cropping', 'w') as f:
    f.write('true' if data.get('roi_cropping_enabled', False) else 'false')

with open('/tmp/roi_linked', 'w') as f:
    f.write('true' if data.get('roi_linked_to_vr', False) else 'false')
PYEOF
        
        ROI_CENTER_R=$(cat /tmp/roi_center_r 2>/dev/null || echo "0")
        ROI_CENTER_A=$(cat /tmp/roi_center_a 2>/dev/null || echo "0")
        ROI_CENTER_S=$(cat /tmp/roi_center_s 2>/dev/null || echo "0")
        ROI_SIZE_X=$(cat /tmp/roi_size_x 2>/dev/null || echo "0")
        ROI_SIZE_Y=$(cat /tmp/roi_size_y 2>/dev/null || echo "0")
        ROI_SIZE_Z=$(cat /tmp/roi_size_z 2>/dev/null || echo "0")
    fi
    
    VR_ACTIVE=$(cat /tmp/vr_active 2>/dev/null || echo "false")
    ROI_CROPPING_ENABLED=$(cat /tmp/roi_cropping 2>/dev/null || echo "false")
    ROI_LINKED=$(cat /tmp/roi_linked 2>/dev/null || echo "false")
fi

# Check output screenshot
SCREENSHOT_EXISTS="false"
SCREENSHOT_SIZE_KB=0
SCREENSHOT_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_SCREENSHOT" ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE_KB=$(du -k "$OUTPUT_SCREENSHOT" 2>/dev/null | cut -f1 || echo "0")
    
    # Check if created during task
    SCREENSHOT_MTIME=$(stat -c %Y "$OUTPUT_SCREENSHOT" 2>/dev/null || echo "0")
    if [ "$SCREENSHOT_MTIME" -gt "$TASK_START" ]; then
        SCREENSHOT_CREATED_DURING_TASK="true"
    fi
    
    # Copy for verification
    cp "$OUTPUT_SCREENSHOT" /tmp/roi_user_screenshot.png 2>/dev/null || true
    echo "User screenshot found: ${SCREENSHOT_SIZE_KB}KB"
fi

# Also check final screenshot
FINAL_SCREENSHOT_SIZE_KB=0
if [ -f /tmp/roi_task_final.png ]; then
    FINAL_SCREENSHOT_SIZE_KB=$(du -k /tmp/roi_task_final.png 2>/dev/null | cut -f1 || echo "0")
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "roi_exists": $ROI_EXISTS,
    "roi_count": $ROI_COUNT,
    "roi_center_r": $ROI_CENTER_R,
    "roi_center_a": $ROI_CENTER_A,
    "roi_center_s": $ROI_CENTER_S,
    "roi_size_x": $ROI_SIZE_X,
    "roi_size_y": $ROI_SIZE_Y,
    "roi_size_z": $ROI_SIZE_Z,
    "volume_rendering_active": $VR_ACTIVE,
    "roi_cropping_enabled": $ROI_CROPPING_ENABLED,
    "roi_linked_to_vr": $ROI_LINKED,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_size_kb": $SCREENSHOT_SIZE_KB,
    "screenshot_created_during_task": $SCREENSHOT_CREATED_DURING_TASK,
    "final_screenshot_size_kb": $FINAL_SCREENSHOT_SIZE_KB,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location with permission handling
rm -f /tmp/roi_task_result.json 2>/dev/null || sudo rm -f /tmp/roi_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/roi_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/roi_task_result.json
chmod 666 /tmp/roi_task_result.json 2>/dev/null || sudo chmod 666 /tmp/roi_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result saved to /tmp/roi_task_result.json"
cat /tmp/roi_task_result.json
echo ""
echo "=== Export Complete ==="