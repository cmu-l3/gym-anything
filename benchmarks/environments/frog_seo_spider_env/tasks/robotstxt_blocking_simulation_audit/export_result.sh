#!/bin/bash
# Export script for Robots.txt Blocking Simulation task

source /workspace/scripts/task_utils.sh

echo "=== Exporting Robots.txt Simulation Result ==="

take_screenshot /tmp/task_final.png

EXPORT_DIR="/home/ga/Documents/SEO/exports"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")

BLOCKED_CSV="$EXPORT_DIR/blocked_urls.csv"
ALLOWED_CSV="$EXPORT_DIR/allowed_pages.csv"

# Check if SF is running
SF_RUNNING="false"
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

# Python script to analyze the CSVs robustly
python3 << PYEOF
import json
import os
import csv
import sys

blocked_csv_path = "$BLOCKED_CSV"
allowed_csv_path = "$ALLOWED_CSV"
task_start_epoch = float($TASK_START_EPOCH)

result = {
    "sf_running": $SF_RUNNING,
    "blocked_csv_exists": False,
    "allowed_csv_exists": False,
    "blocked_csv_valid_timestamp": False,
    "allowed_csv_valid_timestamp": False,
    "blocked_travel_urls_found": 0,
    "blocked_status_verified": False,
    "allowed_other_urls_found": 0,
    "allowed_status_verified": False,
    "timestamp": "$(date -Iseconds)"
}

def is_file_new(path):
    if not os.path.exists(path): return False
    return os.path.getmtime(path) > task_start_epoch

# Check Blocked CSV
if os.path.exists(blocked_csv_path):
    result["blocked_csv_exists"] = True
    if is_file_new(blocked_csv_path):
        result["blocked_csv_valid_timestamp"] = True
        
        try:
            with open(blocked_csv_path, 'r', encoding='utf-8', errors='ignore') as f:
                # Skip header lines if they exist (SF exports sometimes have metadata at top)
                # But standard CSV exports usually have headers on line 1 or 2
                content = f.read()
                f.seek(0)
                
                # Check for relevant content
                if "travel_2" in content:
                    reader = csv.reader(f)
                    headers = next(reader, [])
                    
                    # Find column indices
                    status_idx = -1
                    url_idx = -1
                    
                    # SF columns are usually "Address", "Status Code", "Status"
                    for i, h in enumerate(headers):
                        h_lower = h.lower()
                        if "address" in h_lower or "url" in h_lower:
                            url_idx = i
                        if "status" in h_lower and "code" not in h_lower: # "Status" column (text)
                            status_idx = i
                        elif "status" in h_lower: # Fallback to any status
                            if status_idx == -1: status_idx = i
                            
                    # Scan rows
                    travel_blocked_count = 0
                    status_ok_count = 0
                    
                    for row in reader:
                        if len(row) <= max(url_idx, status_idx): continue
                        
                        url = row[url_idx]
                        status = row[status_idx]
                        
                        if "travel_2" in url:
                            travel_blocked_count += 1
                            # Check for blocked status
                            # SF reports "Blocked by Robots.txt" in Status column
                            # Or status code 0
                            if "blocked" in status.lower() or "robot" in status.lower() or row[status_idx] == "0":
                                status_ok_count += 1
                                
                    result["blocked_travel_urls_found"] = travel_blocked_count
                    result["blocked_status_verified"] = status_ok_count > 0
        except Exception as e:
            print(f"Error parsing blocked CSV: {e}")

# Check Allowed CSV
if os.path.exists(allowed_csv_path):
    result["allowed_csv_exists"] = True
    if is_file_new(allowed_csv_path):
        result["allowed_csv_valid_timestamp"] = True
        
        try:
            with open(allowed_csv_path, 'r', encoding='utf-8', errors='ignore') as f:
                reader = csv.reader(f)
                headers = next(reader, [])
                
                url_idx = -1
                status_code_idx = -1
                
                for i, h in enumerate(headers):
                    h_lower = h.lower()
                    if "address" in h_lower or "url" in h_lower:
                        url_idx = i
                    if "status code" in h_lower:
                        status_code_idx = i
                
                other_allowed_count = 0
                status_200_count = 0
                
                for row in reader:
                    if len(row) <= max(url_idx, status_code_idx): continue
                    
                    url = row[url_idx]
                    status_code = row[status_code_idx]
                    
                    # Check for non-travel URLs (e.g. mystery)
                    if "travel_2" not in url and "books.toscrape.com" in url:
                        other_allowed_count += 1
                        if "200" in status_code:
                            status_200_count += 1
                            
                result["allowed_other_urls_found"] = other_allowed_count
                result["allowed_status_verified"] = status_200_count > 0
                
        except Exception as e:
            print(f"Error parsing allowed CSV: {e}")

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
    
print("Export analysis complete.")
PYEOF

cat /tmp/task_result.json
echo "=== Export Complete ==="