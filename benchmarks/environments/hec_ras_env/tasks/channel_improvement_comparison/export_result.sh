#!/bin/bash
# export_result.sh — channel_improvement_comparison

python3 -u << 'PYEOF'
import json, os, csv, re

results_dir = "/home/ga/Documents/hec_ras_results"
muncie_dir  = "/home/ga/Documents/hec_ras_projects/Muncie"
task_start  = int(open("/tmp/task_start_channelimp").read().strip()) if os.path.exists("/tmp/task_start_channelimp") else 0

result = {
    "task": "channel_improvement_comparison",
    "baseline_json_exists": False,
    "improved_json_exists": False,
    "comparison_csv_exists": False,
    "summary_exists": False,
    "baseline_peak_wse": None,
    "baseline_mean_wse": None,
    "baseline_inundated": None,
    "improved_peak_wse": None,
    "improved_mean_wse": None,
    "improved_inundated": None,
    "csv_has_header": False,
    "csv_rows": [],
    "csv_row_count": 0,
    "summary_word_count": 0,
    "summary_mentions_criterion": False,
    "hdf_modified_after_start": False,
    "hdf_mtime": 0,
}

# Check HDF5
hdf_path = os.path.join(muncie_dir, "Muncie.p04.hdf")
if os.path.exists(hdf_path):
    mtime = int(os.path.getmtime(hdf_path))
    result["hdf_modified_after_start"] = mtime > task_start
    result["hdf_mtime"] = mtime

# Load baseline_results.json
def load_json_metric(path, key):
    try:
        d = json.load(open(path))
        return d.get(key)
    except Exception:
        return None

bj = os.path.join(results_dir, "baseline_results.json")
if os.path.exists(bj):
    result["baseline_json_exists"] = True
    try:
        d = json.load(open(bj))
        result["baseline_peak_wse"]   = d.get("peak_wse_ft") or d.get("peak_wse")
        result["baseline_mean_wse"]   = d.get("mean_peak_wse_ft") or d.get("mean_peak_wse")
        result["baseline_inundated"]  = d.get("inundated_cells") or d.get("n_inundated")
    except Exception as e:
        result["baseline_json_error"] = str(e)

ij = os.path.join(results_dir, "improved_results.json")
if os.path.exists(ij):
    result["improved_json_exists"] = True
    try:
        d = json.load(open(ij))
        result["improved_peak_wse"]   = d.get("peak_wse_ft") or d.get("peak_wse")
        result["improved_mean_wse"]   = d.get("mean_peak_wse_ft") or d.get("mean_peak_wse")
        result["improved_inundated"]  = d.get("inundated_cells") or d.get("n_inundated")
    except Exception as e:
        result["improved_json_error"] = str(e)

# Check scenario_comparison.csv
cj = os.path.join(results_dir, "scenario_comparison.csv")
if os.path.exists(cj):
    result["comparison_csv_exists"] = True
    try:
        with open(cj, newline='') as f:
            reader = csv.reader(f)
            rows   = list(reader)
        if rows:
            header = [h.strip().lower() for h in rows[0]]
            expected_cols = {"scenario", "peak_wse_ft", "mean_peak_wse_ft",
                             "inundated_cells", "total_cells", "flood_reduction_pct"}
            result["csv_has_header"] = expected_cols.issubset(set(header))
            col = {h: i for i, h in enumerate(header)}
            data_rows = rows[1:] if result["csv_has_header"] else rows
            result["csv_row_count"] = len(data_rows)
            for row in data_rows:
                try:
                    rec = {
                        "scenario":           row[col.get("scenario", 0)].strip() if "scenario" in col else row[0].strip(),
                        "peak_wse_ft":        float(row[col["peak_wse_ft"]].strip()) if "peak_wse_ft" in col else None,
                        "mean_peak_wse_ft":   float(row[col["mean_peak_wse_ft"]].strip()) if "mean_peak_wse_ft" in col else None,
                        "inundated_cells":    int(float(row[col["inundated_cells"]].strip())) if "inundated_cells" in col else None,
                        "flood_reduction_pct": float(row[col["flood_reduction_pct"]].strip()) if "flood_reduction_pct" in col else None,
                    }
                    result["csv_rows"].append(rec)
                except (IndexError, ValueError, KeyError):
                    pass
    except Exception as e:
        result["csv_error"] = str(e)

# Check project_benefit_summary.txt
sj = os.path.join(results_dir, "project_benefit_summary.txt")
if os.path.exists(sj):
    result["summary_exists"] = True
    try:
        content = open(sj).read()
        result["summary_text"] = content[:3000]
        result["summary_word_count"] = len(content.split())
        # Check for design criterion mention
        result["summary_mentions_criterion"] = bool(
            re.search(r'0\.3|design.criterion|SRF|qualif', content, re.IGNORECASE)
        )
    except Exception as e:
        result["summary_error"] = str(e)

out_path = "/tmp/channelimp_result.json"
with open(out_path, "w") as f:
    json.dump(result, f, indent=2)
print(f"Export written to {out_path}")
print(json.dumps(result, indent=2))
PYEOF

exit 0
