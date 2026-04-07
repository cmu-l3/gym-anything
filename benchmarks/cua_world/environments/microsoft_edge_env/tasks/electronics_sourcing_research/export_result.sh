#!/bin/bash
# Export script for Electronics Sourcing Research task
set -e

echo "=== Exporting Results ==="

# 1. Take final screenshot of desktop state
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# 2. Gracefully close Edge to ensure bookmarks are flushed to disk
# (Edge writes bookmarks on exit or periodically)
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 3

# 3. Use Python to parse all evidence (bookmarks, files, history)
python3 << 'PYEOF'
import json
import os
import shutil
import sqlite3
import re
import glob

# Constants
TASK_START_FILE = "/tmp/task_start_ts_electronics_sourcing_research.txt"
BOOKMARKS_FILE = "/home/ga/.config/microsoft-edge/Default/Bookmarks"
HISTORY_FILE = "/home/ga/.config/microsoft-edge/Default/History"
REPORT_FILE = "/home/ga/Desktop/sourcing_report.txt"
EVIDENCE_DIR = "/home/ga/Pictures/Evidence"

# Get start time
try:
    with open(TASK_START_FILE, 'r') as f:
        start_time = int(f.read().strip())
except:
    start_time = 0

result = {
    "timestamp": start_time,
    "bookmarks": {"exists": False, "sbc_folder_found": False, "valid_urls": []},
    "report": {"exists": False, "valid_content": False, "vendors_found": [], "prices_found": False},
    "screenshots": {"count": 0, "files": []},
    "history": {"visited_targets": []}
}

# --- Analyze Bookmarks ---
if os.path.exists(BOOKMARKS_FILE):
    result["bookmarks"]["exists"] = True
    try:
        with open(BOOKMARKS_FILE, 'r') as f:
            bm_data = json.load(f)
        
        def find_folder(node, name):
            if node.get('type') == 'folder' and node.get('name') == name:
                return node
            if 'children' in node:
                for child in node['children']:
                    res = find_folder(child, name)
                    if res: return res
            return None
        
        def get_urls_from_node(node):
            urls = []
            if node.get('type') == 'url':
                urls.append(node.get('url'))
            if 'children' in node:
                for child in node['children']:
                    urls.extend(get_urls_from_node(child))
            return urls

        roots = bm_data.get('roots', {})
        sbc_folder = None
        for root in roots.values():
            sbc_folder = find_folder(root, "SBC Tracking")
            if sbc_folder: break
        
        if sbc_folder:
            result["bookmarks"]["sbc_folder_found"] = True
            urls = get_urls_from_node(sbc_folder)
            for url in urls:
                if "adafruit.com" in url: result["bookmarks"]["valid_urls"].append("adafruit")
                if "sparkfun.com" in url: result["bookmarks"]["valid_urls"].append("sparkfun")
                if "digikey.com" in url: result["bookmarks"]["valid_urls"].append("digikey")
    except Exception as e:
        print(f"Error parsing bookmarks: {e}")

# --- Analyze Report ---
if os.path.exists(REPORT_FILE):
    stat = os.stat(REPORT_FILE)
    if stat.st_mtime > start_time:
        result["report"]["exists"] = True
        try:
            with open(REPORT_FILE, 'r', errors='ignore') as f:
                content = f.read().lower()
            
            # Check for vendors
            if "adafruit" in content: result["report"]["vendors_found"].append("adafruit")
            if "sparkfun" in content: result["report"]["vendors_found"].append("sparkfun")
            if "digikey" in content: result["report"]["vendors_found"].append("digikey")
            
            # Check for price patterns ($xx.xx or xx.xx)
            if re.search(r'\$\d+', content) or re.search(r'\d+\.\d{2}', content):
                result["report"]["prices_found"] = True
                
            # Check for stock status keywords
            if any(w in content for w in ["stock", "available", "backorder", "sold out"]):
                result["report"]["valid_content"] = True
        except:
            pass

# --- Analyze Screenshots ---
if os.path.exists(EVIDENCE_DIR):
    pngs = glob.glob(os.path.join(EVIDENCE_DIR, "*.png"))
    valid_pngs = []
    for p in pngs:
        # Check creation time
        if os.path.getmtime(p) > start_time:
            valid_pngs.append(os.path.basename(p))
    
    result["screenshots"]["count"] = len(valid_pngs)
    result["screenshots"]["files"] = valid_pngs

# --- Analyze History ---
# Copy history DB to tmp to avoid locks
if os.path.exists(HISTORY_FILE):
    try:
        shutil.copy2(HISTORY_FILE, "/tmp/history_check.db")
        conn = sqlite3.connect("/tmp/history_check.db")
        cursor = conn.cursor()
        
        targets = ["adafruit.com", "sparkfun.com", "digikey.com"]
        for t in targets:
            cursor.execute("SELECT count(*) FROM urls WHERE url LIKE ?", (f"%{t}%",))
            count = cursor.fetchone()[0]
            if count > 0:
                result["history"]["visited_targets"].append(t)
        conn.close()
    except Exception as e:
        print(f"Error checking history: {e}")

# Save Result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

echo "Export complete. Result saved to /tmp/task_result.json"