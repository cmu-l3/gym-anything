#!/bin/bash
# Export script for Responsive Design Audit task

echo "=== Exporting Responsive Design Audit Result ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Run Python script to analyze artifacts and generate JSON report
python3 << 'PYEOF'
import os
import json
import glob
import time
import sqlite3
import shutil
from PIL import Image

task_start = int(open("/tmp/task_start_time.txt").read().strip())
output_dir = "/home/ga/Desktop/responsive_audit"
result = {
    "task_start": task_start,
    "dir_exists": False,
    "files": {},
    "report": {
        "exists": False,
        "content_length": 0,
        "content": "",
        "mentions_sites": False,
        "mentions_viewports": False
    },
    "history": {}
}

# Check directory
if os.path.exists(output_dir) and os.path.isdir(output_dir):
    result["dir_exists"] = True
    
    # Check expected files
    sites = ["usa_gov", "weather_gov", "nasa_gov"]
    viewports = ["mobile", "tablet", "desktop"]
    
    for site in sites:
        for vp in viewports:
            base_name = f"{site}_{vp}"
            # Check for png or jpg
            found_file = None
            for ext in [".png", ".jpg", ".jpeg"]:
                path = os.path.join(output_dir, base_name + ext)
                if os.path.exists(path):
                    found_file = path
                    break
            
            if found_file:
                stats = os.stat(found_file)
                width, height = 0, 0
                try:
                    with Image.open(found_file) as img:
                        width, height = img.size
                except Exception as e:
                    print(f"Error reading image {found_file}: {e}")

                result["files"][base_name] = {
                    "exists": True,
                    "path": found_file,
                    "size": stats.st_size,
                    "mtime": int(stats.st_mtime),
                    "created_during_task": int(stats.st_mtime) > task_start,
                    "width": width,
                    "height": height
                }
            else:
                result["files"][base_name] = {"exists": False}

    # Check report
    report_path = os.path.join(output_dir, "responsive_report.txt")
    if os.path.exists(report_path):
        stats = os.stat(report_path)
        try:
            with open(report_path, 'r', errors='ignore') as f:
                content = f.read()
            
            lower_content = content.lower()
            sites_mentioned = all(s in lower_content for s in ["usa.gov", "weather.gov", "nasa.gov"])
            viewports_mentioned = any(v in lower_content for v in ["mobile", "tablet", "desktop", "375", "768", "1440"])
            
            result["report"] = {
                "exists": True,
                "path": report_path,
                "size": stats.st_size,
                "mtime": int(stats.st_mtime),
                "created_during_task": int(stats.st_mtime) > task_start,
                "content_length": len(content),
                "mentions_sites": sites_mentioned,
                "mentions_viewports": viewports_mentioned
            }
        except Exception as e:
             print(f"Error reading report: {e}")

# Check Browser History
history_db = "/home/ga/.config/microsoft-edge/Default/History"
baseline_file = "/tmp/history_baseline.json"
initial_counts = {}

if os.path.exists(baseline_file):
    try:
        with open(baseline_file, 'r') as f:
            initial_counts = json.load(f)
    except:
        pass

if os.path.exists(history_db):
    try:
        shutil.copy2(history_db, "/tmp/history_final.sqlite")
        conn = sqlite3.connect("/tmp/history_final.sqlite")
        cursor = conn.cursor()
        domains = ["usa.gov", "weather.gov", "nasa.gov"]
        
        for domain in domains:
            try:
                cursor.execute(f"SELECT count(*) FROM urls WHERE url LIKE '%{domain}%'")
                curr_count = cursor.fetchone()[0]
                prev_count = initial_counts.get(domain, 0)
                result["history"][domain] = {
                    "visited": curr_count > prev_count,
                    "count": curr_count
                }
            except:
                result["history"][domain] = {"visited": False}
        conn.close()
        os.remove("/tmp/history_final.sqlite")
    except Exception as e:
        print(f"Error checking history: {e}")

# Save Result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result JSON generated at /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="