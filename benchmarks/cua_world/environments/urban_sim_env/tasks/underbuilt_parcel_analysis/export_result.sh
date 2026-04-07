#!/bin/bash
echo "=== Exporting underbuilt_parcel_analysis result ==="

source /workspace/scripts/task_utils.sh
activate_venv

# Take final screenshot
take_screenshot /tmp/task_final.png

# Run Python script to securely calculate ground truth, analyze notebook, and package everything
python << 'PYEOF'
import json, re, os, math
import pandas as pd

# Load start time
task_start_path = '/home/ga/.task_start_time'
task_start = int(open(task_start_path).read().strip()) if os.path.exists(task_start_path) else 0

result = {
    "task_start_time": task_start,
    "notebook": {"exists": False, "modified": False, "analysis": {}},
    "csv": {"exists": False, "created": False, "data": []},
    "json_summary": {"exists": False, "created": False, "data": {}},
    "plot": {"exists": False, "created": False, "size_kb": 0},
    "ground_truth": {}
}

# 1. Analyze Notebook
nb_path = "/home/ga/urbansim_projects/notebooks/soft_site_analysis.ipynb"
if os.path.exists(nb_path):
    result["notebook"]["exists"] = True
    result["notebook"]["modified"] = os.path.getmtime(nb_path) > task_start
    try:
        with open(nb_path, 'r') as f:
            nb = json.load(f)
        code_cells = [c for c in nb.get('cells', []) if c.get('cell_type') == 'code']
        all_code = ''
        for c in code_cells:
            src = c.get('source', '')
            if isinstance(src, list):
                src = ''.join(src)
            lines = [l for l in src.split('\n') if not l.strip().startswith('#')]
            all_code += '\n'.join(lines) + '\n'
            
        result["notebook"]["analysis"] = {
            "num_code_cells": len(code_cells),
            "num_executed_cells": sum(1 for c in code_cells if c.get('execution_count') is not None),
            "has_pandas": bool(re.search(r'import pandas|from pandas', all_code)),
            "has_read_hdf": bool(re.search(r'read_hdf|HDFStore', all_code)),
            "has_groupby": bool(re.search(r'groupby', all_code)),
            "has_merge": bool(re.search(r'merge|join', all_code)),
            "has_far_logic": bool(re.search(r'building_sqft.*?/.*?parcel_sqft', all_code)),
            "has_thresholds": bool(re.search(r'5000', all_code)) and bool(re.search(r'0\.5', all_code)),
            "has_to_csv": bool(re.search(r'to_csv', all_code))
        }
    except Exception as e:
        result["notebook"]["analysis"] = {"error": str(e)}

# 2. Read Agent's CSV Output
csv_path = "/home/ga/urbansim_projects/output/top_soft_sites.csv"
if os.path.exists(csv_path):
    result["csv"]["exists"] = True
    result["csv"]["created"] = os.path.getmtime(csv_path) > task_start
    try:
        df_agent = pd.read_csv(csv_path)
        # Standardize column names slightly
        df_agent.columns = [str(c).strip().lower() for c in df_agent.columns]
        result["csv"]["data"] = df_agent.to_dict('records')
    except Exception:
        pass

# 3. Read Agent's JSON Output
json_path = "/home/ga/urbansim_projects/output/soft_sites_summary.json"
if os.path.exists(json_path):
    result["json_summary"]["exists"] = True
    result["json_summary"]["created"] = os.path.getmtime(json_path) > task_start
    try:
        with open(json_path, 'r') as f:
            result["json_summary"]["data"] = json.load(f)
    except Exception:
        pass

# 4. Check Plot
plot_path = "/home/ga/urbansim_projects/output/soft_sites_chart.png"
if os.path.exists(plot_path):
    result["plot"]["exists"] = True
    result["plot"]["created"] = os.path.getmtime(plot_path) > task_start
    result["plot"]["size_kb"] = os.path.getsize(plot_path) / 1024

# 5. Compute Ground Truth Safely
try:
    data_path = '/home/ga/urbansim_projects/data/sanfran_public.h5'
    bld = pd.read_hdf(data_path, 'buildings')
    parcels = pd.read_hdf(data_path, 'parcels')
    
    # Process
    bld_sqft = bld.groupby('parcel_id')['building_sqft'].sum().reset_index()
    p_merged = parcels.merge(bld_sqft, on='parcel_id', how='left')
    p_merged['building_sqft'] = p_merged['building_sqft'].fillna(0)
    p_merged['existing_far'] = p_merged['building_sqft'] / p_merged['parcel_sqft']
    
    # Filter soft sites
    soft_sites = p_merged[
        (p_merged['parcel_sqft'] >= 5000) & 
        (p_merged['existing_far'] < 0.5) & 
        (p_merged['existing_far'] > 0.01)
    ]
    
    # Aggregate by zone
    zone_agg = soft_sites.groupby('zone_id').agg(
        soft_site_count=('parcel_id', 'count'),
        total_soft_site_sqft=('parcel_sqft', 'sum')
    ).reset_index()
    zone_agg = zone_agg[zone_agg['soft_site_count'] > 0]
    
    # Get top 20
    top20 = zone_agg.sort_values('total_soft_site_sqft', ascending=False).head(20)
    
    # Save standard python types to result
    result["ground_truth"]["top_zones"] = top20.to_dict('records')
    result["ground_truth"]["total_soft_sites_citywide"] = int(soft_sites.shape[0])
    result["ground_truth"]["total_soft_site_sqft_citywide"] = float(soft_sites['parcel_sqft'].sum())
    result["ground_truth"]["top_zone_id"] = int(top20.iloc[0]['zone_id']) if not top20.empty else -1
except Exception as e:
    result["ground_truth"]["error"] = str(e)

# Write output safely
tmp_path = '/tmp/_task_result_tmp.json'
with open(tmp_path, 'w') as f:
    json.dump(result, f)
PYEOF

# Move securely to the expected location
rm -f /tmp/task_result.json 2>/dev/null || true
mv /tmp/_task_result_tmp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result JSON prepared."
echo "=== Export complete ==="