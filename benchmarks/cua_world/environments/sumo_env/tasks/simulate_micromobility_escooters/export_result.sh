#!/bin/bash
echo "=== Exporting simulate_micromobility_escooters result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

OUTPUT_DIR="/home/ga/SUMO_Output"

# Helper function to verify a file was created/modified DURING the task
check_file_modified() {
    local file_path="$1"
    if [ -f "$file_path" ]; then
        local mtime=$(stat -c %Y "$file_path" 2>/dev/null || echo "0")
        if [ "$mtime" -ge "$TASK_START" ]; then
            echo "true"
        else
            echo "false"
        fi
    else
        echo "missing"
    fi
}

# Check all expected files
ADD_XML=$(check_file_modified "$OUTPUT_DIR/escooter.add.xml")
ROU_XML=$(check_file_modified "$OUTPUT_DIR/escooter_demand.rou.xml")
SUMOCFG=$(check_file_modified "$OUTPUT_DIR/mixed_mobility.sumocfg")
TRIPINFOS=$(check_file_modified "$OUTPUT_DIR/tripinfos.xml")
COLLISIONS=$(check_file_modified "$OUTPUT_DIR/collisions.xml")
REPORT=$(check_file_modified "$OUTPUT_DIR/micromobility_report.txt")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "files_status": {
        "escooter_add_xml": "$ADD_XML",
        "escooter_rou_xml": "$ROU_XML",
        "mixed_mobility_sumocfg": "$SUMOCFG",
        "tripinfos_xml": "$TRIPINFOS",
        "collisions_xml": "$COLLISIONS",
        "micromobility_report_txt": "$REPORT"
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="