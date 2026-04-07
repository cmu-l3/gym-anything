#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Game Audio Asset Pipeline Result ==="

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Save and close if Ardour is running
if pgrep -f "/usr/lib/ardour" > /dev/null 2>&1; then
    WID=$(DISPLAY=:1 xdotool search --name "MyProject" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        DISPLAY=:1 xdotool windowactivate "$WID" 2>/dev/null || true
        sleep 1
        DISPLAY=:1 xdotool key ctrl+s 2>/dev/null || true
        sleep 3
    fi
    kill_ardour
fi

sleep 1

SESSION_FILE="/home/ga/Audio/sessions/MyProject/MyProject.ardour"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Analyze exported files
EXPORT_DIR="/home/ga/Audio/game_assets"
MANIFEST_PATH="$EXPORT_DIR/asset_manifest.txt"

# Create a temporary python script to gather file information safely
python3 - <<EOF > /tmp/game_audio_asset_pipeline_result.json
import os
import json
import base64

export_dir = "$EXPORT_DIR"
task_start = int("$TASK_START")

result = {
    "session_file_exists": os.path.isfile("$SESSION_FILE"),
    "task_start_timestamp": task_start,
    "wav_files": [],
    "manifest_exists": False,
    "manifest_content": ""
}

if os.path.isdir(export_dir):
    for fname in os.listdir(export_dir):
        fpath = os.path.join(export_dir, fname)
        if os.path.isfile(fpath):
            stat = os.stat(fpath)
            if fname.lower().endswith(".wav"):
                result["wav_files"].append({
                    "name": fname,
                    "size": stat.st_size,
                    "mtime": stat.st_mtime,
                    "created_during_task": stat.st_mtime > task_start
                })
            elif fname.lower() == "asset_manifest.txt" or "manifest" in fname.lower():
                result["manifest_exists"] = True
                try:
                    with open(fpath, "r", encoding="utf-8", errors="ignore") as f:
                        content = f.read()
                        result["manifest_content"] = content
                except Exception:
                    result["manifest_content"] = ""

print(json.dumps(result, indent=2))
EOF

echo "Result saved to /tmp/game_audio_asset_pipeline_result.json"
echo "=== Export Complete ==="