#!/bin/bash
# Export: raycast_snippet_placeholders_live
# Captures snippets export (config) + the TextEdit file (live expansion result)
# + the date the VM thinks it is (so the verifier can match today's date).

set -euo pipefail
echo "=== Export: raycast_snippet_placeholders_live ==="

EXPANSION_FILE="/Users/lume/Desktop/snippet_test.txt"
SNIP_EXPORT="/Users/lume/Desktop/snippets_live.raycastsnippets"
RESULT_FILE="/tmp/raycast_snippet_placeholders_live_result.json"
START_TS=$(cat /tmp/raycast_snippet_placeholders_live_start_ts 2>/dev/null || echo "0")
TODAY=$(cat /tmp/raycast_snippet_placeholders_live_today    2>/dev/null || echo "")

python3 - "$EXPANSION_FILE" "$SNIP_EXPORT" "$START_TS" "$TODAY" "$RESULT_FILE" << 'PYEOF'
import json, os, sys

exp_file, snip_file, start_ts, today, result_file = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4], sys.argv[5]

result = {
    "task_start": start_ts,
    "today_iso": today,
    "exp_file_exists": False,
    "exp_file_is_new": False,
    "exp_file_size_bytes": 0,
    "exp_content": "",
    "snip_file_exists": False,
    "snip_file_is_new": False,
    "snip_file_size_bytes": 0,
    "snip_valid_json": False,
    "snippets": [],
}

# --- TextEdit expansion file ---
if os.path.exists(exp_file):
    result["exp_file_exists"] = True
    st = os.stat(exp_file)
    result["exp_file_size_bytes"] = st.st_size
    result["exp_file_is_new"] = st.st_mtime > start_ts
    try:
        with open(exp_file, "r", errors="replace") as f:
            result["exp_content"] = f.read()
    except Exception as e:
        result["exp_read_error"] = str(e)

# --- snippets_live.raycastsnippets ---
if os.path.exists(snip_file):
    result["snip_file_exists"] = True
    st = os.stat(snip_file)
    result["snip_file_size_bytes"] = st.st_size
    result["snip_file_is_new"] = st.st_mtime > start_ts
    try:
        with open(snip_file, "r", errors="replace") as f:
            data = json.load(f)
        result["snip_valid_json"] = True
        if isinstance(data, list):
            items = data
        elif isinstance(data, dict) and "snippets" in data:
            items = data["snippets"]
        else:
            items = []
        normalized = []
        for it in items:
            if not isinstance(it, dict):
                continue
            normalized.append({
                "name":    str(it.get("name")    or it.get("title")    or ""),
                "keyword": str(it.get("keyword") or it.get("shortcut") or it.get("trigger") or it.get("abbreviation") or ""),
                "text":    str(it.get("text")    or it.get("content")  or it.get("snippet") or it.get("value")        or ""),
            })
        result["snippets"] = normalized
    except json.JSONDecodeError as e:
        result["snip_json_error"] = str(e)
    except Exception as e:
        result["snip_read_error"] = str(e)

with open(result_file, "w") as f:
    json.dump(result, f, indent=2)

print(f"exp_exists={result['exp_file_exists']} is_new={result['exp_file_is_new']} "
      f"snip_exists={result['snip_file_exists']} n_snippets={len(result['snippets'])} today={today}")
PYEOF

echo "Result written to: $RESULT_FILE"
echo "=== Export complete ==="
