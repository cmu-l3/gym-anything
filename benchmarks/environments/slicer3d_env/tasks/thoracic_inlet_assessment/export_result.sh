#!/bin/bash
echo "=== Exporting Thoracic Inlet Assessment Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Get task timing
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)
ELAPSED=$((CURRENT_TIME - TASK_START))

echo "Task duration: ${ELAPSED} seconds"

# Get patient ID
PATIENT_ID=$(cat /tmp/lidc_patient_id 2>/dev/null || echo "LIDC-IDRI-0001")
LIDC_DIR="/home/ga/Documents/SlicerData/LIDC"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Define expected output paths
AP_MARKUP="$LIDC_DIR/thoracic_inlet_ap.mrk.json"
TRANS_MARKUP="$LIDC_DIR/thoracic_inlet_trans.mrk.json"
REPORT_FILE="$LIDC_DIR/thoracic_inlet_report.json"

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/task_final.png ga
sleep 1

# Check for agent outputs with various possible names
echo "Checking for agent outputs..."

AP_EXISTS="false"
AP_CREATED_AFTER_START="false"
AP_PATH=""

POSSIBLE_AP_PATHS=(
    "$AP_MARKUP"
    "$LIDC_DIR/ap_measurement.mrk.json"
    "$LIDC_DIR/AP.mrk.json"
    "$LIDC_DIR/thoracic_ap.mrk.json"
    "/home/ga/Documents/thoracic_inlet_ap.mrk.json"
)

for path in "${POSSIBLE_AP_PATHS[@]}"; do
    if [ -f "$path" ]; then
        AP_EXISTS="true"
        AP_PATH="$path"
        AP_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$AP_MTIME" -gt "$TASK_START" ]; then
            AP_CREATED_AFTER_START="true"
        fi
        echo "Found AP measurement at: $path"
        if [ "$path" != "$AP_MARKUP" ]; then
            cp "$path" "$AP_MARKUP" 2>/dev/null || true
        fi
        break
    fi
done

TRANS_EXISTS="false"
TRANS_CREATED_AFTER_START="false"
TRANS_PATH=""

POSSIBLE_TRANS_PATHS=(
    "$TRANS_MARKUP"
    "$LIDC_DIR/trans_measurement.mrk.json"
    "$LIDC_DIR/transverse.mrk.json"
    "$LIDC_DIR/thoracic_trans.mrk.json"
    "/home/ga/Documents/thoracic_inlet_trans.mrk.json"
)

for path in "${POSSIBLE_TRANS_PATHS[@]}"; do
    if [ -f "$path" ]; then
        TRANS_EXISTS="true"
        TRANS_PATH="$path"
        TRANS_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$TRANS_MTIME" -gt "$TASK_START" ]; then
            TRANS_CREATED_AFTER_START="true"
        fi
        echo "Found transverse measurement at: $path"
        if [ "$path" != "$TRANS_MARKUP" ]; then
            cp "$path" "$TRANS_MARKUP" 2>/dev/null || true
        fi
        break
    fi
done

REPORT_EXISTS="false"
REPORT_PATH=""

POSSIBLE_REPORT_PATHS=(
    "$REPORT_FILE"
    "$LIDC_DIR/report.json"
    "$LIDC_DIR/thoracic_report.json"
    "/home/ga/Documents/thoracic_inlet_report.json"
    "/home/ga/thoracic_inlet_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_PATH="$path"
        echo "Found report at: $path"
        if [ "$path" != "$REPORT_FILE" ]; then
            cp "$path" "$REPORT_FILE" 2>/dev/null || true
        fi
        break
    fi
done

# Also check for any Slicer line markups that might have been saved
echo "Checking for any line markups in LIDC directory..."
find "$LIDC_DIR" -name "*.mrk.json" -newer /tmp/task_start_time.txt 2>/dev/null | while read f; do
    echo "  Found: $f"
done

# Check if Slicer is still running
SLICER_RUNNING="false"
pgrep -f "Slicer" > /dev/null && SLICER_RUNNING="true"

# Try to export measurements from Slicer if still running
if [ "$SLICER_RUNNING" = "true" ]; then
    echo "Attempting to export measurements from Slicer..."
    cat > /tmp/export_measurements.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/LIDC"
os.makedirs(output_dir, exist_ok=True)

# Find all line markups
line_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsLineNode")
print(f"Found {len(line_nodes)} line markup(s)")

for i, node in enumerate(line_nodes):
    n_points = node.GetNumberOfControlPoints()
    if n_points >= 2:
        p1 = [0.0, 0.0, 0.0]
        p2 = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(0, p1)
        node.GetNthControlPointPosition(1, p2)
        length = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
        
        name = node.GetName().lower()
        print(f"  Line '{node.GetName()}': {length:.1f} mm")
        
        # Try to save based on name or index
        if 'ap' in name or i == 0:
            out_path = os.path.join(output_dir, "thoracic_inlet_ap.mrk.json")
            slicer.util.saveNode(node, out_path)
            print(f"    Saved as AP measurement")
        elif 'trans' in name or 'horizontal' in name or i == 1:
            out_path = os.path.join(output_dir, "thoracic_inlet_trans.mrk.json")
            slicer.util.saveNode(node, out_path)
            print(f"    Saved as transverse measurement")

print("Export complete")
PYEOF

    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_measurements.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 8
    pkill -f "export_measurements" 2>/dev/null || true
    
    # Re-check for files after export
    [ -f "$AP_MARKUP" ] && AP_EXISTS="true" && AP_CREATED_AFTER_START="true"
    [ -f "$TRANS_MARKUP" ] && TRANS_EXISTS="true" && TRANS_CREATED_AFTER_START="true"
fi

# Copy files to /tmp for verification
echo "Copying files for verification..."
cp "$AP_MARKUP" /tmp/agent_ap_markup.json 2>/dev/null || true
cp "$TRANS_MARKUP" /tmp/agent_trans_markup.json 2>/dev/null || true
cp "$REPORT_FILE" /tmp/agent_report.json 2>/dev/null || true
cp "$GROUND_TRUTH_DIR/${PATIENT_ID}_thoracic_inlet_gt.json" /tmp/ground_truth.json 2>/dev/null || true

# Set permissions
chmod 644 /tmp/agent_ap_markup.json 2>/dev/null || true
chmod 644 /tmp/agent_trans_markup.json 2>/dev/null || true
chmod 644 /tmp/agent_report.json 2>/dev/null || true
chmod 644 /tmp/ground_truth.json 2>/dev/null || true

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_id": "$PATIENT_ID",
    "task_start_time": $TASK_START,
    "task_end_time": $CURRENT_TIME,
    "elapsed_seconds": $ELAPSED,
    "ap_markup_exists": $AP_EXISTS,
    "ap_created_after_start": $AP_CREATED_AFTER_START,
    "ap_markup_path": "$AP_PATH",
    "trans_markup_exists": $TRANS_EXISTS,
    "trans_created_after_start": $TRANS_CREATED_AFTER_START,
    "trans_markup_path": "$TRANS_PATH",
    "report_exists": $REPORT_EXISTS,
    "report_path": "$REPORT_PATH",
    "slicer_running": $SLICER_RUNNING,
    "screenshot_exists": $([ -f "/tmp/task_final.png" ] && echo "true" || echo "false"),
    "ground_truth_path": "/tmp/ground_truth.json",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="