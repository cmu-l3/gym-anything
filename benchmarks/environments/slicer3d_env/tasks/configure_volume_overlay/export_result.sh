#!/bin/bash
echo "=== Exporting Volume Overlay Configuration Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

EXPORTS_DIR="/home/ga/Documents/SlicerData/Exports"
OUTPUT_SCREENSHOT="$EXPORTS_DIR/overlay_result.png"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot of Slicer state
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/overlay_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/overlay_final.png 2>/dev/null || true

# Check if Slicer is running
SLICER_RUNNING="false"
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
fi

# ============================================================
# Query Slicer's MRML scene for composite node state
# ============================================================
echo "Querying Slicer scene state..."

cat > /tmp/export_overlay_state.py << 'PYEOF'
import slicer
import json
import os

result = {
    "volumes_loaded": 0,
    "flair_node_id": "",
    "t1ce_node_id": "",
    "flair_loaded": False,
    "t1ce_loaded": False,
    "composite_configurations": [],
    "any_overlay_configured": False,
    "correct_overlay_configured": False,
    "opacity_correct": False,
    "best_opacity": 0.0
}

# Find volume nodes
volume_nodes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
result["volumes_loaded"] = volume_nodes.GetNumberOfItems()

flair_node_id = ""
t1ce_node_id = ""

for i in range(volume_nodes.GetNumberOfItems()):
    node = volume_nodes.GetItemAsObject(i)
    name = node.GetName().lower()
    node_id = node.GetID()
    
    if "flair" in name:
        result["flair_loaded"] = True
        result["flair_node_id"] = node_id
        flair_node_id = node_id
    if "t1ce" in name or "t1_ce" in name or "t1-ce" in name or "t1 ce" in name:
        result["t1ce_loaded"] = True
        result["t1ce_node_id"] = node_id
        t1ce_node_id = node_id

# Check slice composite nodes
composite_nodes = slicer.util.getNodesByClass("vtkMRMLSliceCompositeNode")
print(f"Found {composite_nodes.GetNumberOfItems()} slice composite nodes")

for i in range(composite_nodes.GetNumberOfItems()):
    node = composite_nodes.GetItemAsObject(i)
    
    bg_id = node.GetBackgroundVolumeID() or ""
    fg_id = node.GetForegroundVolumeID() or ""
    fg_opacity = node.GetForegroundOpacity()
    
    # Get volume names for readability
    bg_name = ""
    fg_name = ""
    if bg_id:
        bg_node = slicer.mrmlScene.GetNodeByID(bg_id)
        if bg_node:
            bg_name = bg_node.GetName()
    if fg_id:
        fg_node = slicer.mrmlScene.GetNodeByID(fg_id)
        if fg_node:
            fg_name = fg_node.GetName()
    
    config = {
        "slice_name": node.GetName(),
        "background_id": bg_id,
        "background_name": bg_name,
        "foreground_id": fg_id,
        "foreground_name": fg_name,
        "foreground_opacity": fg_opacity,
        "has_foreground": bool(fg_id),
        "has_background": bool(bg_id)
    }
    result["composite_configurations"].append(config)
    
    # Check if this view has overlay configured
    if fg_id and bg_id:
        result["any_overlay_configured"] = True
        
        # Check if correct volumes are configured
        bg_is_flair = (bg_id == flair_node_id) or ("flair" in bg_name.lower())
        fg_is_t1ce = (fg_id == t1ce_node_id) or ("t1ce" in fg_name.lower() or "t1_ce" in fg_name.lower())
        
        if bg_is_flair and fg_is_t1ce:
            result["correct_overlay_configured"] = True
            result["best_opacity"] = fg_opacity
            
            # Check opacity is in acceptable range (40-60%)
            if 0.4 <= fg_opacity <= 0.6:
                result["opacity_correct"] = True

print(f"Composite configurations: {json.dumps(result['composite_configurations'], indent=2)}")

# Save result
with open("/tmp/slicer_overlay_state.json", "w") as f:
    json.dump(result, f, indent=2)

print(f"Overlay state exported: correct={result['correct_overlay_configured']}, opacity={result['best_opacity']:.2f}")
PYEOF

# Run the export script via Slicer
if [ "$SLICER_RUNNING" = "true" ]; then
    su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer --no-splash --no-main-window --python-script /tmp/export_overlay_state.py" > /tmp/export_overlay.log 2>&1 &
    EXPORT_PID=$!
    sleep 12
    kill $EXPORT_PID 2>/dev/null || true
fi

# ============================================================
# Check for user screenshot
# ============================================================
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
    
    # Copy to tmp for verification
    cp "$OUTPUT_SCREENSHOT" /tmp/user_overlay_screenshot.png 2>/dev/null || true
    
    echo "User screenshot found: ${SCREENSHOT_SIZE_KB}KB, created_during_task=$SCREENSHOT_CREATED_DURING_TASK"
else
    echo "No user screenshot at expected path: $OUTPUT_SCREENSHOT"
    
    # Check alternative locations
    ALT_SCREENSHOTS=$(find "$EXPORTS_DIR" /home/ga/Documents/SlicerData -maxdepth 2 -name "*.png" -newer /tmp/task_start_time.txt 2>/dev/null | head -3)
    if [ -n "$ALT_SCREENSHOTS" ]; then
        echo "Found alternative screenshots:"
        echo "$ALT_SCREENSHOTS"
        FIRST_ALT=$(echo "$ALT_SCREENSHOTS" | head -1)
        if [ -f "$FIRST_ALT" ]; then
            SCREENSHOT_EXISTS="true"
            SCREENSHOT_SIZE_KB=$(du -k "$FIRST_ALT" 2>/dev/null | cut -f1 || echo "0")
            SCREENSHOT_CREATED_DURING_TASK="true"
            cp "$FIRST_ALT" /tmp/user_overlay_screenshot.png 2>/dev/null || true
        fi
    fi
fi

# ============================================================
# Load Slicer scene state
# ============================================================
SLICER_STATE_FILE="/tmp/slicer_overlay_state.json"

VOLUMES_LOADED=0
FLAIR_LOADED="false"
T1CE_LOADED="false"
ANY_OVERLAY="false"
CORRECT_OVERLAY="false"
OPACITY_CORRECT="false"
BEST_OPACITY=0

if [ -f "$SLICER_STATE_FILE" ]; then
    VOLUMES_LOADED=$(python3 -c "import json; print(json.load(open('$SLICER_STATE_FILE')).get('volumes_loaded', 0))" 2>/dev/null || echo "0")
    FLAIR_LOADED=$(python3 -c "import json; print('true' if json.load(open('$SLICER_STATE_FILE')).get('flair_loaded', False) else 'false')" 2>/dev/null || echo "false")
    T1CE_LOADED=$(python3 -c "import json; print('true' if json.load(open('$SLICER_STATE_FILE')).get('t1ce_loaded', False) else 'false')" 2>/dev/null || echo "false")
    ANY_OVERLAY=$(python3 -c "import json; print('true' if json.load(open('$SLICER_STATE_FILE')).get('any_overlay_configured', False) else 'false')" 2>/dev/null || echo "false")
    CORRECT_OVERLAY=$(python3 -c "import json; print('true' if json.load(open('$SLICER_STATE_FILE')).get('correct_overlay_configured', False) else 'false')" 2>/dev/null || echo "false")
    OPACITY_CORRECT=$(python3 -c "import json; print('true' if json.load(open('$SLICER_STATE_FILE')).get('opacity_correct', False) else 'false')" 2>/dev/null || echo "false")
    BEST_OPACITY=$(python3 -c "import json; print(json.load(open('$SLICER_STATE_FILE')).get('best_opacity', 0))" 2>/dev/null || echo "0")
fi

# ============================================================
# Create final result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "volumes_loaded": $VOLUMES_LOADED,
    "flair_loaded": $FLAIR_LOADED,
    "t1ce_loaded": $T1CE_LOADED,
    "any_overlay_configured": $ANY_OVERLAY,
    "correct_overlay_configured": $CORRECT_OVERLAY,
    "opacity_correct": $OPACITY_CORRECT,
    "best_opacity": $BEST_OPACITY,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_size_kb": $SCREENSHOT_SIZE_KB,
    "screenshot_created_during_task": $SCREENSHOT_CREATED_DURING_TASK,
    "final_screenshot_path": "/tmp/overlay_final.png",
    "user_screenshot_path": "/tmp/user_overlay_screenshot.png"
}
EOF

# Move to final location
rm -f /tmp/overlay_task_result.json 2>/dev/null || sudo rm -f /tmp/overlay_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/overlay_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/overlay_task_result.json
chmod 666 /tmp/overlay_task_result.json 2>/dev/null || sudo chmod 666 /tmp/overlay_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Complete ==="
echo "Result saved to /tmp/overlay_task_result.json"
cat /tmp/overlay_task_result.json