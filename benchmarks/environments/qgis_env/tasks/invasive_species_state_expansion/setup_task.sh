#!/bin/bash
set -euo pipefail
echo "=== Setting up invasive_species_state_expansion task ==="

source /workspace/scripts/task_utils.sh

if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type wait_for_window &>/dev/null; then
    wait_for_window() {
        local pattern="$1"; local timeout=${2:-30}; local elapsed=0
        while [ $elapsed -lt $timeout ]; do
            DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$pattern" && return 0
            sleep 1; elapsed=$((elapsed + 1))
        done
        return 1
    }
fi
if ! type kill_qgis &>/dev/null; then
    kill_qgis() { pkill -u "${1:-ga}" -f qgis 2>/dev/null || true; sleep 1; }
fi

# ── CLEAN ──────────────────────────────────────────────────────────────────────
EXPORT_DIR="/home/ga/GIS_Data/exports"
GIS_DIR="/home/ga/GIS_Data"
mkdir -p "$GIS_DIR" "$EXPORT_DIR"
rm -f "$EXPORT_DIR/invasion_status_by_state.geojson" 2>/dev/null || true
rm -f "$EXPORT_DIR/invasion_summary.csv" 2>/dev/null || true
rm -f "$GIS_DIR/harmonia_us_occurrences.geojson" 2>/dev/null || true
rm -f "$GIS_DIR/us_states.geojson" 2>/dev/null || true
rm -f /tmp/gt_invasion.json 2>/dev/null || true

# ── SEED: download GBIF occurrences ──────────────────────────────────────────
echo "Downloading Harmonia axyridis occurrences from GBIF..."
# GBIF API: taxonKey 1045608 = Harmonia axyridis, US occurrences with coordinates
# Download multiple pages to get sufficient data coverage
python3 << 'PYEOF'
import urllib.request
import json
import sys
import time

base_url = "https://api.gbif.org/v1/occurrence/search"
params_base = {
    "taxonKey": "1045608",   # Harmonia axyridis
    "country": "US",
    "hasCoordinate": "true",
    "year": "2005,2023",
    "limit": "300"
}

all_features = []
offsets = [0, 300]  # Two pages = up to 600 records

for offset in offsets:
    params = dict(params_base)
    params["offset"] = str(offset)
    query = "&".join(f"{k}={urllib.parse.quote(str(v))}" for k, v in params.items())
    url = f"{base_url}?{query}"
    import urllib.parse
    url = f"{base_url}?" + "&".join(f"{k}={urllib.parse.quote(str(v))}" for k, v in params.items())

    try:
        req = urllib.request.Request(url)
        req.add_header('User-Agent', 'GymAnything-QGISTask/1.0')
        with urllib.request.urlopen(req, timeout=60) as resp:
            data = json.loads(resp.read().decode())
        records = data.get("results", [])
        for rec in records:
            lon = rec.get("decimalLongitude")
            lat = rec.get("decimalLatitude")
            year = rec.get("year")
            if lon is not None and lat is not None and year is not None:
                # Filter to contiguous US (rough bbox)
                if -125 <= lon <= -66 and 24 <= lat <= 50:
                    all_features.append({
                        "type": "Feature",
                        "geometry": {"type": "Point", "coordinates": [float(lon), float(lat)]},
                        "properties": {
                            "year": int(year),
                            "month": rec.get("month"),
                            "gbifID": str(rec.get("gbifID", "")),
                            "species": rec.get("species", "Harmonia axyridis"),
                            "stateProvince": rec.get("stateProvince", "")
                        }
                    })
        print(f"  Page offset={offset}: {len(records)} records, {len(all_features)} total so far", file=sys.stderr)
        if len(records) == 0:
            break
        time.sleep(0.5)  # Be polite to GBIF API
    except Exception as e:
        print(f"  Warning: failed to fetch offset={offset}: {e}", file=sys.stderr)
        break

geojson = {"type": "FeatureCollection", "features": all_features}
with open("/home/ga/GIS_Data/harmonia_us_occurrences.geojson", "w") as f:
    json.dump(geojson, f)

print(f"Total occurrences downloaded: {len(all_features)}")
PYEOF

OCC_COUNT=$(python3 -c "import json; d=json.load(open('$GIS_DIR/harmonia_us_occurrences.geojson')); print(len(d.get('features',[])))" 2>/dev/null || echo "0")
echo "GBIF occurrences: $OCC_COUNT features"

if [ "$OCC_COUNT" -lt "20" ]; then
    echo "ERROR: Too few occurrences downloaded ($OCC_COUNT). Network issue?"
    exit 1
fi

echo "Downloading US state boundaries (Natural Earth 50m)..."
# Download Natural Earth admin-1 states/provinces for USA
cd /tmp
wget -q --timeout=90 --tries=3 \
    "https://naturalearth.s3.amazonaws.com/50m_cultural/ne_50m_admin_1_states_provinces.zip" \
    -O ne_50m_states.zip || {
    echo "ERROR: Failed to download Natural Earth states"
    exit 1
}
unzip -q -o ne_50m_states.zip -d /tmp/ne_states/
# Convert to GeoJSON filtering for USA only
ogr2ogr -f GeoJSON \
    -where "adm0_a3='USA' AND type_en NOT IN ('Territory','Dependency','Other')" \
    "$GIS_DIR/us_states.geojson" \
    /tmp/ne_states/ne_50m_admin_1_states_provinces.shp \
    -select "name,postal,type_en,adm0_a3" 2>/dev/null || {
    echo "ERROR: ogr2ogr failed"
    exit 1
}
rm -rf /tmp/ne_states/ /tmp/ne_50m_states.zip

STATE_COUNT=$(python3 -c "import json; d=json.load(open('$GIS_DIR/us_states.geojson')); print(len(d.get('features',[])))" 2>/dev/null || echo "0")
echo "US states: $STATE_COUNT features"

if [ "$STATE_COUNT" -lt "40" ]; then
    echo "ERROR: Expected ~48+ states, got $STATE_COUNT"
    exit 1
fi

# ── GT-IN-SETUP ───────────────────────────────────────────────────────────────
echo "Computing ground-truth invasion status..."
python3 << 'PYEOF'
import json
import sys

try:
    from shapely.geometry import shape, Point
    HAS_SHAPELY = True
except ImportError:
    HAS_SHAPELY = False
    print("WARNING: shapely not available", file=sys.stderr)

with open("/home/ga/GIS_Data/harmonia_us_occurrences.geojson") as f:
    occ_data = json.load(f)
with open("/home/ga/GIS_Data/us_states.geojson") as f:
    states_data = json.load(f)

# Extract occurrence points by period
early_points = []  # 2005-2012
recent_points = []  # 2016-2023
for feat in occ_data.get("features", []):
    geom = feat.get("geometry", {})
    props = feat.get("properties", {})
    year = props.get("year")
    if geom.get("type") == "Point" and year:
        coords = geom["coordinates"]
        pt = (float(coords[0]), float(coords[1]))
        if 2005 <= year <= 2012:
            early_points.append(pt)
        elif 2016 <= year <= 2023:
            recent_points.append(pt)

print(f"Early period (2005-2012): {len(early_points)} points", file=sys.stderr)
print(f"Recent period (2016-2023): {len(recent_points)} points", file=sys.stderr)

gt_results = {}

if HAS_SHAPELY:
    for feat in states_data.get("features", []):
        props = feat.get("properties", {})
        state_name = props.get("name", props.get("NAME", "Unknown"))
        postal = props.get("postal", props.get("POSTAL", ""))
        try:
            state_geom = shape(feat["geometry"])
        except Exception:
            continue

        early_count = sum(1 for lon, lat in early_points if state_geom.contains(Point(lon, lat)))
        recent_count = sum(1 for lon, lat in recent_points if state_geom.contains(Point(lon, lat)))

        if early_count == 0 and recent_count == 0:
            continue

        if recent_count > early_count and early_count > 0:
            status = "expanding"
        elif early_count == 0 and recent_count > 0:
            status = "new_invasion"
        elif recent_count <= early_count and early_count > 0 and recent_count > 0:
            status = "established"
        elif recent_count == 0 and early_count > 0:
            status = "no_recent_activity"
        else:
            status = "no_recent_activity"

        pct = None
        if early_count > 0:
            pct = round(100.0 * (recent_count - early_count) / early_count, 1)

        gt_results[state_name] = {
            "count_2005_2012": early_count,
            "count_2016_2023": recent_count,
            "pct_change": pct,
            "invasion_status": status,
            "postal": postal
        }

print(f"GT computed for {len(gt_results)} states with occurrences", file=sys.stderr)

# Summary
status_counts = {}
for v in gt_results.values():
    s = v["invasion_status"]
    status_counts[s] = status_counts.get(s, 0) + 1
print(f"Status distribution: {status_counts}", file=sys.stderr)

gt_output = {
    "state_stats": gt_results,
    "status_distribution": status_counts,
    "expected_state_count": len(gt_results),
    "early_period_total": len(early_points),
    "recent_period_total": len(recent_points)
}

with open("/tmp/gt_invasion.json", "w") as f:
    json.dump(gt_output, f, indent=2)
print(f"GT saved: {len(gt_results)} states")
PYEOF

if [ ! -f /tmp/gt_invasion.json ]; then
    echo "ERROR: GT computation failed"
    exit 1
fi

# ── RECORD baseline ────────────────────────────────────────────────────────────
INITIAL_COUNT=$(ls -1 "$EXPORT_DIR"/*.geojson 2>/dev/null | wc -l || echo "0")
echo "$INITIAL_COUNT" > /tmp/invasion_initial_export_count

# Record task start timestamp
date +%s > /tmp/invasion_start_ts

chown -R ga:ga "$GIS_DIR" 2>/dev/null || true
chmod 644 /tmp/gt_invasion.json 2>/dev/null || true

# ── LAUNCH QGIS ────────────────────────────────────────────────────────────────
kill_qgis ga 2>/dev/null || true
sleep 2

echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_invasion.log 2>&1 &"
sleep 6
wait_for_window "QGIS" 40 || echo "Warning: QGIS window not detected"
sleep 3

take_screenshot /tmp/task_start_invasion.png
echo "=== Setup Complete ==="
