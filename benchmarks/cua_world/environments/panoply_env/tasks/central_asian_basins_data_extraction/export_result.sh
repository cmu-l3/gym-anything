#!/bin/bash
echo "=== Exporting result for central_asian_basins_data_extraction ==="

TASK_NAME="central_asian_basins_data_extraction"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    scrot /tmp/task_final.png 2>/dev/null || true

python3 << 'PYEOF'
import json, os, time

task_name = 'central_asian_basins_data_extraction'
start_ts_file = f'/tmp/{task_name}_start_ts'
task_start = int(open(start_ts_file).read().strip()) if os.path.exists(start_ts_file) else 0
timestamp = int(time.time())

output_dir = '/home/ga/Documents/CentralAsia'
files = {
    'png_map': os.path.join(output_dir, 'precip_map_april.png'),
    'json_report': os.path.join(output_dir, 'basin_climatology.json'),
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

# Attempt to extract exact ground truth directly from the NetCDF files using scipy
try:
    from scipy.io import netcdf
    import numpy as np

    # 1. Air Temp
    f_air = netcdf.netcdf_file('/home/ga/PanoplyData/air.mon.ltm.nc', 'r')
    lats = f_air.variables['lat'][:]
    lons = f_air.variables['lon'][:]
    air = f_air.variables['air'][:]
    
    lat_idx = np.argmin(np.abs(lats - 45.0))
    lon_aral_idx = np.argmin(np.abs(lons - 60.0))
    lon_balkhash_idx = np.argmin(np.abs(lons - 75.0))
    
    # Time index 3 = April
    gt_aral_temp = float(air[3, lat_idx, lon_aral_idx])
    gt_balkhash_temp = float(air[3, lat_idx, lon_balkhash_idx])
    f_air.close()

    # 2. Precip
    f_prate = netcdf.netcdf_file('/home/ga/PanoplyData/prate.sfc.mon.ltm.nc', 'r')
    prate = f_prate.variables['prate'][:]
    
    gt_aral_precip = float(prate[3, lat_idx, lon_aral_idx])
    gt_balkhash_precip = float(prate[3, lat_idx, lon_balkhash_idx])
    f_prate.close()

    result['gt_extracted'] = True
    result['gt_aral_temp'] = gt_aral_temp
    result['gt_balkhash_temp'] = gt_balkhash_temp
    result['gt_aral_precip'] = gt_aral_precip
    result['gt_balkhash_precip'] = gt_balkhash_precip
except Exception as e:
    result['gt_extracted'] = False
    result['gt_error'] = str(e)

with open(f'/tmp/{task_name}_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f'Result JSON written to /tmp/{task_name}_result.json')
PYEOF

echo "=== Export complete ==="