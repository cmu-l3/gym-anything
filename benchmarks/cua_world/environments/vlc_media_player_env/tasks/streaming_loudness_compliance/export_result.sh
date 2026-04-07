#!/bin/bash
echo "=== Exporting task results ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# We use a Python script inside the container to reliably measure LUFS 
# and format compliance using ffprobe and ffmpeg's ebur128 filter, 
# preventing host-dependency issues.
cat > /tmp/measure_lufs.py << 'EOF'
import json
import subprocess
import os
import re

def get_metrics(filepath):
    if not os.path.exists(filepath):
        return None
        
    metrics = {
        'exists': True,
        'size': os.path.getsize(filepath),
        'mtime': os.path.getmtime(filepath),
        'codec': '',
        'sample_rate': 0,
        'bitrate': 0,
        'lufs': -99.0
    }
    
    # Get format specs using ffprobe
    cmd_probe = [
        'ffprobe', '-v', 'error', 
        '-select_streams', 'a:0',
        '-show_entries', 'stream=codec_name,sample_rate', 
        '-show_entries', 'format=bit_rate', 
        '-of', 'json', filepath
    ]
    try:
        res = subprocess.run(cmd_probe, capture_output=True, text=True)
        if res.returncode == 0:
            data = json.loads(res.stdout)
            streams = data.get('streams', [])
            if streams:
                metrics['codec'] = streams[0].get('codec_name', '').lower()
                metrics['sample_rate'] = int(streams[0].get('sample_rate', 0))
            metrics['bitrate'] = int(data.get('format', {}).get('bit_rate', 0))
    except Exception as e:
        metrics['error_probe'] = str(e)

    # Get integrated loudness (LUFS) using ffmpeg ebur128
    cmd_lufs = [
        'ffmpeg', '-nostats', '-i', filepath, 
        '-filter_complex', 'ebur128', 
        '-f', 'null', '-'
    ]
    try:
        res2 = subprocess.run(cmd_lufs, capture_output=True, text=True)
        # Parse the stderr output for "I: -xx.x LUFS"
        match = re.search(r'I:\s+(-?\d+\.\d+)\s+LUFS', res2.stderr)
        if match:
            metrics['lufs'] = float(match.group(1))
    except Exception as e:
        metrics['error_lufs'] = str(e)
        
    return metrics

results = {'source_tracks': {}, 'deliverables': {}}

# Measure sources
src_dir = '/home/ga/Music/ep_masters'
for track in ['track_01_overture.wav', 'track_02_nocturne.wav', 'track_03_pulse.wav', 'track_04_finale.wav']:
    results['source_tracks'][track] = get_metrics(os.path.join(src_dir, track))

# Measure deliverables
del_dir = '/home/ga/Music/normalized_delivery'
platforms = {
    'spotify': '.mp3',
    'apple': '.m4a',
    'youtube': '.opus'
}

for track_base in ['track_01_overture', 'track_02_nocturne', 'track_03_pulse', 'track_04_finale']:
    for plat, ext in platforms.items():
        if plat not in results['deliverables']:
            results['deliverables'][plat] = {}
        file_path = os.path.join(del_dir, plat, track_base + ext)
        results['deliverables'][plat][track_base] = get_metrics(file_path)

with open('/tmp/export_metrics.json', 'w') as f:
    json.dump(results, f, indent=2)
EOF

# Run the measurement script
python3 /tmp/measure_lufs.py

# Copy agent's compliance report if it exists
if [ -f "/home/ga/Documents/loudness_compliance_report.json" ]; then
    cp "/home/ga/Documents/loudness_compliance_report.json" /tmp/loudness_compliance_report.json
else
    echo "{}" > /tmp/loudness_compliance_report.json
fi

chmod 666 /tmp/export_metrics.json /tmp/loudness_compliance_report.json

echo "=== Export complete ==="