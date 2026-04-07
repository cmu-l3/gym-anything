#!/bin/bash
echo "=== Exporting model_turn_prohibition result ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Directories
ACOSTA_DIR="/home/ga/SUMO_Scenarios/bologna_acosta"
OUT_DIR="/home/ga/SUMO_Output"

# Clean previous temp files
rm -f /tmp/original.net.xml /tmp/acosta_restricted.net.xml /tmp/tripinfo_restricted.xml /tmp/restriction_report.txt

# Copy original network for baseline verification
cp "${ACOSTA_DIR}/acosta_buslanes.net.xml" /tmp/original.net.xml

# Check and copy output files if they exist
MODIFIED_NET_EXISTS="false"
if [ -f "${OUT_DIR}/acosta_restricted.net.xml" ]; then
    MODIFIED_NET_EXISTS="true"
    cp "${OUT_DIR}/acosta_restricted.net.xml" /tmp/acosta_restricted.net.xml
    NET_MTIME=$(stat -c %Y "${OUT_DIR}/acosta_restricted.net.xml" 2>/dev/null || echo "0")
fi

TRIPINFO_EXISTS="false"
if [ -f "${OUT_DIR}/tripinfo_restricted.xml" ]; then
    TRIPINFO_EXISTS="true"
    cp "${OUT_DIR}/tripinfo_restricted.xml" /tmp/tripinfo_restricted.xml
    TRIP_MTIME=$(stat -c %Y "${OUT_DIR}/tripinfo_restricted.xml" 2>/dev/null || echo "0")
fi

REPORT_EXISTS="false"
if [ -f "${OUT_DIR}/restriction_report.txt" ]; then
    REPORT_EXISTS="true"
    cp "${OUT_DIR}/restriction_report.txt" /tmp/restriction_report.txt
    REPORT_MTIME=$(stat -c %Y "${OUT_DIR}/restriction_report.txt" 2>/dev/null || echo "0")
fi

# Ensure files are readable by verifier
chmod 644 /tmp/original.net.xml 2>/dev/null || true
chmod 644 /tmp/acosta_restricted.net.xml 2>/dev/null || true
chmod 644 /tmp/tripinfo_restricted.xml 2>/dev/null || true
chmod 644 /tmp/restriction_report.txt 2>/dev/null || true

# Check timestamps for anti-gaming
TIMESTAMPS_VALID="false"
if [ "$MODIFIED_NET_EXISTS" = "true" ] && [ "$NET_MTIME" -gt "$TASK_START" ]; then
    TIMESTAMPS_VALID="true"
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Generate export JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "modified_net_exists": $MODIFIED_NET_EXISTS,
    "tripinfo_exists": $TRIPINFO_EXISTS,
    "report_exists": $REPORT_EXISTS,
    "timestamps_valid": $TIMESTAMPS_VALID
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
echo "=== Export complete ==="