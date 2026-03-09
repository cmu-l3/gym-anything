#!/bin/bash
echo "=== Exporting record_multi_lot_position result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

PORTFOLIO_FILE="/home/ga/.jstock/1.0.7/UnitedState/portfolios/My Portfolio/buyportfolio.csv"

# 1. Take final screenshot
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Check File Stats
if [ -f "$PORTFOLIO_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$PORTFOLIO_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    else
        FILE_MODIFIED="false"
    fi
else
    FILE_EXISTS="false"
    FILE_MODIFIED="false"
fi

# 3. Parse CSV to JSON using Python
# We use Python here to handle CSV quoting/escaping reliably
python3 << PYSCRIPT > /tmp/parsed_portfolio.json
import csv
import json
import os
import sys

csv_path = "$PORTFOLIO_FILE"
result = {
    "rows": [],
    "meta_rows": [],
    "original_preserved": False,
    "error": None
}

if not os.path.exists(csv_path):
    result["error"] = "File not found"
    print(json.dumps(result))
    sys.exit(0)

try:
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
        result["rows"] = rows
        
        # Filter for META
        meta_rows = [row for row in rows if "META" in row.get("Code", "") or "META" in row.get("Symbol", "")]
        result["meta_rows"] = meta_rows
        
        # Check originals (AAPL, MSFT, NVDA)
        originals = ["AAPL", "MSFT", "NVDA"]
        found_originals = 0
        for code in originals:
            for row in rows:
                if code in row.get("Code", ""):
                    found_originals += 1
                    break
        
        if found_originals == 3:
            result["original_preserved"] = True

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYSCRIPT

# 4. Assemble Final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "screenshot_path": "/tmp/task_final.png",
    "portfolio_data": $(cat /tmp/parsed_portfolio.json)
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export complete. Result saved to /tmp/task_result.json"