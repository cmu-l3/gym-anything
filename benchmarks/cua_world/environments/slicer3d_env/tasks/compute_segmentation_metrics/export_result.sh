#!/bin/bash
echo "=== Exporting Compute Segmentation Metrics Result ==="

source /workspace/scripts/task_utils.sh

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
EXPORTS_DIR="/home/ga/Documents/SlicerData/Exports"
OUTPUT_REPORT="$EXPORTS_DIR/segmentation_metrics.json"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/task_final.png ga
sleep 1

# ============================================================
# Check if Slicer is running
# ============================================================
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
fi

# ============================================================
# Try to extract metrics from Slicer scene
# ============================================================
echo "Attempting to extract metrics from Slicer scene..."

if [ "$SLICER_RUNNING" = "true" ]; then
    cat > /tmp/extract_seg_metrics.py << 'PYEOF'
import slicer
import os
import json

output_dir = "/home/ga/Documents/SlicerData/Exports"
os.makedirs(output_dir, exist_ok=True)
output_path = os.path.join(output_dir, "segmentation_metrics.json")

# Check what's loaded
print("Checking loaded data...")

# Find segmentation nodes
seg_nodes = slicer.util.getNodesByClass("vtkMRMLSegmentationNode")
print(f"Found {len(seg_nodes)} segmentation node(s)")

for node in seg_nodes:
    print(f"  - {node.GetName()}")

# Find any tables (Segment Comparison creates a table)
table_nodes = slicer.util.getNodesByClass("vtkMRMLTableNode")
print(f"Found {len(table_nodes)} table node(s)")

metrics_data = {
    "num_segmentations_loaded": len(seg_nodes),
    "segmentation_names": [n.GetName() for n in seg_nodes],
    "num_tables": len(table_nodes)
}

# Try to extract comparison metrics from tables
for table in table_nodes:
    table_name = table.GetName().lower()
    print(f"  Checking table: {table.GetName()}")
    
    if "comparison" in table_name or "segment" in table_name:
        # Try to read Dice and Hausdorff from table
        n_rows = table.GetNumberOfRows()
        n_cols = table.GetNumberOfColumns()
        print(f"    Table has {n_rows} rows, {n_cols} columns")
        
        for col_idx in range(n_cols):
            col_name = table.GetColumnName(col_idx)
            if col_name:
                col_name_lower = col_name.lower()
                
                # Get the value from first data row
                if n_rows > 0:
                    value = table.GetCellText(0, col_idx)
                    try:
                        value_float = float(value)
                        
                        if "dice" in col_name_lower:
                            metrics_data["dice_coefficient"] = value_float
                            print(f"    Found Dice: {value_float}")
                        elif "hausdorff" in col_name_lower and "95" not in col_name_lower and "mean" not in col_name_lower:
                            metrics_data["hausdorff_distance_mm"] = value_float
                            print(f"    Found Hausdorff: {value_float}")
                        elif "hausdorff" in col_name_lower and "95" in col_name_lower:
                            metrics_data["hausdorff_95_mm"] = value_float
                        elif "mean" in col_name_lower and "hausdorff" in col_name_lower:
                            metrics_data["mean_hausdorff_mm"] = value_float
                        elif "volume" in col_name_lower and "similarity" in col_name_lower:
                            metrics_data["volume_similarity"] = value_float
                    except (ValueError, TypeError):
                        pass

# Add segmentation names to metrics
if len(seg_nodes) >= 2:
    metrics_data["compare_segmentation"] = seg_nodes[0].GetName()
    metrics_data["reference_segmentation"] = seg_nodes[1].GetName()
elif len(seg_nodes) == 1:
    metrics_data["compare_segmentation"] = seg_nodes[0].GetName()

# Check if we found the key metrics
if "dice_coefficient" in metrics_data:
    print(f"Successfully extracted Dice: {metrics_data['dice_coefficient']}")
    
    # Save the metrics
    with open(output_path, "w") as f:
        json.dump(metrics_data, f, indent=2)
    print(f"Metrics saved to {output_path}")
else:
    print("Dice coefficient not found in tables")
    # Still save what we have
    with open(output_path, "w") as f:
        json.dump(metrics_data, f, indent=2)

print("Extraction complete")
PYEOF

    # Run extraction script
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/extract_seg_metrics.py --no-main-window > /tmp/slicer_extract.log 2>&1 &
    EXTRACT_PID=$!
    
    # Wait with timeout
    for i in {1..20}; do
        if ! kill -0 $EXTRACT_PID 2>/dev/null; then
            break
        fi
        sleep 1
    done
    kill $EXTRACT_PID 2>/dev/null || true
    
    echo "Extraction script output:"
    cat /tmp/slicer_extract.log 2>/dev/null || true
fi

# ============================================================
# Check for output report file
# ============================================================
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
DICE_COEFFICIENT=""
HAUSDORFF_DISTANCE=""
NUM_SEGMENTATIONS=""

if [ -f "$OUTPUT_REPORT" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$OUTPUT_REPORT" 2>/dev/null || echo "0")
    
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
    
    echo "Found output report: $OUTPUT_REPORT"
    cat "$OUTPUT_REPORT"
    
    # Parse the report
    DICE_COEFFICIENT=$(python3 -c "
import json
with open('$OUTPUT_REPORT') as f:
    data = json.load(f)
print(data.get('dice_coefficient', ''))
" 2>/dev/null || echo "")
    
    HAUSDORFF_DISTANCE=$(python3 -c "
import json
with open('$OUTPUT_REPORT') as f:
    data = json.load(f)
print(data.get('hausdorff_distance_mm', ''))
" 2>/dev/null || echo "")
    
    NUM_SEGMENTATIONS=$(python3 -c "
import json
with open('$OUTPUT_REPORT') as f:
    data = json.load(f)
print(data.get('num_segmentations_loaded', 0))
" 2>/dev/null || echo "0")
else
    echo "Output report not found at $OUTPUT_REPORT"
    
    # Search for any metrics files
    echo "Searching for alternative metrics files..."
    find /home/ga -name "*metric*" -o -name "*comparison*" -o -name "*dice*" 2>/dev/null | head -10
fi

# ============================================================
# Check for segmentation files loaded
# ============================================================
AI_SEG_LOADED="false"
REF_SEG_LOADED="false"

# Check via Slicer's recent files or by examining process
if [ "$NUM_SEGMENTATIONS" -ge 2 ]; then
    AI_SEG_LOADED="true"
    REF_SEG_LOADED="true"
elif [ "$NUM_SEGMENTATIONS" -eq 1 ]; then
    AI_SEG_LOADED="true"
fi

# ============================================================
# Load expected metrics for comparison
# ============================================================
EXPECTED_DICE=""
if [ -f /tmp/expected_metrics.json ]; then
    EXPECTED_DICE=$(python3 -c "
import json
with open('/tmp/expected_metrics.json') as f:
    data = json.load(f)
print(data.get('expected_dice_approx', 0.80))
" 2>/dev/null || echo "0.80")
fi

# ============================================================
# Check windows for evidence of Segment Comparison usage
# ============================================================
SEGMENT_COMPARISON_USED="false"
WINDOWS_LIST=$(DISPLAY=:1 wmctrl -l 2>/dev/null || echo "")

if echo "$WINDOWS_LIST" | grep -qi "Segment\|Comparison\|Compare"; then
    SEGMENT_COMPARISON_USED="true"
fi

# Also check Slicer log
if grep -qi "SegmentComparison\|Segment Comparison" /tmp/slicer_launch.log 2>/dev/null; then
    SEGMENT_COMPARISON_USED="true"
fi

# ============================================================
# Create result JSON
# ============================================================
echo "Creating result JSON..."

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "dice_coefficient": "$DICE_COEFFICIENT",
    "hausdorff_distance_mm": "$HAUSDORFF_DISTANCE",
    "expected_dice_approx": "$EXPECTED_DICE",
    "num_segmentations_loaded": "$NUM_SEGMENTATIONS",
    "ai_segmentation_loaded": $AI_SEG_LOADED,
    "reference_segmentation_loaded": $REF_SEG_LOADED,
    "segment_comparison_used": $SEGMENT_COMPARISON_USED,
    "final_screenshot": "/tmp/task_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/segmentation_metrics_result.json 2>/dev/null || sudo rm -f /tmp/segmentation_metrics_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/segmentation_metrics_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/segmentation_metrics_result.json
chmod 666 /tmp/segmentation_metrics_result.json 2>/dev/null || sudo chmod 666 /tmp/segmentation_metrics_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result saved to /tmp/segmentation_metrics_result.json"
cat /tmp/segmentation_metrics_result.json
echo ""

# Copy the output report for verification if it exists
if [ -f "$OUTPUT_REPORT" ]; then
    cp "$OUTPUT_REPORT" /tmp/agent_metrics_report.json 2>/dev/null || true
    chmod 666 /tmp/agent_metrics_report.json 2>/dev/null || true
fi

echo "=== Export Complete ==="