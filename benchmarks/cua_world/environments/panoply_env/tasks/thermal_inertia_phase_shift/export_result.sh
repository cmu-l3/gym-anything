#!/bin/bash
echo "=== Exporting result for thermal_inertia_phase_shift ==="

TASK_NAME="thermal_inertia_phase_shift"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"

# Take final screenshot as evidence
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    scrot /tmp/task_final.png 2>/dev/null || true

python3 << 'PYEOF'
import json, os, time, re

task_name = 'thermal_inertia_phase_shift'
start_ts_file = f'/tmp/{task_name}_start_ts'
task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/ThermalLecture'
files = {
    'land_plot': os.path.join(output_dir, 'land_annual_cycle.png'),
    'ocean_plot': os.path.join(output_dir, 'ocean_annual_cycle.png'),
    'map_plot': os.path.join(output_dir, 'august_global_map.png'),
    'report': os.path.join(output_dir, 'thermal_inertia_report.txt'),
}

result = {
    'task_name': task_name,
    'task_start': task_start,
    'timestamp': timestamp,
}

# Check file existence, size, and modification times
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
report_data = {
    'land_peak_month': '',
    'land_peak_temp': '',
    'ocean_peak_month': '',
    'ocean_peak_temp': '',
    'phase_shift': '',
    'mechanism': ''
}

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            for line in f:
                line = line.strip()
                if line.startswith('LAND_PEAK_MONTH:'):
                    report_data['land_peak_month'] = line.split(':', 1)[1].strip()
                elif line.startswith('LAND_PEAK_TEMP_K:'):
                    report_data['land_peak_temp'] = line.split(':', 1)[1].strip()
                elif line.startswith('OCEAN_PEAK_MONTH:'):
                    report_data['ocean_peak_month'] = line.split(':', 1)[1].strip()
                elif line.startswith('OCEAN_PEAK_TEMP_K:'):
                    report_data['ocean_peak_temp'] = line.split(':', 1)[1].strip()
                elif line.startswith('PHASE_SHIFT_MONTHS:'):
                    report_data['phase_shift'] = line.split(':', 1)[1].strip()
                elif line.startswith('PRIMARY_PHYSICAL_MECHANISM:'):
                    report_data['mechanism'] = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result.update(report_data)

# Save result JSON safely
with open(f'/tmp/{task_name}_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f'Result JSON written to /tmp/{task_name}_result.json')
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="