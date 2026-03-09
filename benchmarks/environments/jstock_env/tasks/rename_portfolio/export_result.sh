#!/bin/bash
echo "=== Exporting rename_portfolio results ==="

# Paths
JSTOCK_DATA_DIR="/home/ga/.jstock/1.0.7/UnitedState"
PORTFOLIOS_DIR="${JSTOCK_DATA_DIR}/portfolios"
NEW_PORTFOLIO_DIR="${PORTFOLIOS_DIR}/Tech Growth Fund"
OLD_PORTFOLIO_DIR="${PORTFOLIOS_DIR}/My Portfolio"
RESULT_FILE="/tmp/task_result.json"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Use Python to check filesystem state and parse CSV robustly
python3 << PYEOF
import json
import os
import csv
import time

result = {
    "task_start_timestamp": $TASK_START_TIME,
    "export_timestamp": time.time(),
    "new_dir_exists": False,
    "old_dir_exists": False,
    "csv_exists": False,
    "csv_mtime": 0,
    "transactions": [],
    "app_running": False
}

new_dir = "$NEW_PORTFOLIO_DIR"
old_dir = "$OLD_PORTFOLIO_DIR"
csv_path = os.path.join(new_dir, "buyportfolio.csv")

# Check directories
if os.path.isdir(new_dir):
    result["new_dir_exists"] = True

if os.path.isdir(old_dir):
    # Check if it still has the csv
    if os.path.exists(os.path.join(old_dir, "buyportfolio.csv")):
        result["old_dir_exists"] = True

# Check CSV content
if os.path.isfile(csv_path):
    result["csv_exists"] = True
    result["csv_mtime"] = os.path.getmtime(csv_path)
    
    try:
        with open(csv_path, 'r', encoding='utf-8') as f:
            # JStock CSVs might have a BOM or specific encoding, handle generally
            reader = csv.DictReader(f)
            for row in reader:
                # Extract key fields
                # Remove quotes if manually parsed or rely on csv module
                code = row.get("Code", "").strip()
                units = row.get("Units", "0").strip()
                price = row.get("Purchase Price", "0").strip()
                
                if code: # Skip empty rows
                    try:
                        result["transactions"].append({
                            "code": code,
                            "units": float(units),
                            "price": float(price)
                        })
                    except ValueError:
                        pass # Ignore parsing errors for non-numeric
    except Exception as e:
        print(f"Error parsing CSV: {e}")

# Check if app is running
try:
    if os.system("pgrep -f 'jstock.jar' > /dev/null") == 0:
        result["app_running"] = True
except:
    pass

# Write result
with open("$RESULT_FILE", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

# Fix permissions
chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "Result exported to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export complete ==="