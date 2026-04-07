#!/bin/bash
echo "=== Exporting implement_low_emission_zone result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

OUT_DIR="/home/ga/SUMO_Output"

# Helper function to verify file existence and age
check_file() {
    if [ -f "$1" ]; then
        mtime=$(stat -c %Y "$1" 2>/dev/null || echo "0")
        if [ "$mtime" -gt "$TASK_START" ]; then
            echo "true"
        else
            echo "false_old"
        fi
    else
        echo "false"
    fi
}

NET_CREATED=$(check_file "$OUT_DIR/pasubio_lez.net.xml")
ROU_CREATED=$(check_file "$OUT_DIR/pasubio_lez.rou.xml")
CFG_CREATED=$(check_file "$OUT_DIR/run_lez.sumocfg")
TRIP_CREATED=$(check_file "$OUT_DIR/lez_tripinfo.xml")
REP_CREATED=$(check_file "$OUT_DIR/lez_report.txt")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "files": {
        "net_xml": "$NET_CREATED",
        "rou_xml": "$ROU_CREATED",
        "cfg_sumocfg": "$CFG_CREATED",
        "tripinfo_xml": "$TRIP_CREATED",
        "report_txt": "$REP_CREATED"
    }
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="