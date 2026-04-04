#!/bin/bash
echo "=== Setting up dissolve_by_continent task ==="

source /workspace/scripts/task_utils.sh

# Verify countries shapefile exists
check_countries_shapefile || exit 1
SHP_PATH=$(ls /home/ga/gvsig_data/countries/*.shp 2>/dev/null | head -1)
echo "Countries shapefile: $SHP_PATH"

# Create exports directory and clean any prior output
mkdir -p /home/ga/gvsig_exports
chown ga:ga /home/ga/gvsig_exports
rm -f /home/ga/gvsig_exports/continents_dissolved.shp
rm -f /home/ga/gvsig_exports/continents_dissolved.shx
rm -f /home/ga/gvsig_exports/continents_dissolved.dbf
rm -f /home/ga/gvsig_exports/continents_dissolved.prj
rm -f /home/ga/gvsig_exports/continents_dissolved.cpg
echo "Cleaned prior output files"

# Record task start timestamp
date +%s > /tmp/task_start_ts.txt

# Pre-compute ground truth: distinct continent values
python3 << 'PYEOF'
import json
try:
    from osgeo import ogr

    ds = ogr.Open('/home/ga/gvsig_data/countries/ne_110m_admin_0_countries.shp')
    if ds is None:
        raise RuntimeError("Cannot open countries shapefile")

    lyr = ds.GetLayer()
    continents = set()
    for feat in lyr:
        cont = feat.GetField('CONTINENT') or ''
        if cont:
            continents.add(cont)
    lyr.ResetReading()
    ds = None

    gt = {
        'continent_count': len(continents),
        'continent_values': sorted(list(continents)),
    }
    with open('/tmp/gt_continents.json', 'w') as f:
        json.dump(gt, f, indent=2)
    print("GT computed:", gt['continent_count'], "continents")
    print("Values:", gt['continent_values'])

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

# Re-copy clean project
PREBUILT_PROJECT="/home/ga/gvsig_data/projects/countries_base.gvsproj"
CLEAN_PROJECT="/workspace/data/projects/countries_base.gvsproj"

if [ -f "$CLEAN_PROJECT" ]; then
    echo "Restoring clean project"
    cp "$CLEAN_PROJECT" "$PREBUILT_PROJECT"
    chown ga:ga "$PREBUILT_PROJECT"
    chmod 644 "$PREBUILT_PROJECT"
fi

if [ -f "$PREBUILT_PROJECT" ]; then
    launch_gvsig "$PREBUILT_PROJECT"
else
    launch_gvsig ""
fi

sleep 3
take_screenshot /tmp/task_start.png
echo "Initial screenshot saved"

echo "=== Task setup complete ==="
echo "Task: Dissolve countries by CONTINENT field, export to continents_dissolved.shp"
exit 0
