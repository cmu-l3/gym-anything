#!/bin/bash
echo "=== Exporting international_field_trip_accounting task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

su - ga -c "$SUGAR_ENV scrot /tmp/trip_task_end.png" 2>/dev/null || true

TASK_START=$(cat /tmp/trip_accounting_start_ts 2>/dev/null || echo "0")
SCRIPT_FILE="/home/ga/Documents/trip_calculator.py"
OUTPUT_FILE="/home/ga/Documents/trip_financial_summary.txt"

export SCRIPT_EXISTS="false"
export OUTPUT_EXISTS="false"
export SCRIPT_SIZE="0"
export OUTPUT_SIZE="0"
export OUTPUT_MODIFIED="false"

if [ -f "$SCRIPT_FILE" ]; then
    SCRIPT_EXISTS="true"
    SCRIPT_SIZE=$(stat --format=%s "$SCRIPT_FILE" 2>/dev/null || echo "0")
fi

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat --format=%s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat --format=%Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        OUTPUT_MODIFIED="true"
    fi
fi

# Use Python to evaluate the ground truth and parse agent output
python3 << 'PYEOF' > /tmp/trip_accounting_result.json
import json
import csv
import os
import re

result = {
    "script_exists": os.environ.get("SCRIPT_EXISTS") == "true",
    "script_size": int(os.environ.get("SCRIPT_SIZE", "0")),
    "output_exists": os.environ.get("OUTPUT_EXISTS") == "true",
    "output_size": int(os.environ.get("OUTPUT_SIZE", "0")),
    "output_modified": os.environ.get("OUTPUT_MODIFIED") == "true",
    "ground_truth": {
        "Total": 0.0,
        "Transport": 0.0,
        "Accommodation": 0.0,
        "Food": 0.0,
        "Activities": 0.0
    },
    "agent_parsed": {},
    "agent_content": "",
    "error": None
}

rates_file = "/home/ga/Documents/rates.json"
expenses_file = "/home/ga/Documents/field_trip_expenses.csv"
output_file = "/home/ga/Documents/trip_financial_summary.txt"

try:
    # Calculate ground truth
    with open(rates_file, 'r') as f:
        rates_data = json.load(f)
    rates = rates_data.get("rates", {})
    rates["USD"] = 1.0
    
    with open(expenses_file, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            cat = row["Category"]
            amt = float(row["Amount"])
            curr = row["Currency"]
            rate = rates.get(curr, 1.0)
            usd_amt = amt / rate
            
            result["ground_truth"]["Total"] += usd_amt
            if cat not in result["ground_truth"]:
                result["ground_truth"][cat] = 0.0
            result["ground_truth"][cat] += usd_amt
            
    # Round ground truth
    for k in result["ground_truth"]:
        result["ground_truth"][k] = round(result["ground_truth"][k], 2)
        
    # Parse agent output
    if result["output_exists"]:
        with open(output_file, 'r') as f:
            content = f.read()
            result["agent_content"] = content[:2000]
            
        # Try to parse values using regex
        # Total Trip Cost: $[X.XX]
        total_match = re.search(r'Total.*Cost:?.*?\$?\s*([0-9,]+\.\d{2})', content, re.IGNORECASE)
        if total_match:
            result["agent_parsed"]["Total"] = float(total_match.group(1).replace(',', ''))
            
        for cat in ["Transport", "Accommodation", "Food", "Activities"]:
            cat_match = re.search(rf'{cat}:?.*?\$?\s*([0-9,]+\.\d{2})', content, re.IGNORECASE)
            if cat_match:
                result["agent_parsed"][cat] = float(cat_match.group(1).replace(',', ''))
                
except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

chmod 666 /tmp/trip_accounting_result.json
echo "Result saved to /tmp/trip_accounting_result.json"
cat /tmp/trip_accounting_result.json
echo "=== Export complete ==="