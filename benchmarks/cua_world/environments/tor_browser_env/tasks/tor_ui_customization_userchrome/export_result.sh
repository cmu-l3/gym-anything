#!/bin/bash
# export_result.sh for tor_ui_customization_userchrome task
# Evaluates the file system and prefs.js safely into a JSON report

echo "=== Exporting tor_ui_customization_userchrome results ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

TASK_START_TS=$(cat /tmp/task_start_ts.txt 2>/dev/null || echo "0")

# Find Tor Browser profile
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

# We will use Python to safely parse and generate the JSON result
python3 << PYEOF > /tmp/task_result.json
import json
import os
import time

result = {
    "profile_found": False,
    "pref_enabled": False,
    "chrome_dir_exists": False,
    "css_file_exists": False,
    "css_file_mtime": 0,
    "css_file_is_new": False,
    "has_comment": False,
    "has_newtab_hidden": False,
    "has_extensions_hidden": False,
    "has_tab_bg_color": False,
    "task_start_ts": ${TASK_START_TS}
}

profile_dir = "${PROFILE_DIR}"

if profile_dir and os.path.exists(profile_dir):
    result["profile_found"] = True
    
    # 1. Check prefs.js
    prefs_file = os.path.join(profile_dir, "prefs.js")
    if os.path.exists(prefs_file):
        with open(prefs_file, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read()
            # Look for the exact preference set to true
            if '"toolkit.legacyUserProfileCustomizations.stylesheets", true' in content:
                result["pref_enabled"] = True

    # 2. Check chrome directory
    chrome_dir = os.path.join(profile_dir, "chrome")
    if os.path.isdir(chrome_dir):
        result["chrome_dir_exists"] = True
        
        # 3. Check userChrome.css
        css_file = os.path.join(chrome_dir, "userChrome.css")
        if os.path.isfile(css_file):
            result["css_file_exists"] = True
            
            # Anti-gaming timestamp check
            mtime = os.path.getmtime(css_file)
            result["css_file_mtime"] = mtime
            if mtime >= result["task_start_ts"]:
                result["css_file_is_new"] = True
                
            # Content checks
            with open(css_file, "r", encoding="utf-8", errors="ignore") as f:
                css_content = f.read()
                
                if "OSINT UI Hardening" in css_content:
                    result["has_comment"] = True
                if "#tabs-newtab-button" in css_content and "display: none" in css_content:
                    result["has_newtab_hidden"] = True
                if "#unified-extensions-button" in css_content and "display: none" in css_content:
                    result["has_extensions_hidden"] = True
                if ".tab-background[selected=\"true\"]" in css_content and "#ffaa00" in css_content.lower():
                    result["has_tab_bg_color"] = True

print(json.dumps(result, indent=2))
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="
cat /tmp/task_result.json