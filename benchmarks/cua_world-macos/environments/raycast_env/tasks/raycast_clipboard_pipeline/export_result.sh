#!/bin/bash
# Export: raycast_clipboard_pipeline
# Reads the TextEdit output file and the snippets export.

set -euo pipefail
echo "=== Export: raycast_clipboard_pipeline ==="

CLIP_OUT="/Users/lume/Desktop/clipboard_test.txt"
SNIP_OUT="/Users/lume/Desktop/snippets.raycastsnippets"
RESULT_FILE="/tmp/raycast_clipboard_pipeline_result.json"
START_TS=$(cat /tmp/raycast_clipboard_pipeline_start_ts 2>/dev/null || echo "0")

python3 - "$CLIP_OUT" "$SNIP_OUT" "$START_TS" "$RESULT_FILE" << 'PYEOF'
import json, os, sys

clip_out, snip_out, start_ts, result_file = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]

result = {
    "task_start": start_ts,
    "clip_file_exists": False,
    "clip_file_is_new": False,
    "clip_file_size_bytes": 0,
    "clip_content": "",
    "snip_file_exists": False,
    "snip_file_is_new": False,
    "snip_file_size_bytes": 0,
    "snip_valid_json": False,
    "snippets": [],
}

# --- clipboard_test.txt ---
if os.path.exists(clip_out):
    result["clip_file_exists"] = True
    st = os.stat(clip_out)
    result["clip_file_size_bytes"] = st.st_size
    result["clip_file_is_new"] = st.st_mtime > start_ts
    try:
        with open(clip_out, "r", errors="replace") as f:
            result["clip_content"] = f.read()
    except Exception as e:
        result["clip_read_error"] = str(e)

# --- snippets.raycastsnippets ---
if os.path.exists(snip_out):
    result["snip_file_exists"] = True
    st = os.stat(snip_out)
    result["snip_file_size_bytes"] = st.st_size
    result["snip_file_is_new"] = st.st_mtime > start_ts
    try:
        with open(snip_out, "r", errors="replace") as f:
            data = json.load(f)
        result["snip_valid_json"] = True
        # Raycast Snippets export: list of {name, keyword/shortcut, text/content} OR
        # may be wrapped as {"snippets": [...]}
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
                "name":    str(it.get("name")    or it.get("title")      or ""),
                "keyword": str(it.get("keyword") or it.get("shortcut")   or it.get("trigger")     or it.get("abbreviation") or ""),
                "text":    str(it.get("text")    or it.get("content")    or it.get("snippet")     or it.get("value")        or ""),
            })
        result["snippets"] = normalized
    except json.JSONDecodeError as e:
        result["snip_json_error"] = str(e)
    except Exception as e:
        result["snip_read_error"] = str(e)

with open(result_file, "w") as f:
    json.dump(result, f, indent=2)

print(f"clip_exists={result['clip_file_exists']} is_new={result['clip_file_is_new']} "
      f"snip_exists={result['snip_file_exists']} n_snippets={len(result['snippets'])}")
PYEOF

echo "Result written to: $RESULT_FILE"
echo "=== Export complete ==="
