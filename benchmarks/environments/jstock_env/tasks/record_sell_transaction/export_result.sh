#!/bin/bash
echo "=== Exporting record_sell_transaction result ==="

# 1. Capture final state screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Define paths
PORTFOLIO_DIR="/home/ga/.jstock/1.0.7/UnitedState/portfolios/My Portfolio"
SELL_CSV="${PORTFOLIO_DIR}/sellportfolio.csv"
BUY_CSV="${PORTFOLIO_DIR}/buyportfolio.csv"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Check file status
SELL_FILE_EXISTS="false"
SELL_FILE_MODIFIED="false"
SELL_FILE_SIZE="0"
SELL_FILE_MTIME="0"

if [ -f "$SELL_CSV" ]; then
    SELL_FILE_EXISTS="true"
    SELL_FILE_SIZE=$(stat -c %s "$SELL_CSV")
    SELL_FILE_MTIME=$(stat -c %Y "$SELL_CSV")
    
    if [ "$SELL_FILE_MTIME" -gt "$TASK_START_TIME" ]; then
        SELL_FILE_MODIFIED="true"
    fi
fi

# 4. Check Buy Portfolio integrity (should still contain 3 original records)
BUY_INTEGRITY="false"
if [ -f "$BUY_CSV" ]; then
    # Count AAPL/MSFT/NVDA occurences
    BUY_COUNT=$(grep -E "AAPL|MSFT|NVDA" "$BUY_CSV" | wc -l)
    if [ "$BUY_COUNT" -ge 3 ]; then
        BUY_INTEGRITY="true"
    fi
fi

# 5. Extract Sell Transaction Data using Python for robust CSV parsing
# We are looking for an AAPL entry
# Expected headers: Code, Symbol, Date, Units, Selling Price, ...
PARSED_DATA=$(python3 -c "
import csv
import json
import sys

csv_path = '$SELL_CSV'
result = {
    'found': False,
    'code': None,
    'date': None,
    'units': 0.0,
    'price': 0.0
}

try:
    with open(csv_path, 'r') as f:
        reader = csv.reader(f)
        headers = next(reader) # skip header
        for row in reader:
            if len(row) > 4 and 'AAPL' in row[0]: # Code is column 0
                result['found'] = True
                result['code'] = row[0]
                # Symbol is row[1]
                result['date'] = row[2]
                try:
                    result['units'] = float(row[3])
                except:
                    result['units'] = 0.0
                try:
                    result['price'] = float(row[4])
                except:
                    result['price'] = 0.0
                break # Just get the first AAPL sell found
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({'found': False, 'error': str(e)}))
" 2>/dev/null || echo '{"found": false}')

# 6. Check if app is running
APP_RUNNING=$(pgrep -f "jstock.jar" > /dev/null && echo "true" || echo "false")

# 7. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START_TIME,
    "file_exists": $SELL_FILE_EXISTS,
    "file_modified_during_task": $SELL_FILE_MODIFIED,
    "file_mtime": $SELL_FILE_MTIME,
    "buy_integrity": $BUY_INTEGRITY,
    "parsed_data": $PARSED_DATA,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 8. Save to final location
rm -f /tmp/task_result.json 2>/dev/null
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="