#!/bin/bash
echo "=== Exporting generate_jst_event_report result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Export Database Ground Truth and File Stats using Python
python3 << 'PYEOF'
import json, subprocess, os, time

task_start = 0
try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        task_start = int(f.read().strip())
except:
    pass

task_end = int(time.time())

# Output file
out_path = '/home/ga/Documents/noto_report.html'
out_exists = os.path.exists(out_path)
out_size = os.path.getsize(out_path) if out_exists else 0
out_mtime = os.path.getmtime(out_path) if out_exists else 0
file_created = out_mtime >= task_start if out_exists else False

# GT Data
gt_id, gt_utc, gt_lat, gt_lon, gt_mag = '', '', '', '', ''
try:
    cmd = 'mysql -u sysop -psysop seiscomp -N -B -e "SELECT e.publicID, o.time_value, o.latitude_value, o.longitude_value, m.magnitude_value FROM Event e JOIN Origin o ON e.preferredOriginID = o.publicID JOIN Magnitude m ON e.preferredMagnitudeID = m.publicID WHERE m.magnitude_value > 7.0 LIMIT 1;"'
    out = subprocess.check_output(cmd, shell=True).decode('utf-8').strip()
    if out:
        parts = out.split('\t')
        if len(parts) >= 5:
            gt_id = parts[0]
            gt_utc = parts[1]
            gt_lat = parts[2]
            gt_lon = parts[3]
            gt_mag = parts[4]
except Exception as e:
    print(f"DB Error: {e}")

data = {
    'task_start': task_start,
    'task_end': task_end,
    'output_exists': out_exists,
    'file_created_during_task': file_created,
    'output_size_bytes': out_size,
    'gt_event_id': gt_id,
    'gt_utc_time': gt_utc,
    'gt_lat': gt_lat,
    'gt_lon': gt_lon,
    'gt_mag': gt_mag
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f)
PYEOF

chmod 666 /tmp/task_result.json

# 3. Copy HTML file for verifier
if [ -f /home/ga/Documents/noto_report.html ]; then
    cp /home/ga/Documents/noto_report.html /tmp/noto_report.html
    chmod 666 /tmp/noto_report.html
else
    touch /tmp/noto_report.html
    chmod 666 /tmp/noto_report.html
fi

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="