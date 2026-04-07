#!/bin/bash
echo "=== Exporting Markdown Docs Builder Result ==="
source /workspace/scripts/task_utils.sh

WORKSPACE="/home/ga/workspace/docs_builder"

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Best-effort: focus VSCode and save all open files
focus_vscode_window 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+shift+s 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+k ctrl+s 2>/dev/null || true
sleep 2

# Navigate to workspace, wipe existing distribution, and execute builder
cd "$WORKSPACE"
rm -rf dist
sudo -u ga node src/index.js > /tmp/build.log 2>&1 || true

# Collect all output HTML artifacts, execution logs, and the raw Source code for verification
python3 << 'PYEOF'
import os
import json

workspace = "/home/ga/workspace/docs_builder"
dist_dir = os.path.join(workspace, "dist")
result = {"html_files": {}, "build_log": "", "src_files": {}}

# Read Execution Log
try:
    with open("/tmp/build.log", "r", encoding="utf-8") as f:
        result["build_log"] = f.read()
except Exception:
    pass

# Read Agent's Source Files
src_files_list = ["src/index.js", "src/parser.js", "src/validator.js", "src/assets.js"]
for sf in src_files_list:
    try:
        with open(os.path.join(workspace, sf), "r", encoding="utf-8") as f:
            result["src_files"][sf] = f.read()
    except Exception:
        pass

# Read Final HTML Output
if os.path.exists(dist_dir):
    for root, _, files in os.walk(dist_dir):
        for file in files:
            if file.endswith('.html'):
                rel_path = os.path.relpath(os.path.join(root, file), dist_dir)
                try:
                    with open(os.path.join(root, file), "r", encoding="utf-8") as f:
                        result["html_files"][rel_path] = f.read()
                except Exception:
                    pass

# Dump to task_result.json safely
with open("/tmp/task_result.json", "w", encoding="utf-8") as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "=== Export complete ==="