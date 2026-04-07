#!/bin/bash
echo "=== Exporting result for enso_baseline_equatorial_diagnostic ==="

TASK_NAME="enso_baseline_equatorial_diagnostic"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    scrot /tmp/task_final.png 2>/dev/null || true

# Extract results using Python
python3 << PYEOF
import json, os, time

task_start = int(open('/tmp/${TASK_NAME}_start_ts').read().strip()) if os.path.exists('/tmp/${TASK_NAME}_start_ts') else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/ENSODiagnostic'
files = {
    'spatial_map': os.path.join(output_dir, 'tropical_pacific_sst_july.png'),
    'line_plot': os.path.join(output_dir, 'equatorial_sst_profile_july.png'),
    'report': os.path.join(output_dir, 'enso_baseline_report.txt'),
}

result = {
    'task_name': '${TASK_NAME}',
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
analysis_month = ''
warm_pool_sst = ''
cold_tongue_sst = ''
sst_gradient = ''
nino34_sst = ''
enso_phase = ''
plot_type_used = ''

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('ANALYSIS_MONTH:'):
                analysis_month = line.split(':', 1)[1].strip()
            elif line.startswith('WARM_POOL_SST_C:'):
                warm_pool_sst = line.split(':', 1)[1].strip()
            elif line.startswith('COLD_TONGUE_SST_C:'):
                cold_tongue_sst = line.split(':', 1)[1].strip()
            elif line.startswith('EQUATORIAL_SST_GRADIENT_C:'):
                sst_gradient = line.split(':', 1)[1].strip()
            elif line.startswith('NINO34_BASELINE_SST_C:'):
                nino34_sst = line.split(':', 1)[1].strip()
            elif line.startswith('ENSO_PHASE:'):
                enso_phase = line.split(':', 1)[1].strip()
            elif line.startswith('PLOT_TYPE_USED:'):
                plot_type_used = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result['analysis_month'] = analysis_month
result['warm_pool_sst'] = warm_pool_sst
result['cold_tongue_sst'] = cold_tongue_sst
result['sst_gradient'] = sst_gradient
result['nino34_sst'] = nino34_sst
result['enso_phase'] = enso_phase
result['plot_type_used'] = plot_type_used

with open('${RESULT_JSON}', 'w') as f:
    json.dump(result, f, indent=2)

print('Result JSON written to ${RESULT_JSON}')
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="