#!/bin/bash
echo "=== Exporting record_portfolio_dividends result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DIV_FILE="/home/ga/.jstock/1.0.7/UnitedState/portfolios/My Portfolio/dividendsummary.csv"

# 1. Gracefully close JStock to force save
# (Agent might have done it, but we double-check)
if pgrep -f "jstock.jar" > /dev/null 2>&1; then
    echo "JStock still running. Sending Alt+F4..."
    su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key alt+F4" 2>/dev/null || true
    sleep 2
    # Confirm "Save?" dialog if it appears
    su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Return" 2>/dev/null || true
    sleep 5
fi

# 2. Capture Final Screenshot
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority import -window root /tmp/task_final.png 2>/dev/null || true

# 3. Check File Metadata
FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_CONTENT_BASE64=""

if [ -f "$DIV_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$DIV_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    
    # Encode content to Base64 to safely transport CSV content inside JSON
    FILE_CONTENT_BASE64=$(base64 -w 0 "$DIV_FILE")
fi

# 4. Parse CSV Content for structured analysis (Python helper)
# We extract the relevant rows into a clean JSON array
PARSED_ROWS=$(python3 -c "
import csv, json, sys, base64

try:
    rows = []
    if '$FILE_EXISTS' == 'true':
        with open('$DIV_FILE', 'r', encoding='utf-8', errors='ignore') as f:
            # Skip header lines that look like configuration if JStock adds weird headers
            # JStock standard CSV has headers on line 1 usually.
            reader = csv.reader(f)
            for row in reader:
                if len(row) >= 4 and 'Code' not in row[0]: # Skip header
                    rows.append({
                        'code': row[0],
                        'symbol': row[1],
                        'date': row[2],
                        'amount': row[3]
                    })
    print(json.dumps(rows))
except Exception as e:
    print('[]')
")

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "file_content_base64": "$FILE_CONTENT_BASE64",
    "parsed_rows": $PARSED_ROWS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="