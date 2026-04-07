#!/bin/bash
echo "=== Exporting result for itcz_seasonal_migration_animation ==="

TASK_NAME="itcz_seasonal_migration_animation"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

python3 << 'PYEOF'
import json
import os
import time
import glob

task_name = 'itcz_seasonal_migration_animation'
start_ts_file = f'/tmp/{task_name}_start_ts'
task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/ITCZ_Lesson'
report_path = os.path.join(output_dir, 'lesson_plan.txt')

result = {
    'task_name': task_name,
    'task_start': task_start,
    'timestamp': timestamp,
    'animation_exists': False,
    'animation_size': 0,
    'animation_mtime': 0,
    'animation_frames': 0,
    'animation_format': 'none'
}

# Find the animation file (itcz_animation.*)
animation_candidates = glob.glob(os.path.join(output_dir, 'itcz_animation.*'))
animation_path = None
if animation_candidates:
    # Get the largest file matching the pattern in case of partial exports
    animation_path = max(animation_candidates, key=os.path.getsize)
    result['animation_exists'] = True
    result['animation_size'] = os.path.getsize(animation_path)
    result['animation_mtime'] = int(os.path.getmtime(animation_path))
    result['animation_format'] = animation_path.split('.')[-1].lower()

# Count frames programmatically
if animation_path and result['animation_size'] > 0:
    frames = 0
    try:
        if result['animation_format'] == 'gif':
            from PIL import Image
            with Image.open(animation_path) as img:
                frames = img.n_frames
        else:
            # Try OpenCV for MP4/AVI
            import cv2
            cap = cv2.VideoCapture(animation_path)
            if cap.isOpened():
                frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
            cap.release()
    except Exception as e:
        print(f"Frame count extraction failed: {e}")
        # If extraction fails but file exists and is reasonably large, we will fall back on size checks in verifier
        pass
    
    result['animation_frames'] = frames

# Parse report fields
report_exists = os.path.exists(report_path)
result['report_exists'] = report_exists
result['report_mtime'] = int(os.path.getmtime(report_path)) if report_exists else 0

target_audience = ''
variable_used = ''
northern_peak = ''
southern_peak = ''
animation_frames_report = ''

if report_exists:
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('TARGET_AUDIENCE:'):
                target_audience = line.split(':', 1)[1].strip()
            elif line.startswith('VARIABLE_USED:'):
                variable_used = line.split(':', 1)[1].strip()
            elif line.startswith('NORTHERN_PEAK_MONTH:'):
                northern_peak = line.split(':', 1)[1].strip()
            elif line.startswith('SOUTHERN_PEAK_MONTH:'):
                southern_peak = line.split(':', 1)[1].strip()
            elif line.startswith('ANIMATION_FRAMES:'):
                animation_frames_report = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result['target_audience'] = target_audience
result['variable_used'] = variable_used
result['northern_peak'] = northern_peak
result['southern_peak'] = southern_peak
result['animation_frames_report'] = animation_frames_report

with open(f'/tmp/{task_name}_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f'Result JSON written to /tmp/{task_name}_result.json')
PYEOF

echo "=== Export complete ==="