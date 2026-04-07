#!/bin/bash
echo "=== Exporting nonres_space_utilization result ==="

source /workspace/scripts/task_utils.sh

# Take final state screenshot
take_screenshot /tmp/task_final.png

activate_venv

# Extract execution information and agent's output metrics into a JSON file
python << 'PYEOF'
import json, os, re

task_start = int(open('/home/ga/.task_start_time').read().strip()) if os.path.exists('/home/ga/.task_start_time') else 0

result = {
    "csv_exists": False,
    "csv_created_during_task": False,
    "csv_has_required_cols": False,
    "agent_num_zones": 0,
    "agent_total_non_res_sqft": 0,
    "agent_total_jobs": 0,
    "agent_median_sqft_per_job": 0,
    "agent_top_5_zones": [],
    "agent_is_sorted": False,
    "plot_exists": False,
    "plot_size_kb": 0,
    "plot_created_during_task": False,
    "notebook_exists": False,
    "notebook_created_during_task": False,
    "notebook_analysis": {}
}

# 1. Analyze Plot
plot_path = '/home/ga/urbansim_projects/output/space_utilization_scatter.png'
if os.path.exists(plot_path):
    result['plot_exists'] = True
    result['plot_size_kb'] = os.path.getsize(plot_path) / 1024
    result['plot_created_during_task'] = os.path.getmtime(plot_path) > task_start

# 2. Analyze Notebook
nb_path = '/home/ga/urbansim_projects/notebooks/space_utilization.ipynb'
if os.path.exists(nb_path):
    result['notebook_exists'] = True
    result['notebook_created_during_task'] = os.path.getmtime(nb_path) > task_start
    try:
        with open(nb_path, 'r') as f:
            nb = json.load(f)
        
        code_cells = [c for c in nb.get('cells', []) if c.get('cell_type') == 'code']
        code = '\n'.join([''.join(c.get('source', [])) for c in code_cells])
        code_no_comments = re.sub(r'#.*', '', code)
        
        num_executed = sum(1 for c in code_cells if c.get('execution_count'))
        has_errors = any(out.get('output_type') == 'error' for c in code_cells for out in c.get('outputs', []))

        result['notebook_analysis'] = {
            'num_executed': num_executed,
            'has_errors': has_errors,
            'has_read_hdf': bool(re.search(r'read_hdf|HDFStore', code_no_comments)),
            'has_merge': bool(re.search(r'merge|join', code_no_comments)),
            'has_groupby': bool(re.search(r'groupby', code_no_comments)),
            'has_scatter': bool(re.search(r'scatter|plot', code_no_comments)),
            'has_to_csv': bool(re.search(r'to_csv', code_no_comments)),
            'has_savefig': bool(re.search(r'savefig', code_no_comments))
        }
    except Exception as e:
        result['notebook_analysis'] = {'error': str(e)}

# 3. Analyze CSV
csv_path = '/home/ga/urbansim_projects/output/zone_space_utilization.csv'
if os.path.exists(csv_path):
    result['csv_exists'] = True
    result['csv_created_during_task'] = os.path.getmtime(csv_path) > task_start
    try:
        import pandas as pd
        df = pd.read_csv(csv_path)
        
        # Standardize column names for checking
        cols = [c.lower().strip() for c in df.columns]
        req_cols = {'zone_id', 'total_non_res_sqft', 'total_jobs', 'sqft_per_job'}
        
        if req_cols.issubset(set(cols)):
            result['csv_has_required_cols'] = True
            
            # Ensure correct column mapping
            df.columns = cols
            
            # Clean data just in case of empty rows
            df = df.dropna(subset=['zone_id', 'total_non_res_sqft', 'total_jobs', 'sqft_per_job'])
            
            result['agent_num_zones'] = len(df)
            result['agent_total_non_res_sqft'] = float(df['total_non_res_sqft'].sum())
            result['agent_total_jobs'] = float(df['total_jobs'].sum())
            result['agent_median_sqft_per_job'] = float(df['sqft_per_job'].median())
            result['agent_top_5_zones'] = df['zone_id'].head(5).astype(int).tolist()
            result['agent_is_sorted'] = bool(df['sqft_per_job'].is_monotonic_increasing)
    except Exception as e:
        result['csv_error'] = str(e)

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Export Complete. Results written to /tmp/task_result.json."