#!/bin/bash
# export_result.sh - Post-task hook for configure_osint_search_engines
# Extracts configuration from SQLite DBs and checks report

echo "=== Exporting OSINT Configuration Results ==="

# 1. Take Final Screenshot (before killing app)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Kill Edge to flush SQLite WAL (Write-Ahead Logging) to disk
# This is CRITICAL. Chromium DBs are often locked or have data in WAL files.
echo "Stopping Edge to flush databases..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 3

# 3. Define paths
PROFILE_DIR="/home/ga/.config/microsoft-edge/Default"
WEB_DATA="$PROFILE_DIR/Web Data"
HISTORY="$PROFILE_DIR/History"
REPORT_FILE="/home/ga/Desktop/osint_config_report.txt"
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
NOW_TIME=$(date +%s)

# 4. Use Python to inspect the SQLite databases and generate JSON
# We copy DBs to /tmp to avoid permission/lock issues
python3 << PYEOF
import sqlite3
import shutil
import json
import os
import sys
import re

# Paths
web_data_src = "$WEB_DATA"
history_src = "$HISTORY"
report_file = "$REPORT_FILE"
start_time = int("$START_TIME")

result = {
    "configs": {},
    "history": {},
    "report": {
        "exists": False,
        "created_during_task": False,
        "content_valid": False,
        "size": 0,
        "content_snippet": ""
    },
    "timestamp": $NOW_TIME
}

# --- CHECK 1: Search Engine Configurations (Web Data) ---
if os.path.exists(web_data_src):
    try:
        # Copy to temp
        tmp_wd = "/tmp/web_data_check.db"
        shutil.copy2(web_data_src, tmp_wd)
        
        conn = sqlite3.connect(tmp_wd)
        cursor = conn.cursor()
        
        # Keywords to check
        targets = ['wayback', 'crt', 'shodan']
        
        for kw in targets:
            # Query for exact keyword match
            # Note: Chromium stores keywords in 'keywords' table
            # Columns: id, short_name, keyword, favicon_url, url, ...
            try:
                cursor.execute("SELECT short_name, url FROM keywords WHERE keyword = ?", (kw,))
                row = cursor.fetchone()
                
                if row:
                    result["configs"][kw] = {
                        "found": True,
                        "name": row[0],
                        "url": row[1]
                    }
                else:
                    result["configs"][kw] = {"found": False}
            except Exception as e:
                print(f"Error querying keyword {kw}: {e}", file=sys.stderr)
                result["configs"][kw] = {"found": False, "error": str(e)}
        
        conn.close()
        os.remove(tmp_wd)
    except Exception as e:
        print(f"Web Data DB error: {e}", file=sys.stderr)

# --- CHECK 2: History Visits (History) ---
if os.path.exists(history_src):
    try:
        # Copy to temp
        tmp_hist = "/tmp/history_check.db"
        shutil.copy2(history_src, tmp_hist)
        
        conn = sqlite3.connect(tmp_hist)
        cursor = conn.cursor()
        
        # Check for visits to specific domains AFTER task start
        # Chromium time is microseconds since 1601-01-01
        # Linux time is seconds since 1970-01-01
        # Conversion: (linux_time + 11644473600) * 1000000
        
        start_webkit = (start_time + 11644473600) * 1000000
        
        domains = {
            'wayback': 'web.archive.org',
            'crt': 'crt.sh',
            'shodan': 'shodan.io'
        }
        
        for key, domain in domains.items():
            try:
                # We check for URL presence. 
                # For a "test search", the URL usually contains query params, but strict domain check is good enough evidence of use.
                query = f"SELECT url, last_visit_time FROM urls WHERE url LIKE '%{domain}%' AND last_visit_time > {start_webkit}"
                cursor.execute(query)
                rows = cursor.fetchall()
                
                result["history"][key] = {
                    "visited": len(rows) > 0,
                    "count": len(rows)
                }
            except Exception as e:
                print(f"Error querying history {domain}: {e}", file=sys.stderr)
                result["history"][key] = {"visited": False}
                
        conn.close()
        os.remove(tmp_hist)
    except Exception as e:
        print(f"History DB error: {e}", file=sys.stderr)

# --- CHECK 3: Report File ---
if os.path.exists(report_file):
    stat = os.stat(report_file)
    result["report"]["exists"] = True
    result["report"]["size"] = stat.st_size
    
    # Check if modified after start
    if stat.st_mtime > start_time:
        result["report"]["created_during_task"] = True
    
    # Check content
    try:
        with open(report_file, 'r', errors='ignore') as f:
            content = f.read()
            result["report"]["content_snippet"] = content[:200]
            
            # Simple content validation checks
            has_wayback = "wayback" in content.lower()
            has_crt = "crt" in content.lower()
            has_shodan = "shodan" in content.lower()
            
            result["report"]["mentions_wayback"] = has_wayback
            result["report"]["mentions_crt"] = has_crt
            result["report"]["mentions_shodan"] = has_shodan
            
            if has_wayback and has_crt and has_shodan:
                result["report"]["content_valid"] = True
    except Exception as e:
        print(f"Report read error: {e}", file=sys.stderr)

# Output JSON
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

PYEOF

# 5. Fix permissions for copy_from_env
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="