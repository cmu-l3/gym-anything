#!/bin/bash
# export_result.sh — flood_frequency_analysis

RESULTS_DIR="/home/ga/Documents/hec_ras_results"
MUNCIE_DIR="/home/ga/Documents/hec_ras_projects/Muncie"
TASK_START_FILE="/tmp/task_start_flood_freq"

python3 -u << 'PYEOF'
import json, os, csv, re

results_dir = "/home/ga/Documents/hec_ras_results"
muncie_dir  = "/home/ga/Documents/hec_ras_projects/Muncie"
task_start  = int(open("/tmp/task_start_flood_freq").read().strip()) if os.path.exists("/tmp/task_start_flood_freq") else 0

result = {
    "task": "flood_frequency_analysis",
    "frequency_csv_exists": False,
    "bfe_file_exists": False,
    "frequency_rows": [],
    "bfe_value": None,
    "bfe_raw_line": "",
    "csv_has_header": False,
    "csv_row_count": 0,
    "return_periods_present": [],
    "design_flows_present": [],
    "wse_values": [],
    "hdf_modified_after_start": False,
    "b04_modified_after_start": False,
}

# Check HDF5 output was updated (simulation was run)
hdf_path = os.path.join(muncie_dir, "Muncie.p04.hdf")
if os.path.exists(hdf_path):
    mtime = int(os.path.getmtime(hdf_path))
    result["hdf_modified_after_start"] = mtime > task_start
    result["hdf_mtime"] = mtime

# Check b04 was modified
b04_path = os.path.join(muncie_dir, "Muncie.b04")
if os.path.exists(b04_path):
    mtime = int(os.path.getmtime(b04_path))
    result["b04_modified_after_start"] = mtime > task_start

# Check frequency_results.csv
csv_path = os.path.join(results_dir, "frequency_results.csv")
if os.path.exists(csv_path):
    result["frequency_csv_exists"] = True
    try:
        with open(csv_path, newline='') as f:
            reader = csv.reader(f)
            rows = list(reader)
        if rows:
            header = [h.strip().lower() for h in rows[0]]
            result["csv_has_header"] = ("return_period" in header and
                                        "design_flow_cfs" in header and
                                        "peak_wse_ft" in header)
            data_rows = rows[1:] if result["csv_has_header"] else rows
            result["csv_row_count"] = len(data_rows)
            for row in data_rows:
                if len(row) >= 3:
                    try:
                        rp   = int(str(row[0]).strip())
                        flow = float(str(row[1]).strip())
                        wse  = float(str(row[2]).strip())
                        result["return_periods_present"].append(rp)
                        result["design_flows_present"].append(flow)
                        result["wse_values"].append(wse)
                        result["frequency_rows"].append({
                            "return_period": rp,
                            "design_flow_cfs": flow,
                            "peak_wse_ft": wse
                        })
                    except (ValueError, IndexError):
                        pass
    except Exception as e:
        result["csv_parse_error"] = str(e)

# Check bfe_documentation.txt
bfe_path = os.path.join(results_dir, "bfe_documentation.txt")
if os.path.exists(bfe_path):
    result["bfe_file_exists"] = True
    try:
        content = open(bfe_path).read()
        result["bfe_raw_line"] = content.strip()[:500]
        m = re.search(r'BFE\s*=\s*([0-9]+\.?[0-9]*)', content, re.IGNORECASE)
        if m:
            result["bfe_value"] = float(m.group(1))
    except Exception as e:
        result["bfe_parse_error"] = str(e)

out_path = "/tmp/flood_freq_result.json"
with open(out_path, "w") as f:
    json.dump(result, f, indent=2)
print(f"Export written to {out_path}")
print(json.dumps(result, indent=2))
PYEOF

exit 0
