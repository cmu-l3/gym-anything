#!/bin/bash
echo "=== Exporting task results ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Run Python script to securely parse files, sqlite dbs, and generate JSON result
python3 << 'PYEOF'
import os
import json
import glob
import sqlite3
import re

result = {
    "torrc_modified_after_start": False,
    "torrc_exitnodes_de": False,
    "torrc_strictnodes_1": False,
    "exit_verification_exists": False,
    "exit_verification_size": 0,
    "exit_verification_content": "",
    "report_exists": False,
    "report_size": 0,
    "report_content": "",
    "history_check_torproject": False,
    "history_metrics_torproject": False
}

# 1. Read task start time
try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        start_time = float(f.read().strip())
except Exception:
    start_time = 0

# 2. Check torrc configuration
torrc_paths = glob.glob('/home/ga/.local/share/torbrowser/tbb/*/tor-browser/Browser/TorBrowser/Data/Tor/torrc')
if torrc_paths:
    torrc_path = torrc_paths[0]
    mtime = os.path.getmtime(torrc_path)
    result['torrc_modified_after_start'] = mtime > start_time
    try:
        with open(torrc_path, 'r', errors='ignore') as f:
            content = f.read().lower()
            # Allow optional leading whitespace
            if re.search(r'^\s*exitnodes\s+\{de\}', content, re.MULTILINE):
                result['torrc_exitnodes_de'] = True
            if re.search(r'^\s*strictnodes\s+1', content, re.MULTILINE):
                result['torrc_strictnodes_1'] = True
    except:
        pass

# 3. Check exit_verification.txt
ver_path = '/home/ga/Documents/exit_verification.txt'
if os.path.exists(ver_path):
    result['exit_verification_exists'] = True
    result['exit_verification_size'] = os.path.getsize(ver_path)
    try:
        with open(ver_path, 'r', errors='ignore') as f:
            result['exit_verification_content'] = f.read()[:2000]
    except:
        pass

# 4. Check tor_exit_config_report.txt
rep_path = '/home/ga/Documents/tor_exit_config_report.txt'
if os.path.exists(rep_path):
    result['report_exists'] = True
    result['report_size'] = os.path.getsize(rep_path)
    try:
        with open(rep_path, 'r', errors='ignore') as f:
            result['report_content'] = f.read()[:2000]
    except:
        pass

# 5. Check browsing history for required site visits
places_paths = glob.glob('/home/ga/.local/share/torbrowser/tbb/*/tor-browser/Browser/TorBrowser/Data/Browser/profile.default/places.sqlite')
if places_paths:
    places_db = places_paths[0]
    temp_db = '/tmp/places_copy.sqlite'
    # Copy DB including WAL to avoid locked database errors while Tor Browser is running
    os.system(f'cp "{places_db}" "{temp_db}" 2>/dev/null')
    os.system(f'cp "{places_db}-wal" "{temp_db}-wal" 2>/dev/null')
    os.system(f'cp "{places_db}-shm" "{temp_db}-shm" 2>/dev/null')
    try:
        conn = sqlite3.connect(temp_db)
        c = conn.cursor()
        c.execute("SELECT url FROM moz_places")
        urls = [r[0].lower() for r in c.fetchall()]
        for u in urls:
            if 'check.torproject.org' in u:
                result['history_check_torproject'] = True
            if 'metrics.torproject.org' in u:
                result['history_metrics_torproject'] = True
        conn.close()
    except Exception as e:
        print(f"Error reading sqlite: {e}")

# Save JSON payload
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="