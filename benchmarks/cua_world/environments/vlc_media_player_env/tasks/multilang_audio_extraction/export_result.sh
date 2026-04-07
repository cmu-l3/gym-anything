#!/bin/bash
# Export script for multilang_audio_extraction task

echo "=== Exporting Multi-Language Audio Extraction Results ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Run Python analyzer inside the environment
# This grabs robust metadata (duration, streams, freq analysis via FFT) without copying massive files.
cat > /tmp/analyze_deliverables.py << 'EOF'
import json
import subprocess
import os
import sys
import numpy as np

def analyze_media(path):
    if not os.path.exists(path):
        return {"exists": False}

    stat = os.stat(path)
    info = {
        "exists": True,
        "size_bytes": stat.st_size,
        "mtime": stat.st_mtime
    }

    # Extract format and stream details via ffprobe
    cmd = ['ffprobe', '-v', 'quiet', '-print_format', 'json', '-show_format', '-show_streams', path]
    try:
        res = subprocess.run(cmd, capture_output=True, text=True)
        data = json.loads(res.stdout)
        info['format'] = data.get('format', {})
        info['streams'] = data.get('streams', [])
    except Exception as e:
        info['ffprobe_error'] = str(e)

    # Perform Fast Fourier Transform (FFT) analysis on the first 1 second (from 5 seconds in)
    try:
        ffmpeg_cmd = [
            'ffmpeg', '-v', 'quiet', '-ss', '00:00:05', '-t', '1', 
            '-i', path, '-f', 's16le', '-acodec', 'pcm_s16le', '-ac', '1', '-ar', '44100', '-'
        ]
        raw_audio = subprocess.run(ffmpeg_cmd, capture_output=True).stdout
        if len(raw_audio) > 0:
            samples = np.frombuffer(raw_audio, dtype=np.int16)
            fft_data = np.fft.rfft(samples)
            freqs = np.fft.rfftfreq(len(samples), 1.0/44100.0)
            peak_freq = freqs[np.argmax(np.abs(fft_data))]
            info['peak_freq'] = float(peak_freq)
        else:
            info['peak_freq'] = 0.0
    except Exception as e:
        info['peak_freq'] = 0.0
        info['freq_error'] = str(e)

    return info

base_dir = "/home/ga/Videos/dubbing_deliverables"
files_to_check = [
    "audio_english.mp3",
    "audio_spanish.mp3",
    "audio_french.mp3",
    "video_only.mp4",
    "english_reference.mp4"
]

results = {}
for f in files_to_check:
    results[f] = analyze_media(os.path.join(base_dir, f))

# Also read task start time
try:
    with open("/tmp/task_start_time.txt", "r") as f:
        results["task_start_time"] = float(f.read().strip())
except:
    results["task_start_time"] = 0.0

with open("/tmp/task_result.json", "w") as f:
    json.dump(results, f, indent=2)
EOF

# Run the analyzer
python3 /tmp/analyze_deliverables.py

# Clean up VLC
pkill -f vlc 2>/dev/null || true

echo "Results processed. Output saved to /tmp/task_result.json."
echo "=== Export complete ==="