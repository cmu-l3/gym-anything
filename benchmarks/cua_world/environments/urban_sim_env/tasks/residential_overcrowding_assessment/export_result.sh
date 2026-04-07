#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh
activate_venv

# Take final screenshot
take_screenshot /tmp/task_end.png

# Analyze Notebook, CSV and output Plot and export as JSON.
python - << 'PYEOF'
import json, os, re, csv

task_start = int(open('/tmp/task_start_time.txt').read().strip()) if os.path.exists('/tmp/task_start_time.txt') else 0

result = {
    "task_start_time": task_start,
    "notebook": {"exists": False, "modified": False, "has_code": False, "patterns": {}, "num_exec": 0},
    "csv": {"exists": False, "modified": False, "columns": [], "rows": 0, "data_sample": {}},
    "plot": {"exists": False, "modified": False, "size_kb": 0}
}

nb_path = "/home/ga/urbansim_projects/notebooks/overcrowding_analysis.ipynb"
if os.path.exists(nb_path):
    result["notebook"]["exists"] = True
    result["notebook"]["modified"] = os.path.getmtime(nb_path) > task_start
    try:
        with open(nb_path, 'r') as f:
            nb = json.load(f)
        code_cells = [c for c in nb.get('cells', []) if c.get('cell_type') == 'code']
        all_code = ""
        for c in code_cells:
            src = c.get('source', '')
            if isinstance(src, list): src = ''.join(src)
            all_code += src + "\n"
        
        # Remove comments/string literals for pure code parsing
        clean = re.sub(r'"""[\s\S]*?"""|\'\'\'[\s\S]*?\'\'\'', '', all_code)
        clean = re.sub(r'"[^"\n]*"|\'[^\'\n]*\'', '', clean)
        
        result["notebook"]["patterns"]["has_hdf"] = bool(re.search(r'read_hdf|HDFStore', clean))
        result["notebook"]["patterns"]["has_merge"] = bool(re.search(r'merge|join', clean))
        result["notebook"]["patterns"]["has_groupby"] = bool(re.search(r'groupby', clean))
        result["notebook"]["num_exec"] = sum(1 for c in code_cells if c.get('execution_count'))
        result["notebook"]["has_code"] = len(clean.strip()) > 20
    except Exception as e:
        print("Notebook parsing error:", e)

csv_path = "/home/ga/urbansim_projects/output/overcrowding_by_zone.csv"
if os.path.exists(csv_path):
    result["csv"]["exists"] = True
    result["csv"]["modified"] = os.path.getmtime(csv_path) > task_start
    try:
        with open(csv_path, 'r') as f:
            reader = csv.DictReader(f)
            result["csv"]["columns"] = reader.fieldnames or []
            rows = list(reader)
            result["csv"]["rows"] = len(rows)
            # Retain a subset of agent data directly for verification
            for r in rows:
                if 'zone_id' in r:
                    result["csv"]["data_sample"][str(r['zone_id'])] = r
                elif 'ZONE_ID' in r:
                    result["csv"]["data_sample"][str(r['ZONE_ID'])] = r
    except Exception as e:
        print("CSV parsing error:", e)

plot_path = "/home/ga/urbansim_projects/output/overcrowding_top20.png"
if os.path.exists(plot_path):
    result["plot"]["exists"] = True
    result["plot"]["modified"] = os.path.getmtime(plot_path) > task_start
    result["plot"]["size_kb"] = os.path.getsize(plot_path) / 1024

with open('/tmp/_task_result_tmp.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/_task_result_tmp.json /tmp/task_result.json 2>/dev/null || sudo cp /tmp/_task_result_tmp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/_task_result_tmp.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="