#!/bin/bash
echo "=== Exporting evaluate_nav_app_penetration result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Helper function to check file stats
check_file() {
    local filepath=$1
    if [ -f "$filepath" ]; then
        local size=$(stat -c %s "$filepath" 2>/dev/null || echo "0")
        local mtime=$(stat -c %Y "$filepath" 2>/dev/null || echo "0")
        local created_during="false"
        if [ "$mtime" -gt "$TASK_START" ]; then
            created_during="true"
        fi
        echo "{\"exists\": true, \"size\": $size, \"created_during_task\": $created_during}"
    else
        echo "{\"exists\": false, \"size\": 0, \"created_during_task\": false}"
    fi
}

XML_0=$(check_file "/home/ga/SUMO_Output/tripinfo_0.xml")
XML_25=$(check_file "/home/ga/SUMO_Output/tripinfo_25.xml")
XML_75=$(check_file "/home/ga/SUMO_Output/tripinfo_75.xml")
CSV_REPORT=$(check_file "/home/ga/SUMO_Output/penetration_report.csv")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/nav_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "files": {
        "tripinfo_0": $XML_0,
        "tripinfo_25": $XML_25,
        "tripinfo_75": $XML_75,
        "csv_report": $CSV_REPORT
    }
}
EOF

# Make accessible to verifier
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="