#!/bin/bash
# Export script for trade_show_video_wall_matrix task

echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# We use an inline Python script to perform reliable ffprobe/ffmpeg SSIM analysis
# This evaluates whether the panels are genuine spatial crops or just squished/resized videos.
python3 << 'EOF'
import json
import os
import subprocess

try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        task_start = int(f.read().strip())
except:
    task_start = 0

results = {
    "task_start": task_start,
    "task_end": int(os.popen('date +%s').read().strip()),
    "panels": {}
}

panels_info = {
    "TL": ("panel_TL.mp4", "1920:1080:0:0"),
    "TR": ("panel_TR.mp4", "1920:1080:1920:0"),
    "BL": ("panel_BL.mp4", "1920:1080:0:1080"),
    "BR": ("panel_BR.mp4", "1920:1080:1920:1080")
}

master_video = "/home/ga/Videos/tradeshow_master_4k.mp4"
output_dir = "/home/ga/Videos/video_wall"

for key, (fname, crop_str) in panels_info.items():
    path = os.path.join(output_dir, fname)
    if not os.path.exists(path):
        results["panels"][key] = {"exists": False}
        continue

    mtime = os.path.getmtime(path)
    
    # Run ffprobe
    cmd_probe = [
        "ffprobe", "-v", "error", 
        "-show_entries", "stream=codec_type,width,height", 
        "-show_entries", "format=duration", 
        "-of", "json", path
    ]
    
    width, height, duration, audio_count = 0, 0, 0, 0
    try:
        probe_out = subprocess.check_output(cmd_probe).decode("utf-8")
        probe_data = json.loads(probe_out)
        streams = probe_data.get("streams", [])
        v_streams = [s for s in streams if s.get("codec_type") == "video"]
        a_streams = [s for s in streams if s.get("codec_type") == "audio"]
        
        if v_streams:
            width = v_streams[0].get("width", 0)
            height = v_streams[0].get("height", 0)
        
        duration = float(probe_data.get("format", {}).get("duration", 0))
        audio_count = len(a_streams)
    except Exception as e:
        print(f"Error probing {fname}: {e}")

    # Run SSIM check to prove spatial integrity (prevent scaling hack)
    # ffmpeg compares the agent's file against a perfect crop of the master
    ssim_score = 0.0
    if width == 1920 and height == 1080:
        cmd_ssim = [
            "ffmpeg", "-i", path, "-i", master_video, 
            "-filter_complex", f"[1:v]crop={crop_str}[ref];[0:v][ref]ssim", 
            "-f", "null", "-"
        ]
        try:
            ssim_out = subprocess.run(cmd_ssim, capture_output=True, text=True).stderr
            for line in ssim_out.split("\n"):
                if "SSIM" in line and "All:" in line:
                    parts = line.split("All:")
                    if len(parts) > 1:
                        ssim_score = float(parts[1].split(" ")[0])
                        break
        except Exception as e:
            print(f"Error calculating SSIM for {fname}: {e}")

    results["panels"][key] = {
        "exists": True,
        "mtime": mtime,
        "width": width,
        "height": height,
        "duration": duration,
        "audio_count": audio_count,
        "ssim": ssim_score
    }

# Save internal evaluation metrics
with open('/tmp/matrix_result.json', 'w') as f:
    json.dump(results, f)
EOF

# Copy the user's manifest file to /tmp so the verifier can grab it cleanly
if [ -f "/home/ga/Documents/wall_manifest.json" ]; then
    cp /home/ga/Documents/wall_manifest.json /tmp/wall_manifest.json
    chmod 666 /tmp/wall_manifest.json
fi

chmod 666 /tmp/matrix_result.json

echo "Exported internal matrix verification to /tmp/matrix_result.json"
echo "=== Export complete ==="