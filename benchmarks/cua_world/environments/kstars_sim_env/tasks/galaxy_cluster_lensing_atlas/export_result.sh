#!/bin/bash
echo "=== Exporting galaxy_cluster_lensing_atlas results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Use Python to safely and comprehensively parse all files in the Lensing directory
# using astropy to handle FITS headers precisely as required by the verifier.
python3 - << PYEOF
import os, json, glob
from astropy.io import fits
from astropy.coordinates import Angle
import astropy.units as u

base_dir = '/home/ga/Lensing'
task_start = $TASK_START

results = {
    "task_start": task_start,
    "fits_files": [],
    "png_files": [],
    "log_exists": False,
    "log_mtime": 0,
    "log_content": ""
}

# 1. Scan for FITS files
for pattern in [f"{base_dir}/**/*.fits", f"{base_dir}/**/*.fit"]:
    for fpath in glob.glob(pattern, recursive=True):
        try:
            stat = os.stat(fpath)
            file_info = {
                "path": fpath,
                "dir": os.path.basename(os.path.dirname(fpath)),
                "name": os.path.basename(fpath),
                "size": stat.st_size,
                "mtime": stat.st_mtime,
                "exptime": -1.0,
                "filter": "",
                "obj_ra_deg": -999.0,
                "obj_dec_deg": -999.0
            }
            
            # Extract headers
            with fits.open(fpath) as hdul:
                h = hdul[0].header
                file_info["exptime"] = float(h.get('EXPTIME', -1))
                file_info["filter"] = str(h.get('FILTER', h.get('FILTER2', ''))).strip()
                
                # Safely parse RA/Dec to degrees
                raw_ra = h.get('OBJCTRA', '')
                raw_dec = h.get('OBJCTDEC', '')
                
                try:
                    if isinstance(raw_ra, (int, float)):
                        # INDI usually writes string hours, but fallback to hourangle
                        file_info["obj_ra_deg"] = Angle(raw_ra, unit=u.hourangle).deg
                    elif raw_ra:
                        file_info["obj_ra_deg"] = Angle(raw_ra, unit=u.hourangle).deg
                except: pass
                
                try:
                    if isinstance(raw_dec, (int, float)):
                        file_info["obj_dec_deg"] = float(raw_dec)
                    elif raw_dec:
                        file_info["obj_dec_deg"] = Angle(raw_dec, unit=u.deg).deg
                except: pass

            results["fits_files"].append(file_info)
        except Exception as e:
            pass

# 2. Scan for PNG files
for pattern in [f"{base_dir}/**/*.png"]:
    for fpath in glob.glob(pattern, recursive=True):
        try:
            stat = os.stat(fpath)
            results["png_files"].append({
                "path": fpath,
                "dir": os.path.basename(os.path.dirname(fpath)),
                "name": os.path.basename(fpath),
                "size": stat.st_size,
                "mtime": stat.st_mtime
            })
        except: pass

# 3. Read observation log
log_path = os.path.join(base_dir, "atlas_log.txt")
if os.path.isfile(log_path):
    results["log_exists"] = True
    results["log_mtime"] = os.stat(log_path).st_mtime
    try:
        with open(log_path, "r", encoding="utf-8") as lf:
            results["log_content"] = lf.read()[:2000] # Cap at 2KB
    except: pass

# Export to JSON
with open('/tmp/task_result.json', 'w') as f:
    json.dump(results, f, indent=2)

print("Result written to /tmp/task_result.json")
PYEOF

chmod 666 /tmp/task_result.json
echo "=== Export complete ==="