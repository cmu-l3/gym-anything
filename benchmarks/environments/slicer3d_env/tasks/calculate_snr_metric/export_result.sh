#!/bin/bash
echo "=== Exporting SNR Metric Task Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

OUTPUT_JSON="/home/ga/Documents/SlicerData/snr_result.json"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/snr_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/snr_final.png 2>/dev/null || true

if [ -f /tmp/snr_final.png ]; then
    SIZE=$(stat -c %s /tmp/snr_final.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SIZE} bytes"
fi

# ============================================================
# Check if output JSON exists and was created during task
# ============================================================
OUTPUT_EXISTS="false"
OUTPUT_VALID_JSON="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE=0
OUTPUT_MTIME=0

SIGNAL_MEAN=""
NOISE_STD=""
SNR_VALUE=""
SNR_CALCULATION_CORRECT="false"

if [ -f "$OUTPUT_JSON" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_JSON" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_JSON" 2>/dev/null || echo "0")
    
    # Check if created during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    echo "Output JSON found: $OUTPUT_JSON"
    echo "  Size: $OUTPUT_SIZE bytes"
    echo "  Modified: $OUTPUT_MTIME"
    echo "  Task start: $TASK_START"
    echo "  Created during task: $FILE_CREATED_DURING_TASK"
    
    # Try to parse JSON and extract values
    PARSE_RESULT=$(python3 << 'PYEOF'
import json
import sys

try:
    with open("/home/ga/Documents/SlicerData/snr_result.json", "r") as f:
        data = json.load(f)
    
    signal_mean = data.get("signal_mean")
    noise_std = data.get("noise_std")
    snr = data.get("snr")
    
    # Validate all fields exist and are numeric
    if signal_mean is None or noise_std is None or snr is None:
        print("MISSING_FIELDS")
        sys.exit(0)
    
    try:
        signal_mean = float(signal_mean)
        noise_std = float(noise_std)
        snr = float(snr)
    except (ValueError, TypeError):
        print("NON_NUMERIC")
        sys.exit(0)
    
    # Check if SNR calculation is correct
    if noise_std > 0:
        expected_snr = signal_mean / noise_std
        calculation_correct = abs(snr - expected_snr) < 0.01 * expected_snr  # 1% tolerance
    else:
        calculation_correct = False
    
    result = {
        "valid": True,
        "signal_mean": signal_mean,
        "noise_std": noise_std,
        "snr": snr,
        "calculation_correct": calculation_correct
    }
    print(json.dumps(result))
    
except json.JSONDecodeError as e:
    print(f"JSON_ERROR:{e}")
except Exception as e:
    print(f"ERROR:{e}")
PYEOF
)
    
    echo "Parse result: $PARSE_RESULT"
    
    if echo "$PARSE_RESULT" | grep -q '"valid": true'; then
        OUTPUT_VALID_JSON="true"
        SIGNAL_MEAN=$(echo "$PARSE_RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('signal_mean', ''))" 2>/dev/null || echo "")
        NOISE_STD=$(echo "$PARSE_RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('noise_std', ''))" 2>/dev/null || echo "")
        SNR_VALUE=$(echo "$PARSE_RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('snr', ''))" 2>/dev/null || echo "")
        CALC_CORRECT=$(echo "$PARSE_RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('calculation_correct', False))" 2>/dev/null || echo "false")
        if [ "$CALC_CORRECT" = "True" ]; then
            SNR_CALCULATION_CORRECT="true"
        fi
    fi
else
    echo "Output JSON NOT found at: $OUTPUT_JSON"
fi

# ============================================================
# Check Slicer state and segmentation
# ============================================================
SLICER_RUNNING="false"
SEGMENTATION_EXISTS="false"
NUM_SEGMENTS=0
SEGMENT_NAMES=""

if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
    echo "Slicer is running"
    
    # Try to query Slicer for segmentation info
    cat > /tmp/check_segments.py << 'PYEOF'
import json
try:
    import slicer
    
    # Look for segmentation nodes
    seg_nodes = slicer.util.getNodesByClass("vtkMRMLSegmentationNode")
    
    result = {
        "segmentation_exists": len(seg_nodes) > 0,
        "num_segmentations": len(seg_nodes),
        "segments": []
    }
    
    for seg_node in seg_nodes:
        segmentation = seg_node.GetSegmentation()
        num_segs = segmentation.GetNumberOfSegments()
        for i in range(num_segs):
            seg_id = segmentation.GetNthSegmentID(i)
            segment = segmentation.GetSegment(seg_id)
            seg_name = segment.GetName()
            result["segments"].append(seg_name)
    
    result["num_segments"] = len(result["segments"])
    
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({"error": str(e), "segmentation_exists": False, "num_segments": 0}))
PYEOF

    # Run the check (with timeout)
    timeout 15 su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/check_segments.py --no-main-window" > /tmp/segment_check.txt 2>&1 &
    sleep 12
    pkill -f "check_segments.py" 2>/dev/null || true
    
    if [ -f /tmp/segment_check.txt ]; then
        SEG_RESULT=$(cat /tmp/segment_check.txt | grep -o '{.*}' | tail -1 || echo "{}")
        if echo "$SEG_RESULT" | grep -q '"segmentation_exists": true'; then
            SEGMENTATION_EXISTS="true"
            NUM_SEGMENTS=$(echo "$SEG_RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('num_segments', 0))" 2>/dev/null || echo "0")
            SEGMENT_NAMES=$(echo "$SEG_RESULT" | python3 -c "import json,sys; print(','.join(json.load(sys.stdin).get('segments', [])))" 2>/dev/null || echo "")
            echo "Segmentation found with $NUM_SEGMENTS segments: $SEGMENT_NAMES"
        fi
    fi
fi

# ============================================================
# Check for Signal and Noise segments specifically
# ============================================================
HAS_SIGNAL_SEGMENT="false"
HAS_NOISE_SEGMENT="false"

if [ -n "$SEGMENT_NAMES" ]; then
    if echo "$SEGMENT_NAMES" | grep -qi "signal"; then
        HAS_SIGNAL_SEGMENT="true"
    fi
    if echo "$SEGMENT_NAMES" | grep -qi "noise"; then
        HAS_NOISE_SEGMENT="true"
    fi
fi

# ============================================================
# Create result JSON
# ============================================================
echo "Creating result JSON..."

TEMP_JSON=$(mktemp /tmp/snr_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_json_exists": $OUTPUT_EXISTS,
    "output_json_valid": $OUTPUT_VALID_JSON,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "signal_mean": "$SIGNAL_MEAN",
    "noise_std": "$NOISE_STD",
    "snr_value": "$SNR_VALUE",
    "snr_calculation_correct": $SNR_CALCULATION_CORRECT,
    "slicer_was_running": $SLICER_RUNNING,
    "segmentation_exists": $SEGMENTATION_EXISTS,
    "num_segments": $NUM_SEGMENTS,
    "segment_names": "$SEGMENT_NAMES",
    "has_signal_segment": $HAS_SIGNAL_SEGMENT,
    "has_noise_segment": $HAS_NOISE_SEGMENT,
    "final_screenshot": "/tmp/snr_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/snr_task_result.json 2>/dev/null || sudo rm -f /tmp/snr_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/snr_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/snr_task_result.json
chmod 666 /tmp/snr_task_result.json 2>/dev/null || sudo chmod 666 /tmp/snr_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

# Also copy the actual output JSON for verification if it exists
if [ -f "$OUTPUT_JSON" ]; then
    cp "$OUTPUT_JSON" /tmp/snr_output_copy.json 2>/dev/null || true
    chmod 666 /tmp/snr_output_copy.json 2>/dev/null || true
fi

echo ""
echo "Result saved to /tmp/snr_task_result.json:"
cat /tmp/snr_task_result.json
echo ""
echo "=== Export Complete ==="