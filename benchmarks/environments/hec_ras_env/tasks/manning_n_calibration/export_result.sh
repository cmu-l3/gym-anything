#!/bin/bash
# export_result.sh — manning_n_calibration

python3 -u << 'PYEOF'
import json, os, csv, re, numpy as np

results_dir = "/home/ga/Documents/hec_ras_results"
muncie_dir  = "/home/ga/Documents/hec_ras_projects/Muncie"
task_start  = int(open("/tmp/task_start_calib").read().strip()) if os.path.exists("/tmp/task_start_calib") else 0

result = {
    "task": "manning_n_calibration",
    "calib_log_exists": False,
    "calib_report_exists": False,
    "log_rows": [],
    "log_row_count": 0,
    "log_has_header": False,
    "n_values_tested": [],
    "simulated_wse_values": [],
    "residual_values": [],
    "report_text": "",
    "report_n_value": None,
    "report_residual": None,
    "report_peak_wse": None,
    "hdf_modified_after_start": False,
    "final_n_in_hdf": None,
}

# Check HDF5 was modified (simulation run)
tmp_hdf = os.path.join(muncie_dir, "Muncie.p04.tmp.hdf")
out_hdf = os.path.join(muncie_dir, "Muncie.p04.hdf")
if os.path.exists(out_hdf):
    mtime = int(os.path.getmtime(out_hdf))
    result["hdf_modified_after_start"] = mtime > task_start

# Read final Manning's n from the template HDF5
try:
    import h5py
    with h5py.File(tmp_hdf, "r") as f:
        mn_path = "Geometry/2D Flow Areas/Muncie/Manning's n"
        if mn_path in f:
            mn_arr = f[mn_path][:]
            finite_mn = mn_arr[np.isfinite(mn_arr) & (mn_arr > 0) & (mn_arr < 1.0)]
            if len(finite_mn) > 0:
                result["final_n_in_hdf"] = round(float(np.mean(finite_mn)), 4)
except Exception as e:
    result["hdf_read_error"] = str(e)

# Check calibration_log.csv
log_path = os.path.join(results_dir, "calibration_log.csv")
if os.path.exists(log_path):
    result["calib_log_exists"] = True
    try:
        with open(log_path, newline='') as f:
            reader = csv.reader(f)
            rows   = list(reader)
        if rows:
            header = [h.strip().lower() for h in rows[0]]
            expected = {"run_id", "mannings_n", "simulated_peak_wse_ft", "residual_ft"}
            result["log_has_header"] = expected.issubset(set(header))
            col = {h: i for i, h in enumerate(header)}
            data_rows = rows[1:] if result["log_has_header"] else rows
            result["log_row_count"] = len(data_rows)
            for row in data_rows:
                try:
                    n_val  = float(row[col.get("mannings_n", 1)].strip())
                    wse    = float(row[col.get("simulated_peak_wse_ft", 2)].strip())
                    res    = float(row[col.get("residual_ft", 3)].strip())
                    result["n_values_tested"].append(n_val)
                    result["simulated_wse_values"].append(wse)
                    result["residual_values"].append(res)
                    result["log_rows"].append({"n": n_val, "wse": wse, "residual": res})
                except (IndexError, ValueError, KeyError):
                    pass
    except Exception as e:
        result["log_parse_error"] = str(e)

# Check calibration_report.txt
rep_path = os.path.join(results_dir, "calibration_report.txt")
if os.path.exists(rep_path):
    result["calib_report_exists"] = True
    try:
        content = open(rep_path).read()
        result["report_text"] = content[:2000]
        # Extract numbers from report
        m_n   = re.search(r'[Mm]anning.*?n\s*[=:]\s*([0-9]+\.[0-9]+)', content)
        m_wse = re.search(r'(?:simulated|final)\s+peak\s+(?:WSE|wse|stage)[^0-9]*([0-9]+\.[0-9]+)', content, re.IGNORECASE)
        m_res = re.search(r'residual[^0-9-]*(-?[0-9]+\.[0-9]+)', content, re.IGNORECASE)
        if m_n:
            result["report_n_value"] = float(m_n.group(1))
        if m_wse:
            result["report_peak_wse"] = float(m_wse.group(1))
        if m_res:
            result["report_residual"] = float(m_res.group(1))
    except Exception as e:
        result["report_parse_error"] = str(e)

out_path = "/tmp/calib_result.json"
with open(out_path, "w") as f:
    json.dump(result, f, indent=2)
print(f"Export written to {out_path}")
print(json.dumps(result, indent=2))
PYEOF

exit 0
