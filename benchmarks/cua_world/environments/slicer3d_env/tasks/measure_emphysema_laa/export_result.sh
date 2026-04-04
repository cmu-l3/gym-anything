#!/bin/bash
echo "=== Exporting Emphysema LAA% Measurement Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Get paths
EXPORTS_DIR="/home/ga/Documents/SlicerData/Exports"
OUTPUT_PATH="$EXPORTS_DIR/emphysema_analysis.json"
LIDC_DIR="/home/ga/Documents/SlicerData/LIDC"

# Get patient ID
PATIENT_ID="LIDC-IDRI-0001"
if [ -f /tmp/emphysema_patient_id.txt ]; then
    PATIENT_ID=$(cat /tmp/emphysema_patient_id.txt)
fi

# Record task timing
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/emphysema_final.png 2>/dev/null || true
sleep 1

# ============================================================
# Check if Slicer is running and extract data
# ============================================================
SLICER_RUNNING="false"
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
    echo "Slicer is running"
    
    # Try to extract segment data from Slicer
    cat > /tmp/export_emphysema_data.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/Exports"
os.makedirs(output_dir, exist_ok=True)

# Get all segments
segmentation_nodes = slicer.util.getNodesByClass("vtkMRMLSegmentationNode")
segment_info = []

for seg_node in segmentation_nodes:
    segmentation = seg_node.GetSegmentation()
    num_segments = segmentation.GetNumberOfSegments()
    
    for i in range(num_segments):
        segment_id = segmentation.GetNthSegmentID(i)
        segment = segmentation.GetSegment(segment_id)
        
        segment_data = {
            "name": segment.GetName(),
            "id": segment_id,
            "node_name": seg_node.GetName()
        }
        segment_info.append(segment_data)
        print(f"Found segment: {segment.GetName()}")

# Try to get segment statistics if available
try:
    import SegmentStatistics
    stats_logic = SegmentStatistics.SegmentStatisticsLogic()
    
    # Get the first segmentation and volume
    if segmentation_nodes:
        seg_node = segmentation_nodes[0]
        
        # Find associated volume
        volume_nodes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
        if volume_nodes:
            volume_node = volume_nodes[0]
            
            # Compute statistics
            stats_logic.getParameterNode().SetParameter("Segmentation", seg_node.GetID())
            stats_logic.getParameterNode().SetParameter("ScalarVolume", volume_node.GetID())
            stats_logic.computeStatistics()
            
            stats = stats_logic.getStatistics()
            print(f"Computed statistics for {len(stats)} segments")
            
            # Export statistics
            stats_path = os.path.join(output_dir, "segment_statistics.json")
            with open(stats_path, "w") as f:
                # Convert stats to JSON-serializable format
                stats_dict = {}
                for key, value in stats.items():
                    if isinstance(value, (int, float, str, bool, list)):
                        stats_dict[key] = value
                    else:
                        stats_dict[key] = str(value)
                json.dump(stats_dict, f, indent=2)
            print(f"Statistics saved to: {stats_path}")
            
except Exception as e:
    print(f"Statistics error: {e}")

# Save segment info
info_path = os.path.join(output_dir, "segments_info.json")
with open(info_path, "w") as f:
    json.dump({"segments": segment_info, "count": len(segment_info)}, f, indent=2)

print(f"Found {len(segment_info)} segments total")
PYEOF

    # Run export script in Slicer
    timeout 30 sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_emphysema_data.py --no-main-window > /tmp/slicer_export.log 2>&1 || true
    sleep 5
fi

# ============================================================
# Check for output file
# ============================================================
OUTPUT_EXISTS="false"
OUTPUT_SIZE="0"
OUTPUT_MTIME="0"
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if created during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    echo "Output file found: $OUTPUT_PATH ($OUTPUT_SIZE bytes)"
else
    echo "Output file NOT found at $OUTPUT_PATH"
    
    # Search for alternative output locations
    echo "Searching for alternative outputs..."
    ALTERNATIVE_FILES=$(find /home/ga -maxdepth 4 -name "*.json" -newer /tmp/task_start_time.txt 2>/dev/null | head -10)
    if [ -n "$ALTERNATIVE_FILES" ]; then
        echo "Found new JSON files:"
        echo "$ALTERNATIVE_FILES"
    fi
fi

# ============================================================
# Parse output JSON if it exists
# ============================================================
REPORTED_TOTAL_LUNG_VOLUME=""
REPORTED_EMPHYSEMA_VOLUME=""
REPORTED_LAA_PERCENT=""
REPORTED_CLASSIFICATION=""
REPORTED_THRESHOLD=""
JSON_VALID="false"
HAS_REQUIRED_FIELDS="false"

if [ "$OUTPUT_EXISTS" = "true" ]; then
    echo "Parsing output JSON..."
    
    PARSED=$(python3 << PYEOF
import json
import sys

try:
    with open("$OUTPUT_PATH", "r") as f:
        data = json.load(f)
    
    result = {
        "valid": True,
        "total_lung_volume_ml": data.get("total_lung_volume_ml", ""),
        "emphysema_volume_ml": data.get("emphysema_volume_ml", ""),
        "laa_percent": data.get("laa_percent", ""),
        "classification": data.get("classification", ""),
        "threshold_hu": data.get("threshold_hu", ""),
        "patient_id": data.get("patient_id", "")
    }
    
    # Check required fields
    required = ["total_lung_volume_ml", "emphysema_volume_ml", "laa_percent"]
    has_all = all(data.get(f) is not None and str(data.get(f)) != "" for f in required)
    result["has_required_fields"] = has_all
    
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({"valid": False, "error": str(e)}))
PYEOF
)
    
    JSON_VALID=$(echo "$PARSED" | python3 -c "import json,sys; print(json.load(sys.stdin).get('valid', False))" 2>/dev/null || echo "false")
    
    if [ "$JSON_VALID" = "True" ] || [ "$JSON_VALID" = "true" ]; then
        JSON_VALID="true"
        REPORTED_TOTAL_LUNG_VOLUME=$(echo "$PARSED" | python3 -c "import json,sys; print(json.load(sys.stdin).get('total_lung_volume_ml', ''))" 2>/dev/null || echo "")
        REPORTED_EMPHYSEMA_VOLUME=$(echo "$PARSED" | python3 -c "import json,sys; print(json.load(sys.stdin).get('emphysema_volume_ml', ''))" 2>/dev/null || echo "")
        REPORTED_LAA_PERCENT=$(echo "$PARSED" | python3 -c "import json,sys; print(json.load(sys.stdin).get('laa_percent', ''))" 2>/dev/null || echo "")
        REPORTED_CLASSIFICATION=$(echo "$PARSED" | python3 -c "import json,sys; print(json.load(sys.stdin).get('classification', ''))" 2>/dev/null || echo "")
        REPORTED_THRESHOLD=$(echo "$PARSED" | python3 -c "import json,sys; print(json.load(sys.stdin).get('threshold_hu', ''))" 2>/dev/null || echo "")
        HAS_REQUIRED_FIELDS=$(echo "$PARSED" | python3 -c "import json,sys; v=json.load(sys.stdin).get('has_required_fields', False); print('true' if v else 'false')" 2>/dev/null || echo "false")
        
        echo "Parsed values:"
        echo "  Total lung volume: $REPORTED_TOTAL_LUNG_VOLUME mL"
        echo "  Emphysema volume: $REPORTED_EMPHYSEMA_VOLUME mL"
        echo "  LAA%: $REPORTED_LAA_PERCENT"
        echo "  Classification: $REPORTED_CLASSIFICATION"
        echo "  Threshold: $REPORTED_THRESHOLD HU"
    fi
fi

# ============================================================
# Check for segmentation evidence
# ============================================================
SEGMENTS_FOUND="false"
SEGMENT_COUNT="0"

if [ -f "$EXPORTS_DIR/segments_info.json" ]; then
    SEGMENT_COUNT=$(python3 -c "import json; print(json.load(open('$EXPORTS_DIR/segments_info.json')).get('count', 0))" 2>/dev/null || echo "0")
    if [ "$SEGMENT_COUNT" -gt 0 ]; then
        SEGMENTS_FOUND="true"
    fi
fi

# ============================================================
# Load ground truth for comparison
# ============================================================
GT_LAA_PERCENT=""
GT_TOTAL_LUNG_VOLUME=""
GT_CLASSIFICATION=""

if [ -f "/tmp/emphysema_ground_truth.json" ]; then
    GT_LAA_PERCENT=$(python3 -c "import json; print(json.load(open('/tmp/emphysema_ground_truth.json')).get('laa_percent', ''))" 2>/dev/null || echo "")
    GT_TOTAL_LUNG_VOLUME=$(python3 -c "import json; print(json.load(open('/tmp/emphysema_ground_truth.json')).get('total_lung_volume_ml', ''))" 2>/dev/null || echo "")
    GT_CLASSIFICATION=$(python3 -c "import json; print(json.load(open('/tmp/emphysema_ground_truth.json')).get('classification', ''))" 2>/dev/null || echo "")
    
    echo ""
    echo "Ground truth values:"
    echo "  LAA%: $GT_LAA_PERCENT"
    echo "  Total lung volume: $GT_TOTAL_LUNG_VOLUME mL"
    echo "  Classification: $GT_CLASSIFICATION"
fi

# ============================================================
# Check internal consistency
# ============================================================
VALUES_CONSISTENT="false"
CALCULATED_LAA=""

if [ -n "$REPORTED_TOTAL_LUNG_VOLUME" ] && [ -n "$REPORTED_EMPHYSEMA_VOLUME" ] && [ -n "$REPORTED_LAA_PERCENT" ]; then
    CALCULATED_LAA=$(python3 << PYEOF
try:
    total = float("$REPORTED_TOTAL_LUNG_VOLUME")
    emph = float("$REPORTED_EMPHYSEMA_VOLUME")
    reported = float("$REPORTED_LAA_PERCENT")
    
    if total > 0:
        calculated = (emph / total) * 100.0
        # Check if within 1% tolerance
        if abs(calculated - reported) <= 1.0:
            print("true")
        else:
            print(f"{calculated:.2f}")
    else:
        print("false")
except:
    print("false")
PYEOF
)
    
    if [ "$CALCULATED_LAA" = "true" ]; then
        VALUES_CONSISTENT="true"
    fi
fi

# ============================================================
# Create result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "patient_id": "$PATIENT_ID",
    "slicer_was_running": $SLICER_RUNNING,
    "output_exists": $OUTPUT_EXISTS,
    "output_size_bytes": $OUTPUT_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "json_valid": $JSON_VALID,
    "has_required_fields": $HAS_REQUIRED_FIELDS,
    "reported_total_lung_volume_ml": "$REPORTED_TOTAL_LUNG_VOLUME",
    "reported_emphysema_volume_ml": "$REPORTED_EMPHYSEMA_VOLUME",
    "reported_laa_percent": "$REPORTED_LAA_PERCENT",
    "reported_classification": "$REPORTED_CLASSIFICATION",
    "reported_threshold_hu": "$REPORTED_THRESHOLD",
    "values_internally_consistent": $VALUES_CONSISTENT,
    "segments_found": $SEGMENTS_FOUND,
    "segment_count": $SEGMENT_COUNT,
    "gt_laa_percent": "$GT_LAA_PERCENT",
    "gt_total_lung_volume_ml": "$GT_TOTAL_LUNG_VOLUME",
    "gt_classification": "$GT_CLASSIFICATION",
    "final_screenshot": "/tmp/emphysema_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/emphysema_task_result.json 2>/dev/null || sudo rm -f /tmp/emphysema_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/emphysema_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/emphysema_task_result.json
chmod 666 /tmp/emphysema_task_result.json 2>/dev/null || sudo chmod 666 /tmp/emphysema_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Complete ==="
echo "Result saved to: /tmp/emphysema_task_result.json"
cat /tmp/emphysema_task_result.json