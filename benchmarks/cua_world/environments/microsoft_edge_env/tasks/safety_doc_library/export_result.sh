#!/bin/bash
# Export results for Safety Documentation Library task
set -e

echo "=== Exporting Task Result ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Execute Python script to gather detailed evidence
python3 << 'PYEOF'
import json
import os
import glob
import sqlite3
import shutil
import tempfile
import time
import subprocess

# Paths
base_dir = "/home/ga/Documents/SafetyLibrary"
osha_dir = os.path.join(base_dir, "OSHA")
epa_dir = os.path.join(base_dir, "EPA")
index_path = os.path.join(base_dir, "index.txt")
start_time_path = "/tmp/task_start_time.txt"

# Get task start time
try:
    with open(start_time_path, 'r') as f:
        task_start_time = int(f.read().strip())
except:
    task_start_time = 0

result = {
    "structure": {
        "base_exists": os.path.isdir(base_dir),
        "osha_exists": os.path.isdir(osha_dir),
        "epa_exists": os.path.isdir(epa_dir),
        "index_exists": os.path.isfile(index_path)
    },
    "files": {
        "osha_pdfs": [],
        "epa_pdfs": []
    },
    "index_content": {
        "size": 0,
        "content": "",
        "mentions_osha": False,
        "mentions_epa": False,
        "has_urls": False,
        "line_count": 0
    },
    "history": {
        "visited_osha": False,
        "visited_epa": False
    },
    "timestamps_valid": True
}

def is_pdf(filepath):
    """Check if file has PDF magic bytes."""
    try:
        with open(filepath, 'rb') as f:
            header = f.read(4)
            return header.startswith(b'%PDF')
    except:
        return False

def get_file_info(directory):
    files = []
    if not os.path.isdir(directory):
        return files
    
    for f in os.listdir(directory):
        fpath = os.path.join(directory, f)
        if os.path.isfile(fpath):
            stat = os.stat(fpath)
            # Check modification time against task start
            if stat.st_mtime < task_start_time:
                result["timestamps_valid"] = False
            
            # Only count valid PDFs > 10KB
            is_valid_pdf = is_pdf(fpath)
            size_kb = stat.st_size / 1024
            
            if is_valid_pdf and size_kb > 10:
                files.append({
                    "name": f,
                    "size_kb": size_kb,
                    "mtime": stat.st_mtime
                })
    return files

# Analyze directories
result["files"]["osha_pdfs"] = get_file_info(osha_dir)
result["files"]["epa_pdfs"] = get_file_info(epa_dir)

# Analyze index file
if result["structure"]["index_exists"]:
    stat = os.stat(index_path)
    if stat.st_mtime < task_start_time:
        result["timestamps_valid"] = False
        
    result["index_content"]["size"] = stat.st_size
    try:
        with open(index_path, 'r', errors='ignore') as f:
            content = f.read()
            result["index_content"]["content"] = content[:1000] # Snippet for debugging
            result["index_content"]["mentions_osha"] = "osha" in content.lower()
            result["index_content"]["mentions_epa"] = "epa" in content.lower()
            result["index_content"]["has_urls"] = "http" in content
            result["index_content"]["line_count"] = len(content.splitlines())
    except:
        pass

# Analyze Browser History
history_path = "/home/ga/.config/microsoft-edge/Default/History"
if os.path.exists(history_path):
    try:
        # Copy history to temp to avoid lock
        tmp_fd, tmp_path = tempfile.mkstemp()
        os.close(tmp_fd)
        shutil.copy2(history_path, tmp_path)
        
        conn = sqlite3.connect(tmp_path)
        cursor = conn.cursor()
        
        # Check for OSHA visit
        cursor.execute("SELECT count(*) FROM urls WHERE url LIKE '%osha.gov%'")
        if cursor.fetchone()[0] > 0:
            result["history"]["visited_osha"] = True
            
        # Check for EPA visit
        cursor.execute("SELECT count(*) FROM urls WHERE url LIKE '%epa.gov%'")
        if cursor.fetchone()[0] > 0:
            result["history"]["visited_epa"] = True
            
        conn.close()
        os.unlink(tmp_path)
    except Exception as e:
        print(f"Error checking history: {e}")

# Save result
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Analysis complete. Result saved to /tmp/task_result.json")
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="