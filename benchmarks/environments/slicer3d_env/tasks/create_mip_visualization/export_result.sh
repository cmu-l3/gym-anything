#!/bin/bash
echo "=== Exporting MIP Visualization Task Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Define paths
EXPORT_DIR="/home/ga/Documents/SlicerData/Exports"
OUTPUT_FILE="$EXPORT_DIR/chest_mip_coronal.png"

# Take final screenshot of Slicer state
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true
sleep 1

# ================================================================
# CHECK OUTPUT FILE
# ================================================================
OUTPUT_EXISTS="false"
OUTPUT_SIZE_BYTES="0"
OUTPUT_MTIME="0"
FILE_CREATED_DURING_TASK="false"
FILE_MODIFIED_DURING_TASK="false"

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE_BYTES=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    # Check if file was created/modified during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
        FILE_MODIFIED_DURING_TASK="true"
    fi
    
    echo "Output file found: $OUTPUT_FILE"
    echo "  Size: $OUTPUT_SIZE_BYTES bytes"
    echo "  Modified: $(date -d @$OUTPUT_MTIME)"
else
    echo "Output file NOT found: $OUTPUT_FILE"
fi

# Also search for any PNG files in export directory created during task
ALTERNATIVE_OUTPUTS=""
if [ -d "$EXPORT_DIR" ]; then
    for f in "$EXPORT_DIR"/*.png; do
        if [ -f "$f" ] && [ "$f" != "$OUTPUT_FILE" ]; then
            fmtime=$(stat -c %Y "$f" 2>/dev/null || echo "0")
            if [ "$fmtime" -gt "$TASK_START" ]; then
                ALTERNATIVE_OUTPUTS="$ALTERNATIVE_OUTPUTS $f"
                echo "Found alternative output: $f"
            fi
        fi
    done
fi

# ================================================================
# GET IMAGE PROPERTIES (if output exists)
# ================================================================
IMAGE_WIDTH="0"
IMAGE_HEIGHT="0"
IMAGE_FORMAT="unknown"
IMAGE_COLORS="0"

if [ "$OUTPUT_EXISTS" = "true" ]; then
    python3 << PYEOF
import json
import sys

try:
    from PIL import Image
    img = Image.open("$OUTPUT_FILE")
    
    # Count unique colors (sample for large images)
    if img.width * img.height > 100000:
        img_small = img.resize((200, 200))
        colors = len(set(img_small.getdata()))
    else:
        colors = len(set(img.getdata()))
    
    result = {
        "width": img.width,
        "height": img.height,
        "format": img.format or "unknown",
        "mode": img.mode,
        "colors": colors
    }
    print(json.dumps(result))
    img.close()
except Exception as e:
    print(json.dumps({"error": str(e), "width": 0, "height": 0, "format": "error", "colors": 0}))
PYEOF
    
    IMAGE_PROPS=$(python3 << 'PYPROP'
import json
try:
    from PIL import Image
    img = Image.open("/home/ga/Documents/SlicerData/Exports/chest_mip_coronal.png")
    if img.width * img.height > 100000:
        img_small = img.resize((200, 200))
        colors = len(set(img_small.getdata()))
    else:
        colors = len(set(img.getdata()))
    print(json.dumps({"width": img.width, "height": img.height, "format": img.format or "PNG", "colors": colors}))
    img.close()
except Exception as e:
    print(json.dumps({"width": 0, "height": 0, "format": "error", "colors": 0, "error": str(e)}))
PYPROP
)
    
    IMAGE_WIDTH=$(echo "$IMAGE_PROPS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('width', 0))" 2>/dev/null || echo "0")
    IMAGE_HEIGHT=$(echo "$IMAGE_PROPS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('height', 0))" 2>/dev/null || echo "0")
    IMAGE_FORMAT=$(echo "$IMAGE_PROPS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('format', 'unknown'))" 2>/dev/null || echo "unknown")
    IMAGE_COLORS=$(echo "$IMAGE_PROPS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('colors', 0))" 2>/dev/null || echo "0")
    
    echo "Image properties: ${IMAGE_WIDTH}x${IMAGE_HEIGHT}, format=$IMAGE_FORMAT, colors=$IMAGE_COLORS"
fi

# ================================================================
# CHECK SLICER STATE
# ================================================================
SLICER_RUNNING="false"
SLICER_WINDOW_TITLE=""
DATA_LOADED="false"

if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
    
    # Get window title
    SLICER_WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Slicer" | head -1 | cut -d' ' -f5- || echo "")
    
    # Check if CTChest is in window title (indicates data loaded)
    if echo "$SLICER_WINDOW_TITLE" | grep -qi "CTChest\|chest"; then
        DATA_LOADED="true"
    fi
fi

echo "Slicer running: $SLICER_RUNNING"
echo "Window title: $SLICER_WINDOW_TITLE"

# ================================================================
# TRY TO QUERY SLICER STATE VIA PYTHON
# ================================================================
SLAB_MODE_ACTIVE="unknown"
SLAB_TYPE="unknown"
SLAB_THICKNESS="0"
VOLUME_LOADED="false"

# Create a Python script to query Slicer state
cat > /tmp/query_slicer_state.py << 'PYEOF'
import json
import sys

try:
    import slicer
    
    result = {
        "volume_loaded": False,
        "volume_name": "",
        "slab_mode_active": False,
        "slab_type": "unknown",
        "slab_thickness_mm": 0,
        "coronal_view_active": False
    }
    
    # Check if any volume is loaded
    volumes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
    if volumes.GetNumberOfItems() > 0:
        result["volume_loaded"] = True
        vol = volumes.GetItemAsObject(0)
        result["volume_name"] = vol.GetName() if vol else ""
    
    # Check slice view composite nodes for slab settings
    layout_manager = slicer.app.layoutManager()
    if layout_manager:
        # Check coronal (green) slice view
        green_widget = layout_manager.sliceWidget("Green")
        if green_widget:
            result["coronal_view_active"] = True
            
            slice_logic = green_widget.sliceLogic()
            slice_node = slice_logic.GetSliceNode()
            composite_node = slice_logic.GetSliceCompositeNode()
            
            # Check slab mode
            if hasattr(slice_node, 'GetSlabMode'):
                slab_mode = slice_node.GetSlabMode()
                result["slab_mode_active"] = slab_mode > 0
                
            # Check slab type
            if hasattr(slice_node, 'GetSlabReconstructionType'):
                slab_type_id = slice_node.GetSlabReconstructionType()
                slab_types = {0: "Mean", 1: "Min", 2: "Max", 3: "Sum"}
                result["slab_type"] = slab_types.get(slab_type_id, f"Type{slab_type_id}")
            
            # Check slab thickness
            if hasattr(slice_node, 'GetSlabNumberOfSlices'):
                num_slices = slice_node.GetSlabNumberOfSlices()
                # Convert to mm using volume spacing
                if result["volume_loaded"] and volumes.GetNumberOfItems() > 0:
                    vol = volumes.GetItemAsObject(0)
                    spacing = vol.GetSpacing()
                    # Coronal view uses anterior-posterior spacing
                    result["slab_thickness_mm"] = num_slices * spacing[1]
    
    print(json.dumps(result))
    
except Exception as e:
    print(json.dumps({"error": str(e)}))
PYEOF

# Try to run query via Slicer's Python (if Slicer is running)
if [ "$SLICER_RUNNING" = "true" ]; then
    echo "Querying Slicer state..."
    
    # Run Python script in Slicer context
    SLICER_STATE=$(timeout 15 su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer --python-code \"
import json
try:
    import slicer
    result = {'volume_loaded': False, 'slab_mode_active': False, 'slab_type': 'unknown', 'slab_thickness_mm': 0}
    
    volumes = slicer.util.getNodesByClass('vtkMRMLScalarVolumeNode')
    if volumes.GetNumberOfItems() > 0:
        result['volume_loaded'] = True
    
    layout_manager = slicer.app.layoutManager()
    if layout_manager:
        green_widget = layout_manager.sliceWidget('Green')
        if green_widget:
            slice_node = green_widget.sliceLogic().GetSliceNode()
            if hasattr(slice_node, 'GetSlabMode'):
                result['slab_mode_active'] = slice_node.GetSlabMode() > 0
            if hasattr(slice_node, 'GetSlabReconstructionType'):
                types = {0: 'Mean', 1: 'Min', 2: 'Max', 3: 'Sum'}
                result['slab_type'] = types.get(slice_node.GetSlabReconstructionType(), 'unknown')
            if hasattr(slice_node, 'GetSlabNumberOfSlices') and result['volume_loaded']:
                vol = volumes.GetItemAsObject(0)
                spacing = vol.GetSpacing()
                result['slab_thickness_mm'] = slice_node.GetSlabNumberOfSlices() * spacing[1]
    
    print('SLICER_STATE:' + json.dumps(result))
except Exception as e:
    print('SLICER_STATE:' + json.dumps({'error': str(e)}))
\" --no-main-window --exit-after-startup 2>/dev/null | grep 'SLICER_STATE:' | sed 's/SLICER_STATE://'") 2>/dev/null || echo "{}")
    
    if [ -n "$SLICER_STATE" ] && echo "$SLICER_STATE" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
        VOLUME_LOADED=$(echo "$SLICER_STATE" | python3 -c "import json,sys; print('true' if json.load(sys.stdin).get('volume_loaded', False) else 'false')" 2>/dev/null || echo "false")
        SLAB_MODE_ACTIVE=$(echo "$SLICER_STATE" | python3 -c "import json,sys; print('true' if json.load(sys.stdin).get('slab_mode_active', False) else 'false')" 2>/dev/null || echo "unknown")
        SLAB_TYPE=$(echo "$SLICER_STATE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('slab_type', 'unknown'))" 2>/dev/null || echo "unknown")
        SLAB_THICKNESS=$(echo "$SLICER_STATE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('slab_thickness_mm', 0))" 2>/dev/null || echo "0")
        
        echo "Slicer state queried:"
        echo "  Volume loaded: $VOLUME_LOADED"
        echo "  Slab mode: $SLAB_MODE_ACTIVE"
        echo "  Slab type: $SLAB_TYPE"
        echo "  Slab thickness: $SLAB_THICKNESS mm"
    else
        echo "Could not parse Slicer state response"
    fi
fi

# ================================================================
# CREATE RESULT JSON
# ================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "output_size_bytes": $OUTPUT_SIZE_BYTES,
    "output_mtime": $OUTPUT_MTIME,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_modified_during_task": $FILE_MODIFIED_DURING_TASK,
    "image_width": $IMAGE_WIDTH,
    "image_height": $IMAGE_HEIGHT,
    "image_format": "$IMAGE_FORMAT",
    "image_colors": $IMAGE_COLORS,
    "slicer_was_running": $SLICER_RUNNING,
    "slicer_window_title": "$SLICER_WINDOW_TITLE",
    "data_loaded": $DATA_LOADED,
    "volume_loaded": $VOLUME_LOADED,
    "slab_mode_active": "$SLAB_MODE_ACTIVE",
    "slab_type": "$SLAB_TYPE",
    "slab_thickness_mm": $SLAB_THICKNESS,
    "alternative_outputs": "$ALTERNATIVE_OUTPUTS",
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location with permission handling
rm -f /tmp/mip_task_result.json 2>/dev/null || sudo rm -f /tmp/mip_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/mip_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/mip_task_result.json
chmod 666 /tmp/mip_task_result.json 2>/dev/null || sudo chmod 666 /tmp/mip_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result saved to /tmp/mip_task_result.json"
cat /tmp/mip_task_result.json
echo ""
echo "=== Export Complete ==="