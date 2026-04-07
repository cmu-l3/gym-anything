#!/bin/bash
echo "=== Exporting Audiobook Task Result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# We run a python script inside the container to reliably gather audio data 
# via ffprobe and ffmpeg without dealing with complex bash jq parsing
cat << 'EOF' > /tmp/export_helper.py
import os
import json
import subprocess

task_start = 0
if os.path.exists("/tmp/task_start_time.txt"):
    with open("/tmp/task_start_time.txt") as f:
        try:
            task_start = int(f.read().strip())
        except:
            pass

delivery_dir = "/home/ga/Music/audiobook_delivery"
result = {
    "task_start": task_start,
    "files": {},
    "manifest_exists": False,
    "manifest_valid_json": False,
    "manifest_content": {}
}

for i in range(1, 5):
    filename = f"chapter_0{i}.mp3"
    filepath = os.path.join(delivery_dir, filename)
    file_data = {"exists": False}

    if os.path.exists(filepath):
        file_data["exists"] = True
        mtime = os.path.getmtime(filepath)
        file_data["created_during_task"] = mtime > task_start
        file_data["size"] = os.path.getsize(filepath)

        # Extract info using ffprobe
        cmd = ["ffprobe", "-v", "quiet", "-print_format", "json", "-show_format", "-show_streams", filepath]
        try:
            out = subprocess.check_output(cmd)
            info = json.loads(out)
            streams = info.get("streams", [{}])
            format_info = info.get("format", {})

            file_data["codec"] = streams[0].get("codec_name", "unknown")
            file_data["channels"] = int(streams[0].get("channels", 0))
            file_data["bitrate"] = int(format_info.get("bit_rate", 0))
            file_data["duration"] = float(format_info.get("duration", 0))

            tags = format_info.get("tags", {})
            tags_lower = {k.lower(): str(v) for k, v in tags.items()}
            file_data["tags"] = {
                "artist": tags_lower.get("artist", ""),
                "album": tags_lower.get("album", ""),
                "title": tags_lower.get("title", ""),
                "track": tags_lower.get("track", "")
            }
        except Exception as e:
            file_data["error"] = str(e)

        # Measure actual volume to prevent gaming (e.g. creating silent MP3s)
        try:
            vol_cmd = f"ffmpeg -i '{filepath}' -af volumedetect -vn -sn -f null /dev/null 2>&1 | grep mean_volume"
            vol_out = subprocess.check_output(vol_cmd, shell=True).decode()
            mean_vol = float(vol_out.split("mean_volume:")[1].split("dB")[0].strip())
            file_data["mean_volume"] = mean_vol
        except Exception:
            file_data["mean_volume"] = -99.0

    result["files"][filename] = file_data

manifest_path = os.path.join(delivery_dir, "manifest.json")
if os.path.exists(manifest_path):
    result["manifest_exists"] = True
    try:
        with open(manifest_path, 'r') as f:
            result["manifest_content"] = json.load(f)
        result["manifest_valid_json"] = True
    except:
        result["manifest_valid_json"] = False

# Save to temp location securely
with open("/tmp/task_result_temp.json", "w") as f:
    json.dump(result, f, indent=2)
EOF

python3 /tmp/export_helper.py

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/task_result_temp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="