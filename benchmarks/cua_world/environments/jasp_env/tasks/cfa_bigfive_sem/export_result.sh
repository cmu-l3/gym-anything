#!/bin/bash
echo "=== Exporting CFA Big Five SEM result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

JASP_FILE="/home/ga/Documents/JASP/CFA_BigFive.jasp"
REPORT_FILE="/home/ga/Documents/JASP/CFA_BigFive_Report.txt"

# 1. Check JASP File
if [ -f "$JASP_FILE" ]; then
    JASP_EXISTS="true"
    JASP_SIZE=$(stat -c %s "$JASP_FILE" 2>/dev/null || echo "0")
    JASP_MTIME=$(stat -c %Y "$JASP_FILE" 2>/dev/null || echo "0")
    
    if [ "$JASP_MTIME" -gt "$TASK_START" ]; then
        JASP_NEW="true"
    else
        JASP_NEW="false"
    fi
else
    JASP_EXISTS="false"
    JASP_SIZE="0"
    JASP_NEW="false"
fi

# 2. Check Report File and Content
REPORT_CONTENT=""
CFI_VAL="0"
RMSEA_VAL="0"
REPORT_EXISTS="false"

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    # Read first 2000 chars of report for JSON (avoid huge files)
    REPORT_CONTENT=$(head -c 2000 "$REPORT_FILE" | base64 -w 0)
    
    # Try to extract metrics using grep/regex for the JSON summary
    # Matches formats like "CFI: 0.95" or "CFI 0.95" or "0.95"
    CFI_VAL=$(grep -i "CFI" "$REPORT_FILE" | grep -oE "[0-9]\.[0-9]+" | head -1 || echo "0")
    RMSEA_VAL=$(grep -i "RMSEA" "$REPORT_FILE" | grep -oE "[0-9]\.[0-9]+" | head -1 || echo "0")
fi

# 3. Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 4. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "jasp_file_exists": $JASP_EXISTS,
    "jasp_file_new": $JASP_NEW,
    "jasp_file_size": $JASP_SIZE,
    "report_exists": $REPORT_EXISTS,
    "report_content_b64": "$REPORT_CONTENT",
    "extracted_cfi": "$CFI_VAL",
    "extracted_rmsea": "$RMSEA_VAL",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="