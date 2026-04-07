#!/bin/bash
echo "=== Exporting UX Research Analysis Results ==="

# Record task completion time
date +%s > /tmp/task_end_time.txt

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
UX_DIR="/home/ga/Documents/ux_report"

# Python script to safely gather media properties and dump JSON
cat << 'EOF' > /tmp/export_helper.py
import json
import os
import subprocess
import sys

TASK_START = int(sys.argv[1])
UX_DIR = sys.argv[2]

def get_file_info(filename):
    path = os.path.join(UX_DIR, filename)
    if os.path.isfile(path):
        st = os.stat(path)
        return {
            "exists": True,
            "size": st.st_size,
            "created_during_task": st.st_mtime > TASK_START
        }
    return {"exists": False, "size": 0, "created_during_task": False}

def probe_media(filename, stream_type="a:0"):
    path = os.path.join(UX_DIR, filename)
    if not os.path.isfile(path): return {}
    cmd = [
        'ffprobe', '-v', 'error',
        '-select_streams', stream_type,
        '-show_entries', 'stream=codec_name,channels',
        '-show_entries', 'format=duration',
        '-of', 'json', path
    ]
    try:
        out = subprocess.check_output(cmd, stderr=subprocess.DEVNULL)
        return json.loads(out.decode('utf-8'))
    except Exception:
        return {}

data = {
    "voice_file": get_file_info("player_voice_full.mp3"),
    "voice_audio": probe_media("player_voice_full.mp3", "a:0"),
    "highlight_file": get_file_info("bug_highlight.mp4"),
    "highlight_audio": probe_media("bug_highlight.mp4", "a:0"),
    "highlight_video": probe_media("bug_highlight.mp4", "v:0"),
    "snap1": get_file_info("error_frame_1.png"),
    "snap2": get_file_info("error_frame_2.png"),
    "snap3": get_file_info("error_frame_3.png"),
    "manifest_file": get_file_info("ux_manifest.json")
}

with open("/tmp/ux_export_result.json", "w") as f:
    json.dump(data, f, indent=2)
EOF

python3 /tmp/export_helper.py "$TASK_START" "$UX_DIR"

# Explicitly copy the manifest to make it easier for verifier to pull
cp -f "$UX_DIR/ux_manifest.json" /tmp/ux_manifest.json 2>/dev/null || true
chmod 666 /tmp/ux_export_result.json /tmp/ux_manifest.json 2>/dev/null || true

# Take final screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

echo "=== Export complete ==="