#!/bin/bash
# Export script for TLS Certificate Audit task

echo "=== Exporting TLS Certificate Audit Result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Use Python for robust data extraction
python3 << 'PYEOF'
import json
import os
import shutil
import sqlite3
import tempfile
import re
import sys

# Get task start time
try:
    with open("/tmp/task_start_ts_tls_certificate_audit.txt", "r") as f:
        task_start = int(f.read().strip())
except:
    task_start = 0

# --- HISTORY CHECK ---
history_path = "/home/ga/.config/microsoft-edge/Default/History"
visited_domains = []

if os.path.exists(history_path):
    # Copy DB to temp file to avoid locks
    tmp_db = tempfile.mktemp(suffix=".sqlite")
    try:
        shutil.copy2(history_path, tmp_db)
        conn = sqlite3.connect(tmp_db)
        cursor = conn.cursor()
        
        # Query visits after task start
        # Edge stores time in microseconds since 1601-01-01 (Windows epoch)
        # Unix epoch (1970) is 11644473600 seconds after Windows epoch
        # conversion: (timestamp - 11644473600) * 1000000 = edge_time
        edge_start_time = (task_start + 11644473600) * 1000000
        
        cursor.execute("SELECT url FROM urls WHERE last_visit_time > ?", (edge_start_time,))
        urls = [row[0] for row in cursor.fetchall()]
        
        target_domains = ["treasury.gov", "ssa.gov", "sec.gov", "usa.gov", "cisa.gov"]
        for domain in target_domains:
            if any(domain in url for url in urls):
                visited_domains.append(domain)
                
        conn.close()
    except Exception as e:
        print(f"Error querying history: {e}", file=sys.stderr)
    finally:
        if os.path.exists(tmp_db):
            os.remove(tmp_db)

# --- REPORT CHECK ---
report_path = "/home/ga/Desktop/tls_audit_report.txt"
report_exists = False
report_created_during_task = False
report_content = ""

if os.path.exists(report_path):
    report_exists = True
    stat = os.stat(report_path)
    # Check modification time
    if stat.st_mtime > task_start:
        report_created_during_task = True
    
    # Read content
    try:
        with open(report_path, "r", errors="replace") as f:
            report_content = f.read()
    except Exception as e:
        print(f"Error reading report: {e}", file=sys.stderr)

# --- COMPILE RESULT ---
result = {
    "task_start": task_start,
    "visited_domains": visited_domains,
    "report": {
        "exists": report_exists,
        "created_during_task": report_created_during_task,
        "content_length": len(report_content),
        "content_snippet": report_content  # Verifier will analyze full content
    }
}

with open("/tmp/tls_audit_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(f"Result exported. Visited: {visited_domains}")
print(f"Report exists: {report_exists}, Created during task: {report_created_during_task}")
PYEOF

echo "=== Export Complete ==="