#!/bin/bash
echo "=== Exporting english_letter_frequency_analysis task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Take final screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/task_final.png" 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Run a Python script to compute the EXACT dynamic ground truth directly from the file,
# and parse the agent's output CSV. This prevents any gaming by hardcoding standards.
python3 << PYEOF > /tmp/letter_freq_analysis.json 2>/dev/null || echo '{"error":"parse_failed"}' > /tmp/letter_freq_analysis.json
import json
import os
import string

result = {
    "task_start": ${TASK_START},
    "script_exists": False,
    "script_size": 0,
    "script_mtime": 0,
    "csv_exists": False,
    "csv_size": 0,
    "csv_mtime": 0,
    "csv_header_exact": False,
    "csv_rows": [],
    "gt_counts": {},
    "gt_percs": {},
    "error": None
}

script_path = "/home/ga/Documents/letter_freq.py"
csv_path = "/home/ga/Documents/frequencies.csv"
input_path = "/home/ga/Documents/alice_in_wonderland.txt"

try:
    if os.path.exists(script_path):
        result["script_exists"] = True
        result["script_size"] = os.path.getsize(script_path)
        result["script_mtime"] = os.path.getmtime(script_path)

    if os.path.exists(csv_path):
        result["csv_exists"] = True
        result["csv_size"] = os.path.getsize(csv_path)
        result["csv_mtime"] = os.path.getmtime(csv_path)

        with open(csv_path, 'r', encoding='utf-8', errors='replace') as f:
            lines = [l.strip() for l in f.readlines() if l.strip()]
        
        if lines:
            if lines[0] == "Letter,Count,Percentage":
                result["csv_header_exact"] = True
                lines = lines[1:]
            
            for line in lines:
                parts = [p.strip() for p in line.split(',')]
                if len(parts) >= 3:
                    result["csv_rows"].append({"letter": parts[0], "count": parts[1], "perc": parts[2]})
except Exception as e:
    result["error"] = str(e)

# Compute dynamic ground truth based on the exact file state
try:
    if os.path.exists(input_path):
        with open(input_path, 'r', encoding='utf-8', errors='replace') as f:
            text = f.read().upper()
        
        counts = {char: text.count(char) for char in string.ascii_uppercase}
        total = sum(counts.values())
        result["gt_counts"] = counts
        
        if total > 0:
            result["gt_percs"] = {k: round((v / total) * 100, 2) for k, v in counts.items()}
except Exception as e:
    if not result["error"]:
        result["error"] = "GT error: " + str(e)

print(json.dumps(result))
PYEOF

# Ensure permissions
chmod 666 /tmp/letter_freq_analysis.json
echo "Result parsed and saved to /tmp/letter_freq_analysis.json"
echo "=== Export complete ==="