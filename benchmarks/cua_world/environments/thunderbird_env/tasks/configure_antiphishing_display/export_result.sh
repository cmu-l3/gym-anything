#!/bin/bash
set -euo pipefail

echo "=== Exporting task results ==="

# 1. Capture final screenshot before closing
echo "Capturing final state screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Gracefully close Thunderbird to force preferences to flush to disk
echo "Flushing preferences to disk..."
su - ga -c "DISPLAY=:1 wmctrl -c 'Thunderbird'" 2>/dev/null || true
sleep 3
# If still running, kill it
pkill -f "thunderbird" 2>/dev/null || true
sleep 2

# 3. Parse prefs.js and generate result JSON securely using Python
echo "Parsing Thunderbird preferences..."
python3 << 'EOF'
import json
import re
import os

prefs_path = "/home/ga/.thunderbird/default-release/prefs.js"
start_time_path = "/tmp/task_start_time.txt"

start_time = 0
if os.path.exists(start_time_path):
    with open(start_time_path, "r") as f:
        try:
            start_time = int(f.read().strip())
        except:
            pass

prefs_mtime = 0
if os.path.exists(prefs_path):
    prefs_mtime = int(os.path.getmtime(prefs_path))

# Defaults mirror the insecure injected start state
prefs = {
    "html_as": 0,
    "show_headers": 1,
    "condensed": True,
    "disable_remote": False,
    "doc_fonts": 1
}

if os.path.exists(prefs_path):
    with open(prefs_path, "r", encoding="utf-8", errors="ignore") as f:
        content = f.read()

    m1 = re.search(r'user_pref\("mailnews\.display\.html_as",\s*(\d+)\);', content)
    if m1: prefs["html_as"] = int(m1.group(1))

    m2 = re.search(r'user_pref\("mail\.show_headers",\s*(\d+)\);', content)
    if m2: prefs["show_headers"] = int(m2.group(1))

    m3 = re.search(r'user_pref\("mail\.showCondensedAddresses",\s*(true|false)\);', content)
    if m3: prefs["condensed"] = (m3.group(1) == "true")

    m4 = re.search(r'user_pref\("mailnews\.message_display\.disable_remote_image",\s*(true|false)\);', content)
    if m4: prefs["disable_remote"] = (m4.group(1) == "true")

    m5 = re.search(r'user_pref\("browser\.display\.use_document_fonts",\s*(\d+)\);', content)
    if m5: prefs["doc_fonts"] = int(m5.group(1))

output = {
    "task_start_time": start_time,
    "prefs_mtime": prefs_mtime,
    "prefs_modified_during_task": prefs_mtime > start_time,
    "prefs": prefs,
    "screenshot_exists": os.path.exists("/tmp/task_final.png")
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(output, f)
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result JSON saved to /tmp/task_result.json:"
cat /tmp/task_result.json
echo -e "\n=== Export complete ==="