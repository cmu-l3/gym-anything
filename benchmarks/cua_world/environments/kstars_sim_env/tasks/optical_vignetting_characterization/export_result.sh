#!/bin/bash
echo "=== Exporting optical_vignetting_characterization results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

# The core export is done via a Python script to robustly generate the hidden 
# test data, execute the agent's code against it, and dump the JSON securely.
python3 - << 'EOF'
import os
import json
import glob
import subprocess
import numpy as np
from astropy.io import fits

try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        task_start = int(f.read().strip())
except:
    task_start = 0

# 1. Collect FITS files from Calibration directories
fits_files = []
for pattern in ['/home/ga/Calibration/**/*.fits', '/home/ga/Calibration/**/*.fit']:
    for f_path in glob.glob(pattern, recursive=True):
        try:
            stat = os.stat(f_path)
            frame_type = ""
            exptime = -1.0
            filt = ""
            try:
                with fits.open(f_path) as hdul:
                    h = hdul[0].header
                    frame_type = str(h.get('IMAGETYP', h.get('FRAME', ''))).strip()
                    exptime = float(h.get('EXPTIME', -1))
                    filt = str(h.get('FILTER', '')).strip()
            except Exception:
                pass
            
            fits_files.append({
                'path': f_path,
                'name': os.path.basename(f_path),
                'size': stat.st_size,
                'mtime': stat.st_mtime,
                'frame_type': frame_type,
                'exptime': exptime,
                'filter': filt
            })
        except Exception:
            pass

# 2. Check Script and Report Existence
script_path = '/home/ga/analyze_sensor.py'
report_path = '/home/ga/Documents/sensor_report.txt'

script_exists = os.path.isfile(script_path)
report_exists = os.path.isfile(report_path)

report_size = os.stat(report_path).st_size if report_exists else 0
report_content = ""
if report_exists:
    with open(report_path, 'r', errors='replace') as f:
        report_content = f.read(1000)

# 3. Dynamic Evaluation: Generate Hidden Synthetic FITS
# This ensures the agent didn't hardcode outputs.
eval_fits_path = '/tmp/hidden_eval.fits'
H, W = 1000, 1000
np.random.seed(42) # Deterministic for consistent verifier true values
data = np.random.normal(loc=35000, scale=200, size=(H, W)).astype(np.float32)

# Apply specific vignetting to the corners
data[:50, :50] *= 0.65
data[:50, -50:] *= 0.65
data[-50:, :50] *= 0.65
data[-50:, -50:] *= 0.65

# Calculate the EXACT true values according to task definition
true_center = np.mean(data[H//2-50 : H//2+50, W//2-50 : W//2+50])
corners = np.concatenate([
    data[:50, :50].flatten(),
    data[:50, -50:].flatten(),
    data[-50:, :50].flatten(),
    data[-50:, -50:].flatten()
])
true_corners = np.mean(corners)
true_vignetting = float(true_corners / true_center)
true_rms = float(np.std(data))

# Save hidden evaluation FITS
hdu = fits.PrimaryHDU(data)
hdu.writeto(eval_fits_path, overwrite=True)
os.chmod(eval_fits_path, 0o666) # Ensure readable

# 4. Execute Agent's Script on the Hidden FITS
agent_stdout = ""
agent_stderr = ""
script_ran = False

if script_exists:
    try:
        # Run as user 'ga' to prevent permission issues
        res = subprocess.run(['sudo', '-u', 'ga', 'python3', script_path, eval_fits_path],
                             capture_output=True, text=True, timeout=15)
        agent_stdout = res.stdout
        agent_stderr = res.stderr
        script_ran = True
    except subprocess.TimeoutExpired:
        agent_stderr = "Timeout Expired"
    except Exception as e:
        agent_stderr = str(e)

# Clean up hidden file so it's not lingering
if os.path.exists(eval_fits_path):
    os.remove(eval_fits_path)

# 5. Build Result JSON
result = {
    "task_start": task_start,
    "fits_files": fits_files,
    "script_exists": script_exists,
    "report_exists": report_exists,
    "report_size": report_size,
    "report_content": report_content,
    "script_ran": script_ran,
    "agent_stdout": agent_stdout,
    "agent_stderr": agent_stderr,
    "true_vignetting": true_vignetting,
    "true_rms": true_rms
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
EOF

echo "Result JSON generated."
echo "=== Export complete ==="