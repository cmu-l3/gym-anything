#!/bin/bash
echo "=== Exporting Slice Annotation Configuration Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot FIRST (captures current state)
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

SCREENSHOT_EXISTS="false"
SCREENSHOT_SIZE=0
if [ -f /tmp/task_final.png ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SCREENSHOT_SIZE} bytes"
fi

# Check if Slicer is running
SLICER_RUNNING="false"
SLICER_PID=""
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
    SLICER_PID=$(pgrep -f "Slicer" | head -1)
    echo "Slicer is running (PID: $SLICER_PID)"
fi

# Export annotation settings from Slicer
echo "Querying Slicer annotation settings..."
cat > /tmp/export_annotations.py << 'PYEOF'
import slicer
import json
import os

result = {
    "slicer_running": True,
    "data_loaded": False,
    "volume_count": 0,
    
    # Per-view settings
    "red_orientation_enabled": False,
    "yellow_orientation_enabled": False,
    "green_orientation_enabled": False,
    
    "red_orientation_type": 0,
    "yellow_orientation_type": 0,
    "green_orientation_type": 0,
    
    # Global DICOM annotation settings
    "dicom_annotations_visible": True,
    "corner_annotations_visible": False,
    
    # Detailed corner annotation settings
    "top_left_annotation": "",
    "top_right_annotation": "",
    "bottom_left_annotation": "",
    "bottom_right_annotation": "",
    
    # View settings
    "views_queried": [],
    "errors": []
}

try:
    # Check loaded volumes
    volume_nodes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
    if volume_nodes:
        result["volume_count"] = volume_nodes.GetNumberOfItems()
        result["data_loaded"] = volume_nodes.GetNumberOfItems() > 0

    # Get layout manager
    layoutManager = slicer.app.layoutManager()
    
    # Query each slice view
    for viewName in ['Red', 'Yellow', 'Green']:
        try:
            sliceWidget = layoutManager.sliceWidget(viewName)
            if not sliceWidget:
                result["errors"].append(f"{viewName} widget not found")
                continue
                
            result["views_queried"].append(viewName)
            
            sliceNode = sliceWidget.mrmlSliceNode()
            sliceView = sliceWidget.sliceView()
            
            # Get orientation marker settings
            # OrientationMarkerType: 0=None, 1=Cube, 2=Human, 3=Axes
            if hasattr(sliceNode, 'GetOrientationMarkerType'):
                ort_type = sliceNode.GetOrientationMarkerType()
                result[f"{viewName.lower()}_orientation_type"] = ort_type
                result[f"{viewName.lower()}_orientation_enabled"] = ort_type > 0
            
            # Check for orientation marker visibility through the view
            if hasattr(sliceNode, 'GetOrientationMarkerEnabled'):
                result[f"{viewName.lower()}_orientation_enabled"] = sliceNode.GetOrientationMarkerEnabled()
            
            # Get slice annotation display node
            # This controls DICOM overlay info (patient name, date, etc.)
            sliceCompositeNode = sliceWidget.mrmlSliceCompositeNode()
            if sliceCompositeNode:
                # Check for annotation visibility settings
                if hasattr(sliceCompositeNode, 'GetSliceIntersectionVisibility'):
                    pass  # Different setting
                    
        except Exception as e:
            result["errors"].append(f"{viewName}: {str(e)}")
    
    # Query application-level annotation settings
    try:
        # Access view controller widgets for annotation settings
        for viewName in ['Red', 'Yellow', 'Green']:
            sliceWidget = layoutManager.sliceWidget(viewName)
            if sliceWidget:
                controller = sliceWidget.sliceController()
                if controller:
                    # Controller has various display options
                    pass
    except Exception as e:
        result["errors"].append(f"Controller query: {str(e)}")
    
    # Check DataProbe settings (shows pixel values and DICOM info)
    try:
        # DataProbe module handles the info display
        dataProbeLogic = slicer.modules.dataprobe.logic() if hasattr(slicer.modules, 'dataprobe') else None
        if dataProbeLogic:
            result["data_probe_available"] = True
    except Exception:
        result["data_probe_available"] = False
    
    # Get annotation visibility from view nodes
    try:
        for viewName in ['Red', 'Yellow', 'Green']:
            sliceWidget = layoutManager.sliceWidget(viewName)
            if sliceWidget:
                sliceNode = sliceWidget.mrmlSliceNode()
                
                # Check ruler/scale visibility
                if hasattr(sliceNode, 'GetRulerType'):
                    result[f"{viewName.lower()}_ruler_type"] = sliceNode.GetRulerType()
                
                # Check orientation marker size
                if hasattr(sliceNode, 'GetOrientationMarkerSize'):
                    result[f"{viewName.lower()}_orientation_size"] = sliceNode.GetOrientationMarkerSize()
                    
    except Exception as e:
        result["errors"].append(f"View node query: {str(e)}")

    # Summarize orientation marker status
    result["all_orientation_enabled"] = (
        result.get("red_orientation_enabled", False) and
        result.get("yellow_orientation_enabled", False) and
        result.get("green_orientation_enabled", False)
    )
    
    result["any_orientation_enabled"] = (
        result.get("red_orientation_enabled", False) or
        result.get("yellow_orientation_enabled", False) or
        result.get("green_orientation_enabled", False)
    )

except Exception as e:
    result["errors"].append(f"Main error: {str(e)}")
    import traceback
    result["traceback"] = traceback.format_exc()

# Save result
output_path = "/tmp/slicer_annotation_query.json"
with open(output_path, "w") as f:
    json.dump(result, f, indent=2)

print("Annotation query result:")
print(json.dumps(result, indent=2))
PYEOF

# Run the query in Slicer (headless mode with existing scene)
if [ "$SLICER_RUNNING" = "true" ]; then
    # Try to run Python in existing Slicer instance
    su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer --no-main-window --python-script /tmp/export_annotations.py" > /tmp/slicer_query.log 2>&1 &
    QUERY_PID=$!
    sleep 10
    kill $QUERY_PID 2>/dev/null || true
fi

# Read query results
SLICER_QUERY_RESULT=""
if [ -f /tmp/slicer_annotation_query.json ]; then
    SLICER_QUERY_RESULT=$(cat /tmp/slicer_annotation_query.json)
    echo "Slicer annotation query completed"
fi

# Parse query results for key values
RED_ORIENTATION="false"
YELLOW_ORIENTATION="false"
GREEN_ORIENTATION="false"
ALL_ORIENTATION="false"
ANY_ORIENTATION="false"
DATA_LOADED="false"

if [ -f /tmp/slicer_annotation_query.json ]; then
    RED_ORIENTATION=$(python3 -c "import json; print(str(json.load(open('/tmp/slicer_annotation_query.json')).get('red_orientation_enabled', False)).lower())" 2>/dev/null || echo "false")
    YELLOW_ORIENTATION=$(python3 -c "import json; print(str(json.load(open('/tmp/slicer_annotation_query.json')).get('yellow_orientation_enabled', False)).lower())" 2>/dev/null || echo "false")
    GREEN_ORIENTATION=$(python3 -c "import json; print(str(json.load(open('/tmp/slicer_annotation_query.json')).get('green_orientation_enabled', False)).lower())" 2>/dev/null || echo "false")
    ALL_ORIENTATION=$(python3 -c "import json; print(str(json.load(open('/tmp/slicer_annotation_query.json')).get('all_orientation_enabled', False)).lower())" 2>/dev/null || echo "false")
    ANY_ORIENTATION=$(python3 -c "import json; print(str(json.load(open('/tmp/slicer_annotation_query.json')).get('any_orientation_enabled', False)).lower())" 2>/dev/null || echo "false")
    DATA_LOADED=$(python3 -c "import json; print(str(json.load(open('/tmp/slicer_annotation_query.json')).get('data_loaded', False)).lower())" 2>/dev/null || echo "false")
fi

# Get initial state for comparison
INITIAL_ANY_ORIENTATION="false"
if [ -f /tmp/initial_annotation_state.json ]; then
    INITIAL_ANY_ORIENTATION=$(python3 -c "
import json
data = json.load(open('/tmp/initial_annotation_state.json'))
any_enabled = data.get('red_orientation_visible', False) or data.get('yellow_orientation_visible', False) or data.get('green_orientation_visible', False)
print(str(any_enabled).lower())
" 2>/dev/null || echo "false")
fi

# Determine if settings were changed
SETTINGS_CHANGED="false"
if [ "$ANY_ORIENTATION" = "true" ] && [ "$INITIAL_ANY_ORIENTATION" = "false" ]; then
    SETTINGS_CHANGED="true"
elif [ "$ANY_ORIENTATION" != "$INITIAL_ANY_ORIENTATION" ]; then
    SETTINGS_CHANGED="true"
fi

# Create final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "data_loaded": $DATA_LOADED,
    
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_size_bytes": $SCREENSHOT_SIZE,
    
    "red_orientation_enabled": $RED_ORIENTATION,
    "yellow_orientation_enabled": $YELLOW_ORIENTATION,
    "green_orientation_enabled": $GREEN_ORIENTATION,
    "all_orientation_enabled": $ALL_ORIENTATION,
    "any_orientation_enabled": $ANY_ORIENTATION,
    
    "settings_changed": $SETTINGS_CHANGED,
    "initial_any_orientation": $INITIAL_ANY_ORIENTATION,
    
    "screenshot_path": "/tmp/task_final.png",
    "initial_screenshot_path": "/tmp/task_initial.png",
    "slicer_query_path": "/tmp/slicer_annotation_query.json"
}
EOF

# Move to final location
rm -f /tmp/slice_annotations_result.json 2>/dev/null || sudo rm -f /tmp/slice_annotations_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/slice_annotations_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/slice_annotations_result.json
chmod 666 /tmp/slice_annotations_result.json 2>/dev/null || sudo chmod 666 /tmp/slice_annotations_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Complete ==="
echo "Result saved to /tmp/slice_annotations_result.json"
cat /tmp/slice_annotations_result.json