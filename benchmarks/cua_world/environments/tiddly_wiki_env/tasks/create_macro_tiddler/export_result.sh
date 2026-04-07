#!/bin/bash
echo "=== Exporting create_macro_tiddler result ==="

# Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Extract information safely using Python
python3 << 'EOF'
import json
import os
import urllib.request
import urllib.error

tiddler_dir = "/home/ga/mywiki/tiddlers"

def get_file_content(path):
    try:
        with open(path, 'r', encoding='utf-8') as f:
            return f.read()
    except Exception:
        return ""

def get_api_content(title):
    try:
        url = "http://localhost:8080/recipes/default/tiddlers/" + urllib.parse.quote(title)
        req = urllib.request.urlopen(url)
        data = json.loads(req.read().decode('utf-8'))
        return {
            "text": data.get("text", ""),
            "tags": data.get("tags", "")
        }
    except Exception:
        return {"text": "", "tags": ""}

# Find Macro file
macro_files = [f for f in os.listdir(tiddler_dir) if "projectstatusmacro" in f.lower().replace(" ", "")]
macro_path = os.path.join(tiddler_dir, macro_files[0]) if macro_files else ""

# Find Dashboard file
dash_files = [f for f in os.listdir(tiddler_dir) if "activeprojects" in f.lower().replace(" ", "") or "active_projects" in f.lower()]
dash_path = os.path.join(tiddler_dir, dash_files[0]) if dash_files else ""

# Start time for anti-gaming checks
try:
    with open("/tmp/task_start_time.txt", "r") as f:
        start_time = int(f.read().strip())
except Exception:
    start_time = 0

macro_mtime = int(os.path.getmtime(macro_path)) if macro_path else 0
dash_mtime = int(os.path.getmtime(dash_path)) if dash_path else 0

result = {
    "macro_file_exists": bool(macro_path),
    "macro_created_during_task": macro_mtime > start_time,
    "macro_file_content": get_file_content(macro_path),
    "macro_api_data": get_api_content("ProjectStatusMacro"),
    
    "dash_file_exists": bool(dash_path),
    "dash_created_during_task": dash_mtime > start_time,
    "dash_file_content": get_file_content(dash_path),
    "dash_api_data": get_api_content("Active Projects"),
    
    "screenshot_exists": os.path.exists("/tmp/task_final.png")
}

with open("/tmp/task_result.json", "w", encoding='utf-8') as f:
    json.dump(result, f, ensure_ascii=False)
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result JSON saved to /tmp/task_result.json"
echo "=== Export complete ==="