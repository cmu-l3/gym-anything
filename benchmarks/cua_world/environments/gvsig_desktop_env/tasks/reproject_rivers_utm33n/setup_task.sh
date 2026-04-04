#!/bin/bash
echo "=== Setting up reproject_rivers_utm33n task ==="

source /workspace/scripts/task_utils.sh

# Verify rivers shapefile exists (installed by install_gvsig.sh)
RIVERS_SHP="/home/ga/gvsig_data/rivers/ne_110m_rivers_lake_centerlines.shp"
if [ ! -f "$RIVERS_SHP" ]; then
    echo "ERROR: Rivers shapefile not found at $RIVERS_SHP"
    exit 1
fi
echo "Rivers shapefile: $RIVERS_SHP"

# Create exports directory and clean any prior output
mkdir -p /home/ga/gvsig_exports
chown ga:ga /home/ga/gvsig_exports
rm -f /home/ga/gvsig_exports/rivers_utm33n.shp
rm -f /home/ga/gvsig_exports/rivers_utm33n.shx
rm -f /home/ga/gvsig_exports/rivers_utm33n.dbf
rm -f /home/ga/gvsig_exports/rivers_utm33n.prj
rm -f /home/ga/gvsig_exports/rivers_utm33n.cpg
echo "Cleaned prior output files"

# Record task start timestamp
date +%s > /tmp/task_start_ts.txt
echo "Task start timestamp: $(cat /tmp/task_start_ts.txt)"

# Pre-compute ground truth: original feature count
python3 << 'PYEOF'
import json
try:
    from osgeo import ogr
    ds = ogr.Open('/home/ga/gvsig_data/rivers/ne_110m_rivers_lake_centerlines.shp')
    if ds is None:
        result = {"error": "Cannot open rivers shapefile"}
    else:
        lyr = ds.GetLayer()
        count = lyr.GetFeatureCount()
        srs = lyr.GetSpatialRef()
        epsg_src = srs.GetAttrValue('AUTHORITY', 1) if srs else 'unknown'
        result = {"river_count": count, "source_epsg": epsg_src}
    with open('/tmp/gt_rivers.json', 'w') as f:
        json.dump(result, f)
    print("GT rivers:", result)
except Exception as e:
    import traceback
    print("GT pre-compute error:", e)
    traceback.print_exc()
PYEOF

# Ensure directories are writable by ga
chown -R ga:ga /home/ga/gvsig_data 2>/dev/null || true
chown -R ga:ga /home/ga/gvsig_exports 2>/dev/null || true

# Kill any running gvSIG
kill_gvsig

# Re-copy the clean pre-built project on every task start to prevent state bleed
PREBUILT_PROJECT="/home/ga/gvsig_data/projects/countries_base.gvsproj"
CLEAN_PROJECT="/workspace/data/projects/countries_base.gvsproj"

if [ -f "$CLEAN_PROJECT" ]; then
    echo "Restoring clean project from workspace: $CLEAN_PROJECT"
    cp "$CLEAN_PROJECT" "$PREBUILT_PROJECT"
    chown ga:ga "$PREBUILT_PROJECT"
    chmod 644 "$PREBUILT_PROJECT"
fi

# Launch gvSIG (rivers task - use empty project so agent loads the rivers layer)
echo "Launching gvSIG..."
launch_gvsig ""

# Take initial screenshot
sleep 3
take_screenshot /tmp/task_start.png
echo "Initial screenshot saved to /tmp/task_start.png"

echo "=== Task setup complete ==="
echo "Task: Reproject rivers layer to EPSG:32633 (UTM Zone 33N)"
echo "Source: $RIVERS_SHP"
echo "Output: /home/ga/gvsig_exports/rivers_utm33n.shp"
exit 0
