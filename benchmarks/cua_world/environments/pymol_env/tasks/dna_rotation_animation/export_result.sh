#!/bin/bash
echo "=== Exporting DNA Rotation Animation Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/dna_animation_end_screenshot.png

# Collect result data using Python heredoc for robust JSON generation
python3 << 'PYEOF'
import json
import os

try:
    with open("/tmp/dna_animation_start_ts", "r") as f:
        TASK_START = int(f.read().strip())
except Exception:
    TASK_START = 0

images_dir = "/home/ga/PyMOL_Data/images/"
report_path = "/home/ga/PyMOL_Data/1bna_report.txt"

result = {
    "frames": [],
    "report_exists": False,
    "report_content": ""
}

# Report check
if os.path.isfile(report_path):
    result["report_exists"] = True
    with open(report_path, "r", errors="replace") as f:
        result["report_content"] = f.read()

# Frame check
if os.path.isdir(images_dir):
    for filename in os.listdir(images_dir):
        if filename.lower().endswith(".png"):
            filepath = os.path.join(images_dir, filename)
            mtime = int(os.path.getmtime(filepath))
            
            # Anti-gaming: must be created after task start
            if mtime > TASK_START:
                size = os.path.getsize(filepath)
                result["frames"].append({
                    "filename": filename,
                    "size_bytes": size,
                    "mtime": mtime
                })

# Sort frames alphabetically
result["frames"] = sorted(result["frames"], key=lambda x: x["filename"])

with open("/tmp/dna_animation_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(f"Exported {len(result['frames'])} new frames to result JSON.")
PYEOF

echo "=== Export Complete ==="