#!/bin/bash
# export_result.sh — floodplain_technical_report
# Collects agent output files, checks existence/size/timestamps,
# and packages everything into /tmp/floodplain_result.json for the verifier.

source /workspace/scripts/task_utils.sh

echo "=== Exporting floodplain_technical_report results ==="

# Take final screenshot
take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_floodplain 2>/dev/null || echo "0")

python3 -u << 'PYEOF'
import json, os, re, csv

results_dir = "/home/ga/Documents/hec_ras_results"
muncie_dir  = "/home/ga/Documents/hec_ras_projects/Muncie"
task_start  = int(open("/tmp/task_start_floodplain").read().strip()) if os.path.exists("/tmp/task_start_floodplain") else 0

result = {
    "task": "floodplain_technical_report",
    # --- File existence ---
    "profile_csv_exists": False,
    "infra_csv_exists": False,
    "summary_exists": False,
    # --- File timestamps ---
    "profile_created_during_task": False,
    "infra_created_during_task": False,
    "summary_created_during_task": False,
    # --- Simulation evidence ---
    "b04_modified": False,
    "hdf_modified_after_start": False,
    # --- Profile CSV content ---
    "profile_row_count": 0,
    "profile_has_header": False,
    "profile_rows": [],
    # --- Infrastructure CSV content ---
    "infra_row_count": 0,
    "infra_has_header": False,
    "infra_rows": [],
    # --- Summary content ---
    "summary_raw": "",
    "summary_values": {},
}

# ── Check simulation evidence ──
hdf_path = os.path.join(muncie_dir, "Muncie.p04.hdf")
if not os.path.exists(hdf_path):
    hdf_path = os.path.join(muncie_dir, "Muncie.p04.tmp.hdf")
if os.path.exists(hdf_path):
    mtime = int(os.path.getmtime(hdf_path))
    result["hdf_modified_after_start"] = mtime > task_start

b04_path = os.path.join(muncie_dir, "Muncie.b04")
b04_backup = os.path.join(muncie_dir, "Muncie.b04.original_backup")
if os.path.exists(b04_path) and os.path.exists(b04_backup):
    curr_size = os.path.getsize(b04_path)
    orig_size = os.path.getsize(b04_backup)
    curr_mtime = int(os.path.getmtime(b04_path))
    result["b04_modified"] = (curr_size != orig_size) or (curr_mtime > task_start)

# ── Check floodplain_profile.csv ──
profile_path = os.path.join(results_dir, "floodplain_profile.csv")
if os.path.exists(profile_path):
    result["profile_csv_exists"] = True
    mtime = int(os.path.getmtime(profile_path))
    result["profile_created_during_task"] = mtime > task_start
    try:
        with open(profile_path, newline='') as f:
            reader = csv.reader(f)
            rows = list(reader)
        if rows:
            header = [h.strip() for h in rows[0]]
            expected_cols = ["River_Station", "Peak_WSE_ft", "Max_Velocity_fps",
                             "Bed_Elev_ft", "Flood_Depth_ft", "Sensitivity_Delta_WSE_ft"]
            result["profile_has_header"] = all(c in header for c in expected_cols)
            data_rows = rows[1:] if result["profile_has_header"] else rows
            result["profile_row_count"] = len(data_rows)
            for row in data_rows[:100]:  # cap at 100 rows
                if len(row) >= 6:
                    try:
                        result["profile_rows"].append({
                            "River_Station": float(row[0].strip()),
                            "Peak_WSE_ft": float(row[1].strip()),
                            "Max_Velocity_fps": float(row[2].strip()),
                            "Bed_Elev_ft": float(row[3].strip()),
                            "Flood_Depth_ft": float(row[4].strip()),
                            "Sensitivity_Delta_WSE_ft": float(row[5].strip()),
                        })
                    except (ValueError, IndexError):
                        pass
    except Exception as e:
        result["profile_parse_error"] = str(e)

# ── Check infrastructure_impact.csv ──
infra_path = os.path.join(results_dir, "infrastructure_impact.csv")
if os.path.exists(infra_path):
    result["infra_csv_exists"] = True
    mtime = int(os.path.getmtime(infra_path))
    result["infra_created_during_task"] = mtime > task_start
    try:
        with open(infra_path, newline='') as f:
            reader = csv.reader(f)
            rows = list(reader)
        if rows:
            header = [h.strip() for h in rows[0]]
            expected_cols = ["Facility_Name", "River_Station", "FFE_ft",
                             "Interpolated_WSE_ft", "Flood_Depth_ft", "Status"]
            result["infra_has_header"] = all(c in header for c in expected_cols)
            data_rows = rows[1:] if result["infra_has_header"] else rows
            result["infra_row_count"] = len(data_rows)
            for row in data_rows:
                if len(row) >= 6:
                    try:
                        result["infra_rows"].append({
                            "Facility_Name": row[0].strip(),
                            "River_Station": float(row[1].strip()),
                            "FFE_ft": float(row[2].strip()),
                            "Interpolated_WSE_ft": float(row[3].strip()),
                            "Flood_Depth_ft": float(row[4].strip()),
                            "Status": row[5].strip().upper(),
                        })
                    except (ValueError, IndexError):
                        pass
    except Exception as e:
        result["infra_parse_error"] = str(e)

# ── Check report_summary.txt ──
summary_path = os.path.join(results_dir, "report_summary.txt")
if os.path.exists(summary_path):
    result["summary_exists"] = True
    mtime = int(os.path.getmtime(summary_path))
    result["summary_created_during_task"] = mtime > task_start
    try:
        content = open(summary_path).read()
        result["summary_raw"] = content[:3000]
        # Parse labeled values
        for label in ["NUM_CROSS_SECTIONS", "MAX_FLOOD_DEPTH_FT",
                      "MAX_FLOOD_DEPTH_STATION", "FACILITIES_FLOODED",
                      "FACILITIES_SAFE", "MAX_SENSITIVITY_DELTA_FT"]:
            m = re.search(rf'{label}\s*=\s*([^\n\r]+)', content)
            if m:
                val = m.group(1).strip()
                try:
                    result["summary_values"][label] = float(val)
                except ValueError:
                    result["summary_values"][label] = val
    except Exception as e:
        result["summary_parse_error"] = str(e)

out_path = "/tmp/floodplain_result.json"
with open(out_path, "w") as f:
    json.dump(result, f, indent=2)
print(f"Export written to {out_path}")
print(json.dumps(result, indent=2))
PYEOF

# Ensure ground truth and result are readable by the verifier
chmod 666 /tmp/floodplain_result.json /tmp/floodplain_gt.json 2>/dev/null || true

echo "=== Export complete ==="
exit 0
