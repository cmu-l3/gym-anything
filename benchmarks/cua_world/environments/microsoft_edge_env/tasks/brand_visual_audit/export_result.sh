#!/bin/bash
# export_result.sh - Post-task hook for brand_visual_audit
# Exports report status, content analysis, and history verification

echo "=== Exporting Brand Visual Audit results ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Run Python script to analyze results
python3 << 'PYEOF'
import json
import os
import re
import shutil
import sqlite3
import tempfile
import time

# Paths
REPORT_PATH = "/home/ga/Desktop/brand_audit.txt"
HISTORY_PATH = "/home/ga/.config/microsoft-edge/Default/History"
TASK_START_FILE = "/tmp/task_start_time.txt"
OUTPUT_JSON = "/tmp/task_result.json"

# Read task start time
try:
    with open(TASK_START_FILE, 'r') as f:
        task_start_ts = int(f.read().strip())
except:
    task_start_ts = 0

# --- Analyze Report File ---
report_data = {
    "exists": False,
    "created_during_task": False,
    "size_bytes": 0,
    "content_hex_count": 0,
    "content_font_families": 0,
    "content_font_sizes": 0,
    "mentions_github": False,
    "mentions_python": False
}

if os.path.exists(REPORT_PATH):
    stat = os.stat(REPORT_PATH)
    report_data["exists"] = True
    report_data["size_bytes"] = stat.st_size
    # Check if modified after task start
    if stat.st_mtime > task_start_ts:
        report_data["created_during_task"] = True
    
    # Analyze content
    try:
        with open(REPORT_PATH, 'r', errors='ignore') as f:
            content = f.read()
            lower_content = content.lower()
            
            # Check site mentions
            report_data["mentions_github"] = "github" in lower_content
            report_data["mentions_python"] = "python" in lower_content
            
            # Regex counts
            # Hex codes: #123, #123456, #12345678
            hex_matches = re.findall(r'#[0-9a-fA-F]{3,8}\b', content)
            report_data["content_hex_count"] = len(set(hex_matches)) # Unique colors
            
            # Font families (heuristic keywords or font-family property)
            # Look for common font names or the CSS property
            font_keywords = [
                "sans-serif", "serif", "monospace", "system-ui", "arial", 
                "helvetica", "segoe", "roboto", "inter", "source sans", 
                "fira", "consolas", "menlo", "ubuntu", "cantarell"
            ]
            font_matches = 0
            if "font-family" in lower_content:
                font_matches += 1
            for kw in font_keywords:
                if kw in lower_content:
                    font_matches += 1
            report_data["content_font_families"] = font_matches
            
            # Font sizes: digits followed by units
            size_matches = re.findall(r'\b\d+(\.\d+)?(px|rem|em|pt)\b', lower_content)
            report_data["content_font_sizes"] = len(size_matches)
            
    except Exception as e:
        print(f"Error analyzing report: {e}")

# --- Analyze Browser History ---
history_data = {
    "visited_github": False,
    "visited_python": False
}

if os.path.exists(HISTORY_PATH):
    # Copy DB to temp file to avoid locks
    temp_db = tempfile.mktemp()
    try:
        shutil.copy2(HISTORY_PATH, temp_db)
        conn = sqlite3.connect(temp_db)
        cursor = conn.cursor()
        
        # Calculate WebKit timestamp for task start
        # WebKit epoch: Jan 1 1601. Unix epoch: Jan 1 1970.
        # Difference: 11644473600 seconds.
        # Units: Microseconds.
        webkit_start_time = (task_start_ts + 11644473600) * 1000000
        
        # Query for visits after start time
        query = "SELECT url FROM urls WHERE last_visit_time > ?"
        cursor.execute(query, (webkit_start_time,))
        rows = cursor.fetchall()
        
        for row in rows:
            url = row[0].lower()
            if "github.com" in url:
                history_data["visited_github"] = True
            if "python.org" in url:
                history_data["visited_python"] = True
                
        conn.close()
    except Exception as e:
        print(f"Error analyzing history: {e}")
    finally:
        if os.path.exists(temp_db):
            os.remove(temp_db)

# --- Compile Result ---
result = {
    "task_start_ts": task_start_ts,
    "report": report_data,
    "history": history_data,
    "timestamp": time.time()
}

with open(OUTPUT_JSON, 'w') as f:
    json.dump(result, f, indent=2)

print("Analysis complete. JSON saved.")
PYEOF

# 3. Secure the result file permissions
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="