#!/bin/bash
echo "=== Exporting MovieLens task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Capture final screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/task_final.png" 2>/dev/null || true

# Run Python script to evaluate agent's artifacts and build JSON output
python3 << 'PYEOF' > /tmp/task_result.json
import json
import os
import subprocess
import time

result = {
    "script_exists": False,
    "script_content": "",
    "txt_exists": False,
    "txt_content": "",
    "txt_mtime": 0,
    "html_exists": False,
    "html_content": "",
    "html_mtime": 0,
    "dynamic_run_success": False,
    "dynamic_txt_exists": False,
    "dynamic_txt_content": "",
    "dynamic_html_exists": False,
    "dynamic_html_content": "",
    "task_start_time": 0
}

try:
    with open("/tmp/task_start_time.txt", "r") as f:
        result["task_start_time"] = int(f.read().strip())
except:
    pass

script_path = "/home/ga/Documents/rating_analyzer.py"
txt_path = "/home/ga/Documents/rating_summary.txt"
html_path = "/home/ga/Documents/rating_summary.html"
data_path = "/home/ga/Documents/ml-100k/u.data"
data_bak = "/home/ga/Documents/ml-100k/u.data.bak"

# 1. Read static outputs
if os.path.exists(script_path):
    result["script_exists"] = True
    try:
        with open(script_path, "r", encoding="utf-8", errors="replace") as f:
            result["script_content"] = f.read()
    except:
        pass

if os.path.exists(txt_path):
    result["txt_exists"] = True
    result["txt_mtime"] = os.path.getmtime(txt_path)
    try:
        with open(txt_path, "r", encoding="utf-8", errors="replace") as f:
            result["txt_content"] = f.read()
    except:
        pass

if os.path.exists(html_path):
    result["html_exists"] = True
    result["html_mtime"] = os.path.getmtime(html_path)
    try:
        with open(html_path, "r", encoding="utf-8", errors="replace") as f:
            result["html_content"] = f.read()
    except:
        pass

# 2. Dynamic Verification (Anti-Gaming Test)
if result["script_exists"]:
    try:
        # Backup original data
        if os.path.exists(data_path):
            os.rename(data_path, data_bak)
        
        # Create synthetic data with known different properties (avg: 2.80, 5-star: 3)
        synthetic_data = "1\t1\t5\t881250949\n1\t2\t5\t881250949\n1\t3\t5\t881250949\n1\t4\t2\t881250949\n1\t5\t2\t881250949\n1\t6\t2\t881250949\n1\t7\t2\t881250949\n1\t8\t2\t881250949\n1\t9\t2\t881250949\n1\t10\t1\t881250949\n"
        with open(data_path, "w") as f:
            f.write(synthetic_data)
        
        # Remove old output files
        if os.path.exists(txt_path): os.remove(txt_path)
        if os.path.exists(html_path): os.remove(html_path)
        
        # Run agent's script as user 'ga'
        try:
            subprocess.run(["su", "-", "ga", "-c", f"python3 {script_path}"], timeout=30, capture_output=True)
            result["dynamic_run_success"] = True
        except subprocess.TimeoutExpired:
            pass # Script timed out
        
        # Check newly generated files
        if os.path.exists(txt_path):
            result["dynamic_txt_exists"] = True
            with open(txt_path, "r", encoding="utf-8", errors="replace") as f:
                result["dynamic_txt_content"] = f.read()
                
        if os.path.exists(html_path):
            result["dynamic_html_exists"] = True
            with open(html_path, "r", encoding="utf-8", errors="replace") as f:
                result["dynamic_html_content"] = f.read()
                
    except Exception as e:
        pass # Handle gracefully
    finally:
        # Restore original dataset
        if os.path.exists(data_bak):
            os.replace(data_bak, data_path)

print(json.dumps(result))
PYEOF

chmod 666 /tmp/task_result.json
echo "=== Export complete ==="