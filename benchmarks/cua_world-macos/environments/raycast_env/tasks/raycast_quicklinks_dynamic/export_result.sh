#!/bin/bash
# Export: raycast_quicklinks_dynamic
# Reads the agent's Quicklinks export file and records its content.

set -euo pipefail
echo "=== Export: raycast_quicklinks_dynamic ==="

EXPORT_FILE="/Users/lume/Desktop/my_quicklinks.json"
RESULT_FILE="/tmp/raycast_quicklinks_dynamic_result.json"
START_TS=$(cat /tmp/raycast_quicklinks_dynamic_start_ts 2>/dev/null || echo "0")

python3 - "$EXPORT_FILE" "$START_TS" "$RESULT_FILE" << 'PYEOF'
import json, os, sys

export_file, start_ts, result_file = sys.argv[1], int(sys.argv[2]), sys.argv[3]

result = {
    "task_start": start_ts,
    "export_file_exists": False,
    "export_file_size_bytes": 0,
    "export_file_is_new": False,
    "valid_json": False,
    "quicklinks": [],
    "quicklink_count": 0,
}

if os.path.exists(export_file):
    result["export_file_exists"] = True
    st = os.stat(export_file)
    result["export_file_size_bytes"] = st.st_size
    result["export_file_is_new"] = st.st_mtime > start_ts
    try:
        with open(export_file, "r") as f:
            data = json.load(f)
        result["valid_json"] = True
        # Raycast Quicklinks export is a list of {name, link, ...} objects.
        # Some exports may wrap as {"quicklinks": [...]}.
        if isinstance(data, list):
            items = data
        elif isinstance(data, dict) and "quicklinks" in data:
            items = data["quicklinks"]
        else:
            items = []
        normalized = []
        for it in items:
            if not isinstance(it, dict):
                continue
            normalized.append({
                "name": str(it.get("name") or it.get("title") or ""),
                "link": str(it.get("link") or it.get("url") or ""),
                "description": str(it.get("description") or ""),
            })
        result["quicklinks"] = normalized
        result["quicklink_count"] = len(normalized)
    except json.JSONDecodeError as e:
        result["json_error"] = str(e)
    except Exception as e:
        result["read_error"] = str(e)

with open(result_file, "w") as f:
    json.dump(result, f, indent=2)

print(f"exists={result['export_file_exists']} is_new={result['export_file_is_new']} "
      f"count={result['quicklink_count']}")
PYEOF

echo "Result written to: $RESULT_FILE"
echo "=== Export complete ==="
