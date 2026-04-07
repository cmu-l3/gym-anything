#!/bin/bash
echo "=== Exporting create_service_dependency_map result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Use Python to safely parse all tiddler files and package them into a JSON
# This avoids bash string manipulation nightmares with multi-line text and special characters
python3 << EOF
import os
import json
import re

TIDDLER_DIR = "/home/ga/mywiki/tiddlers"
TARGETS = [
    "UserService", "ProductCatalog", "InventoryService",
    "PaymentGateway", "OrderService", "NotificationService",
    "Service Dependency Map"
]

result = {
    "task_start_time": int($TASK_START),
    "tiddlers": {},
    "gui_saves": 0
}

def find_tiddler_file(title):
    if not os.path.exists(TIDDLER_DIR): return None
    # Check exact match first
    sanitized = re.sub(r'[\/\\\\:*?"<>|]', '_', title)
    exact_path = os.path.join(TIDDLER_DIR, sanitized + ".tid")
    if os.path.exists(exact_path):
        return exact_path
    
    # Fallback to case-insensitive scan
    for f in os.listdir(TIDDLER_DIR):
        if not f.endswith('.tid'): continue
        name = f[:-4].replace('_', ' ')
        if name.lower() == title.lower() or name.lower() == sanitized.lower():
            return os.path.join(TIDDLER_DIR, f)
    return None

for t in TARGETS:
    path = find_tiddler_file(t)
    if path and os.path.exists(path):
        try:
            with open(path, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
            mtime = os.path.getmtime(path)
            result["tiddlers"][t] = {"exists": True, "content": content, "mtime": mtime}
        except Exception as e:
            result["tiddlers"][t] = {"exists": False, "content": "", "mtime": 0, "error": str(e)}
    else:
        result["tiddlers"][t] = {"exists": False, "content": "", "mtime": 0}

# Check TiddlyWiki server log for saves (Anti-gaming check)
log_path = "/home/ga/tiddlywiki.log"
if os.path.exists(log_path):
    try:
        with open(log_path, 'r', encoding='utf-8', errors='ignore') as f:
            log_content = f.read()
            # Count how many times the UI dispatched a save
            result["gui_saves"] = len(re.findall(r"Dispatching 'save' task:", log_content))
    except:
        pass

# Safely write the JSON file
temp_json = "/tmp/result_temp.json"
with open(temp_json, "w", encoding='utf-8') as f:
    json.dump(result, f, ensure_ascii=False)

os.system("rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null")
os.system(f"cp {temp_json} /tmp/task_result.json")
os.system("chmod 666 /tmp/task_result.json")
os.system(f"rm -f {temp_json}")
EOF

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="