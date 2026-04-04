#!/bin/bash
echo "=== Exporting Measurement Quality Audit Results ==="

source /workspace/scripts/task_utils.sh

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
RESULT_FILE="/tmp/task_result.json"
CASE_ID="amos_0001"

# Get actual case ID
if [ -f /tmp/amos_case_id ]; then
    CASE_ID=$(cat /tmp/amos_case_id)
fi

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || true

# Get task timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Check for Slicer running
SLICER_RUNNING="false"
if pgrep -f "Slicer" > /dev/null; then
    SLICER_RUNNING="true"
fi

# Check for corrected measurements file
CORRECTED_MARKUPS="$AMOS_DIR/corrected_measurements.mrk.json"
CORRECTED_EXISTS="false"
CORRECTED_SIZE=0
CORRECTED_CREATED_DURING_TASK="false"

if [ -f "$CORRECTED_MARKUPS" ]; then
    CORRECTED_EXISTS="true"
    CORRECTED_SIZE=$(stat -c%s "$CORRECTED_MARKUPS" 2>/dev/null || echo 0)
    CORRECTED_MTIME=$(stat -c%Y "$CORRECTED_MARKUPS" 2>/dev/null || echo 0)
    if [ "$CORRECTED_MTIME" -gt "$TASK_START" ]; then
        CORRECTED_CREATED_DURING_TASK="true"
    fi
fi

# Check for audit report
AUDIT_REPORT="$AMOS_DIR/measurement_audit_report.json"
REPORT_EXISTS="false"
REPORT_SIZE=0
REPORT_CREATED_DURING_TASK="false"

if [ -f "$AUDIT_REPORT" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c%s "$AUDIT_REPORT" 2>/dev/null || echo 0)
    REPORT_MTIME=$(stat -c%Y "$AUDIT_REPORT" 2>/dev/null || echo 0)
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
fi

# Copy files to /tmp for verification
if [ -f "$CORRECTED_MARKUPS" ]; then
    cp "$CORRECTED_MARKUPS" /tmp/corrected_measurements.mrk.json 2>/dev/null || true
    chmod 644 /tmp/corrected_measurements.mrk.json 2>/dev/null || true
fi

if [ -f "$AUDIT_REPORT" ]; then
    cp "$AUDIT_REPORT" /tmp/measurement_audit_report.json 2>/dev/null || true
    chmod 644 /tmp/measurement_audit_report.json 2>/dev/null || true
fi

# Copy trainee measurements for reference
if [ -f "$AMOS_DIR/trainee_measurements.mrk.json" ]; then
    cp "$AMOS_DIR/trainee_measurements.mrk.json" /tmp/trainee_measurements.mrk.json 2>/dev/null || true
    chmod 644 /tmp/trainee_measurements.mrk.json 2>/dev/null || true
fi

# Copy ground truth for verifier
GT_FILE="$GROUND_TRUTH_DIR/${CASE_ID}_measurement_audit_gt.json"
if [ -f "$GT_FILE" ]; then
    cp "$GT_FILE" /tmp/measurement_audit_gt.json 2>/dev/null || true
    chmod 644 /tmp/measurement_audit_gt.json 2>/dev/null || true
fi

# Calculate elapsed time
ELAPSED=$((TASK_END - TASK_START))

# Check if Slicer has any markups (try to export from running Slicer)
MARKUPS_IN_SCENE=0
if [ "$SLICER_RUNNING" = "true" ]; then
    # Try to export markups from Slicer
    cat > /tmp/export_markups.py << 'PYEOF'
import slicer
import os
import json

output_dir = "/home/ga/Documents/SlicerData/AMOS"
os.makedirs(output_dir, exist_ok=True)

# Find all line markups
lineNodes = slicer.util.getNodesByClass("vtkMRMLMarkupsLineNode")
print(f"Found {len(lineNodes)} line markups in scene")

# Look for corrected measurements
corrected_nodes = []
for node in lineNodes:
    name = node.GetName()
    print(f"  Markup: {name}")
    if "corrected" in name.lower():
        corrected_nodes.append(node)

print(f"Found {len(corrected_nodes)} corrected markup(s)")

# If we found corrected markups and no file exists yet, try to save them
corrected_path = os.path.join(output_dir, "corrected_measurements.mrk.json")
if corrected_nodes and not os.path.exists(corrected_path):
    # Create a temporary scene with just the corrected markups
    markups_data = {"markups": []}
    for node in corrected_nodes:
        # Save individual node
        temp_path = os.path.join("/tmp", f"{node.GetName()}.mrk.json")
        slicer.util.saveNode(node, temp_path)
    print(f"Exported corrected markups to individual files")
PYEOF

    timeout 10 sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_markups.py --no-main-window > /tmp/export_markups.log 2>&1 || true
    sleep 2
fi

# Check screenshot exists
SCREENSHOT_EXISTS="false"
if [ -f /tmp/task_final_state.png ]; then
    SCREENSHOT_EXISTS="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "elapsed_seconds": $ELAPSED,
    "slicer_was_running": $SLICER_RUNNING,
    "corrected_markups_exists": $CORRECTED_EXISTS,
    "corrected_markups_size": $CORRECTED_SIZE,
    "corrected_created_during_task": $CORRECTED_CREATED_DURING_TASK,
    "audit_report_exists": $REPORT_EXISTS,
    "audit_report_size": $REPORT_SIZE,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "case_id": "$CASE_ID"
}
EOF

# Move to final location with permission handling
rm -f "$RESULT_FILE" 2>/dev/null || sudo rm -f "$RESULT_FILE" 2>/dev/null || true
cp "$TEMP_JSON" "$RESULT_FILE" 2>/dev/null || sudo cp "$TEMP_JSON" "$RESULT_FILE"
chmod 666 "$RESULT_FILE" 2>/dev/null || sudo chmod 666 "$RESULT_FILE" 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Results Summary ==="
echo "Slicer running: $SLICER_RUNNING"
echo "Corrected markups: $CORRECTED_EXISTS (${CORRECTED_SIZE} bytes, created during task: $CORRECTED_CREATED_DURING_TASK)"
echo "Audit report: $REPORT_EXISTS (${REPORT_SIZE} bytes, created during task: $REPORT_CREATED_DURING_TASK)"
echo "Elapsed time: ${ELAPSED}s"
echo ""
echo "Result saved to: $RESULT_FILE"
cat "$RESULT_FILE"
echo ""
echo "=== Export Complete ==="