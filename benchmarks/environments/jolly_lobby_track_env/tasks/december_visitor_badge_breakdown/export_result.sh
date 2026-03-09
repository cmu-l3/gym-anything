#!/bin/bash
echo "=== Exporting december_visitor_badge_breakdown result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot "december_visitor_badge_breakdown_final"

# Build result JSON using Python3 for safe JSON encoding
python3 - << 'PYEOF'
import os
import json

target_file = "/home/ga/Desktop/dec2025_visitor_analysis.csv"

result = {
    "task": "december_visitor_badge_breakdown",
    "file_exists": os.path.isfile(target_file),
    "file_size": 0,
    "file_content": "",
    "file_path": target_file,
}

if result["file_exists"]:
    result["file_size"] = os.path.getsize(target_file)
    try:
        with open(target_file, "r", encoding="utf-8", errors="replace") as f:
            result["file_content"] = f.read(4000)
    except Exception as e:
        result["file_content"] = f"ERROR reading file: {e}"

with open("/tmp/december_visitor_badge_breakdown_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(f"File exists: {result['file_exists']}")
print(f"File size: {result['file_size']} bytes")
if result["file_exists"]:
    preview = result["file_content"][:200].replace("\n", " ")
    print(f"Content preview: {preview}")
PYEOF

echo "=== Export Complete ==="
