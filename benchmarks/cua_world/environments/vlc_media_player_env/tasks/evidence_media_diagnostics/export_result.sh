#!/bin/bash
echo "=== Exporting evidence_media_diagnostics result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Prepare export directory for processed files
mkdir -p /tmp/evidence_processed
mkdir -p /tmp/evidence_intake_state

# Copy the processed files to /tmp so the verifier can pull them
for f in /home/ga/Documents/evidence_processed/*; do
    if [ -f "$f" ]; then
        cp "$f" /tmp/evidence_processed/ 2>/dev/null || true
    fi
done

# Copy the report to /tmp
if [ -f /home/ga/Documents/evidence_report.json ]; then
    cp /home/ga/Documents/evidence_report.json /tmp/evidence_report.json 2>/dev/null || true
fi

# Create a metadata JSON file with timestamps
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $([ -f /home/ga/Documents/evidence_report.json ] && echo "true" || echo "false"),
    "report_mtime": $(stat -c %Y /home/ga/Documents/evidence_report.json 2>/dev/null || echo "0"),
    "processed_files": {
EOF

# Add mtimes for processed files into the JSON
FIRST="true"
for f in /home/ga/Documents/evidence_processed/*; do
    if [ -f "$f" ]; then
        if [ "$FIRST" = "true" ]; then
            FIRST="false"
        else
            echo "," >> "$TEMP_JSON"
        fi
        FNAME=$(basename "$f")
        MTIME=$(stat -c %Y "$f" 2>/dev/null || echo "0")
        echo "        \"$FNAME\": $MTIME" >> "$TEMP_JSON"
    fi
done

cat >> "$TEMP_JSON" << EOF
    }
}
EOF

# Move result to predictable location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result metadata saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="