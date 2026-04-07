#!/bin/bash
echo "=== Exporting site_georeferencing result ==="

source /workspace/scripts/task_utils.sh || true

# Take final screenshot before parsing result
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/georeferencing_result.json"

# ── Write the export Python script ────────────────────────────────────────
cat > /tmp/export_georef.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_georeferenced.ifc"

# Read task start timestamp
task_start = 0.0
try:
    with open("/tmp/task_start_timestamp") as f:
        task_start = float(f.read().strip())
except Exception:
    pass

if not os.path.exists(ifc_path):
    result = {
        "file_exists": False,
        "file_mtime": 0.0,
        "crs_count": 0,
        "crs_names": [],
        "map_conversion_count": 0,
        "map_conversions": [],
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)
        
        # Parse IfcProjectedCRS
        crs_list = list(ifc.by_type("IfcProjectedCRS"))
        crs_names = [getattr(c, "Name", "") or "" for c in crs_list]
        
        # Parse IfcMapConversion
        mc_list = list(ifc.by_type("IfcMapConversion"))
        mc_data = []
        for mc in mc_list:
            easting = getattr(mc, "Eastings", 0.0)
            northing = getattr(mc, "Northings", 0.0)
            height = getattr(mc, "OrthogonalHeight", 0.0)
            
            mc_data.append({
                "Eastings": float(easting) if easting is not None else 0.0,
                "Northings": float(northing) if northing is not None else 0.0,
                "OrthogonalHeight": float(height) if height is not None else 0.0
            })
            
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "crs_count": len(crs_list),
            "crs_names": crs_names,
            "map_conversion_count": len(mc_list),
            "map_conversions": mc_data,
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "crs_count": 0,
            "crs_names": [],
            "map_conversion_count": 0,
            "map_conversions": [],
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

# ── Run via blender --background to access bundled ifcopenshell ────────────
/opt/blender/blender --background --python /tmp/export_georef.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

# ── Fallback if export produced no output ─────────────────────────────────
if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"file_mtime":0,"crs_count":0,"map_conversion_count":0,"task_start":0,"error":"Export script produced no output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"