#!/bin/bash
echo "=== Exporting Adjust Lung Window Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/task_final.png ga
sleep 1

# ============================================================
# Extract current W/L values from Slicer
# ============================================================
CURRENT_WINDOW=""
CURRENT_LEVEL=""
VOLUME_NAME=""
SLICER_RUNNING="false"
DATA_LOADED="false"

if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Create Python script to extract W/L values
    cat > /tmp/extract_wl.py << 'PYEOF'
import slicer
import json
import os

result = {
    "volumes_found": 0,
    "volume_name": "",
    "current_window": None,
    "current_level": None,
    "auto_wl_on": False,
    "error": None
}

try:
    volumes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
    result["volumes_found"] = len(volumes)
    
    if volumes:
        # Get the first volume (should be the CT)
        vol = volumes[0]
        result["volume_name"] = vol.GetName()
        
        display_node = vol.GetDisplayNode()
        if display_node:
            result["current_window"] = display_node.GetWindow()
            result["current_level"] = display_node.GetLevel()
            result["auto_wl_on"] = display_node.GetAutoWindowLevel()
        else:
            result["error"] = "No display node found"
    else:
        result["error"] = "No volumes found in scene"
        
except Exception as e:
    result["error"] = str(e)

# Write result to file
output_path = "/tmp/slicer_wl_state.json"
with open(output_path, "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

    # Run extraction script
    echo "Extracting window/level values from Slicer..."
    su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/extract_wl.py --no-main-window > /tmp/slicer_extract.log 2>&1" &
    EXTRACT_PID=$!
    
    # Wait for extraction (with timeout)
    for i in {1..20}; do
        if [ -f /tmp/slicer_wl_state.json ]; then
            echo "W/L state extracted"
            break
        fi
        if ! ps -p $EXTRACT_PID > /dev/null 2>&1; then
            break
        fi
        sleep 1
    done
    
    # Kill extraction process
    kill $EXTRACT_PID 2>/dev/null || true
    
    # Parse the extracted values
    if [ -f /tmp/slicer_wl_state.json ]; then
        CURRENT_WINDOW=$(python3 -c "import json; d=json.load(open('/tmp/slicer_wl_state.json')); print(d.get('current_window', ''))" 2>/dev/null || echo "")
        CURRENT_LEVEL=$(python3 -c "import json; d=json.load(open('/tmp/slicer_wl_state.json')); print(d.get('current_level', ''))" 2>/dev/null || echo "")
        VOLUME_NAME=$(python3 -c "import json; d=json.load(open('/tmp/slicer_wl_state.json')); print(d.get('volume_name', ''))" 2>/dev/null || echo "")
        VOLUMES_FOUND=$(python3 -c "import json; d=json.load(open('/tmp/slicer_wl_state.json')); print(d.get('volumes_found', 0))" 2>/dev/null || echo "0")
        
        if [ "$VOLUMES_FOUND" -gt 0 ]; then
            DATA_LOADED="true"
        fi
        
        echo "Extracted values:"
        echo "  Volume: $VOLUME_NAME"
        echo "  Window: $CURRENT_WINDOW"
        echo "  Level: $CURRENT_LEVEL"
    fi
fi

# ============================================================
# Get initial state for comparison
# ============================================================
INITIAL_WINDOW=$(python3 -c "import json; d=json.load(open('/tmp/initial_wl_state.json')); print(d.get('initial_window', 400))" 2>/dev/null || echo "400")
INITIAL_LEVEL=$(python3 -c "import json; d=json.load(open('/tmp/initial_wl_state.json')); print(d.get('initial_level', 40))" 2>/dev/null || echo "40")

# ============================================================
# Check if values changed
# ============================================================
VALUES_CHANGED="false"
if [ -n "$CURRENT_WINDOW" ] && [ -n "$CURRENT_LEVEL" ]; then
    # Use Python for float comparison
    VALUES_CHANGED=$(python3 << PYEOF
import math
try:
    curr_w = float("$CURRENT_WINDOW")
    curr_l = float("$CURRENT_LEVEL")
    init_w = float("$INITIAL_WINDOW")
    init_l = float("$INITIAL_LEVEL")
    
    # Check if either value changed significantly (>10%)
    w_changed = abs(curr_w - init_w) > (init_w * 0.1) if init_w != 0 else curr_w != init_w
    l_changed = abs(curr_l - init_l) > 10  # Level can cross zero, use absolute diff
    
    if w_changed or l_changed:
        print("true")
    else:
        print("false")
except:
    print("false")
PYEOF
)
fi

# ============================================================
# Check screenshot quality
# ============================================================
SCREENSHOT_EXISTS="false"
SCREENSHOT_SIZE_KB=0

if [ -f /tmp/task_final.png ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE_KB=$(du -k /tmp/task_final.png 2>/dev/null | cut -f1 || echo "0")
fi

# ============================================================
# Create result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "data_loaded": $DATA_LOADED,
    "volume_name": "$VOLUME_NAME",
    "initial_window": $INITIAL_WINDOW,
    "initial_level": $INITIAL_LEVEL,
    "current_window": ${CURRENT_WINDOW:-null},
    "current_level": ${CURRENT_LEVEL:-null},
    "values_changed": $VALUES_CHANGED,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_size_kb": $SCREENSHOT_SIZE_KB,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/lung_window_result.json 2>/dev/null || sudo rm -f /tmp/lung_window_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/lung_window_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/lung_window_result.json
chmod 666 /tmp/lung_window_result.json 2>/dev/null || sudo chmod 666 /tmp/lung_window_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result ==="
cat /tmp/lung_window_result.json
echo ""

# Close Slicer gracefully
echo "Closing 3D Slicer..."
close_slicer

echo "=== Export Complete ==="