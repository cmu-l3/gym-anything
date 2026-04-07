#!/bin/bash
echo "=== Exporting compute_station_distances results ==="

# Record final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

CSV_FILE="/home/ga/Documents/station_distances.csv"
SUM_FILE="/home/ga/Documents/distance_summary.txt"

echo "Bundling outputs and ground truth..."

# Use Python to safely read file contents and metadata, combined with the hidden ground truth
python3 << 'PYEOF'
import json
import os

def safe_read(filepath):
    if not os.path.exists(filepath):
        return ""
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            return f.read()
    except Exception as e:
        return f"ERROR_READING: {str(e)}"

def get_mtime(filepath):
    try:
        return int(os.stat(filepath).st_mtime)
    except:
        return 0

# Retrieve task start time
try:
    with open("/tmp/task_start_time.txt", "r") as f:
        task_start = int(f.read().strip())
except:
    task_start = 0

csv_path = "/home/ga/Documents/station_distances.csv"
sum_path = "/home/ga/Documents/distance_summary.txt"
gt_path = "/tmp/ground_truth/gt.json"

# Load Ground Truth
try:
    with open(gt_path, "r") as f:
        gt_data = json.load(f)
except Exception as e:
    gt_data = {"error": f"Failed to load ground truth: {e}"}

# Build export package
export_data = {
    "task_start_time": task_start,
    "csv_exists": os.path.exists(csv_path),
    "csv_mtime": get_mtime(csv_path),
    "csv_content": safe_read(csv_path),
    "sum_exists": os.path.exists(sum_path),
    "sum_mtime": get_mtime(sum_path),
    "sum_content": safe_read(sum_path),
    "ground_truth": gt_data
}

# Write out safely
temp_json = "/tmp/temp_result.json"
with open(temp_json, "w") as f:
    json.dump(export_data, f)
PYEOF

# Move securely with permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/temp_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f /tmp/temp_result.json

echo "Result JSON saved to /tmp/task_result.json"
echo "=== Export complete ==="