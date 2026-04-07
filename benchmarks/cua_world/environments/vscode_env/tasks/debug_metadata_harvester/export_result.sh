#!/bin/bash
set -e
echo "=== Exporting Metadata Harvester Result ==="

source /workspace/scripts/task_utils.sh

# Record end time
date +%s > /tmp/task_end_time.txt

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Force VSCode to save any open files
focus_vscode_window 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+shift+s 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+k ctrl+s 2>/dev/null || true
sleep 2

WORKSPACE_DIR="/home/ga/workspace/metadata_harvester"

# Delete any existing DB to ensure we test the agent's current code
rm -f "$WORKSPACE_DIR/output.sqlite"

# Run the agent's harvester script programmatically via Python
# This creates a JSON export containing test evaluations
sudo -u ga python3 << 'PY_EXPORT'
import os
import json
import sqlite3
import subprocess

workspace = "/home/ga/workspace/metadata_harvester"
start_time_file = "/tmp/task_start_time.txt"

# 1. Determine if the file was actually edited
try:
    with open(start_time_file, "r") as f:
        start_time = int(f.read().strip())
    mtime = int(os.path.getmtime(os.path.join(workspace, "harvester.py")))
    file_modified = mtime > start_time
except Exception:
    file_modified = False

# 2. Run the harvester.py script
res = subprocess.run(
    ["python3", "harvester.py"],
    cwd=workspace,
    capture_output=True,
    text=True
)

output_data = {
    "file_modified": file_modified,
    "exit_code": res.returncode,
    "stdout": res.stdout,
    "stderr": res.stderr,
    "db_exists": False,
    "record_count": 0,
    "record_0001_authors": "",
    "record_0001_title": "",
    "record_0027_authors": ""
}

# 3. Inspect the resulting database
db_path = os.path.join(workspace, "output.sqlite")
if os.path.exists(db_path):
    output_data["db_exists"] = True
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        
        # Check Total Count
        cursor.execute("SELECT COUNT(*) FROM records")
        output_data["record_count"] = cursor.fetchone()[0]
        
        # Check Record 0001 (Title & Multi-Author)
        cursor.execute("SELECT author, title FROM records WHERE id='oai:arXiv.org:0704.0001'")
        row1 = cursor.fetchone()
        if row1:
            output_data["record_0001_authors"] = row1[0] if row1[0] else ""
            output_data["record_0001_title"] = row1[1] if row1[1] else ""
            
        # Check Record 0027 (Unicode)
        cursor.execute("SELECT author FROM records WHERE id='oai:arXiv.org:0704.0027'")
        row2 = cursor.fetchone()
        if row2:
            output_data["record_0027_authors"] = row2[0] if row2[0] else ""
            
        conn.close()
    except Exception as e:
        output_data["db_error"] = str(e)

# 4. Save to JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(output_data, f, indent=2)
PY_EXPORT

# Ensure proper permissions for verifier reading
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="