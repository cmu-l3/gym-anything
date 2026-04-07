#!/bin/bash
echo "=== Exporting robot_depth_scanning_reconstruction Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/robot_depth_scanning_start_ts 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/robot_depth_scanning_end_screenshot.png

# Run Python analysis script to safely parse all exported CSVs and JSONs
python3 << 'PYEOF' > /tmp/robot_depth_scanning_result.json
import os
import json
import csv
import glob

start_ts = 0
try:
    with open('/tmp/robot_depth_scanning_start_ts', 'r') as f:
        start_ts = int(f.read().strip())
except:
    pass

export_dir = '/home/ga/Documents/CoppeliaSim/exports'
merged_csv = os.path.join(export_dir, 'merged_pointcloud.csv')
report_json = os.path.join(export_dir, 'scanning_report.json')
depth_csvs = glob.glob(os.path.join(export_dir, 'depth_view_*.csv'))

res = {
    'task_start': start_ts,
    'merged_csv_exists': os.path.exists(merged_csv),
    'merged_csv_is_new': False,
    'report_json_exists': os.path.exists(report_json),
    'report_json_is_new': False,
    'depth_csv_count': len(depth_csvs),
    'depth_csvs_new_count': 0,
    'depth_valid_count': 0,
    'num_poses_in_json': 0,
    'pc_num_points': 0,
    'pc_centroid': None,
    'error_log': []
}

# Check file timestamps
if res['merged_csv_exists'] and os.path.getmtime(merged_csv) > start_ts:
    res['merged_csv_is_new'] = True
if res['report_json_exists'] and os.path.getmtime(report_json) > start_ts:
    res['report_json_is_new'] = True

# Analyze raw depth CSVs
for dcsv in depth_csvs:
    if os.path.getmtime(dcsv) > start_ts:
        res['depth_csvs_new_count'] += 1
        try:
            with open(dcsv, 'r') as f:
                vals = []
                # Handle varying CSV structures (could be 1D, 2D, with or without headers)
                reader = csv.reader(f)
                for row in reader:
                    for v in row:
                        v_str = v.strip()
                        if v_str:
                            try:
                                vals.append(float(v_str))
                            except ValueError:
                                pass
            
            # Check for variance indicating an object was actually seen (not just background/1.0)
            if vals:
                min_v = min(vals)
                max_v = max(vals)
                if (max_v - min_v) > 0.001 and min_v < 0.999:
                    res['depth_valid_count'] += 1
        except Exception as e:
            res['error_log'].append(f"Error reading depth CSV {os.path.basename(dcsv)}: {str(e)}")

# Analyze JSON report
def count_matrices(obj):
    count = 0
    if isinstance(obj, list):
        # CoppeliaSim pose matrices are typically 12 elements (3x4) or 16 elements (4x4)
        if len(obj) in (12, 16) and all(isinstance(x, (int, float)) for x in obj):
            return 1
        # Or a 4x4 nested list
        if len(obj) == 4 and isinstance(obj[0], list) and len(obj[0]) == 4:
            return 1
        for item in obj:
            count += count_matrices(item)
    elif isinstance(obj, dict):
        for k, v in obj.items():
            count += count_matrices(v)
    return count

if res['report_json_exists']:
    try:
        with open(report_json, 'r') as f:
            data = json.load(f)
            res['num_poses_in_json'] = count_matrices(data)
    except Exception as e:
        res['error_log'].append(f"Error reading report JSON: {str(e)}")

# Analyze Point Cloud CSV
if res['merged_csv_exists']:
    try:
        with open(merged_csv, 'r') as f:
            reader = csv.reader(f)
            headers = next(reader, [])
            headers_lower = [h.strip().lower() for h in headers]
            
            hx_idx = next((i for i, h in enumerate(headers_lower) if h in ['world_x', 'x', 'x_m']), None)
            hy_idx = next((i for i, h in enumerate(headers_lower) if h in ['world_y', 'y', 'y_m']), None)
            hz_idx = next((i for i, h in enumerate(headers_lower) if h in ['world_z', 'z', 'z_m']), None)
            
            rows = list(reader)
            res['pc_num_points'] = len(rows)
            
            if hx_idx is not None and hy_idx is not None and hz_idx is not None:
                xs, ys, zs = [], [], []
                for row in rows:
                    try:
                        xs.append(float(row[hx_idx]))
                        ys.append(float(row[hy_idx]))
                        zs.append(float(row[hz_idx]))
                    except (IndexError, ValueError):
                        pass
                
                if xs:
                    res['pc_centroid'] = [sum(xs)/len(xs), sum(ys)/len(ys), sum(zs)/len(zs)]
    except Exception as e:
        res['error_log'].append(f"Error reading merged pointcloud CSV: {str(e)}")

print(json.dumps(res, indent=2))
PYEOF

echo "Analysis JSON saved to /tmp/robot_depth_scanning_result.json"
cat /tmp/robot_depth_scanning_result.json

echo "=== Export Complete ==="