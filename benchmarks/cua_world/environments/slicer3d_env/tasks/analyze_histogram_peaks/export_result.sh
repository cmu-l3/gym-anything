#!/bin/bash
echo "=== Exporting Histogram Analysis Results ==="

# Source utilities if available
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
fi

# Get task timing
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final_screenshot.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_final_screenshot.png 2>/dev/null || true

# Define paths
OUTPUT_FILE="/home/ga/Documents/SlicerData/histogram_analysis.json"
SAMPLE_DATA="/home/ga/Documents/SlicerData/SampleData/MRHead.nrrd"

# ============================================================
# CHECK OUTPUT JSON FILE
# ============================================================
OUTPUT_EXISTS="false"
OUTPUT_CREATED_AFTER_START="false"
VALID_JSON="false"
VALID_STRUCTURE="false"
PROPER_ORDERING="false"

BACKGROUND_PEAK=""
LOW_TISSUE_PEAK=""
HIGH_TISSUE_PEAK=""
VOLUME_NAME=""

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c%Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    echo "Output file found: $OUTPUT_FILE ($OUTPUT_SIZE bytes)"
    echo "Output mtime: $OUTPUT_MTIME, Task start: $TASK_START"
    
    # Check if created after task start (anti-gaming)
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        OUTPUT_CREATED_AFTER_START="true"
        echo "File was created during task execution"
    else
        echo "WARNING: File existed before task started"
    fi
    
    # Validate JSON and extract values
    python3 << 'PYEOF'
import json
import sys
import os

output_file = "/home/ga/Documents/SlicerData/histogram_analysis.json"

try:
    with open(output_file, 'r') as f:
        data = json.load(f)
    
    # Write validation results
    results = {
        "valid_json": True,
        "valid_structure": False,
        "proper_ordering": False,
        "volume_name": "",
        "background_peak": "",
        "low_tissue_peak": "",
        "high_tissue_peak": ""
    }
    
    # Check for required fields
    required_fields = ["background_peak", "low_tissue_peak", "high_tissue_peak"]
    has_all_fields = all(field in data for field in required_fields)
    
    if has_all_fields:
        results["valid_structure"] = True
        
        # Extract values
        results["volume_name"] = str(data.get("volume_name", ""))
        
        try:
            bg = float(data.get("background_peak", 0))
            low = float(data.get("low_tissue_peak", 0))
            high = float(data.get("high_tissue_peak", 0))
            
            results["background_peak"] = str(bg)
            results["low_tissue_peak"] = str(low)
            results["high_tissue_peak"] = str(high)
            
            # Check ordering
            if bg < low < high:
                results["proper_ordering"] = True
        except (ValueError, TypeError):
            pass
    
    # Write results to temp file for shell script
    with open("/tmp/json_validation.json", "w") as f:
        json.dump(results, f)
    
    print("JSON validation complete")
    
except json.JSONDecodeError as e:
    results = {"valid_json": False, "error": str(e)}
    with open("/tmp/json_validation.json", "w") as f:
        json.dump(results, f)
    print(f"JSON parse error: {e}")
    
except Exception as e:
    results = {"valid_json": False, "error": str(e)}
    with open("/tmp/json_validation.json", "w") as f:
        json.dump(results, f)
    print(f"Error: {e}")
PYEOF

    # Read validation results
    if [ -f /tmp/json_validation.json ]; then
        VALID_JSON=$(python3 -c "import json; print('true' if json.load(open('/tmp/json_validation.json')).get('valid_json', False) else 'false')" 2>/dev/null || echo "false")
        VALID_STRUCTURE=$(python3 -c "import json; print('true' if json.load(open('/tmp/json_validation.json')).get('valid_structure', False) else 'false')" 2>/dev/null || echo "false")
        PROPER_ORDERING=$(python3 -c "import json; print('true' if json.load(open('/tmp/json_validation.json')).get('proper_ordering', False) else 'false')" 2>/dev/null || echo "false")
        VOLUME_NAME=$(python3 -c "import json; print(json.load(open('/tmp/json_validation.json')).get('volume_name', ''))" 2>/dev/null || echo "")
        BACKGROUND_PEAK=$(python3 -c "import json; print(json.load(open('/tmp/json_validation.json')).get('background_peak', ''))" 2>/dev/null || echo "")
        LOW_TISSUE_PEAK=$(python3 -c "import json; print(json.load(open('/tmp/json_validation.json')).get('low_tissue_peak', ''))" 2>/dev/null || echo "")
        HIGH_TISSUE_PEAK=$(python3 -c "import json; print(json.load(open('/tmp/json_validation.json')).get('high_tissue_peak', ''))" 2>/dev/null || echo "")
    fi
else
    echo "Output file NOT found at $OUTPUT_FILE"
fi

# ============================================================
# CHECK SLICER STATE
# ============================================================
SLICER_RUNNING="false"
VOLUME_LOADED="false"
MRHEAD_LOADED="false"

if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
    echo "Slicer is running"
    
    # Try to query Slicer for loaded volumes
    cat > /tmp/check_slicer_state.py << 'PYEOF'
import json
import sys

try:
    import slicer
    
    result = {
        "slicer_accessible": True,
        "volume_count": 0,
        "volume_names": [],
        "mrhead_loaded": False
    }
    
    # Get all scalar volume nodes
    nodes = slicer.util.getNodesByClass('vtkMRMLScalarVolumeNode')
    result["volume_count"] = len(nodes)
    
    for node in nodes:
        name = node.GetName()
        result["volume_names"].append(name)
        if "mrhead" in name.lower() or "mr head" in name.lower():
            result["mrhead_loaded"] = True
    
    with open("/tmp/slicer_state.json", "w") as f:
        json.dump(result, f)
    
    print(f"Found {len(nodes)} volume(s)")
    
except Exception as e:
    result = {"slicer_accessible": False, "error": str(e)}
    with open("/tmp/slicer_state.json", "w") as f:
        json.dump(result, f)
    print(f"Error querying Slicer: {e}")
PYEOF

    # Try to run the check script via Slicer
    timeout 15 sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --no-splash --no-main-window \
        --python-script /tmp/check_slicer_state.py > /tmp/slicer_check.log 2>&1 || true
    
    # Read Slicer state if available
    if [ -f /tmp/slicer_state.json ]; then
        VOLUME_COUNT=$(python3 -c "import json; print(json.load(open('/tmp/slicer_state.json')).get('volume_count', 0))" 2>/dev/null || echo "0")
        MRHEAD_LOADED=$(python3 -c "import json; print('true' if json.load(open('/tmp/slicer_state.json')).get('mrhead_loaded', False) else 'false')" 2>/dev/null || echo "false")
        
        if [ "$VOLUME_COUNT" -gt 0 ]; then
            VOLUME_LOADED="true"
        fi
    fi
fi

# ============================================================
# CHECK WINDOW STATE (VLM evidence)
# ============================================================
HISTOGRAM_VISIBLE="false"
VOLUMES_MODULE_VISIBLE="false"

WINDOW_LIST=$(DISPLAY=:1 wmctrl -l 2>/dev/null || echo "")
echo "Current windows: $WINDOW_LIST"

if echo "$WINDOW_LIST" | grep -qi "volume\|histogram"; then
    VOLUMES_MODULE_VISIBLE="true"
fi

# ============================================================
# CREATE RESULT JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_json_exists": $OUTPUT_EXISTS,
    "output_created_after_start": $OUTPUT_CREATED_AFTER_START,
    "valid_json": $VALID_JSON,
    "valid_structure": $VALID_STRUCTURE,
    "proper_ordering": $PROPER_ORDERING,
    "volume_name": "$VOLUME_NAME",
    "background_peak": "$BACKGROUND_PEAK",
    "low_tissue_peak": "$LOW_TISSUE_PEAK",
    "high_tissue_peak": "$HIGH_TISSUE_PEAK",
    "slicer_running": $SLICER_RUNNING,
    "volume_loaded": $VOLUME_LOADED,
    "mrhead_loaded": $MRHEAD_LOADED,
    "volumes_module_visible": $VOLUMES_MODULE_VISIBLE,
    "screenshot_path": "/tmp/task_final_screenshot.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/histogram_task_result.json 2>/dev/null || sudo rm -f /tmp/histogram_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/histogram_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/histogram_task_result.json
chmod 666 /tmp/histogram_task_result.json 2>/dev/null || sudo chmod 666 /tmp/histogram_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Complete ==="
echo "Result saved to /tmp/histogram_task_result.json"
cat /tmp/histogram_task_result.json