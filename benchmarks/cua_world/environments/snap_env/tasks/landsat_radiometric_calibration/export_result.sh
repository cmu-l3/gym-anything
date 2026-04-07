#!/bin/bash
echo "=== Exporting landsat_radiometric_calibration results ==="

# 1. Capture final visual state
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Extract verification data using Python script inside container
python3 << 'PYEOF'
import os
import json
import xml.etree.ElementTree as ET

result = {
    "task_start": 0,
    "dim_found": False,
    "dim_created_during_task": False,
    "tif_found": False,
    "tif_created_during_task": False,
    "bands": [],
    "total_bands": 0,
    "calibration_math_found": False,
    "float_type_found": False,
    "xml_error": None
}

# Get task start time
try:
    with open("/tmp/task_start_time.txt", "r") as f:
        result["task_start"] = int(f.read().strip())
except:
    pass

export_dir = "/home/ga/snap_exports"

if os.path.exists(export_dir):
    # Check for DIMAP product
    dim_files = [f for f in os.listdir(export_dir) if f.endswith(".dim")]
    if dim_files:
        # Use the expected name if it exists, else the first found
        target_dim = "landsat_sr_calibrated.dim"
        if target_dim in dim_files:
            dim_path = os.path.join(export_dir, target_dim)
        else:
            dim_path = os.path.join(export_dir, dim_files[0])
            
        result["dim_found"] = True
        
        # Check creation time
        if int(os.path.getmtime(dim_path)) > result["task_start"]:
            result["dim_created_during_task"] = True

        # Parse DIMAP XML to extract structural and mathematical correctness
        try:
            tree = ET.parse(dim_path)
            root = tree.getroot()
            
            for sbi in root.iter('Spectral_Band_Info'):
                result["total_bands"] += 1
                band_info = {}
                
                name_el = sbi.find('BAND_NAME')
                if name_el is not None and name_el.text:
                    band_info['name'] = name_el.text

                type_el = sbi.find('DATA_TYPE')
                if type_el is not None and type_el.text:
                    btype = type_el.text.lower()
                    band_info['type'] = btype
                    if 'float' in btype:
                        result["float_type_found"] = True

                expr_el = sbi.find('VIRTUAL_BAND_EXPRESSION')
                if expr_el is not None and expr_el.text:
                    expr = expr_el.text
                    band_info['expression'] = expr
                    # Look for the scale factor applied (0.0000275 or scientific notation)
                    if '0.0000275' in expr or '2.75E-5' in expr.upper():
                        result["calibration_math_found"] = True

                result["bands"].append(band_info)
        except Exception as e:
            result["xml_error"] = str(e)

    # Check for GeoTIFF export
    tif_files = [f for f in os.listdir(export_dir) if f.lower().endswith((".tif", ".tiff"))]
    if tif_files:
        target_tif = "landsat_sr_calibrated.tif"
        if target_tif in tif_files:
            tif_path = os.path.join(export_dir, target_tif)
        else:
            tif_path = os.path.join(export_dir, tif_files[0])
            
        result["tif_found"] = True
        if int(os.path.getmtime(tif_path)) > result["task_start"]:
            result["tif_created_during_task"] = True

# Write out JSON result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "=== Export complete ==="