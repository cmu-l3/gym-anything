#!/bin/bash
echo "=== Exporting result for typhoon_basin_cat_model_calibration ==="

TASK_NAME="typhoon_basin_cat_model_calibration"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    scrot /tmp/task_final.png 2>/dev/null || true

python3 << 'PYEOF'
import json, os, time

task_name = 'typhoon_basin_cat_model_calibration'
start_ts_file = f'/tmp/{task_name}_start_ts'
task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/CatModel'
files = {
    'sst_plot': os.path.join(output_dir, 'wp_sst_august.png'),
    'slp_plot': os.path.join(output_dir, 'wp_slp_august.png'),
    'report': os.path.join(output_dir, 'calibration_report.txt'),
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
calibration_basin = ''
calibration_month = ''
mdr_peak_sst = ''
genesis_threshold_met = ''
monsoon_trough_present = ''
trough_min_slp = ''
basin_annual_risk = ''
peak_season = ''
data_sources = ''

if os.path.exists(report_path):
    try:
        with open(report_path, 'r', errors='replace') as f:
            content = f.read()
        for line in content.splitlines():
            line = line.strip()
            if line.startswith('CALIBRATION_BASIN:'):
                calibration_basin = line.split(':', 1)[1].strip()
            elif line.startswith('CALIBRATION_MONTH:'):
                calibration_month = line.split(':', 1)[1].strip()
            elif line.startswith('MDR_PEAK_SST_C:'):
                mdr_peak_sst = line.split(':', 1)[1].strip()
            elif line.startswith('GENESIS_THRESHOLD_MET:'):
                genesis_threshold_met = line.split(':', 1)[1].strip()
            elif line.startswith('MONSOON_TROUGH_PRESENT:'):
                monsoon_trough_present = line.split(':', 1)[1].strip()
            elif line.startswith('TROUGH_MIN_SLP_HPA:'):
                trough_min_slp = line.split(':', 1)[1].strip()
            elif line.startswith('BASIN_ANNUAL_RISK:'):
                basin_annual_risk = line.split(':', 1)[1].strip()
            elif line.startswith('PEAK_SEASON:'):
                peak_season = line.split(':', 1)[1].strip()
            elif line.startswith('DATA_SOURCES:'):
                data_sources = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f'Warning: could not parse report: {e}')

result['calibration_basin'] = calibration_basin
result['calibration_month'] = calibration_month
result['mdr_peak_sst'] = mdr_peak_sst
result['genesis_threshold_met'] = genesis_threshold_met
result['monsoon_trough_present'] = monsoon_trough_present
result['trough_min_slp'] = trough_min_slp
result['basin_annual_risk'] = basin_annual_risk
result['peak_season'] = peak_season
result['data_sources'] = data_sources

with open(f'/tmp/{task_name}_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f'Result JSON written to /tmp/{task_name}_result.json')
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="