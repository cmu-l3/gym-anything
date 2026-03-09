#!/bin/bash
echo "=== Setting up field_calc_gdp_percapita task ==="

source /workspace/scripts/task_utils.sh

# Verify countries shapefile exists
check_countries_shapefile || exit 1
SHP_PATH=$(ls /home/ga/gvsig_data/countries/*.shp 2>/dev/null | head -1)
echo "Countries shapefile: $SHP_PATH"

# Create exports directory and clean any prior output
mkdir -p /home/ga/gvsig_exports
chown ga:ga /home/ga/gvsig_exports
rm -f /home/ga/gvsig_exports/countries_gdp_percapita.shp
rm -f /home/ga/gvsig_exports/countries_gdp_percapita.shx
rm -f /home/ga/gvsig_exports/countries_gdp_percapita.dbf
rm -f /home/ga/gvsig_exports/countries_gdp_percapita.prj
rm -f /home/ga/gvsig_exports/countries_gdp_percapita.cpg
echo "Cleaned prior output files"

# Record task start timestamp
date +%s > /tmp/task_start_ts.txt
echo "Task start timestamp: $(cat /tmp/task_start_ts.txt)"

# Pre-compute ground truth GDP_PCAP for key countries
python3 << 'PYEOF'
import json
try:
    from osgeo import ogr

    ds = ogr.Open('/home/ga/gvsig_data/countries/ne_110m_admin_0_countries.shp')
    if ds is None:
        raise RuntimeError("Cannot open countries shapefile")

    lyr = ds.GetLayer()
    gt = {}
    target_countries = {
        'United States of America', 'China', 'Germany', 'India',
        'Brazil', 'Japan', 'France', 'United Kingdom', 'Australia',
        'South Africa', 'Nigeria', 'Mexico', 'Canada',
    }
    for feat in lyr:
        name = feat.GetField('NAME') or feat.GetField('ADMIN') or ''
        # Also check SOVEREIGNT and formal names
        sov = feat.GetField('SOVEREIGNT') or ''
        match_name = name if name in target_countries else (sov if sov in target_countries else None)
        if match_name:
            gdp = feat.GetField('GDP_MD_EST')
            pop = feat.GetField('POP_EST')
            if gdp and pop and pop > 0:
                gdp_pcap = (float(gdp) * 1_000_000) / float(pop)
                gt[match_name] = {
                    'gdp_md_est': float(gdp),
                    'pop_est': float(pop),
                    'gdp_pcap': round(gdp_pcap, 2)
                }
    lyr.ResetReading()
    ds = None
    with open('/tmp/gt_gdp_pcap.json', 'w') as f:
        json.dump(gt, f, indent=2)
    print("GT computed for", len(gt), "countries")
    print("Sample:", {k: v['gdp_pcap'] for k, v in list(gt.items())[:5]})
except Exception as e:
    import traceback
    print("GT pre-compute error:", e)
    traceback.print_exc()
PYEOF

# Ensure directories are writable
chown -R ga:ga /home/ga/gvsig_data 2>/dev/null || true
chown -R ga:ga /home/ga/gvsig_exports 2>/dev/null || true

# Kill any running gvSIG
kill_gvsig

# Re-copy clean project
PREBUILT_PROJECT="/home/ga/gvsig_data/projects/countries_base.gvsproj"
CLEAN_PROJECT="/workspace/data/projects/countries_base.gvsproj"

if [ -f "$CLEAN_PROJECT" ]; then
    echo "Restoring clean project from workspace"
    cp "$CLEAN_PROJECT" "$PREBUILT_PROJECT"
    chown ga:ga "$PREBUILT_PROJECT"
    chmod 644 "$PREBUILT_PROJECT"
fi

# Launch gvSIG with the countries project loaded
if [ -f "$PREBUILT_PROJECT" ]; then
    echo "Launching gvSIG with countries project..."
    launch_gvsig "$PREBUILT_PROJECT"
else
    echo "Launching gvSIG fresh..."
    launch_gvsig ""
fi

sleep 3
take_screenshot /tmp/task_start.png
echo "Initial screenshot saved to /tmp/task_start.png"

echo "=== Task setup complete ==="
echo "Task: Add GDP_PCAP field using field calculator, export to countries_gdp_percapita.shp"
exit 0
