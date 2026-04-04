#!/bin/bash
# export_result.sh — dam_breach_scenario

python3 -u << 'PYEOF'
import json, os, re

results_dir = "/home/ga/Documents/hec_ras_results"
muncie_dir  = "/home/ga/Documents/hec_ras_projects/Muncie"
task_start  = int(open("/tmp/task_start_dambreach").read().strip()) if os.path.exists("/tmp/task_start_dambreach") else 0

result = {
    "task": "dam_breach_scenario",
    "report_exists": False,
    "b04_modified": False,
    "hdf_modified_after_start": False,
    "b04_peak_flow": None,
    "b04_line_count": 0,
    "report_peak_breach_flow": None,
    "report_peak_wse": None,
    "report_mean_peak_wse": None,
    "report_peak_timestep_min": None,
    "report_summary_word_count": 0,
    "report_raw": "",
}

# Check HDF5 was updated
hdf_path = os.path.join(muncie_dir, "Muncie.p04.hdf")
if os.path.exists(hdf_path):
    mtime = int(os.path.getmtime(hdf_path))
    result["hdf_modified_after_start"] = mtime > task_start

# Inspect the b04 file for modifications
b04_path = os.path.join(muncie_dir, "Muncie.b04")
b04_orig = os.path.join(muncie_dir, "Muncie.b04.original_backup")
if os.path.exists(b04_path):
    try:
        content = open(b04_path).read()
        result["b04_line_count"] = len(content.splitlines())
        # If line count differs from backup, it was modified
        if os.path.exists(b04_orig):
            orig_lines = len(open(b04_orig).read().splitlines())
            result["b04_modified"] = result["b04_line_count"] != orig_lines
            result["b04_original_line_count"] = orig_lines
        # Extract peak flow value from hydrograph section
        flows = re.findall(r'^\s*\d+\.\s+([\d.]+)\s*$', content, re.MULTILINE)
        if flows:
            flow_vals = [float(f) for f in flows]
            result["b04_peak_flow"] = max(flow_vals)
    except Exception as e:
        result["b04_parse_error"] = str(e)

# Check dam_breach_report.txt
rep_path = os.path.join(results_dir, "dam_breach_report.txt")
if os.path.exists(rep_path):
    result["report_exists"] = True
    try:
        content = open(rep_path).read()
        result["report_raw"] = content[:3000]
        # Parse labeled fields
        m = re.search(r'PEAK_BREACH_FLOW_CFS\s*=\s*([0-9]+\.?[0-9]*)', content)
        if m: result["report_peak_breach_flow"] = float(m.group(1))
        m = re.search(r'PEAK_WSE_FT\s*=\s*([0-9]+\.?[0-9]*)', content)
        if m: result["report_peak_wse"] = float(m.group(1))
        m = re.search(r'MEAN_PEAK_WSE_FT\s*=\s*([0-9]+\.?[0-9]*)', content)
        if m: result["report_mean_peak_wse"] = float(m.group(1))
        m = re.search(r'PEAK_WSE_TIMESTEP_MIN\s*=\s*([0-9]+\.?[0-9]*)', content)
        if m: result["report_peak_timestep_min"] = float(m.group(1))
        # Count words in summary (non-header lines)
        summary_lines = [l for l in content.splitlines()
                         if l.strip() and '=' not in l and not l.startswith('#')]
        result["report_summary_word_count"] = sum(len(l.split()) for l in summary_lines)
    except Exception as e:
        result["report_parse_error"] = str(e)

out_path = "/tmp/dambreach_result.json"
with open(out_path, "w") as f:
    json.dump(result, f, indent=2)
print(f"Export written to {out_path}")
print(json.dumps(result, indent=2))
PYEOF

exit 0
