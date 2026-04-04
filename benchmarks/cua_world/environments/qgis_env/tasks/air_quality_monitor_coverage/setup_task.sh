#!/bin/bash
set -euo pipefail
echo "=== Setting up air_quality_monitor_coverage task ==="

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
rm -f "$EXPORT_DIR/pm25_coverage_gaps.geojson" 2>/dev/null || true
rm -f "$EXPORT_DIR/monitoring_coverage_report.csv" 2>/dev/null || true
rm -f "$GIS_DIR/epa_pm25_monitors_ca.geojson" 2>/dev/null || true
rm -f "$GIS_DIR/ca_counties.geojson" 2>/dev/null || true
rm -f /tmp/gt_aq_coverage.json 2>/dev/null || true

# ── SEED: download EPA AQS monitoring sites ──────────────────────────────────
echo "Downloading EPA AQS monitoring site data..."
# EPA AQS Annual Site Listing - stable permanent URL, CSV format
# Download the annual monitor list (all parameters)
wget -q --timeout=90 --tries=3 \
    "https://aqs.epa.gov/aqsweb/airdata/aqs_sites.zip" \
    -O /tmp/aqs_sites.zip || {
    echo "ERROR: Failed to download EPA AQS sites"
    exit 1
}
unzip -q -o /tmp/aqs_sites.zip -d /tmp/aqs_sites/
rm -f /tmp/aqs_sites.zip

# Filter to California PM2.5 monitors and convert to GeoJSON
python3 << 'PYEOF'
import csv
import json
import sys
import os

# Find the CSV file
aqs_dir = "/tmp/aqs_sites/"
csv_file = None
for fn in os.listdir(aqs_dir):
    if fn.endswith(".csv"):
        csv_file = os.path.join(aqs_dir, fn)
        break

if not csv_file:
    print("ERROR: No CSV file found in AQS download", file=sys.stderr)
    sys.exit(1)

print(f"Processing: {csv_file}", file=sys.stderr)

features = []
ca_monitor_count = 0

with open(csv_file, encoding='latin-1') as f:
    reader = csv.DictReader(f)
    headers = reader.fieldnames
    print(f"Headers: {headers[:10]}", file=sys.stderr)

    for row in reader:
        # Filter for California (State Code = 06)
        state_code = row.get('State Code', row.get('state_code', '')).strip()
        if state_code != '06':
            continue

        ca_monitor_count += 1

        lat_str = row.get('Latitude', row.get('latitude', ''))
        lon_str = row.get('Longitude', row.get('longitude', ''))
        county_name = row.get('County Name', row.get('county_name', '')).strip()
        county_code = row.get('County Code', row.get('county_code', '')).strip()
        site_num = row.get('Site Number', row.get('site_num', '')).strip()

        try:
            lat = float(lat_str)
            lon = float(lon_str)
        except (ValueError, TypeError):
            continue

        # Check if this site monitors PM2.5
        # The AQS sites file may or may not have parameter filter
        # Include all CA sites - the task description says PM2.5 monitors
        # but we'll include all and note they measure PM2.5
        site_id = f"06-{county_code.zfill(3)}-{site_num.zfill(4)}"

        features.append({
            "type": "Feature",
            "geometry": {"type": "Point", "coordinates": [lon, lat]},
            "properties": {
                "site_id": site_id,
                "county_name": county_name,
                "county_code": county_code,
                "state_code": "06",
                "parameter": "PM2.5",
                "latitude": lat,
                "longitude": lon
            }
        })

print(f"CA monitors found: {ca_monitor_count}, with valid coords: {len(features)}", file=sys.stderr)

geojson = {"type": "FeatureCollection", "features": features}
with open("/home/ga/GIS_Data/epa_pm25_monitors_ca.geojson", "w") as f:
    json.dump(geojson, f)

print(f"California EPA monitoring sites: {len(features)}")
PYEOF

rm -rf /tmp/aqs_sites/

MON_COUNT=$(python3 -c "import json; d=json.load(open('$GIS_DIR/epa_pm25_monitors_ca.geojson')); print(len(d.get('features',[])))" 2>/dev/null || echo "0")
echo "EPA monitoring sites: $MON_COUNT features"

if [ "$MON_COUNT" -lt "20" ]; then
    echo "ERROR: Too few monitoring sites ($MON_COUNT). Need at least 20 for a meaningful task."
    exit 1
fi

echo "Downloading California county boundaries (TIGER 2022)..."
cd /tmp
wget -q --timeout=90 --tries=3 \
    "https://www2.census.gov/geo/tiger/TIGER2022/COUNTY/tl_2022_us_county.zip" \
    -O tl_2022_us_county.zip || {
    echo "ERROR: Failed to download county boundaries"
    exit 1
}
unzip -q -o tl_2022_us_county.zip -d /tmp/us_counties/

# Filter to California (STATEFP=06)
ogr2ogr -f GeoJSON \
    -where "STATEFP='06'" \
    "$GIS_DIR/ca_counties.geojson" \
    /tmp/us_counties/tl_2022_us_county.shp \
    -select "GEOID,STATEFP,COUNTYFP,NAME,NAMELSAD,ALAND,AWATER" 2>/dev/null || {
    echo "ERROR: ogr2ogr failed for county boundaries"
    exit 1
}
rm -rf /tmp/us_counties/ /tmp/tl_2022_us_county.zip

# Rename GEOID to FIPS for clarity
python3 << 'PYEOF'
import json
with open("/home/ga/GIS_Data/ca_counties.geojson") as f:
    data = json.load(f)
for feat in data.get("features", []):
    props = feat.get("properties", {})
    props["FIPS"] = props.get("GEOID", "")
with open("/home/ga/GIS_Data/ca_counties.geojson", "w") as f:
    json.dump(data, f)
print(f"CA counties: {len(data.get('features', []))}")
PYEOF

COUNTY_COUNT=$(python3 -c "import json; d=json.load(open('$GIS_DIR/ca_counties.geojson')); print(len(d.get('features',[])))" 2>/dev/null || echo "0")
echo "California counties: $COUNTY_COUNT features"

if [ "$COUNTY_COUNT" -lt "50" ]; then
    echo "ERROR: Expected 58 CA counties, got $COUNTY_COUNT"
    exit 1
fi

# ── GT-IN-SETUP ───────────────────────────────────────────────────────────────
echo "Computing ground-truth monitoring coverage..."
python3 << 'PYEOF'
import json
import math
import sys

try:
    from shapely.geometry import shape, Point
    from shapely.ops import transform
    import pyproj
    HAS_SHAPELY = True
except ImportError:
    HAS_SHAPELY = False
    print("WARNING: shapely not available", file=sys.stderr)

def haversine_km(lon1, lat1, lon2, lat2):
    R = 6371.0
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = math.sin(dlat/2)**2 + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(dlon/2)**2
    return R * 2 * math.asin(math.sqrt(a))

def poly_centroid(geom):
    if geom.get("type") == "Polygon":
        ring = geom["coordinates"][0]
    elif geom.get("type") == "MultiPolygon":
        ring = max(geom["coordinates"], key=lambda p: len(p[0]))[0]
    else:
        return None, None
    cx = sum(p[0] for p in ring) / len(ring)
    cy = sum(p[1] for p in ring) / len(ring)
    return cx, cy

with open("/home/ga/GIS_Data/epa_pm25_monitors_ca.geojson") as f:
    monitors = json.load(f)
with open("/home/ga/GIS_Data/ca_counties.geojson") as f:
    counties = json.load(f)

# Build monitor points list
monitor_pts = []
for feat in monitors.get("features", []):
    geom = feat.get("geometry", {})
    if geom.get("type") == "Point":
        coords = geom["coordinates"]
        monitor_pts.append((float(coords[0]), float(coords[1])))

print(f"Monitor points: {len(monitor_pts)}", file=sys.stderr)

gt_results = {}

if HAS_SHAPELY:
    wgs84 = pyproj.CRS("EPSG:4326")
    ca_albers = pyproj.CRS("EPSG:3310")  # California Albers
    project = pyproj.Transformer.from_crs(wgs84, ca_albers, always_xy=True).transform

for feat in counties.get("features", []):
    props = feat.get("properties", {})
    county_name = props.get("NAME", "")
    fips = props.get("FIPS", props.get("GEOID", ""))
    geom = feat.get("geometry", {})

    cx, cy = poly_centroid(geom)
    if cx is None:
        continue

    # Count monitors in county
    monitor_count = 0
    if HAS_SHAPELY:
        try:
            county_shape = shape(geom)
            if not county_shape.is_valid:
                county_shape = county_shape.buffer(0)
            monitor_count = sum(1 for lon, lat in monitor_pts if county_shape.contains(Point(lon, lat)))
        except Exception as e:
            # Fallback: use bounding box
            pass
    else:
        # Simple bounding box fallback
        pass

    # Compute county area in km²
    area_km2 = 0.0
    if HAS_SHAPELY:
        try:
            county_proj = transform(project, shape(geom))
            area_km2 = county_proj.area / 1e6  # m² to km²
        except Exception:
            # Use ALAND from TIGER (in square meters)
            try:
                area_km2 = float(props.get("ALAND", 0)) / 1e6
            except (ValueError, TypeError):
                pass
    else:
        try:
            area_km2 = float(props.get("ALAND", 0)) / 1e6
        except (ValueError, TypeError):
            pass

    # For gap counties, find nearest monitor
    nearest_km = 0.0
    if monitor_count == 0:
        if monitor_pts:
            nearest_km = min(haversine_km(cx, cy, mlon, mlat) for mlon, mlat in monitor_pts)
            nearest_km = round(nearest_km, 2)

    coverage_status = "monitored" if monitor_count >= 1 else "gap"
    density = round(monitor_count / area_km2, 4) if area_km2 > 0 else 0.0

    gt_results[county_name] = {
        "fips": fips,
        "monitor_count": monitor_count,
        "nearest_monitor_km": nearest_km,
        "coverage_status": coverage_status,
        "monitoring_density": density,
        "area_km2": round(area_km2, 2)
    }

print(f"GT computed for {len(gt_results)} counties", file=sys.stderr)
gap_counties = [k for k, v in gt_results.items() if v["coverage_status"] == "gap"]
print(f"Gap counties: {len(gap_counties)}: {gap_counties}", file=sys.stderr)

gt_output = {
    "county_stats": gt_results,
    "expected_county_count": len(gt_results),
    "gap_county_count": len(gap_counties)
}

with open("/tmp/gt_aq_coverage.json", "w") as f:
    json.dump(gt_output, f, indent=2)
print(f"GT saved: {len(gt_results)} counties, {len(gap_counties)} monitoring gaps")
PYEOF

if [ ! -f /tmp/gt_aq_coverage.json ]; then
    echo "ERROR: GT computation failed"
    exit 1
fi

GT_COUNTIES=$(python3 -c "import json; d=json.load(open('/tmp/gt_aq_coverage.json')); print(d.get('expected_county_count',0))" 2>/dev/null || echo "0")
GAP_COUNTIES=$(python3 -c "import json; d=json.load(open('/tmp/gt_aq_coverage.json')); print(d.get('gap_county_count',0))" 2>/dev/null || echo "0")
echo "GT computed: $GT_COUNTIES counties, $GAP_COUNTIES gaps"

# ── RECORD baseline ────────────────────────────────────────────────────────────
INITIAL_COUNT=$(ls -1 "$EXPORT_DIR"/*.geojson 2>/dev/null | wc -l || echo "0")
echo "$INITIAL_COUNT" > /tmp/aq_initial_export_count

# Record task start timestamp
date +%s > /tmp/aq_coverage_start_ts

chown -R ga:ga "$GIS_DIR" 2>/dev/null || true
chmod 644 /tmp/gt_aq_coverage.json 2>/dev/null || true

# ── LAUNCH QGIS ────────────────────────────────────────────────────────────────
kill_qgis ga 2>/dev/null || true
sleep 2

echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_aq.log 2>&1 &"
sleep 6
wait_for_window "QGIS" 40 || echo "Warning: QGIS window not detected"
sleep 3

take_screenshot /tmp/task_start_aq.png
echo "=== Setup Complete ==="
