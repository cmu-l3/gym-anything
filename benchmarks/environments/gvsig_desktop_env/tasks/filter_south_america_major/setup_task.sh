#!/bin/bash
echo "=== Setting up filter_south_america_major task ==="

source /workspace/scripts/task_utils.sh

# Verify countries shapefile exists
check_countries_shapefile || exit 1
SHP_PATH=$(ls /home/ga/gvsig_data/countries/*.shp 2>/dev/null | head -1)
echo "Countries shapefile: $SHP_PATH"

# Create exports directory and clean any prior output
mkdir -p /home/ga/gvsig_exports
chown ga:ga /home/ga/gvsig_exports
rm -f /home/ga/gvsig_exports/south_america_major.shp
rm -f /home/ga/gvsig_exports/south_america_major.shx
rm -f /home/ga/gvsig_exports/south_america_major.dbf
rm -f /home/ga/gvsig_exports/south_america_major.prj
rm -f /home/ga/gvsig_exports/south_america_major.cpg
echo "Cleaned prior output files"

# Record task start timestamp
date +%s > /tmp/task_start_ts.txt

# Pre-compute ground truth: which countries qualify
python3 << 'PYEOF'
import json
try:
    from osgeo import ogr

    ds = ogr.Open('/home/ga/gvsig_data/countries/ne_110m_admin_0_countries.shp')
    if ds is None:
        raise RuntimeError("Cannot open countries shapefile")

    lyr = ds.GetLayer()
    qualifying = []
    for feat in lyr:
        continent = feat.GetField('CONTINENT') or ''
        pop = feat.GetField('POP_EST') or 0
        name = feat.GetField('NAME') or feat.GetField('ADMIN') or ''
        if continent == 'South America' and int(pop) > 5_000_000:
            qualifying.append({'name': name, 'pop_est': int(pop), 'continent': continent})

    lyr.ResetReading()
    ds = None

    qualifying_sorted = sorted(qualifying, key=lambda x: x['pop_est'], reverse=True)
    gt = {
        'count': len(qualifying_sorted),
        'names': [c['name'] for c in qualifying_sorted],
        'min_pop': min(c['pop_est'] for c in qualifying_sorted) if qualifying_sorted else 0,
    }

    with open('/tmp/gt_south_america.json', 'w') as f:
        json.dump(gt, f, indent=2)

    print("GT computed:", gt['count'], "qualifying countries")
    for c in qualifying_sorted:
        print(f"  {c['name']}: {c['pop_est']:,}")

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
echo "Task: Select South America countries with POP_EST > 5M, export to south_america_major.shp"
exit 0
