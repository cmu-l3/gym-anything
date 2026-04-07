#!/bin/bash
echo "=== Exporting result for planetary_circulation_zonal_mean_profile ==="

TASK_NAME="planetary_circulation_zonal_mean_profile"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    scrot /tmp/task_final.png 2>/dev/null || true

python3 << 'PYEOF'
import json, os, time

task_name = 'planetary_circulation_zonal_mean_profile'
start_ts_file = f'/tmp/{task_name}_start_ts'
task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/ZonalCirculation'
files = {
    'png': os.path.join(output_dir, 'zonal_slp_annual.png'),
    'csv': os.path.join(output_dir, 'zonal_slp_annual.csv'),
    'report': os.path.join(output_dir, 'pressure_belts_report.txt'),
}

result = {
    'task_name': task_name,
    'task_start': task_start,
    'timestamp': timestamp,
}

# Check file existence and metadata
for key, path in files.items():
    if os.path.exists(path):
        result[key + '_exists'] = True
        result[key + '_size'] = os.path.getsize(path)
        result[key + '_mtime'] = int(os.path.getmtime(path))
    else:
        result[key + '_exists'] = False
        result[key + '_size'] = 0
        result[key + '_mtime'] = 0

# Extract info from CSV
csv_path = files['csv']
csv_rows = 0
val_equator = None
val_30s = None
val_60s = None
num_cols_list = []

if result['csv_exists']:
    try:
        with open(csv_path, 'r', errors='replace') as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('#'): continue
                
                # Try comma separated, fallback to space/tab
                if ',' in line:
                    parts = [p.strip() for p in line.split(',')]
                else:
                    parts = [p.strip() for p in line.split()]
                    
                if len(parts) >= 2:
                    try:
                        lat = float(parts[0])
                        val = float(parts[1])
                        csv_rows += 1
                        num_cols_list.append(len(parts))
                        
                        if abs(lat - 0.0) <= 1.5:
                            val_equator = val
                        elif abs(lat - (-30.0)) <= 1.5:
                            val_30s = val
                        elif abs(lat - (-60.0)) <= 1.5:
                            val_60s = val
                    except ValueError:
                        pass
    except Exception as e:
        print(f"Error parsing CSV: {e}")

result['csv_rows'] = csv_rows
result['val_equator'] = val_equator
result['val_30s'] = val_30s
result['val_60s'] = val_60s
result['avg_cols'] = sum(num_cols_list) / len(num_cols_list) if num_cols_list else 0

# Parse report fields
report_path = files['report']
sh_lat = ''
nh_lat = ''
eq_lat = ''

if result['report_exists']:
    try:
        with open(report_path, 'r', errors='replace') as f:
            for line in f:
                line = line.strip()
                if line.startswith('SH_SUBTROPICAL_HIGH_LAT:'):
                    sh_lat = line.split(':', 1)[1].strip()
                elif line.startswith('NH_SUBTROPICAL_HIGH_LAT:'):
                    nh_lat = line.split(':', 1)[1].strip()
                elif line.startswith('EQUATORIAL_TROUGH_LAT:'):
                    eq_lat = line.split(':', 1)[1].strip()
    except Exception:
        pass

result['sh_lat'] = sh_lat
result['nh_lat'] = nh_lat
result['eq_lat'] = eq_lat

with open(f'/tmp/{task_name}_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f'Result JSON written to /tmp/{task_name}_result.json')
PYEOF

echo "=== Export complete ==="