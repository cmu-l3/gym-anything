#!/bin/bash
# Export script for esl_language_shadowing_package task
set -e

echo "=== Exporting task results ==="

TARGET_DIR="/home/ga/Music/shadowing_package"
RESULT_JSON="/tmp/task_result.json"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Use an inline python script to safely build the verification JSON and probe media
python3 << EOF
import os
import json
import subprocess

TARGET_DIR = "${TARGET_DIR}"
FILES = ["phrase_01.mp3", "phrase_02.mp3", "phrase_03.mp3", "phrase_04.mp3", "phrase_05.mp3"]

def get_duration(path):
    try:
        res = subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'default=noprint_wrappers=1:nokey=1', path], capture_output=True, text=True, timeout=10)
        return float(res.stdout.strip())
    except:
        return 0.0

def get_codec(path):
    try:
        res = subprocess.run(['ffprobe', '-v', 'error', '-select_streams', 'a:0', '-show_entries', 'stream=codec_name', '-of', 'default=noprint_wrappers=1:nokey=1', path], capture_output=True, text=True, timeout=10)
        return res.stdout.strip()
    except:
        return "unknown"

result = {"files": {}, "playlist_exists": False, "playlist_content": []}

# Probe each expected file
for f in FILES:
    fpath = os.path.join(TARGET_DIR, f)
    if os.path.exists(fpath):
        result["files"][f] = {
            "exists": True,
            "duration": get_duration(fpath),
            "codec": get_codec(fpath),
            "size": os.path.getsize(fpath)
        }
    else:
        result["files"][f] = {"exists": False}

# Probe the M3U playlist
m3u_path = os.path.join(TARGET_DIR, "shadowing_practice.m3u")
if os.path.exists(m3u_path):
    result["playlist_exists"] = True
    os.system(f"cp '{m3u_path}' /tmp/shadowing_practice.m3u 2>/dev/null")
    try:
        with open(m3u_path, 'r', encoding='utf-8', errors='ignore') as pfile:
            # Keep only non-empty, non-comment lines
            lines = [line.strip() for line in pfile if line.strip() and not line.strip().startswith('#')]
            result["playlist_content"] = lines
    except Exception as e:
        result["playlist_content"] = [f"ERROR_READING: {str(e)}"]

# Safely output the JSON
try:
    with open("${RESULT_JSON}", "w") as f:
        json.dump(result, f, indent=2)
except Exception as e:
    print(f"Error writing JSON: {e}")
EOF

chmod 666 "$RESULT_JSON" 2>/dev/null || true

# Kill VLC gracefully
pkill -f "vlc" 2>/dev/null || true

echo "Result JSON saved to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export complete ==="