#!/bin/bash
set -e
echo "=== Exporting IoT Buoy Firmware Result ==="

WORKSPACE_DIR="/home/ga/workspace/buoy_firmware"
HIDDEN_DATA="/var/lib/app/ground_truth/hidden_telemetry.json"
RESULT_FILE="/tmp/task_result.json"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Best-effort: focus VSCode and save all open files
DISPLAY=:1 wmctrl -a "Visual Studio Code" 2>/dev/null || true
sleep 1
sudo -u ga DISPLAY=:1 xdotool key --delay 200 ctrl+shift+s 2>/dev/null || true
sleep 1
sudo -u ga DISPLAY=:1 xdotool key --delay 200 ctrl+k ctrl+s 2>/dev/null || true
sleep 2

# Remove any stale result file
rm -f "$RESULT_FILE"

# Collect code and run the simulation script against the hidden ground truth
python3 << PYEXPORT
import json
import os
import subprocess
import time

workspace = "$WORKSPACE_DIR"
hidden_data = "$HIDDEN_DATA"
result_file = "$RESULT_FILE"

export_data = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_path": "/tmp/task_final.png",
    "files": {},
    "hidden_output": {},
    "execution_error": None
}

# 1. Collect modified source code
files_to_export = [
    "core/uart_ring_buffer.py",
    "parsers/gps_nmea.py",
    "sensors/salinity_adc.py",
    "sensors/temp_ds18.py",
    "network/lora_decoder.py",
    "simulate_buoy.py"
]

for rel_path in files_to_export:
    path = os.path.join(workspace, rel_path)
    try:
        with open(path, "r", encoding="utf-8") as f:
            export_data["files"][rel_path] = f.read()
    except Exception as e:
        export_data["files"][rel_path] = None
        print(f"Warning: error reading {path}: {e}")

# 2. Execute simulate_buoy.py against the hidden data
try:
    cmd = ["python3", os.path.join(workspace, "simulate_buoy.py"), hidden_data]
    # Run as 'ga' user to prevent permissions cheating, but we need to ensure the script has access to hidden_data.
    # hidden_data is 644, so 'ga' can read it.
    proc = subprocess.run(
        ["sudo", "-u", "ga"] + cmd,
        cwd=workspace,
        capture_output=True,
        text=True,
        timeout=10
    )
    if proc.returncode == 0:
        try:
            export_data["hidden_output"] = json.loads(proc.stdout)
        except json.JSONDecodeError:
            export_data["execution_error"] = "Output was not valid JSON"
    else:
        export_data["execution_error"] = f"Script failed: {proc.stderr}"
except Exception as e:
    export_data["execution_error"] = str(e)

with open(result_file, "w", encoding="utf-8") as out:
    json.dump(export_data, out, indent=2)

print(f"Exported data to {result_file}")
PYEXPORT

chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "=== Export Complete ==="