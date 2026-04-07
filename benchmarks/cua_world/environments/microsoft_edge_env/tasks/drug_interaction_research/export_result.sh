#!/bin/bash
# export_result.sh for drug_interaction_research

echo "=== Exporting Drug Interaction Research Result ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Kill Edge to ensure databases (History, Bookmarks) are flushed to disk
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 3

# 3. Run Python script to extract evidence
python3 << 'PYEOF'
import json
import os
import sqlite3
import shutil
import time
import re
import sys

# Paths
TASK_START_FILE = "/tmp/task_start_time.txt"
REPORT_FILE = "/home/ga/Desktop/drug_interaction_report.txt"
DOWNLOADS_DIR = "/home/ga/Downloads"
HISTORY_DB = "/home/ga/.config/microsoft-edge/Default/History"
BOOKMARKS_FILE = "/home/ga/.config/microsoft-edge/Default/Bookmarks"
OUTPUT_JSON = "/tmp/task_result.json"

# Load Task Start Time
try:
    with open(TASK_START_FILE, 'r') as f:
        task_start_time = int(f.read().strip())
except:
    task_start_time = 0

result = {
    "report": {
        "exists": False,
        "modified_after_start": False,
        "size": 0,
        "content_check": {
            "has_warfarin": False,
            "has_lisinopril": False,
            "has_metformin": False,
            "has_safety_keywords": False
        }
    },
    "history": {
        "visited_authoritative": False,
        "domains_visited": []
    },
    "downloads": {
        "count_new": 0,
        "files": []
    },
    "bookmarks": {
        "folder_exists": False,
        "valid_links_count": 0,
        "folder_name_match": False
    }
}

# --- CHECK REPORT ---
if os.path.exists(REPORT_FILE):
    stat = os.stat(REPORT_FILE)
    result["report"]["exists"] = True
    result["report"]["size"] = stat.st_size
    result["report"]["modified_after_start"] = stat.st_mtime > task_start_time
    
    try:
        with open(REPORT_FILE, 'r', errors='ignore') as f:
            content = f.read().lower()
            result["report"]["content_check"]["has_warfarin"] = "warfarin" in content
            result["report"]["content_check"]["has_lisinopril"] = "lisinopril" in content
            result["report"]["content_check"]["has_metformin"] = "metformin" in content
            
            keywords = ["interaction", "bleeding", "hypoglycemia", "renal", "potassium", "monitor", "risk", "inr", "contraindication"]
            found_keywords = [k for k in keywords if k in content]
            result["report"]["content_check"]["has_safety_keywords"] = len(found_keywords) >= 2
    except Exception as e:
        print(f"Error reading report: {e}")

# --- CHECK DOWNLOADS ---
if os.path.exists(DOWNLOADS_DIR):
    new_files = []
    for f in os.listdir(DOWNLOADS_DIR):
        fp = os.path.join(DOWNLOADS_DIR, f)
        if os.path.isfile(fp):
            stat = os.stat(fp)
            if stat.st_mtime > task_start_time:
                new_files.append(f)
    result["downloads"]["count_new"] = len(new_files)
    result["downloads"]["files"] = new_files

# --- CHECK HISTORY ---
if os.path.exists(HISTORY_DB):
    temp_db = "/tmp/history_copy.sqlite"
    try:
        shutil.copy2(HISTORY_DB, temp_db)
        conn = sqlite3.connect(temp_db)
        cursor = conn.cursor()
        
        # Check visits to authoritative domains
        auth_domains = ["medlineplus.gov", "dailymed.nlm.nih.gov", "fda.gov", "drugs.com", "nih.gov", "mayoclinic.org"]
        query_parts = [f"url LIKE '%{d}%'" for d in auth_domains]
        query = f"SELECT url FROM urls WHERE {' OR '.join(query_parts)}"
        
        cursor.execute(query)
        rows = cursor.fetchall()
        
        if rows:
            result["history"]["visited_authoritative"] = True
            # Extract unique domains for feedback
            visited = set()
            for row in rows:
                url = row[0]
                for d in auth_domains:
                    if d in url:
                        visited.add(d)
            result["history"]["domains_visited"] = list(visited)
            
        conn.close()
    except Exception as e:
        print(f"Error checking history: {e}")
    finally:
        if os.path.exists(temp_db):
            os.remove(temp_db)

# --- CHECK BOOKMARKS ---
if os.path.exists(BOOKMARKS_FILE):
    try:
        with open(BOOKMARKS_FILE, 'r') as f:
            bk_data = json.load(f)
            
        def find_folder(node, target_name):
            if node.get('type') == 'folder' and node.get('name', '').strip().lower() == target_name.lower():
                return node
            
            if 'children' in node:
                for child in node['children']:
                    res = find_folder(child, target_name)
                    if res: return res
            return None

        folder = None
        for root in bk_data.get('roots', {}).values():
            folder = find_folder(root, "Patient Safety References")
            if folder: break
            
        if folder:
            result["bookmarks"]["folder_exists"] = True
            result["bookmarks"]["folder_name_match"] = True
            
            # Count authoritative links inside
            valid_count = 0
            auth_domains = ["medlineplus.gov", "dailymed.nlm.nih.gov", "fda.gov", "drugs.com", "nih.gov", "mayoclinic.org"]
            
            for child in folder.get('children', []):
                if child.get('type') == 'url':
                    url = child.get('url', '')
                    if any(d in url for d in auth_domains):
                        valid_count += 1
            
            result["bookmarks"]["valid_links_count"] = valid_count
            
    except Exception as e:
        print(f"Error checking bookmarks: {e}")

# Save Result
with open(OUTPUT_JSON, 'w') as f:
    json.dump(result, f, indent=2)

print("Analysis complete. JSON saved.")
PYEOF

# 4. Copy to final output location with permissive permissions
rm -f /tmp/drug_interaction_result.json 2>/dev/null || true
cp /tmp/task_result.json /tmp/drug_interaction_result.json
chmod 666 /tmp/drug_interaction_result.json

echo "=== Export Complete ==="