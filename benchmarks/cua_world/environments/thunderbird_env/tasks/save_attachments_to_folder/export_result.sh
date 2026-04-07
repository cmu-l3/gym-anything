#!/bin/bash
echo "=== Exporting save_attachments_to_folder result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Perform file integrity and existence checks via Python
# This handles extraction of sizes and timestamps reliably inside the container
python3 << 'PYEOF'
import json
import os
import time

result = {
    "pdf_exists": False,
    "csv_exists": False,
    "pdf_valid_content": False,
    "csv_valid_content": False,
    "pdf_size": 0,
    "csv_size": 0,
    "pdf_created_during_task": False,
    "csv_created_during_task": False,
    "task_start_time": 0
}

pdf_path = "/home/ga/Documents/ProjectFiles/project_report.pdf"
csv_path = "/home/ga/Documents/ProjectFiles/materials_costs.csv"

# Load task start time
try:
    with open("/tmp/task_start_time.txt", "r") as f:
        result["task_start_time"] = int(f.read().strip())
except Exception:
    result["task_start_time"] = 0

# Check PDF
if os.path.exists(pdf_path):
    result["pdf_exists"] = True
    result["pdf_size"] = os.path.getsize(pdf_path)
    result["pdf_created_during_task"] = os.path.getmtime(pdf_path) > result["task_start_time"]
    
    try:
        with open(pdf_path, "rb") as f:
            header = f.read(4)
            result["pdf_valid_content"] = (header == b"%PDF")
    except Exception:
        pass

# Check CSV
if os.path.exists(csv_path):
    result["csv_exists"] = True
    result["csv_size"] = os.path.getsize(csv_path)
    result["csv_created_during_task"] = os.path.getmtime(csv_path) > result["task_start_time"]
    
    try:
        with open(csv_path, "r", encoding="utf-8", errors="ignore") as f:
            lines = f.readlines()
            result["csv_valid_content"] = len(lines) >= 20 and "Item,Quantity,Unit" in lines[0]
    except Exception:
        pass

# Save results for verifier
with open("/tmp/task_result_data.json", "w") as f:
    json.dump(result, f)
PYEOF

# Safely move JSON to final accessible path
rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/task_result_data.json /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/task_result_data.json

echo "Results exported successfully to /tmp/task_result.json."
cat /tmp/task_result.json
echo "=== Export complete ==="