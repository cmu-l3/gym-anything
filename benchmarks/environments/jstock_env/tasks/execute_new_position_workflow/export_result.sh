#!/bin/bash
echo "=== Exporting execute_new_position_workflow results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
JSTOCK_DATA_DIR="/home/ga/.jstock/1.0.7/UnitedState"
WATCHLIST_FILE="${JSTOCK_DATA_DIR}/watchlist/My Watchlist/realtimestock.csv"
PORTFOLIO_FILE="${JSTOCK_DATA_DIR}/portfolios/My Portfolio/buyportfolio.csv"
DEPOSIT_FILE="${JSTOCK_DATA_DIR}/portfolios/My Portfolio/depositsummary.csv"

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Extract Data using Python for robustness
# We read the CSVs and dump specific relevant lines to JSON
python3 -c "
import csv
import json
import os
import sys

result = {
    'task_start': $TASK_START,
    'deposit_found': False,
    'deposit_data': {},
    'portfolio_found': False,
    'portfolio_data': {},
    'watchlist_found': False,
    'watchlist_data': {},
    'file_timestamps': {}
}

# Check Deposits
dep_file = '$DEPOSIT_FILE'
if os.path.exists(dep_file):
    result['file_timestamps']['deposit'] = os.path.getmtime(dep_file)
    try:
        with open(dep_file, 'r', encoding='utf-8') as f:
            # JStock CSVs sometimes have weird quoting, use basic reader
            reader = csv.reader(f)
            headers = next(reader, None)
            for row in reader:
                if len(row) >= 2:
                    # Look for 2500
                    amount = row[1].replace(',', '')
                    comment = row[2] if len(row) > 2 else ''
                    if '2500' in amount:
                        result['deposit_found'] = True
                        result['deposit_data'] = {'amount': amount, 'comment': comment}
    except Exception as e:
        print(f'Error reading deposits: {e}', file=sys.stderr)

# Check Portfolio
port_file = '$PORTFOLIO_FILE'
if os.path.exists(port_file):
    result['file_timestamps']['portfolio'] = os.path.getmtime(port_file)
    try:
        with open(port_file, 'r', encoding='utf-8') as f:
            reader = csv.reader(f)
            headers = next(reader, None)
            for row in reader:
                # Look for TSLA
                if len(row) > 1 and 'TSLA' in row[0]: # Code column
                    result['portfolio_found'] = True
                    # row format: Code, Symbol, Date, Units, Purchase Price, ...
                    result['portfolio_data'] = {
                        'code': row[0],
                        'units': row[3],
                        'price': row[4]
                    }
    except Exception as e:
        print(f'Error reading portfolio: {e}', file=sys.stderr)

# Check Watchlist
watch_file = '$WATCHLIST_FILE'
if os.path.exists(watch_file):
    result['file_timestamps']['watchlist'] = os.path.getmtime(watch_file)
    try:
        with open(watch_file, 'r', encoding='utf-8') as f:
            # Skip timestamp=0 line
            lines = f.readlines()
            start_idx = 1 if lines and 'timestamp' in lines[0] else 0
            
            reader = csv.reader(lines[start_idx:])
            headers = next(reader, None)
            
            # Map header indices
            fall_idx = -1
            if headers:
                for i, h in enumerate(headers):
                    if 'Fall Below' in h:
                        fall_idx = i
            
            for row in reader:
                if len(row) > 1 and 'TSLA' in row[0]:
                    result['watchlist_found'] = True
                    fall_val = row[fall_idx] if fall_idx != -1 and len(row) > fall_idx else '0.0'
                    result['watchlist_data'] = {
                        'symbol': row[0],
                        'fall_below': fall_val
                    }
    except Exception as e:
        print(f'Error reading watchlist: {e}', file=sys.stderr)

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# 3. Secure output file permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Export complete."
cat /tmp/task_result.json