#!/bin/bash
echo "=== Exporting Surgical Planning View Configuration Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot first
echo "Capturing final screenshot..."
take_screenshot /tmp/surgical_view_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
fi

# Create Python script to export segment properties
cat > /tmp/export_segment_props.py << 'PYEOF'
import slicer
import json
import os

output = {
    "segments": {},
    "segmentation_found": False,
    "display_node_found": False,
    "segment_count": 0
}

# Find segmentation node
segmentationNodes = slicer.util.getNodesByClass("vtkMRMLSegmentationNode")
print(f"Found {len(segmentationNodes)} segmentation node(s)")

if segmentationNodes:
    segmentationNode = segmentationNodes[0]
    output["segmentation_found"] = True
    
    displayNode = segmentationNode.GetDisplayNode()
    if displayNode:
        output["display_node_found"] = True
        
        segmentation = segmentationNode.GetSegmentation()
        output["segment_count"] = segmentation.GetNumberOfSegments()
        
        for i in range(segmentation.GetNumberOfSegments()):
            segment_id = segmentation.GetNthSegmentID(i)
            segment = segmentation.GetSegment(segment_id)
            name = segment.GetName()
            
            color = segment.GetColor()
            opacity_3d = displayNode.GetSegmentOpacity3D(segment_id)
            opacity_2d = displayNode.GetSegmentOpacity2DFill(segment_id)
            visible = displayNode.GetSegmentVisibility(segment_id)
            visible_3d = displayNode.GetSegmentVisibility3D(segment_id)
            
            # Convert color from 0-1 to 0-255 for easier verification
            output["segments"][name] = {
                "segment_id": segment_id,
                "color_r_float": color[0],
                "color_g_float": color[1],
                "color_b_float": color[2],
                "color_r_255": int(color[0] * 255),
                "color_g_255": int(color[1] * 255),
                "color_b_255": int(color[2] * 255),
                "opacity_3d": opacity_3d,
                "opacity_2d": opacity_2d,
                "visible": visible,
                "visible_3d": visible_3d
            }
            
            print(f"Segment '{name}':")
            print(f"  Color RGB(255): ({int(color[0]*255)}, {int(color[1]*255)}, {int(color[2]*255)})")
            print(f"  Opacity 3D: {opacity_3d:.2f}")
            print(f"  Visible: {visible}, Visible3D: {visible_3d}")

# Check 3D view state
layoutManager = slicer.app.layoutManager()
if layoutManager:
    threeDWidget = layoutManager.threeDWidget(0)
    if threeDWidget:
        output["3d_view_visible"] = threeDWidget.isVisible()

# Save to file
output_path = "/tmp/segment_properties.json"
with open(output_path, "w") as f:
    json.dump(output, f, indent=2)

print(f"\nExported segment properties to {output_path}")
PYEOF

# Run export script in Slicer
if [ "$SLICER_RUNNING" = "true" ]; then
    echo "Exporting segment properties from Slicer..."
    
    # Use Slicer's Python to export
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --no-splash --no-main-window \
        --python-code "exec(open('/tmp/export_segment_props.py').read())" \
        > /tmp/slicer_export.log 2>&1 &
    
    EXPORT_PID=$!
    
    # Wait with timeout
    for i in {1..30}; do
        if [ -f /tmp/segment_properties.json ]; then
            echo "Segment properties exported successfully"
            break
        fi
        if ! kill -0 $EXPORT_PID 2>/dev/null; then
            break
        fi
        sleep 1
    done
    
    kill $EXPORT_PID 2>/dev/null || true
fi

# Load exported segment properties
SEGMENT_PROPS="{}"
if [ -f /tmp/segment_properties.json ]; then
    SEGMENT_PROPS=$(cat /tmp/segment_properties.json)
fi

# Load initial properties for comparison
INITIAL_PROPS="{}"
if [ -f /tmp/initial_segment_properties.json ]; then
    INITIAL_PROPS=$(cat /tmp/initial_segment_properties.json)
fi

# Check for property changes (anti-gaming)
PROPERTIES_CHANGED="false"
if [ -f /tmp/segment_properties.json ] && [ -f /tmp/initial_segment_properties.json ]; then
    PROPERTIES_CHANGED=$(python3 << 'PYEOF'
import json

try:
    with open("/tmp/initial_segment_properties.json") as f:
        initial = json.load(f)
    with open("/tmp/segment_properties.json") as f:
        final = json.load(f)
    
    changes = 0
    for name, props in final.get("segments", {}).items():
        if name in initial:
            init = initial[name]
            # Check for color changes (tolerance of 0.05 in float values)
            if abs(props.get("color_r_float", 0) - init.get("color_r", 0)) > 0.05:
                changes += 1
            if abs(props.get("color_g_float", 0) - init.get("color_g", 0)) > 0.05:
                changes += 1
            if abs(props.get("color_b_float", 0) - init.get("color_b", 0)) > 0.05:
                changes += 1
            # Check for opacity changes
            if abs(props.get("opacity_3d", 0) - init.get("opacity_3d", 0)) > 0.05:
                changes += 1
    
    print("true" if changes >= 3 else "false")
except Exception as e:
    print("false")
PYEOF
)
fi

# Check screenshot file info
SCREENSHOT_EXISTS="false"
SCREENSHOT_SIZE_KB=0
if [ -f /tmp/surgical_view_final.png ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE_KB=$(du -k /tmp/surgical_view_final.png 2>/dev/null | cut -f1 || echo "0")
fi

# Create comprehensive result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "properties_changed": $PROPERTIES_CHANGED,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_size_kb": $SCREENSHOT_SIZE_KB,
    "segment_data": $SEGMENT_PROPS,
    "initial_properties": $INITIAL_PROPS,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Validate JSON
python3 -c "import json; json.load(open('$TEMP_JSON'))" 2>/dev/null || {
    echo "WARNING: Generated invalid JSON, creating minimal result"
    cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "properties_changed": $PROPERTIES_CHANGED,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "error": "Failed to export segment properties"
}
EOF
}

# Move to final location
rm -f /tmp/surgical_view_result.json 2>/dev/null || sudo rm -f /tmp/surgical_view_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/surgical_view_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/surgical_view_result.json
chmod 666 /tmp/surgical_view_result.json 2>/dev/null || sudo chmod 666 /tmp/surgical_view_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result saved to /tmp/surgical_view_result.json"
cat /tmp/surgical_view_result.json
echo ""
echo "=== Export Complete ==="