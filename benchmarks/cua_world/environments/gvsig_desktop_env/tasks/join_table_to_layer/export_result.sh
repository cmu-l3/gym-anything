#!/bin/bash
echo "=== Exporting join_table_to_layer results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
EXPORTS_DIR="/home/ga/gvsig_data/exports"
OUTPUT_BASE="$EXPORTS_DIR/countries_with_indicators"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if app was running
APP_RUNNING="false"
if pgrep -f "gvSIG" > /dev/null; then
    APP_RUNNING="true"
fi

# Ensure pyshp is available for verification analysis
if ! pip3 freeze | grep -q pyshp; then
    pip3 install pyshp --quiet 2>/dev/null || true
fi

# -------------------------------------------------------------------
# Analyze output file using Python
# We analyze INSIDE the container to handle dependencies and file access
# then export the extracted metadata to JSON for the host verifier.
# -------------------------------------------------------------------
python3 << PYEOF
import os
import json
import time
import sys

# Define default result structure
result = {
    "task_start": $TASK_START,
    "task_end": int(time.time()),
    "app_was_running": $APP_RUNNING,
    "files_exist": False,
    "shp_exists": False,
    "shx_exists": False,
    "dbf_exists": False,
    "file_created_during_task": False,
    "output_size_bytes": 0,
    "feature_count": 0,
    "field_count": 0,
    "field_names": [],
    "original_field_count": 0,
    "usa_co2": None,
    "chn_life_exp": None,
    "screenshot_path": "/tmp/task_final.png"
}

output_base = "$OUTPUT_BASE"
exports_dir = "$EXPORTS_DIR"

# 1. Check for file existence (handle case-insensitivity or slight naming variations)
shp_path = output_base + ".shp"
if not os.path.exists(shp_path):
    # Search for any shp in exports dir created recently
    if os.path.isdir(exports_dir):
        for f in os.listdir(exports_dir):
            if f.endswith(".shp"):
                shp_path = os.path.join(exports_dir, f)
                output_base = os.path.splitext(shp_path)[0]
                break

if os.path.exists(shp_path):
    result["shp_exists"] = True
    result["output_size_bytes"] = os.path.getsize(shp_path)
    result["file_created_during_task"] = os.path.getmtime(shp_path) > result["task_start"]
    
    # Check companion files
    if os.path.exists(output_base + ".shx"): result["shx_exists"] = True
    if os.path.exists(output_base + ".dbf"): result["dbf_exists"] = True
    
    if result["shp_exists"] and result["shx_exists"] and result["dbf_exists"]:
        result["files_exist"] = True

    # 2. Analyze Shapefile content
    try:
        import shapefile
        sf = shapefile.Reader(shp_path)
        
        # Get fields (skip DeletionFlag)
        fields = [f[0].upper() for f in sf.fields]
        result["field_names"] = fields
        result["field_count"] = len(fields)
        result["feature_count"] = len(sf)
        
        # 3. Extract validation values (USA CO2, China LifeExp)
        # We need to find which index corresponds to ISO code and joined fields
        
        # Find ISO field index
        iso_idx = -1
        for i, f in enumerate(fields):
            if f in ["ISO_A3", "ISO3", "ISO_A3_EH"]:
                iso_idx = i - 1 # Adjust for DeletionFlag usually handled by pyshp? 
                                # pyshp .records() usually aligns with .fields[1:]
                                # Let's use dictionary-based record access if possible, or mapping
                break
        
        # Find CO2 field index
        co2_idx = -1
        for i, f in enumerate(fields):
            if "CO2" in f:
                co2_idx = i - 1
                break
                
        # Find Life Exp field index
        life_idx = -1
        for i, f in enumerate(fields):
            if "LIFE" in f or "LE00" in f:
                life_idx = i - 1
                break
        
        # Iterate records to find USA and CHN
        # Pyshp records are lists of values
        if iso_idx >= 0:
            for rec in sf.records():
                try:
                    iso_val = str(rec[iso_idx]).strip()
                    
                    if iso_val == "USA" and co2_idx >= 0:
                        result["usa_co2"] = float(rec[co2_idx])
                    
                    if iso_val == "CHN" and life_idx >= 0:
                        result["chn_life_exp"] = float(rec[life_idx])
                        
                    if result["usa_co2"] is not None and result["chn_life_exp"] is not None:
                        break
                except (ValueError, IndexError):
                    continue

    except Exception as e:
        print(f"Error analyzing shapefile: {e}", file=sys.stderr)

# Get original field count
try:
    with open("/tmp/original_field_count.txt", "r") as f:
        result["original_field_count"] = int(f.read().strip())
except:
    pass

# Save result to JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result JSON generated.")
PYEOF

# Fix permissions so host can copy it
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="