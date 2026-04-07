#!/bin/bash
echo "=== Exporting high_rise_fire_resource_demand result ==="

source /workspace/scripts/task_utils.sh
activate_venv

take_screenshot /tmp/task_end.png
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

# Use Python to evaluate the outputs comprehensively and compute ground truth
python << 'PYEOF'
import json, os, math
import pandas as pd
import numpy as np

task_start = int(open('/home/ga/.task_start_time').read().strip()) if os.path.exists('/home/ga/.task_start_time') else 0

result = {
    "notebook_exists": False,
    "notebook_executed": False,
    "csv_exists": False,
    "csv_structure_ok": False,
    "csv_filtered_ok": False,
    "csv_sorted_ok": False,
    "csv_math_ok": False,
    "json_exists": False,
    "json_keys_ok": False,
    "json_accuracy": {},
    "plot_exists": False,
    "plot_size_kb": 0,
    "plot_created": False,
    "task_start_time": task_start
}

# 1. Compute Ground Truth (Hidden from agent)
try:
    bld = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'buildings')
    pcl = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'parcels')
    bld = bld.join(pcl[['zone_id']], on='parcel_id')
    
    ru = bld['residential_units'].fillna(0) >= 30
    sq = bld['non_residential_sqft'].fillna(0) >= 50000
    st = bld['stories'].fillna(0) >= 5
    
    bld['is_high_demand'] = ru | sq | st
    bld['hd_res_units'] = np.where(bld['is_high_demand'], bld['residential_units'].fillna(0), 0)
    
    zones = bld.groupby('zone_id').agg(
        total_buildings=('parcel_id', 'count'),
        high_demand_buildings=('is_high_demand', 'sum'),
        total_residential_units_in_high_demand=('hd_res_units', 'sum')
    ).reset_index()
    
    zones['pct_high_demand'] = zones['high_demand_buildings'] / zones['total_buildings']
    zones['fire_resource_score'] = (zones['high_demand_buildings'] * 5) + (zones['total_residential_units_in_high_demand'] * 0.1)
    
    zones = zones[zones['high_demand_buildings'] > 0]
    zones = zones.sort_values('fire_resource_score', ascending=False)
    
    gt_total_hd = int(zones['high_demand_buildings'].sum())
    gt_top_zone = int(zones.iloc[0]['zone_id']) if len(zones) > 0 else 0
    gt_top_10_avg = float(zones.head(10)['fire_resource_score'].mean()) if len(zones) > 0 else 0
except Exception as e:
    gt_total_hd, gt_top_zone, gt_top_10_avg = 0, 0, 0
    result["gt_error"] = str(e)

# 2. Check CSV Output
csv_path = "/home/ga/urbansim_projects/output/fire_resource_demand.csv"
if os.path.exists(csv_path):
    result["csv_exists"] = True
    try:
        df = pd.read_csv(csv_path)
        req_cols = ['zone_id', 'total_buildings', 'high_demand_buildings', 'pct_high_demand', 'total_residential_units_in_high_demand', 'fire_resource_score']
        
        if all(c in df.columns for c in req_cols):
            result["csv_structure_ok"] = True
            
            # Check Filtering
            result["csv_filtered_ok"] = (df['high_demand_buildings'] == 0).sum() == 0
            
            # Check Math on agent's own aggregates
            expected_score = (df['high_demand_buildings'].fillna(0) * 5) + (df['total_residential_units_in_high_demand'].fillna(0) * 0.1)
            result["csv_math_ok"] = np.allclose(df['fire_resource_score'].fillna(-1), expected_score, atol=0.01)
            
            # Check Sorting
            result["csv_sorted_ok"] = df['fire_resource_score'].is_monotonic_decreasing
    except Exception as e:
        result["csv_error"] = str(e)

# 3. Check JSON Output
json_path = "/home/ga/urbansim_projects/output/safety_summary.json"
if os.path.exists(json_path):
    result["json_exists"] = True
    try:
        with open(json_path, 'r') as f:
            j = json.load(f)
        
        req_keys = ["total_high_demand_buildings_citywide", "zone_with_highest_score", "top_10_zones_avg_score"]
        if all(k in j for k in req_keys):
            result["json_keys_ok"] = True
            
            result["json_accuracy"] = {
                "total_match": bool(abs(j["total_high_demand_buildings_citywide"] - gt_total_hd) < 2),
                "top_zone_match": bool(int(j["zone_with_highest_score"]) == gt_top_zone),
                "avg_match": bool(abs(float(j["top_10_zones_avg_score"]) - gt_top_10_avg) < 1.0)
            }
    except Exception as e:
        result["json_error"] = str(e)

# 4. Check Notebook Execution
nb_path = "/home/ga/urbansim_projects/notebooks/fire_resource_assessment.ipynb"
if os.path.exists(nb_path):
    result["notebook_exists"] = True
    try:
        with open(nb_path, 'r') as f:
            nb = json.load(f)
        code_cells = [c for c in nb.get('cells', []) if c.get('cell_type') == 'code']
        num_executed = sum(1 for c in code_cells if c.get('execution_count') is not None)
        result["notebook_executed"] = num_executed >= 2
    except:
        pass

# 5. Check Plot Output
plot_path = "/home/ga/urbansim_projects/output/top_20_fire_demand_zones.png"
if os.path.exists(plot_path):
    result["plot_exists"] = True
    result["plot_size_kb"] = os.path.getsize(plot_path) / 1024
    result["plot_created"] = os.path.getmtime(plot_path) > task_start

# Finalize
result["timestamp"] = __import__('datetime').datetime.now().isoformat()
with open('/tmp/_task_result_tmp.json', 'w') as f:
    json.dump(result, f, indent=2, default=str)
PYEOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/_task_result_tmp.json /tmp/task_result.json 2>/dev/null || sudo cp /tmp/_task_result_tmp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/_task_result_tmp.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="