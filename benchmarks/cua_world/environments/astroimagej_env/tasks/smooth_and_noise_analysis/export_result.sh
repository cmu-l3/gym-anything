#!/bin/bash
echo "=== Exporting Gaussian Smoothing and Noise Analysis Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

OUTPUT_DIR="/home/ga/AstroImages/eagle_smoothing/output"

# Run Python script to analyze the agent's output files
python3 << 'PYEOF'
import json
import os
import re
import glob
import numpy as np

try:
    from astropy.io import fits
    HAS_ASTROPY = True
except ImportError:
    HAS_ASTROPY = False

OUTPUT_DIR = "/home/ga/AstroImages/eagle_smoothing/output"
START_TIME_FILE = "/tmp/task_start_time.txt"

# Get task start time
try:
    with open(START_TIME_FILE, "r") as f:
        task_start = int(f.read().strip())
except:
    task_start = 0

result = {
    "smoothed_file_exists": False,
    "smoothed_created_during_task": False,
    "smoothed_mean": None,
    "smoothed_std": None,
    "smoothed_shape": None,
    
    "residual_file_exists": False,
    "residual_created_during_task": False,
    "residual_mean": None,
    "residual_std": None,
    "residual_shape": None,
    
    "report_file_exists": False,
    "report_content": "",
    "reported_orig_mean": None,
    "reported_orig_std": None,
    "reported_smooth_mean": None,
    "reported_smooth_std": None,
    "reported_resid_mean": None,
    "reported_resid_std": None,
    "reported_nrf": None
}

def check_fits_file(filepath):
    """Check existence, mtime, and extract stats from FITS"""
    info = {"exists": False, "created_during_task": False, "mean": None, "std": None, "shape": None}
    
    if os.path.exists(filepath):
        info["exists"] = True
        mtime = os.path.getmtime(filepath)
        if mtime >= task_start:
            info["created_during_task"] = True
            
        if HAS_ASTROPY:
            try:
                with fits.open(filepath) as hdul:
                    data = hdul[0].data.astype(float)
                    info["mean"] = float(np.nanmean(data))
                    info["std"] = float(np.nanstd(data))
                    info["shape"] = list(data.shape)
            except Exception as e:
                print(f"Error reading {filepath}: {e}")
    return info

# 1. Analyze Smoothed Image
smoothed_path = os.path.join(OUTPUT_DIR, "eagle_ha_smoothed.fits")
if not os.path.exists(smoothed_path):
    # Try finding any file with 'smooth' in name
    alt_smooth = glob.glob(os.path.join(OUTPUT_DIR, "*smooth*.fits"))
    if alt_smooth: smoothed_path = alt_smooth[0]

smooth_info = check_fits_file(smoothed_path)
result["smoothed_file_exists"] = smooth_info["exists"]
result["smoothed_created_during_task"] = smooth_info["created_during_task"]
result["smoothed_mean"] = smooth_info["mean"]
result["smoothed_std"] = smooth_info["std"]
result["smoothed_shape"] = smooth_info["shape"]

# 2. Analyze Residual Image
residual_path = os.path.join(OUTPUT_DIR, "eagle_ha_residual.fits")
if not os.path.exists(residual_path):
    alt_resid = glob.glob(os.path.join(OUTPUT_DIR, "*resid*.fits"))
    if alt_resid: residual_path = alt_resid[0]

resid_info = check_fits_file(residual_path)
result["residual_file_exists"] = resid_info["exists"]
result["residual_created_during_task"] = resid_info["created_during_task"]
result["residual_mean"] = resid_info["mean"]
result["residual_std"] = resid_info["std"]
result["residual_shape"] = resid_info["shape"]

# 3. Analyze Report File
report_path = os.path.join(OUTPUT_DIR, "smoothing_report.txt")
if not os.path.exists(report_path):
    alt_reports = glob.glob(os.path.join(OUTPUT_DIR, "*.txt"))
    if alt_reports: report_path = alt_reports[0]

if os.path.exists(report_path):
    result["report_file_exists"] = True
    try:
        with open(report_path, "r") as f:
            content = f.read()
            result["report_content"] = content
            
            # Helper to extract numbers following keywords
            def extract_val(pattern):
                match = re.search(pattern, content, re.IGNORECASE)
                if match:
                    try: return float(match.group(1).replace(',', ''))
                    except: pass
                return None

            # Attempt flexible parsing
            result["reported_orig_mean"] = extract_val(r'orig.*?mean.*?([0-9]+\.?[0-9]*)')
            result["reported_orig_std"] = extract_val(r'orig.*?std(?:dev|.*deviation).*?([0-9]+\.?[0-9]*)')
            
            result["reported_smooth_mean"] = extract_val(r'smooth.*?mean.*?([0-9]+\.?[0-9]*)')
            result["reported_smooth_std"] = extract_val(r'smooth.*?std(?:dev|.*deviation).*?([0-9]+\.?[0-9]*)')
            
            result["reported_resid_mean"] = extract_val(r'resid.*?mean.*?([-+]?[0-9]+\.?[0-9]*([eE][-+]?[0-9]+)?)')
            result["reported_resid_std"] = extract_val(r'resid.*?std(?:dev|.*deviation).*?([0-9]+\.?[0-9]*)')
            
            result["reported_nrf"] = extract_val(r'(?:noise reduction|nrf|factor).*?([0-9]+\.?[0-9]*)')
            
    except Exception as e:
        print(f"Error reading report: {e}")

# Check if AIJ is running
import subprocess
try:
    aij_running = "true" if subprocess.run(["pgrep", "-f", "AstroImageJ"], capture_output=True).returncode == 0 else "false"
except:
    aij_running = "false"
result["aij_running"] = aij_running

# Write results
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result JSON exported.")
PYEOF

echo "=== Export complete ==="