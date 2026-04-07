#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Secure Web Application Result ==="

WORKSPACE_DIR="/home/ga/workspace/securenotes"
RESULT_FILE="/tmp/security_remediation_result.json"

# Best-effort: focus VSCode and save all open files
focus_vscode_window 2>/dev/null || true
sleep 1

echo "Saving all files..."
safe_xdotool ga :1 key --delay 200 ctrl+shift+s 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+k ctrl+s 2>/dev/null || true
sleep 2

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Remove any stale result file
rm -f "$RESULT_FILE"

# Collect all relevant source files and check syntax
python3 << PYEXPORT
import json, os, subprocess

workspace = "$WORKSPACE_DIR"
task_start_time = int(open("/tmp/task_start_time.txt").read().strip()) if os.path.exists("/tmp/task_start_time.txt") else 0

files_to_export = [
    "app.js",
    "routes/auth.js",
    "routes/notes.js",
    "routes/files.js",
    "routes/api.js",
    "views/notes.ejs",
    "package.json"
]

result = {
    "files": {},
    "syntax_checks": {},
    "mtime_checks": {}
}

for rel_path in files_to_export:
    path = os.path.join(workspace, rel_path)
    try:
        with open(path, "r", encoding="utf-8") as f:
            result["files"][rel_path] = f.read()
            
        mtime = int(os.path.getmtime(path))
        result["mtime_checks"][rel_path] = {
            "mtime": mtime,
            "modified_during_task": mtime > task_start_time
        }
        
        # Syntax check for JS files
        if path.endswith(".js"):
            proc = subprocess.run(["node", "-c", path], capture_output=True, text=True)
            result["syntax_checks"][rel_path] = {
                "valid": proc.returncode == 0,
                "error": proc.stderr if proc.returncode != 0 else ""
            }
    except FileNotFoundError:
        result["files"][rel_path] = None
        result["syntax_checks"][rel_path] = {"valid": False, "error": "File not found"}
    except Exception as e:
        result["files"][rel_path] = None
        result["syntax_checks"][rel_path] = {"valid": False, "error": str(e)}

with open("$RESULT_FILE", "w", encoding="utf-8") as out:
    json.dump(result, out, indent=2)

print(f"Exported files to $RESULT_FILE")
PYEXPORT

# Fix permissions
chmod 666 "$RESULT_FILE" 2>/dev/null || sudo chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "=== Export Complete ==="