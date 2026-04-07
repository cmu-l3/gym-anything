#!/bin/bash
# export_result.sh for public_lab_kiosk_configuration
# Flushes Tor Browser preferences and extracts the modified states

echo "=== Exporting task results ==="

# Capture final state screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Gently close Tor Browser to force it to flush settings to prefs.js
echo "Flushing browser settings..."
WINDOW_ID=$(DISPLAY=:1 wmctrl -l | grep -iE "tor browser" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    DISPLAY=:1 wmctrl -i -c "$WINDOW_ID" 2>/dev/null || true
    sleep 2
fi

# Ensure processes are closing to unlock files
pkill -15 -u ga -f "tor-browser" 2>/dev/null || true
pkill -15 -u ga -f "firefox.*TorBrowser" 2>/dev/null || true
sleep 3

# Check for directory creation
DIR_EXISTS="false"
DIR_MTIME=0
if [ -d "/home/ga/Desktop/LabDownloads" ]; then
    DIR_EXISTS="true"
    DIR_MTIME=$(stat -c %Y "/home/ga/Desktop/LabDownloads" 2>/dev/null || echo "0")
fi

# Find Tor Browser profile directory
PROFILE_DIR=""
for candidate in \
    "/home/ga/.local/share/torbrowser/tbb/x86_64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default" \
    "/home/ga/.local/share/torbrowser/tbb/aarch64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default" \
    "/home/ga/.local/share/torbrowser/tbb/tor-browser/Browser/TorBrowser/Data/Browser/profile.default"
do
    if [ -d "$candidate" ]; then
        PROFILE_DIR="$candidate"
        break
    fi
done

# Use a Python script to reliably parse user_pref() entries from prefs.js (and user.js)
# Output a clean JSON representing the final state for the verifier.
python3 << PYEOF
import os
import re
import json
import time

task_start_ts = 0
try:
    with open('/tmp/task_start_timestamp', 'r') as f:
        task_start_ts = int(f.read().strip())
except:
    pass

profile_dir = "${PROFILE_DIR}"
prefs_file = os.path.join(profile_dir, "prefs.js")
user_file = os.path.join(profile_dir, "user.js")

prefs = {}

def parse_mozilla_prefs(filepath):
    if not os.path.exists(filepath):
        return
    with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
        for line in f:
            line = line.strip()
            # Match: user_pref("key", value);
            match = re.match(r'^user_pref\("([^"]+)",\s*(.*)\);$', line)
            if match:
                key = match.group(1)
                val_str = match.group(2)
                
                # Parse the value
                if val_str == "true":
                    prefs[key] = True
                elif val_str == "false":
                    prefs[key] = False
                elif val_str.startswith('"') and val_str.endswith('"'):
                    # JSON loads helps unescape strings
                    try:
                        prefs[key] = json.loads(val_str)
                    except:
                        prefs[key] = val_str[1:-1]
                else:
                    try:
                        prefs[key] = int(val_str)
                    except:
                        prefs[key] = val_str

parse_mozilla_prefs(prefs_file)
parse_mozilla_prefs(user_file) # user.js takes precedence if agent created it

result = {
    "task_start_timestamp": task_start_ts,
    "dir_exists": "${DIR_EXISTS}" == "true",
    "dir_mtime": int("${DIR_MTIME}" or "0"),
    "download_folderList": prefs.get("browser.download.folderList"),
    "download_dir": prefs.get("browser.download.dir"),
    "download_useDownloadDir": prefs.get("browser.download.useDownloadDir"),
    "startup_homepage": prefs.get("browser.startup.homepage"),
    "ui_customization_state": prefs.get("browser.uiCustomization.state")
}

# Write out the resulting JSON
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result JSON saved to /tmp/task_result.json:"
cat /tmp/task_result.json
echo "=== Export complete ==="