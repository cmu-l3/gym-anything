#!/bin/bash
echo "=== Exporting task results ==="

# Capture the final state screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Run a Python script to deeply inspect the artifacts (XML and NetCDF structures)
python3 << 'EOF'
import os
import json
import xml.etree.ElementTree as ET
import numpy as np

result = {
    "dimap_exists": False,
    "dimap_mtime": 0,
    "dimap_has_albedo": False,
    "albedo_mean": None,
    "netcdf_exists": False,
    "netcdf_mtime": 0,
    "netcdf_vars": 0,
    "netcdf_size": 0,
    "task_start": 0
}

# Fetch start time to ensure files were actually modified during the task
try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        result["task_start"] = int(f.read().strip())
except:
    pass

export_dir = "/home/ga/snap_exports"
dim_file = os.path.join(export_dir, "landsat_albedo.dim")
data_dir = os.path.join(export_dir, "landsat_albedo.data")
nc_file = os.path.join(export_dir, "landsat_albedo.nc")

# 1. Inspect DIMAP File
if os.path.exists(dim_file) and os.path.isdir(data_dir):
    result["dimap_exists"] = True
    result["dimap_mtime"] = int(os.path.getmtime(dim_file))

    try:
        tree = ET.parse(dim_file)
        root = tree.getroot()
        albedo_img_path = None
        
        # Look for a band with 'albedo' in the name
        for band in root.iter('Spectral_Band_Info'):
            name = band.find('BAND_NAME')
            if name is not None and name.text and 'albedo' in name.text.lower():
                result["dimap_has_albedo"] = True
                albedo_img_path = os.path.join(data_dir, f"{name.text}.img")
                break
        
        # If found, check the physical values in the flat .img binary
        if albedo_img_path and os.path.exists(albedo_img_path):
            data = np.fromfile(albedo_img_path, dtype=np.float32) 
            valid = data[np.isfinite(data) & (data != 0) & (data != -999)]
            if len(valid) > 0:
                result["albedo_mean"] = float(np.mean(valid))
    except Exception as e:
        print(f"Error parsing DIMAP XML or Raster: {e}")

# 2. Inspect NetCDF File
if os.path.exists(nc_file):
    result["netcdf_exists"] = True
    result["netcdf_mtime"] = int(os.path.getmtime(nc_file))
    result["netcdf_size"] = os.path.getsize(nc_file)

    try:
        import netCDF4
        ds = netCDF4.Dataset(nc_file, 'r')
        dims = set(ds.dimensions.keys())
        # Filter out projection arrays or dimension variables to count valid raster variables
        vars_list = [v for v in ds.variables.keys() if v not in dims and 'mercator' not in v.lower() and v not in ['crs', 'lat', 'lon']]
        result["netcdf_vars"] = len(vars_list)
        ds.close()
    except ImportError:
        # Fallback to ncdump if python3-netcdf4 failed to install
        import subprocess
        try:
            out = subprocess.check_output(['ncdump', '-h', nc_file]).decode('utf-8')
            lines = [l for l in out.split('\n') if 'float ' in l or 'double ' in l]
            result["netcdf_vars"] = len(lines)
        except:
            pass
    except Exception as e:
        print(f"Error reading NetCDF file: {e}")

# Save telemetry output for the verifier to load via copy_from_env
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=4)
EOF

chmod 666 /tmp/task_result.json
echo "Results exported to /tmp/task_result.json"