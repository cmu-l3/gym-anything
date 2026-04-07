#!/bin/bash
echo "=== Exporting configure_event_action_script task results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Extract configuration and logs safely using Python
python3 << 'PYEOF'
import os
import json
import subprocess

task_start = 0
if os.path.exists("/tmp/task_start_time.txt"):
    with open("/tmp/task_start_time.txt", "r") as f:
        try:
            task_start = int(f.read().strip())
        except ValueError:
            pass

target_event_id = ""
if os.path.exists("/tmp/target_event_id.txt"):
    with open("/tmp/target_event_id.txt", "r") as f:
        target_event_id = f.read().strip()

script_path = "/home/ga/scripts/log_event.sh"
log_path = "/home/ga/event_activity.log"

# Check script
script_exists = os.path.exists(script_path)
script_executable = os.access(script_path, os.X_OK) if script_exists else False

# Check config files for scripts.script
config_contains_script = False
config_paths = [
    "/home/ga/.seiscomp/scevent.cfg",
    os.path.join(os.environ.get("SEISCOMP_ROOT", "/home/ga/seiscomp"), "etc/scevent.cfg")
]

for cfg in config_paths:
    if os.path.exists(cfg):
        with open(cfg, "r") as f:
            if "scripts.script" in f.read():
                config_contains_script = True
                break

# Check log file
log_exists = os.path.exists(log_path)
log_mtime = int(os.path.getmtime(log_path)) if log_exists else 0

log_content = ""
if log_exists:
    try:
        with open(log_path, "r", errors="ignore") as f:
            log_content = f.read()[:2048]  # Limit size
    except Exception as e:
        log_content = str(e)

# Check scevent status
scevent_running = False
try:
    status_out = subprocess.check_output(
        "su - ga -c 'seiscomp status scevent'", 
        shell=True, stderr=subprocess.STDOUT
    ).decode("utf-8")
    if "is running" in status_out:
        scevent_running = True
except Exception:
    pass

result = {
    "task_start": task_start,
    "target_event_id": target_event_id,
    "script_exists": script_exists,
    "script_executable": script_executable,
    "config_contains_script": config_contains_script,
    "log_exists": log_exists,
    "log_mtime": log_mtime,
    "log_content": log_content,
    "scevent_running": scevent_running
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export Complete ==="