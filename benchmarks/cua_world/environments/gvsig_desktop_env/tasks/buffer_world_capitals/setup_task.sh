#!/bin/bash
echo "=== Setting up buffer_world_capitals task ==="

source /workspace/scripts/task_utils.sh

# Verify populated places shapefile exists (installed by install_gvsig.sh)
CITIES_SHP="/home/ga/gvsig_data/cities/ne_110m_populated_places.shp"
if [ ! -f "$CITIES_SHP" ]; then
    echo "ERROR: Cities shapefile not found at $CITIES_SHP"
    exit 1
fi
echo "Cities shapefile: $CITIES_SHP"

# Create exports directory and clean any prior output
mkdir -p /home/ga/gvsig_exports
chown ga:ga /home/ga/gvsig_exports
rm -f /home/ga/gvsig_exports/capital_buffers.shp
rm -f /home/ga/gvsig_exports/capital_buffers.shx
rm -f /home/ga/gvsig_exports/capital_buffers.dbf
rm -f /home/ga/gvsig_exports/capital_buffers.prj
rm -f /home/ga/gvsig_exports/capital_buffers.cpg
echo "Cleaned prior output files"

# Record task start timestamp
date +%s > /tmp/task_start_ts.txt

# Pre-compute ground truth: how many Admin-0 capitals exist
python3 << 'PYEOF'
import json
try:
    from osgeo import ogr

    ds = ogr.Open('/home/ga/gvsig_data/cities/ne_110m_populated_places.shp')
    if ds is None:
        raise RuntimeError("Cannot open cities shapefile")

    lyr = ds.GetLayer()
    capitals = []
    for feat in lyr:
        fc = feat.GetField('FEATURECLA') or ''
        name = feat.GetField('NAME') or ''
        if fc == 'Admin-0 capital':
            capitals.append(name)

    lyr.ResetReading()
    ds = None

    gt = {
        'admin0_capital_count': len(capitals),
        'sample_capitals': capitals[:10],
    }
    with open('/tmp/gt_capitals.json', 'w') as f:
        json.dump(gt, f, indent=2)
    print(f"GT: {len(capitals)} Admin-0 capitals found")
    print(f"Sample: {capitals[:5]}")

except Exception as e:
    import traceback
    print("GT pre-compute error:", e)
    traceback.print_exc()
PYEOF

# Ensure permissions
chown -R ga:ga /home/ga/gvsig_data 2>/dev/null || true
chown -R ga:ga /home/ga/gvsig_exports 2>/dev/null || true

# Kill any running gvSIG
kill_gvsig

# Launch fresh (cities layer not in default project, agent must load it)
echo "Launching gvSIG..."
launch_gvsig ""

sleep 3
take_screenshot /tmp/task_start.png
echo "Initial screenshot saved"

echo "=== Task setup complete ==="
echo "Task: Buffer Admin-0 capital cities by 2 degrees, export to capital_buffers.shp"
echo "Source: $CITIES_SHP"
exit 0
