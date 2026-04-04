#!/bin/bash
echo "=== Exporting split_transaction_strategy_lots result ==="

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check JStock status
APP_RUNNING=$(pgrep -f "jstock.jar" > /dev/null && echo "true" || echo "false")

# 3. Analyze Portfolio File
PORTFOLIO_FILE="/home/ga/.jstock/1.0.7/UnitedState/portfolios/My Portfolio/buyportfolio.csv"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_MODIFIED="false"

if [ -f "$PORTFOLIO_FILE" ]; then
    FILE_MTIME=$(stat -c %Y "$PORTFOLIO_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# 4. Python script to parse CSV and extract relevant rows (safer than bash)
# We export a JSON object containing the parsed rows for AAPL
python3 -c "
import csv
import json
import sys
import os

filepath = '$PORTFOLIO_FILE'
result = {
    'file_exists': False,
    'aapl_rows': [],
    'total_aapl_units': 0.0
}

if os.path.exists(filepath):
    result['file_exists'] = True
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            for row in reader:
                if row.get('Code') == 'AAPL':
                    # Extract raw values
                    units = float(row.get('Units', 0))
                    comment = row.get('Comment', '')
                    date = row.get('Date', '')
                    price = row.get('Purchase Price', '')
                    
                    result['aapl_rows'].append({
                        'units': units,
                        'comment': comment,
                        'date': date,
                        'price': price
                    })
                    result['total_aapl_units'] += units
    except Exception as e:
        result['error'] = str(e)

print(json.dumps(result))
" > /tmp/parsed_portfolio.json

# 5. Combine everything into final result
# Using jq is standard, but since we might not have it, use python to merge
python3 -c "
import json

with open('/tmp/parsed_portfolio.json', 'r') as f:
    data = json.load(f)

final_result = {
    'task_start': $TASK_START,
    'app_running': '$APP_RUNNING' == 'true',
    'file_modified': '$FILE_MODIFIED' == 'true',
    'screenshot_path': '/tmp/task_final.png',
    'portfolio_data': data
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(final_result, f, indent=2)
"

# Cleanup permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="