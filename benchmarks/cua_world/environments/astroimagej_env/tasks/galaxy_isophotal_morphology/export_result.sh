#!/bin/bash
echo "=== Exporting Galaxy Morphology Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

MEASURE_DIR="/home/ga/AstroImages/measurements"
CSV_PATH="$MEASURE_DIR/galaxy_morphology.csv"
REPORT_PATH="$MEASURE_DIR/morphology_report.txt"

# Initialize Export Vars
CSV_EXISTS="false"
REPORT_EXISTS="false"
REPORT_COPIED="false"

# Check CSV
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    # Ensure standard permissions for verification reads
    chmod 644 "$CSV_PATH" 2>/dev/null || true
fi

# Check and safely copy Report
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    cp "$REPORT_PATH" "/tmp/agent_morphology_report.txt"
    chmod 666 "/tmp/agent_morphology_report.txt"
    REPORT_COPIED="true"
fi

# Check if AIJ is still running
AIJ_RUNNING="false"
if is_aij_running; then
    AIJ_RUNNING="true"
fi

# Create export JSON
TEMP_JSON=$(mktemp /tmp/morphology_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "csv_exists": $CSV_EXISTS,
    "report_exists": $REPORT_EXISTS,
    "report_copied": $REPORT_COPIED,
    "aij_running": $AIJ_RUNNING,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Safe move to /tmp
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

# Safely close AIJ
close_astroimagej

echo "Export complete. Results saved to /tmp/task_result.json"