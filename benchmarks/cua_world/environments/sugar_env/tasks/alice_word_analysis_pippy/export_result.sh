#!/bin/bash
# Do NOT use set -e
echo "=== Exporting alice_word_analysis_pippy task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Capture final screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/alice_task_end.png" 2>/dev/null || true

PY_FILE="/home/ga/Documents/alice_analysis.py"
TXT_FILE="/home/ga/Documents/alice_analysis.txt"

# Anti-gaming: Test re-execution of script to ensure it actually works
rm -f /tmp/reexec_success_flag
if [ -f "$PY_FILE" ]; then
    echo "Testing re-execution of script..."
    # Backup original agent output
    cp "$TXT_FILE" /tmp/agent_output.txt 2>/dev/null || true
    rm -f "$TXT_FILE"
    
    # Run script with a timeout (as ga user)
    su - ga -c "cd /home/ga/Documents && timeout 30 python3 $PY_FILE" > /tmp/reexec.log 2>&1
    
    # Check if file was created successfully by the script
    if [ -f "$TXT_FILE" ]; then
        touch /tmp/reexec_success_flag
    fi
    
    # Restore original agent output for content verification
    if [ -f /tmp/agent_output.txt ]; then
        cp /tmp/agent_output.txt "$TXT_FILE"
    fi
fi

# Use Python to safely gather all details and output JSON
python3 << 'PYEOF' > /tmp/alice_word_analysis_result.json
import json
import os
import re

result = {
    "py_exists": False,
    "txt_exists": False,
    "py_size": 0,
    "txt_size": 0,
    "py_modified": False,
    "txt_modified": False,
    "py_has_open": False,
    "py_has_loop": False,
    "txt_content": "",
    "reexec_success": False,
    "error": None
}

try:
    task_start = 0
    if os.path.exists("/tmp/alice_task_start_ts"):
        with open("/tmp/alice_task_start_ts", "r") as f:
            task_start = int(f.read().strip())

    py_file = "/home/ga/Documents/alice_analysis.py"
    txt_file = "/home/ga/Documents/alice_analysis.txt"

    if os.path.exists(py_file):
        result["py_exists"] = True
        result["py_size"] = os.path.getsize(py_file)
        result["py_modified"] = os.path.getmtime(py_file) > task_start
        with open(py_file, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read()
            # Look for basic IO constructs to ensure it's a real script
            result["py_has_open"] = "open(" in content
            result["py_has_loop"] = bool(re.search(r'\b(for|while)\b', content))
            
    if os.path.exists(txt_file):
        result["txt_exists"] = True
        result["txt_size"] = os.path.getsize(txt_file)
        result["txt_modified"] = os.path.getmtime(txt_file) > task_start
        with open(txt_file, "r", encoding="utf-8", errors="ignore") as f:
            result["txt_content"] = f.read()[:5000]  # Grab enough to verify but limit size

    if os.path.exists("/tmp/reexec_success_flag"):
        result["reexec_success"] = True

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

chmod 666 /tmp/alice_word_analysis_result.json
echo "Result saved to /tmp/alice_word_analysis_result.json"
cat /tmp/alice_word_analysis_result.json
echo "=== Export complete ==="