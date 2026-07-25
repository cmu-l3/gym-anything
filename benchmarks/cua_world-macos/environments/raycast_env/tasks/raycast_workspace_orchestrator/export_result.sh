#!/bin/bash
# Export: raycast_workspace_orchestrator
# Reads the generated script, captures file metadata + full content into JSON.

set -euo pipefail
echo "=== Export: raycast_workspace_orchestrator ==="

SCRIPT_FILE="/Users/lume/Documents/Raycast/Script Commands/Workspace/workspace.sh"
RESULT_FILE="/tmp/raycast_workspace_orchestrator_result.json"
START_TS=$(cat /tmp/raycast_workspace_orchestrator_start_ts 2>/dev/null || echo "0")

python3 - "$SCRIPT_FILE" "$START_TS" "$RESULT_FILE" << 'PYEOF'
import json, os, stat, sys

script_file, start_ts, result_file = sys.argv[1], int(sys.argv[2]), sys.argv[3]

result = {
    "task_start": start_ts,
    "script_path": script_file,
    "script_exists": False,
    "script_size_bytes": 0,
    "script_is_new": False,
    "script_is_executable": False,
    "script_content": "",
}

if os.path.exists(script_file):
    result["script_exists"] = True
    st = os.stat(script_file)
    result["script_size_bytes"] = st.st_size
    result["script_is_new"] = st.st_mtime > start_ts
    result["script_is_executable"] = bool(st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH))
    try:
        with open(script_file, "r") as f:
            result["script_content"] = f.read()
    except Exception as e:
        result["read_error"] = str(e)

with open(result_file, "w") as f:
    json.dump(result, f, indent=2)

print(f"script_exists={result['script_exists']}, is_new={result['script_is_new']}, "
      f"executable={result['script_is_executable']}, size={result['script_size_bytes']}")
PYEOF

echo "Result written to: $RESULT_FILE"
echo "=== Export complete ==="
