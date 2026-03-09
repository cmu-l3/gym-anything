#!/bin/bash
echo "=== Exporting Apply Color LUT Task Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    take_screenshot /tmp/task_final.png ga 2>/dev/null || true
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
fi

# Get initial state
INITIAL_COLORMAP=$(cat /tmp/initial_colormap.txt 2>/dev/null || echo "Grey")
echo "Initial colormap was: $INITIAL_COLORMAP"

# Query current colormap state from Slicer
echo "Querying current colormap state..."
cat > /tmp/get_final_colormap.py << 'PYEOF'
import slicer
import json

result = {
    "volume_loaded": False,
    "volume_name": "",
    "current_colormap": "",
    "display_node_exists": False,
    "color_node_id": "",
    "window_level": [0, 0],
    "color_node_type": ""
}

try:
    # Get all scalar volume nodes
    volume_nodes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
    
    if volume_nodes.GetNumberOfItems() > 0:
        result["volume_loaded"] = True
        volume_node = volume_nodes.GetItemAsObject(0)
        result["volume_name"] = volume_node.GetName()
        
        # Get display node
        display_node = volume_node.GetDisplayNode()
        if display_node:
            result["display_node_exists"] = True
            result["window_level"] = [display_node.GetWindow(), display_node.GetLevel()]
            
            # Get color node
            color_node = display_node.GetColorNode()
            if color_node:
                result["current_colormap"] = color_node.GetName()
                result["color_node_id"] = color_node.GetID()
                result["color_node_type"] = color_node.GetClassName()
    
    # Also check if Volumes module was accessed (check module history)
    module_logic = slicer.app.moduleManager()
    if module_logic:
        result["modules_available"] = True
    
    print(json.dumps(result))
    
except Exception as e:
    result["error"] = str(e)
    print(json.dumps(result))
PYEOF

FINAL_STATE=""
if [ "$SLICER_RUNNING" = "true" ]; then
    # Try to run Python script via Slicer
    FINAL_STATE=$(/opt/Slicer/bin/PythonSlicer /tmp/get_final_colormap.py 2>/dev/null || echo '{"error": "query_failed"}')
    echo "Final state from Slicer: $FINAL_STATE"
fi

# Parse final state
CURRENT_COLORMAP=""
VOLUME_LOADED="false"
DISPLAY_NODE_EXISTS="false"

if [ -n "$FINAL_STATE" ] && [ "$FINAL_STATE" != '{"error": "query_failed"}' ]; then
    CURRENT_COLORMAP=$(echo "$FINAL_STATE" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('current_colormap', ''))" 2>/dev/null || echo "")
    VOLUME_LOADED=$(echo "$FINAL_STATE" | python3 -c "import json,sys; d=json.load(sys.stdin); print('true' if d.get('volume_loaded', False) else 'false')" 2>/dev/null || echo "false")
    DISPLAY_NODE_EXISTS=$(echo "$FINAL_STATE" | python3 -c "import json,sys; d=json.load(sys.stdin); print('true' if d.get('display_node_exists', False) else 'false')" 2>/dev/null || echo "false")
fi

echo "Current colormap: $CURRENT_COLORMAP"

# Check if colormap changed
COLORMAP_CHANGED="false"
if [ -n "$CURRENT_COLORMAP" ] && [ "$CURRENT_COLORMAP" != "$INITIAL_COLORMAP" ]; then
    COLORMAP_CHANGED="true"
fi

# Check if it's a grayscale colormap
IS_GRAYSCALE="true"
GRAYSCALE_NAMES="Grey Gray Grayscale Greyscale White Black"
if [ -n "$CURRENT_COLORMAP" ]; then
    IS_GRAYSCALE="false"
    for gs_name in $GRAYSCALE_NAMES; do
        if [ "$CURRENT_COLORMAP" = "$gs_name" ]; then
            IS_GRAYSCALE="true"
            break
        fi
    done
fi

# Known color LUT names for validation
VALID_COLOR="false"
COLOR_LUTS="Ocean Cool Warm Hot Cold Rainbow fMRI fMRIPA Spectrum Red Green Blue Yellow Cyan Magenta PET-Heat PET-Rainbow Labels FreeSurfer"
if [ -n "$CURRENT_COLORMAP" ]; then
    for lut_name in $COLOR_LUTS; do
        if echo "$CURRENT_COLORMAP" | grep -qi "$lut_name"; then
            VALID_COLOR="true"
            break
        fi
    done
    # If not grayscale and not explicitly matched, still might be valid color
    if [ "$IS_GRAYSCALE" = "false" ] && [ "$COLORMAP_CHANGED" = "true" ]; then
        VALID_COLOR="true"
    fi
fi

# Screenshot analysis - check if final screenshot has color content
SCREENSHOT_HAS_COLOR="false"
if [ -f /tmp/task_final.png ]; then
    # Use Python/PIL to analyze color content
    COLOR_ANALYSIS=$(python3 << 'PYEOF'
import json
try:
    from PIL import Image
    import colorsys
    
    img = Image.open("/tmp/task_final.png")
    img_rgb = img.convert("RGB")
    
    # Sample pixels from center region (where brain would be)
    w, h = img_rgb.size
    center_x, center_y = w // 2, h // 2
    sample_region = 100
    
    colored_pixels = 0
    total_sampled = 0
    
    for x in range(center_x - sample_region, center_x + sample_region, 10):
        for y in range(center_y - sample_region, center_y + sample_region, 10):
            if 0 <= x < w and 0 <= y < h:
                r, g, b = img_rgb.getpixel((x, y))
                total_sampled += 1
                
                # Check if pixel has significant color (not grayscale)
                # Grayscale: R ≈ G ≈ B
                max_diff = max(abs(r-g), abs(g-b), abs(r-b))
                if max_diff > 30:  # Significant color difference
                    colored_pixels += 1
    
    color_ratio = colored_pixels / total_sampled if total_sampled > 0 else 0
    has_color = color_ratio > 0.1  # At least 10% of sampled pixels have color
    
    print(json.dumps({
        "has_color": has_color,
        "color_ratio": color_ratio,
        "colored_pixels": colored_pixels,
        "total_sampled": total_sampled
    }))
except Exception as e:
    print(json.dumps({"error": str(e), "has_color": False}))
PYEOF
2>/dev/null || echo '{"has_color": false}')
    
    SCREENSHOT_HAS_COLOR=$(echo "$COLOR_ANALYSIS" | python3 -c "import json,sys; d=json.load(sys.stdin); print('true' if d.get('has_color', False) else 'false')" 2>/dev/null || echo "false")
    echo "Screenshot color analysis: $COLOR_ANALYSIS"
fi

# Check screenshot file info
SCREENSHOT_EXISTS="false"
SCREENSHOT_SIZE_KB=0
if [ -f /tmp/task_final.png ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE_KB=$(du -k /tmp/task_final.png 2>/dev/null | cut -f1 || echo "0")
fi

# Close Slicer
echo "Closing 3D Slicer..."
close_slicer 2>/dev/null || pkill -f "Slicer" 2>/dev/null || true

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "volume_loaded": $VOLUME_LOADED,
    "display_node_exists": $DISPLAY_NODE_EXISTS,
    "initial_colormap": "$INITIAL_COLORMAP",
    "current_colormap": "$CURRENT_COLORMAP",
    "colormap_changed": $COLORMAP_CHANGED,
    "is_grayscale": $IS_GRAYSCALE,
    "valid_color_lut": $VALID_COLOR,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_size_kb": $SCREENSHOT_SIZE_KB,
    "screenshot_has_color": $SCREENSHOT_HAS_COLOR,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location with permission handling
rm -f /tmp/color_lut_task_result.json 2>/dev/null || sudo rm -f /tmp/color_lut_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/color_lut_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/color_lut_task_result.json
chmod 666 /tmp/color_lut_task_result.json 2>/dev/null || sudo chmod 666 /tmp/color_lut_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result ==="
cat /tmp/color_lut_task_result.json
echo ""
echo "=== Export Complete ==="