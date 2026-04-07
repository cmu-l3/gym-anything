#!/bin/bash
echo "=== Exporting result for topographic_pressure_fingerprint ==="

TASK_NAME="topographic_pressure_fingerprint"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

python3 << 'PYEOF'
import json, os, time

task_name = 'topographic_pressure_fingerprint'
start_ts_file = f'/tmp/{task_name}_start_ts'
task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/PressureLecture'
files = {
    'surface_png': os.path.join(output_dir, 'surface_pressure_jan.png'),
    'slp_png': os.path.join(output_dir, 'sealevel_pressure_jan.png'),
    'report': os.path.join(output_dir, 'lecture_notes.txt'),
}

result = {
    'task_name': task_name,
    'task_start': task_start,
    'timestamp': timestamp,
}

for key, path in files.items():
    if os.path.exists(path):
        result[key + '_exists'] = True
        result[key + '_size'] = os.path.getsize(path)
        result[key + '_mtime'] = int(os.path.getmtime(path))
    else:
        result[key + '_exists'] = False
        result[key + '_size'] = 0
        result[key + '_mtime'] = 0

# Parse report fields
report_path = files['report']
report_fields = {
    'FEATURE_1': '',
    'FEATURE_1_PRESSURE_HPA': '',
    'FEATURE_2': '',
    'FEATURE_2_PRESSURE_HPA': '',
    'FEATURE_3': '',
    'SEALEVEL_MEAN_HPA': '',
    'KEY_DIFFERENCE': ''
}

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
            
        # Parse multi-line or single-line fields
        lines = content.splitlines()
        for i, line in enumerate(lines):
            line = line.strip()
            for key in report_fields.keys():
                if line.startswith(f"{key}:"):
                    # Extract everything after the colon
                    val = line.split(':', 1)[1].strip()
                    
                    # For KEY_DIFFERENCE, it might span multiple lines, so grab subsequent text until a new key or EOF
                    if key == 'KEY_DIFFERENCE':
                        extra_text = []
                        for j in range(i+1, len(lines)):
                            next_line = lines[j].strip()
                            # If it starts with an uppercase word and colon, it's likely a new key (shouldn't happen if it's the last field, but safe to check)
                            if ':' in next_line and next_line.split(':')[0].isupper():
                                break
                            extra_text.append(next_line)
                        val = val + " " + " ".join(extra_text)
                    
                    report_fields[key] = val
                    break
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result.update({k.lower(): v.strip() for k, v in report_fields.items()})

with open(f'/tmp/{task_name}_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f'Result JSON written to /tmp/{task_name}_result.json')
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="