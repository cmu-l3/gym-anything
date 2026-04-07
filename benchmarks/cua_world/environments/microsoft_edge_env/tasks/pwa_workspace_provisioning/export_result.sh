#!/bin/bash
# export_result.sh - Post-task hook for PWA Workspace Provisioning
# Scans for created .desktop files and validates PWA installation.

echo "=== Exporting PWA Workspace Provisioning Result ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Helper to find PWA desktop files
find_pwa_desktop_file() {
    local search_term=$1
    local search_dirs=("/home/ga/.local/share/applications" "/home/ga/Desktop")
    
    # Grep for the search term in the file content (Name or Exec line)
    # Return the first match that was modified after task start
    for dir in "${search_dirs[@]}"; do
        if [ -d "$dir" ]; then
            grep -l -i "$search_term" "$dir"/*.desktop 2>/dev/null | while read -r file; do
                local mtime=$(stat -c %Y "$file")
                if [ "$mtime" -gt "$TASK_START" ]; then
                    echo "$file"
                    return 0
                fi
            done
        fi
    done
}

# Python script to analyze found desktop files
python3 << PYEOF
import json
import os
import glob
import time
import re

task_start = $TASK_START
search_dirs = ["/home/ga/.local/share/applications", "/home/ga/Desktop"]

targets = [
    {"key": "photopea", "name": "Photopea", "url_fragment": "photopea.com"},
    {"key": "excalidraw", "name": "Excalidraw", "url_fragment": "excalidraw.com"},
    {"key": "devdocs", "name": "DevDocs", "url_fragment": "devdocs.io"}
]

results = {
    "task_start": task_start,
    "task_end": $TASK_END,
    "apps": {}
}

def parse_desktop_file(filepath):
    """Extract Name and Exec from .desktop file."""
    info = {"path": filepath, "name": "", "exec": "", "is_pwa": False}
    try:
        with open(filepath, 'r', errors='ignore') as f:
            content = f.read()
            
            # Extract Name
            name_match = re.search(r'^Name=(.+)$', content, re.MULTILINE)
            if name_match:
                info["name"] = name_match.group(1).strip()
                
            # Extract Exec
            exec_match = re.search(r'^Exec=(.+)$', content, re.MULTILINE)
            if exec_match:
                info["exec"] = exec_match.group(1).strip()
                
            # Check if it looks like a PWA launch command
            # Typically: microsoft-edge --profile-directory=Default --app-id=...
            # or: --app=https://...
            if "--app-id=" in info["exec"] or "--app=" in info["exec"]:
                info["is_pwa"] = True
                
    except Exception as e:
        info["error"] = str(e)
    return info

# Scan all .desktop files created/modified after task start
found_files = []
for d in search_dirs:
    if os.path.exists(d):
        for f in glob.glob(os.path.join(d, "*.desktop")):
            try:
                if os.path.getmtime(f) > task_start:
                    found_files.append(parse_desktop_file(f))
            except:
                pass

# Match found files to targets
for target in targets:
    match = None
    # Look for best match
    for f in found_files:
        # Check name or exec command for target keywords
        if (target["key"] in f["name"].lower() or 
            target["url_fragment"] in f["exec"].lower()):
            match = f
            break
    
    if match:
        results["apps"][target["key"]] = {
            "installed": True,
            "path": match["path"],
            "name_found": match["name"],
            "is_valid_pwa": match["is_pwa"],
            "exec_cmd": match["exec"]
        }
    else:
        results["apps"][target["key"]] = {
            "installed": False
        }

# Verify Edge Web Applications directory as secondary confirmation
web_apps_dir = "/home/ga/.config/microsoft-edge/Default/Web Applications"
web_apps_count = 0
if os.path.exists(web_apps_dir):
    # Count directories in Manifest Resources or similar structure
    # Edge stores icons/manifests in subdirectories here
    web_apps_count = len([name for name in os.listdir(web_apps_dir) if os.path.isdir(os.path.join(web_apps_dir, name))])

results["edge_web_apps_count"] = web_apps_count

# Save result
with open("/tmp/pwa_result_temp.json", "w") as f:
    json.dump(results, f, indent=2)

PYEOF

# Move result to final location
mv /tmp/pwa_result_temp.json /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="