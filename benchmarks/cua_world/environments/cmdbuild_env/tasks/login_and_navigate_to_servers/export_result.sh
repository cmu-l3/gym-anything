#!/bin/bash
echo "=== Exporting login_and_navigate_to_servers result ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

take_screenshot /tmp/task_final.png

python3 << 'PYEOF'
import sys, json
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

token = get_token()
result = {
    "logged_in": False,
    "server_class_found": False,
    "server_count": 0
}

if token:
    result["logged_in"] = True
    # Check if Server class exists and has records
    for cls_name in ["Server", "VirtualServer", "PhysicalServer", "InternalServer"]:
        count = count_cards(cls_name, token)
        if count > 0:
            result["server_class_found"] = True
            result["server_count"] = count
            result["server_class"] = cls_name
            break

    if not result["server_class_found"]:
        # Try broader search
        classes = find_all_classes(r"[Ss]erver", token)
        for cls_name in classes:
            count = count_cards(cls_name, token)
            if count > 0:
                result["server_class_found"] = True
                result["server_count"] = count
                result["server_class"] = cls_name
                break

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(f"Export: logged_in={result['logged_in']}, server_class={result.get('server_class','N/A')}, count={result['server_count']}")
PYEOF

echo "=== Export complete ==="
