#!/bin/bash
# Export script for match_recognize_stock_analysis

set -e

echo "=== Exporting Task Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Paths
CSV_PATH="/home/ga/Desktop/reversal_patterns.csv"
SQL_PATH="/home/ga/Desktop/find_patterns.sql"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Python script to parse results safely
python3 << PYEOF
import json
import os
import csv
import re

result = {
    "csv_exists": False,
    "sql_exists": False,
    "rows": [],
    "sql_content": "",
    "match_recognize_found": False,
    "files_created_during_task": False
}

# 1. Check CSV
if os.path.exists("${CSV_PATH}"):
    result["csv_exists"] = True
    try:
        # Check timestamp
        mtime = os.path.getmtime("${CSV_PATH}")
        if mtime > float("${TASK_START}"):
            result["files_created_during_task"] = True
            
        with open("${CSV_PATH}", 'r') as f:
            # Handle potential BOM or weird encoding
            content = f.read().strip()
            if content:
                # Naive CSV parse to list of dicts
                reader = csv.DictReader(content.splitlines())
                # Normalize keys to upper case/stripped just in case
                for row in reader:
                    clean_row = {k.strip().upper(): v.strip() for k, v in row.items() if k}
                    result["rows"].append(clean_row)
    except Exception as e:
        result["csv_error"] = str(e)

# 2. Check SQL
if os.path.exists("${SQL_PATH}"):
    result["sql_exists"] = True
    try:
        with open("${SQL_PATH}", 'r') as f:
            content = f.read()
            result["sql_content"] = content
            # Case insensitive check for MATCH_RECOGNIZE
            if re.search(r"MATCH_RECOGNIZE", content, re.IGNORECASE):
                result["match_recognize_found"] = True
    except Exception as e:
        result["sql_error"] = str(e)

# Write result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Export processed.")
PYEOF

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json