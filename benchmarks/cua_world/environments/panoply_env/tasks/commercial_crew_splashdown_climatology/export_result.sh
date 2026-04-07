#!/bin/bash
echo "=== Exporting result for commercial_crew_splashdown_climatology ==="

TASK_NAME="commercial_crew_splashdown_climatology"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    scrot /tmp/task_final.png 2>/dev/null || true

python3 << 'PYEOF'
import json, os, time

task_name = 'commercial_crew_splashdown_climatology'
start_ts_file = f'/tmp/{task_name}_start_ts'
task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/RecoveryOps'
files = {
    'sst_plot': os.path.join(output_dir, 'sst_september.png'),
    'precip_plot': os.path.join(output_dir, 'precip_september.png'),
    'report': os.path.join(output_dir, 'splashdown_recommendation.txt'),
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
alpha_sst = ''
bravo_sst = ''
recommended_site = ''

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('SITE_ALPHA_GOM_SST:'):
                alpha_sst = line.split(':', 1)[1].strip()
            elif line.startswith('SITE_BRAVO_BAJA_SST:'):
                bravo_sst = line.split(':', 1)[1].strip()
            elif line.startswith('RECOMMENDED_SITE:'):
                recommended_site = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result['alpha_sst'] = alpha_sst
result['bravo_sst'] = bravo_sst
result['recommended_site'] = recommended_site

with open(f'/tmp/{task_name}_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f'Result JSON written to /tmp/{task_name}_result.json')
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="