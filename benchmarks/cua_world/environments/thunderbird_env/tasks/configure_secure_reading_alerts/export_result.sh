#!/bin/bash
set -euo pipefail

echo "=== Exporting Task Results ==="

# 1. Take final screenshot BEFORE closing Thunderbird
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Close Thunderbird gracefully to force it to write prefs.js
echo "Gracefully closing Thunderbird to flush preferences..."
if pgrep -f "thunderbird" > /dev/null; then
    su - ga -c "DISPLAY=:1 wmctrl -c 'Mozilla Thunderbird'" 2>/dev/null || true
    # Wait up to 10 seconds for it to exit
    for i in {1..10}; do
        if ! pgrep -f "thunderbird" > /dev/null; then
            break
        fi
        sleep 1
    done
    # Force kill if it's still hanging
    pkill -f "thunderbird" || true
fi

sleep 2

# 3. Read the timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_MTIME=$(cat /tmp/initial_prefs_mtime.txt 2>/dev/null || echo "0")

# 4. Extract Preferences into JSON using Python
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

python3 - <<EOF > "$TEMP_JSON"
import os, glob, re, json, time

task_start = int($TASK_START)
initial_mtime = int($INITIAL_MTIME)

result = {
    "task_start": task_start,
    "initial_mtime": initial_mtime,
    "prefs_mtime": 0,
    "prefs_modified_during_task": False,
    "prefs": {}
}

profile_dirs = glob.glob('/home/ga/.thunderbird/*default*')
if profile_dirs:
    prefs_path = os.path.join(profile_dirs[0], 'prefs.js')
    if os.path.exists(prefs_path):
        current_mtime = int(os.path.getmtime(prefs_path))
        result["prefs_mtime"] = current_mtime
        result["prefs_modified_during_task"] = current_mtime > initial_mtime
        
        with open(prefs_path, 'r', errors='ignore') as f:
            for line in f:
                match = re.search(r'user_pref\("([^"]+)",\s*(.+?)\);', line)
                if match:
                    key = match.group(1)
                    val = match.group(2).strip()
                    
                    if val == 'true': val = True
                    elif val == 'false': val = False
                    elif val.startswith('"'): val = val.strip('"')
                    else:
                        try: val = int(val)
                        except: pass
                        
                    result["prefs"][key] = val

with open("$TEMP_JSON", "w") as f:
    json.dump(result, f, indent=2)
EOF

# 5. Move JSON to final accessible path
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="