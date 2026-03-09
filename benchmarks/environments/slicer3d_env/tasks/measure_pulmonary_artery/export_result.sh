#!/bin/bash
echo "=== Exporting Pulmonary Artery Measurement Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

if [ -f /tmp/task_final.png ]; then
    SIZE=$(stat -c %s /tmp/task_final.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SIZE} bytes"
fi

# ============================================================
# Check for measurement file
# ============================================================
MEASUREMENT_FILE="/home/ga/Documents/SlicerData/Exports/pa_measurement.json"
MEASUREMENT_EXISTS="false"
MEASUREMENT_VALUE=""
MEASUREMENT_VALID="false"
FILE_CREATED_DURING_TASK="false"

if [ -f "$MEASUREMENT_FILE" ]; then
    MEASUREMENT_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$MEASUREMENT_FILE" 2>/dev/null || echo "0")
    
    # Check if file was created during task
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
        echo "Measurement file was created during task"
    else
        echo "WARNING: Measurement file existed before task started"
    fi
    
    # Parse measurement value
    MEASUREMENT_VALUE=$(python3 << 'PYEOF'
import json
import sys

try:
    with open("/home/ga/Documents/SlicerData/Exports/pa_measurement.json", 'r') as f:
        data = json.load(f)
    
    # Look for diameter under various possible keys
    diameter = None
    for key in ['diameter_mm', 'diameter', 'value', 'measurement', 'pa_diameter']:
        if key in data and data[key] is not None:
            try:
                diameter = float(data[key])
                break
            except (ValueError, TypeError):
                continue
    
    if diameter is not None:
        print(f"{diameter:.2f}")
    else:
        print("")
except Exception as e:
    print("", file=sys.stderr)
    print("")
PYEOF
)
    
    # Validate measurement is in plausible range
    if [ -n "$MEASUREMENT_VALUE" ]; then
        MEASUREMENT_VALID=$(python3 -c "
try:
    val = float('$MEASUREMENT_VALUE')
    print('true' if 15 <= val <= 45 else 'false')
except:
    print('false')
" 2>/dev/null || echo "false")
    fi
    
    echo "Measurement file found: $MEASUREMENT_FILE"
    echo "Measurement value: $MEASUREMENT_VALUE mm"
    echo "Measurement valid: $MEASUREMENT_VALID"
else
    echo "Measurement file NOT found at $MEASUREMENT_FILE"
    
    # Search for alternative locations
    for alt_path in \
        "/home/ga/Documents/SlicerData/Exports/"*.json \
        "/home/ga/Documents/"*.json \
        "/home/ga/pa_measurement.json" \
        "/tmp/pa_measurement.json"; do
        if [ -f "$alt_path" ] 2>/dev/null; then
            echo "Found alternative file: $alt_path"
        fi
    done
fi

# ============================================================
# Check Slicer state and markups
# ============================================================
SLICER_RUNNING="false"
MARKUP_EXISTS="false"
MARKUP_LENGTH=""
MARKUP_COORDS=""
VOLUME_LOADED="false"

if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
    echo "Slicer is running"
    
    # Try to query Slicer for markup information
    QUERY_SCRIPT=$(mktemp /tmp/query_slicer.XXXXXX.py)
    cat > "$QUERY_SCRIPT" << 'PYEOF'
import json
import sys

try:
    import slicer
    
    result = {
        "markup_exists": False,
        "markup_length_mm": None,
        "markup_coords": None,
        "volume_loaded": False,
        "num_volumes": 0
    }
    
    # Check for volumes
    volumeNodes = slicer.util.getNodesByClass('vtkMRMLScalarVolumeNode')
    result["num_volumes"] = len(volumeNodes)
    result["volume_loaded"] = len(volumeNodes) > 0
    
    # Check for line markups (ruler measurements)
    lineNodes = slicer.util.getNodesByClass('vtkMRMLMarkupsLineNode')
    
    if lineNodes:
        result["markup_exists"] = True
        
        # Get the first line markup
        lineNode = lineNodes[0]
        
        if lineNode.GetNumberOfControlPoints() >= 2:
            # Get line length
            result["markup_length_mm"] = lineNode.GetLineLengthWorld()
            
            # Get endpoint coordinates
            p1 = [0.0, 0.0, 0.0]
            p2 = [0.0, 0.0, 0.0]
            lineNode.GetNthControlPointPosition(0, p1)
            lineNode.GetNthControlPointPosition(1, p2)
            result["markup_coords"] = {"p1": p1, "p2": p2}
    
    print(json.dumps(result))
    
except Exception as e:
    print(json.dumps({"error": str(e)}), file=sys.stderr)
    print(json.dumps({"markup_exists": False, "volume_loaded": False}))
PYEOF

    # Run query with timeout
    SLICER_QUERY_RESULT=$(timeout 15 sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-code "$(cat $QUERY_SCRIPT)" 2>/dev/null || echo '{"markup_exists": false}')
    rm -f "$QUERY_SCRIPT"
    
    # Parse results
    if [ -n "$SLICER_QUERY_RESULT" ]; then
        MARKUP_EXISTS=$(echo "$SLICER_QUERY_RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(str(d.get('markup_exists', False)).lower())" 2>/dev/null || echo "false")
        MARKUP_LENGTH=$(echo "$SLICER_QUERY_RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); v=d.get('markup_length_mm'); print(f'{v:.2f}' if v else '')" 2>/dev/null || echo "")
        VOLUME_LOADED=$(echo "$SLICER_QUERY_RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(str(d.get('volume_loaded', False)).lower())" 2>/dev/null || echo "false")
    fi
    
    echo "Markup exists: $MARKUP_EXISTS"
    echo "Markup length: $MARKUP_LENGTH mm"
    echo "Volume loaded: $VOLUME_LOADED"
else
    echo "Slicer is NOT running"
fi

# ============================================================
# Determine clinical interpretation
# ============================================================
CLINICAL_INTERPRETATION="unknown"

if [ -n "$MEASUREMENT_VALUE" ] && [ "$MEASUREMENT_VALID" = "true" ]; then
    CLINICAL_INTERPRETATION=$(python3 -c "
val = float('$MEASUREMENT_VALUE')
if val <= 25:
    print('normal')
elif val <= 29:
    print('borderline')
else:
    print('enlarged')
" 2>/dev/null || echo "unknown")
fi

echo "Clinical interpretation: $CLINICAL_INTERPRETATION"

# ============================================================
# Create result JSON
# ============================================================
RESULT_JSON="/tmp/pa_measurement_result.json"

# Handle null values for JSON
MEASUREMENT_VALUE_JSON="${MEASUREMENT_VALUE:-null}"
if [ "$MEASUREMENT_VALUE_JSON" != "null" ]; then
    MEASUREMENT_VALUE_JSON="$MEASUREMENT_VALUE"
fi

MARKUP_LENGTH_JSON="${MARKUP_LENGTH:-null}"
if [ "$MARKUP_LENGTH_JSON" != "null" ]; then
    MARKUP_LENGTH_JSON="$MARKUP_LENGTH"
fi

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_id": "measure_pulmonary_artery@1",
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "measurement_file_exists": $MEASUREMENT_EXISTS,
    "measurement_value_mm": $MEASUREMENT_VALUE_JSON,
    "measurement_in_valid_range": $MEASUREMENT_VALID,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "slicer_was_running": $SLICER_RUNNING,
    "markup_exists": $MARKUP_EXISTS,
    "markup_length_mm": $MARKUP_LENGTH_JSON,
    "volume_loaded": $VOLUME_LOADED,
    "clinical_interpretation": "$CLINICAL_INTERPRETATION",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f "$RESULT_JSON" 2>/dev/null || sudo rm -f "$RESULT_JSON" 2>/dev/null || true
cp "$TEMP_JSON" "$RESULT_JSON" 2>/dev/null || sudo cp "$TEMP_JSON" "$RESULT_JSON"
chmod 666 "$RESULT_JSON" 2>/dev/null || sudo chmod 666 "$RESULT_JSON" 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Complete ==="
echo "Result saved to: $RESULT_JSON"
cat "$RESULT_JSON"