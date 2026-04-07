#!/bin/bash
# Export script for NHTSA Fleet Safety Audit
# Collects report content, download file info, and history visits.

echo "=== Exporting NHTSA Audit Result ==="

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# 2. Python script to aggregate all evidence into a single JSON
python3 << 'PYEOF'
import json
import os
import shutil
import sqlite3
import time
import re

# Paths
report_path = "/home/ga/Desktop/fleet_safety_report.txt"
downloads_dir = "/home/ga/Downloads"
history_path = "/home/ga/.config/microsoft-edge/Default/History"
ts_file = "/tmp/task_start_ts_nhtsa_fleet_safety_audit.txt"
baseline_file = "/tmp/nhtsa_history_baseline.txt"
output_json = "/tmp/nhtsa_audit_result.json"

# Load Task Start Time
try:
    with open(ts_file, 'r') as f:
        task_start = int(f.read().strip())
except:
    task_start = 0

# 1. Analyze Report File
report_data = {
    "exists": False,
    "content": "",
    "modified_after_start": False,
    "vehicles_found": [],
    "ratings_found": [],
    "recalls_found": []
}

if os.path.exists(report_path):
    report_data["exists"] = True
    stat = os.stat(report_path)
    if stat.st_mtime > task_start:
        report_data["modified_after_start"] = True
    
    try:
        with open(report_path, 'r', errors='ignore') as f:
            content = f.read()
            report_data["content"] = content
            lower_content = content.lower()
            
            # Check for vehicles
            if "toyota" in lower_content or "camry" in lower_content:
                report_data["vehicles_found"].append("Camry")
            if "ford" in lower_content or "f-150" in lower_content or "f150" in lower_content:
                report_data["vehicles_found"].append("F-150")
            if "jeep" in lower_content or "wrangler" in lower_content:
                report_data["vehicles_found"].append("Wrangler")
                
            # Naive regex checks for data presence (verifier does strict scoring)
            # looking for numbers 1-5 near "star" or "rating"
            if re.search(r'(star|rating).*?[1-5]', lower_content):
                report_data["ratings_found"] = True
            
            # looking for digits near "recall"
            if re.search(r'recall.*?\d', lower_content):
                report_data["recalls_found"] = True
                
    except Exception as e:
        report_data["error"] = str(e)

# 2. Analyze Downloads
download_data = {
    "files": [],
    "has_nhtsa_download": False
}

if os.path.exists(downloads_dir):
    for fname in os.listdir(downloads_dir):
        fpath = os.path.join(downloads_dir, fname)
        if os.path.isfile(fpath):
            stat = os.stat(fpath)
            # Check if created/modified after task start
            if stat.st_mtime > task_start or stat.st_ctime > task_start:
                download_data["files"].append({
                    "name": fname,
                    "size": stat.st_size
                })
                # Check for technical report keywords
                if any(kw in fname.lower() for kw in ["report", "nhtsa", "stability", "esc", "vehicle"]):
                    download_data["has_nhtsa_download"] = True
                # PDF/HTML are likely formats
                if fname.lower().endswith(('.pdf', '.html', '.htm')):
                    download_data["has_nhtsa_download"] = True

# 3. Analyze Browser History
history_data = {
    "visited_nhtsa": False,
    "visited_vehicles": []
}

try:
    if os.path.exists(history_path):
        # Copy to temp to avoid locks
        temp_db = "/tmp/history_check.db"
        shutil.copy2(history_path, temp_db)
        
        conn = sqlite3.connect(temp_db)
        cursor = conn.cursor()
        
        # Check for general NHTSA visit
        cursor.execute("SELECT COUNT(*) FROM urls WHERE url LIKE '%nhtsa.gov%'")
        current_count = cursor.fetchone()[0]
        
        # Load baseline
        baseline_count = 0
        if os.path.exists(baseline_file):
            with open(baseline_file, 'r') as f:
                baseline_count = int(f.read().strip())
        
        if current_count > baseline_count:
            history_data["visited_nhtsa"] = True
            
        # Check for specific vehicle pages (approximate URLs)
        # 2023 Toyota Camry
        cursor.execute("SELECT url FROM urls WHERE url LIKE '%nhtsa.gov%' AND url LIKE '%2023%' AND (url LIKE '%toyota%' OR url LIKE '%camry%')")
        if cursor.fetchone():
            history_data["visited_vehicles"].append("Camry")
            
        # 2023 Ford F-150
        cursor.execute("SELECT url FROM urls WHERE url LIKE '%nhtsa.gov%' AND url LIKE '%2023%' AND (url LIKE '%ford%' OR url LIKE '%f-150%' OR url LIKE '%f150%')")
        if cursor.fetchone():
            history_data["visited_vehicles"].append("F-150")
            
        # 2023 Jeep Wrangler
        cursor.execute("SELECT url FROM urls WHERE url LIKE '%nhtsa.gov%' AND url LIKE '%2023%' AND (url LIKE '%jeep%' OR url LIKE '%wrangler%')")
        if cursor.fetchone():
            history_data["visited_vehicles"].append("Wrangler")
            
        conn.close()
        os.remove(temp_db)
except Exception as e:
    history_data["error"] = str(e)

# Combine results
result = {
    "report": report_data,
    "downloads": download_data,
    "history": history_data,
    "task_timestamp": task_start
}

with open(output_json, 'w') as f:
    json.dump(result, f, indent=2)

print(f"Export complete. Report exists: {report_data['exists']}. Downloads: {len(download_data['files'])}")
PYEOF

echo "=== Export Complete ==="