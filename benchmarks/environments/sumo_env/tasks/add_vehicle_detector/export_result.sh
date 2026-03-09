#!/bin/bash
echo "=== Exporting add_vehicle_detector result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

WORK_DIR="/home/ga/SUMO_Scenarios/bologna_acosta"
DETECTOR_FILE="${WORK_DIR}/acosta_detectors.add.xml"

# Check if detector file was modified
DETECTOR_MODIFIED="false"
ORIGINAL_SIZE=$(stat -c%s /workspace/data/bologna_acosta/acosta_detectors.add.xml 2>/dev/null || echo "0")
CURRENT_SIZE=$(stat -c%s "$DETECTOR_FILE" 2>/dev/null || echo "0")
if [ "$CURRENT_SIZE" != "$ORIGINAL_SIZE" ]; then
    DETECTOR_MODIFIED="true"
fi

# Check if new detector was added
HAS_NEW_DETECTOR="false"
if grep -q 'new_detector_1' "$DETECTOR_FILE" 2>/dev/null; then
    HAS_NEW_DETECTOR="true"
fi

# Check for inductionLoop element
HAS_INDUCTION_LOOP="false"
if grep -q 'inductionLoop.*new_detector_1\|new_detector_1.*inductionLoop' "$DETECTOR_FILE" 2>/dev/null; then
    HAS_INDUCTION_LOOP="true"
fi

# Check if netedit is still running
NETEDIT_RUNNING="false"
if is_netedit_running; then
    NETEDIT_RUNNING="true"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "netedit_running": $NETEDIT_RUNNING,
    "detector_file_modified": $DETECTOR_MODIFIED,
    "has_new_detector": $HAS_NEW_DETECTOR,
    "has_induction_loop": $HAS_INDUCTION_LOOP,
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="
