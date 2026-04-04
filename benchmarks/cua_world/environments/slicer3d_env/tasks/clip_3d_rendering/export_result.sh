#!/bin/bash
echo "=== Exporting Clip 3D Rendering Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

SCREENSHOT_DIR="/home/ga/Documents/SlicerData/Screenshots"
OUTPUT_SCREENSHOT="$SCREENSHOT_DIR/clipped_brain_rendering.png"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot of Slicer state
echo "Capturing final state screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

if [ -f /tmp/task_final.png ]; then
    SIZE=$(stat -c%s /tmp/task_final.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: $SIZE bytes"
fi

# ============================================================
# Check for output screenshot
# ============================================================
SCREENSHOT_EXISTS="false"
SCREENSHOT_SIZE_BYTES=0
SCREENSHOT_MTIME=0
SCREENSHOT_CREATED_DURING_TASK="false"

# Also search for any new screenshots in common locations
SEARCH_PATHS=(
    "$OUTPUT_SCREENSHOT"
    "$SCREENSHOT_DIR/clipped*.png"
    "$SCREENSHOT_DIR/Screenshot*.png"
    "/home/ga/Desktop/*.png"
    "/home/ga/*.png"
)

FOUND_SCREENSHOT=""
for pattern in "${SEARCH_PATHS[@]}"; do
    for f in $pattern; do
        if [ -f "$f" ]; then
            mtime=$(stat -c%Y "$f" 2>/dev/null || echo "0")
            if [ "$mtime" -gt "$TASK_START" ]; then
                echo "Found screenshot created during task: $f"
                FOUND_SCREENSHOT="$f"
                break 2
            fi
        fi
    done
done

# Check expected output location
if [ -f "$OUTPUT_SCREENSHOT" ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE_BYTES=$(stat -c%s "$OUTPUT_SCREENSHOT" 2>/dev/null || echo "0")
    SCREENSHOT_MTIME=$(stat -c%Y "$OUTPUT_SCREENSHOT" 2>/dev/null || echo "0")
    
    if [ "$SCREENSHOT_MTIME" -gt "$TASK_START" ]; then
        SCREENSHOT_CREATED_DURING_TASK="true"
    fi
    
    echo "Output screenshot found: $OUTPUT_SCREENSHOT"
    echo "  Size: $SCREENSHOT_SIZE_BYTES bytes"
    echo "  Created during task: $SCREENSHOT_CREATED_DURING_TASK"
    
    # Copy to verification location
    cp "$OUTPUT_SCREENSHOT" /tmp/user_screenshot.png 2>/dev/null || true
elif [ -n "$FOUND_SCREENSHOT" ]; then
    # Use alternative screenshot if found
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE_BYTES=$(stat -c%s "$FOUND_SCREENSHOT" 2>/dev/null || echo "0")
    SCREENSHOT_MTIME=$(stat -c%Y "$FOUND_SCREENSHOT" 2>/dev/null || echo "0")
    SCREENSHOT_CREATED_DURING_TASK="true"
    
    cp "$FOUND_SCREENSHOT" /tmp/user_screenshot.png 2>/dev/null || true
    echo "Using alternative screenshot: $FOUND_SCREENSHOT"
fi

# ============================================================
# Query Slicer state via Python
# ============================================================
echo "Querying Slicer state..."

SLICER_STATE_JSON='{}'

if pgrep -f "Slicer" > /dev/null 2>&1; then
    echo "Slicer is running, querying scene state..."
    
    cat > /tmp/query_slicer_state.py << 'PYEOF'
import slicer
import json
import os
import math

result = {
    "volume_count": 0,
    "volume_name": "",
    "volume_rendering_active": False,
    "vr_display_count": 0,
    "roi_count": 0,
    "roi_node_name": "",
    "clipping_enabled": False,
    "roi_bounds": None,
    "volume_bounds": None,
    "roi_differs_from_volume": False,
    "scene_node_count": 0
}

try:
    # Count scene nodes
    result["scene_node_count"] = slicer.mrmlScene.GetNumberOfNodes()
    
    # Check for volume nodes
    volume_nodes = slicer.util.getNodesByClass('vtkMRMLScalarVolumeNode')
    result["volume_count"] = len(volume_nodes)
    if volume_nodes:
        result["volume_name"] = volume_nodes[0].GetName()
        
        # Get volume bounds
        vol = volume_nodes[0]
        bounds = [0]*6
        vol.GetBounds(bounds)
        result["volume_bounds"] = list(bounds)
    
    # Check for volume rendering display nodes
    vr_nodes = slicer.util.getNodesByClass('vtkMRMLVolumeRenderingDisplayNode')
    result["vr_display_count"] = len(vr_nodes)
    
    for vr in vr_nodes:
        if vr.GetVisibility():
            result["volume_rendering_active"] = True
            
            # Check clipping/cropping
            if vr.GetCroppingEnabled():
                result["clipping_enabled"] = True
            
            # Get ROI node (can be MarkupsROI or AnnotationROI)
            roi = vr.GetMarkupsROINode()
            if roi is None:
                roi = vr.GetROINode()
            
            if roi is not None:
                result["roi_count"] += 1
                result["roi_node_name"] = roi.GetName()
                
                # Get ROI bounds
                roi_bounds = [0]*6
                roi.GetBounds(roi_bounds)
                result["roi_bounds"] = list(roi_bounds)
                
                # Check if ROI differs significantly from volume bounds
                if result["volume_bounds"]:
                    vb = result["volume_bounds"]
                    rb = result["roi_bounds"]
                    
                    # Calculate volume of each
                    vol_size = (vb[1]-vb[0]) * (vb[3]-vb[2]) * (vb[5]-vb[4])
                    roi_size = (rb[1]-rb[0]) * (rb[3]-rb[2]) * (rb[5]-rb[4])
                    
                    if vol_size > 0:
                        ratio = roi_size / vol_size
                        # If ROI is 50-95% of volume, it's a meaningful clip
                        if 0.3 < ratio < 0.95:
                            result["roi_differs_from_volume"] = True
                        result["roi_volume_ratio"] = ratio
    
    # Also check for standalone ROI nodes
    markup_rois = slicer.util.getNodesByClass('vtkMRMLMarkupsROINode')
    annotation_rois = slicer.util.getNodesByClass('vtkMRMLAnnotationROINode')
    result["roi_count"] = max(result["roi_count"], len(markup_rois) + len(annotation_rois))

except Exception as e:
    result["error"] = str(e)

# Save result
with open('/tmp/slicer_state.json', 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

    # Run the query script
    timeout 30 su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/query_slicer_state.py --no-main-window" > /tmp/slicer_query.log 2>&1 || true
    
    if [ -f /tmp/slicer_state.json ]; then
        SLICER_STATE_JSON=$(cat /tmp/slicer_state.json)
        echo "Slicer state queried successfully"
    else
        echo "Warning: Could not query Slicer state"
    fi
fi

# ============================================================
# Extract values from Slicer state
# ============================================================
VOLUME_COUNT=$(echo "$SLICER_STATE_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('volume_count', 0))" 2>/dev/null || echo "0")
VOLUME_RENDERING_ACTIVE=$(echo "$SLICER_STATE_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print('true' if d.get('volume_rendering_active', False) else 'false')" 2>/dev/null || echo "false")
ROI_COUNT=$(echo "$SLICER_STATE_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('roi_count', 0))" 2>/dev/null || echo "0")
CLIPPING_ENABLED=$(echo "$SLICER_STATE_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print('true' if d.get('clipping_enabled', False) else 'false')" 2>/dev/null || echo "false")
ROI_DIFFERS=$(echo "$SLICER_STATE_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print('true' if d.get('roi_differs_from_volume', False) else 'false')" 2>/dev/null || echo "false")
ROI_VOLUME_RATIO=$(echo "$SLICER_STATE_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('roi_volume_ratio', 1.0))" 2>/dev/null || echo "1.0")

# Check if Slicer is running
SLICER_RUNNING="false"
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
fi

# ============================================================
# Create result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_size_bytes": $SCREENSHOT_SIZE_BYTES,
    "screenshot_created_during_task": $SCREENSHOT_CREATED_DURING_TASK,
    "volume_count": $VOLUME_COUNT,
    "volume_rendering_active": $VOLUME_RENDERING_ACTIVE,
    "roi_count": $ROI_COUNT,
    "clipping_enabled": $CLIPPING_ENABLED,
    "roi_differs_from_volume": $ROI_DIFFERS,
    "roi_volume_ratio": $ROI_VOLUME_RATIO,
    "slicer_state": $SLICER_STATE_JSON
}
EOF

# Move to final location with permission handling
rm -f /tmp/clip_task_result.json 2>/dev/null || sudo rm -f /tmp/clip_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/clip_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/clip_task_result.json
chmod 666 /tmp/clip_task_result.json 2>/dev/null || sudo chmod 666 /tmp/clip_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result ==="
cat /tmp/clip_task_result.json
echo ""
echo "=== Export Complete ==="