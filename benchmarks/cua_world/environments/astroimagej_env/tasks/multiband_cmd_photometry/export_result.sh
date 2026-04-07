#!/bin/bash
echo "=== Exporting Multi-Band CMD Photometry Results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

PROJECT_DIR="/home/ga/AstroImages/m12_cmd"
RESULTS_DIR="$PROJECT_DIR/results"

# Analyze results using Python
python3 << 'PYEOF'
import json, os, glob, sys, re

try:
    import numpy as np
    HAS_NUMPY = True
except ImportError:
    HAS_NUMPY = False

PROJECT = "/home/ga/AstroImages/m12_cmd"
RESULTS = f"{PROJECT}/results"

result = {
    # V-band measurements
    "v_band_measurement_found": False,
    "v_band_measurement_path": None,
    "v_band_num_stars": 0,
    # B-band measurements
    "b_band_measurement_found": False,
    "b_band_measurement_path": None,
    "b_band_num_stars": 0,
    # Calibrated photometry
    "calibrated_csv_found": False,
    "calibrated_csv_path": None,
    "calibrated_num_stars": 0,
    "calibrated_columns": [],
    "bv_values": [],
    "v_cal_values": [],
    # Zero-points
    "zp_v_found": False,
    "zp_b_found": False,
    "zp_v_value": None,
    "zp_b_value": None,
    # CMD plot
    "cmd_plot_found": False,
    "cmd_plot_path": None,
    "cmd_plot_size_bytes": 0,
    # Report
    "report_found": False,
    "report_path": None,
    "report_content": "",
    "report_mentions_zp": False,
    "report_mentions_bv": False,
    "report_mentions_brightest": False,
    # Python script
    "analysis_script_found": False,
    # Window state
    "windows_list": "",
}

# Check windows
try:
    import subprocess
    wl = subprocess.check_output(
        ["wmctrl", "-l"], env={"DISPLAY": ":1"}, stderr=subprocess.DEVNULL
    ).decode()
    result["windows_list"] = wl
except Exception:
    pass

# ================================================================
# Search for measurement files from AstroImageJ
# ================================================================
SEARCH_DIRS = [PROJECT, RESULTS, "/home/ga/AstroImages", "/home/ga", "/tmp"]
measurement_files = []
for d in SEARCH_DIRS:
    if not os.path.isdir(d):
        continue
    for pattern in [
        "*Measurements*.xls", "*Measurements*.tbl", "*Measurements*.csv",
        "*measurements*.xls", "*measurements*.tbl", "*measurements*.csv",
        "*photometry*.csv", "*photometry*.tbl",
        "v_band_*.csv", "v_band_*.xls", "b_band_*.csv", "b_band_*.xls",
    ]:
        measurement_files.extend(glob.glob(f"{d}/{pattern}"))
        measurement_files.extend(glob.glob(f"{d}/**/{pattern}", recursive=True))

measurement_files = sorted(set(measurement_files))
print(f"Found {len(measurement_files)} measurement files: {measurement_files}")

# Classify measurement files as V-band or B-band
for mf in measurement_files:
    fname = os.path.basename(mf).lower()
    try:
        with open(mf, 'r', errors='ignore') as f:
            content = f.read(5000)
        line_count = max(content.count('\n') - 1, 0)

        is_v = ('vcomb' in fname or 'vcomb' in content.lower() or
                'v_band' in fname or 'v-band' in fname)
        is_b = ('bcomb' in fname or 'bcomb' in content.lower() or
                'b_band' in fname or 'b-band' in fname)

        if is_v and not result["v_band_measurement_found"]:
            result["v_band_measurement_found"] = True
            result["v_band_measurement_path"] = mf
            result["v_band_num_stars"] = line_count
        elif is_b and not result["b_band_measurement_found"]:
            result["b_band_measurement_found"] = True
            result["b_band_measurement_path"] = mf
            result["b_band_num_stars"] = line_count
        elif not is_v and not is_b:
            # Assign to first empty slot
            if not result["v_band_measurement_found"]:
                result["v_band_measurement_found"] = True
                result["v_band_measurement_path"] = mf
                result["v_band_num_stars"] = line_count
            elif not result["b_band_measurement_found"]:
                result["b_band_measurement_found"] = True
                result["b_band_measurement_path"] = mf
                result["b_band_num_stars"] = line_count
    except Exception as e:
        print(f"Error reading {mf}: {e}")

# ================================================================
# Check for calibrated photometry CSV
# ================================================================
cal_patterns = [
    f"{RESULTS}/calibrated_photometry.csv",
    f"{RESULTS}/calibrated*.csv",
    f"{PROJECT}/calibrated_photometry.csv",
    f"{PROJECT}/calibrated*.csv",
    f"{PROJECT}/results/calibrated*.csv",
]
for pattern in cal_patterns:
    matches = glob.glob(pattern)
    if matches:
        cal_path = matches[0]
        result["calibrated_csv_found"] = True
        result["calibrated_csv_path"] = cal_path
        try:
            with open(cal_path, 'r') as f:
                lines = f.readlines()
            if lines:
                result["calibrated_columns"] = [c.strip() for c in lines[0].split(',')]
                result["calibrated_num_stars"] = len(lines) - 1

                # Parse B-V and V_cal values
                header = [c.lower().strip() for c in result["calibrated_columns"]]
                bv_idx = None
                vcal_idx = None
                for i, col in enumerate(header):
                    col_clean = col.replace(' ', '_').replace('-', '_')
                    if any(k in col_clean for k in ['bv', 'b_v', 'color']):
                        bv_idx = i
                    if any(k in col_clean for k in ['v_cal', 'vcal']):
                        vcal_idx = i

                for line in lines[1:]:
                    parts = line.strip().split(',')
                    try:
                        if bv_idx is not None and bv_idx < len(parts):
                            result["bv_values"].append(float(parts[bv_idx]))
                        if vcal_idx is not None and vcal_idx < len(parts):
                            result["v_cal_values"].append(float(parts[vcal_idx]))
                    except (ValueError, IndexError):
                        continue
        except Exception as e:
            print(f"Error parsing calibrated CSV: {e}")
        break

# ================================================================
# Check for CMD plot
# ================================================================
cmd_patterns = [
    f"{RESULTS}/cmd_plot.png",
    f"{RESULTS}/cmd*.png",
    f"{RESULTS}/CMD*.png",
    f"{RESULTS}/*.png",
    f"{PROJECT}/cmd_plot.png",
    f"{PROJECT}/cmd*.png",
]
for pattern in cmd_patterns:
    matches = glob.glob(pattern)
    if matches:
        img_path = matches[0]
        size = os.path.getsize(img_path)
        if size > 1000:  # at least 1KB
            result["cmd_plot_found"] = True
            result["cmd_plot_path"] = img_path
            result["cmd_plot_size_bytes"] = size
            break

# ================================================================
# Check for summary report
# ================================================================
report_patterns = [
    f"{RESULTS}/photometry_report.txt",
    f"{RESULTS}/*report*.txt",
    f"{PROJECT}/photometry_report.txt",
    f"{PROJECT}/*report*.txt",
]
for pattern in report_patterns:
    matches = glob.glob(pattern)
    if matches:
        rpt_path = matches[0]
        result["report_found"] = True
        result["report_path"] = rpt_path
        try:
            with open(rpt_path, 'r') as f:
                content = f.read()
            result["report_content"] = content[:3000]
            cl = content.lower()

            result["report_mentions_zp"] = any(kw in cl for kw in [
                'zero point', 'zero-point', 'zeropoint', 'zp_v', 'zp_b', 'zp =', 'zp='])
            result["report_mentions_bv"] = any(kw in cl for kw in [
                'b-v', 'b_v', 'bv', 'color index', 'color range'])
            result["report_mentions_brightest"] = any(kw in cl for kw in [
                'brightest', 'bright star', 'magnitude', 'v_cal',
                'calibrated v', 'v ='])

            # Extract zero-point values from report
            zp_v_match = re.search(
                r'ZP[_\s]*V[^=:\d]*[=:]\s*([-+]?\d+\.?\d*)', content, re.IGNORECASE)
            zp_b_match = re.search(
                r'ZP[_\s]*B[^=:\d]*[=:]\s*([-+]?\d+\.?\d*)', content, re.IGNORECASE)
            if zp_v_match:
                result["zp_v_found"] = True
                result["zp_v_value"] = float(zp_v_match.group(1))
            if zp_b_match:
                result["zp_b_found"] = True
                result["zp_b_value"] = float(zp_b_match.group(1))

            # Also try generic patterns like "V zero point: -21.3"
            if not result["zp_v_found"]:
                alt_v = re.search(
                    r'V[- ]?(?:band\s+)?zero[- ]?point[^=:\d]*[=:]\s*([-+]?\d+\.?\d*)',
                    content, re.IGNORECASE)
                if alt_v:
                    result["zp_v_found"] = True
                    result["zp_v_value"] = float(alt_v.group(1))
            if not result["zp_b_found"]:
                alt_b = re.search(
                    r'B[- ]?(?:band\s+)?zero[- ]?point[^=:\d]*[=:]\s*([-+]?\d+\.?\d*)',
                    content, re.IGNORECASE)
                if alt_b:
                    result["zp_b_found"] = True
                    result["zp_b_value"] = float(alt_b.group(1))
        except Exception as e:
            print(f"Error reading report: {e}")
        break

# ================================================================
# Check for analysis script
# ================================================================
script_patterns = [
    f"{PROJECT}/analyze_cmd.py",
    f"{PROJECT}/*.py",
    f"{RESULTS}/*.py",
]
for pattern in script_patterns:
    if glob.glob(pattern):
        result["analysis_script_found"] = True
        break

# Load ground truth and embed in result
gt_path = "/tmp/cmd_ground_truth.json"
if os.path.exists(gt_path):
    with open(gt_path) as f:
        result["ground_truth"] = json.load(f)

# Close AstroImageJ
os.system("pkill -f 'astroimagej\\|aij\\|AstroImageJ' 2>/dev/null")

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
chmod_cmd = "chmod 666 /tmp/task_result.json"
os.system(chmod_cmd)
print("Export complete")
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="
