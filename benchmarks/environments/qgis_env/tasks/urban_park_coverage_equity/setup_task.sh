#!/bin/bash
set -euo pipefail
echo "=== Setting up urban_park_coverage_equity task ==="

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
rm -f "$EXPORT_DIR/park_coverage_by_tract.geojson" 2>/dev/null || true
rm -f "$EXPORT_DIR/greenspace_equity_summary.csv" 2>/dev/null || true
rm -f "$GIS_DIR/portland_parks_osm.geojson" 2>/dev/null || true
rm -f "$GIS_DIR/portland_census_tracts.geojson" 2>/dev/null || true
rm -f /tmp/gt_park_coverage.json 2>/dev/null || true

# ── SEED: download Portland parks from Overpass API ──────────────────────────
echo "Downloading Portland parks from OpenStreetMap Overpass API..."
# Portland, OR bounding box: lat 45.43-45.60, lon -122.84-122.47
python3 << 'PYEOF'
import urllib.request
import urllib.parse
import json
import sys

overpass_url = "https://overpass-api.de/api/interpreter"
# Query for parks, recreation areas, and greenspaces in Portland
query = """
[out:json][timeout:90];
(
  way["leisure"~"^(park|recreation_ground|nature_reserve|garden|playground)$"](45.43,-122.84,45.60,-122.47);
  relation["leisure"~"^(park|recreation_ground|nature_reserve|garden)$"]["type"="multipolygon"](45.43,-122.84,45.60,-122.47);
);
out geom;
"""

data_encoded = urllib.parse.urlencode({"data": query}).encode()
req = urllib.request.Request(overpass_url, data=data_encoded)
req.add_header('User-Agent', 'GymAnything-QGISTask/1.0')
req.add_header('Content-Type', 'application/x-www-form-urlencoded')

try:
    with urllib.request.urlopen(req, timeout=120) as resp:
        result = json.loads(resp.read().decode())
except Exception as e:
    print(f"ERROR: Overpass API failed: {e}", file=sys.stderr)
    sys.exit(1)

features = []
for elem in result.get("elements", []):
    tags = elem.get("tags", {})
    elem_type = elem.get("type")

    if elem_type == "way":
        nodes = elem.get("geometry", [])
        if len(nodes) >= 3:
            coords = [[n["lon"], n["lat"]] for n in nodes]
            if coords[0] != coords[-1]:
                coords.append(coords[0])  # Close the ring
            features.append({
                "type": "Feature",
                "geometry": {"type": "Polygon", "coordinates": [coords]},
                "properties": {
                    "osm_id": elem.get("id"),
                    "name": tags.get("name", ""),
                    "leisure": tags.get("leisure", ""),
                    "access": tags.get("access", "public")
                }
            })
    elif elem_type == "relation":
        # Handle multipolygon relations
        members = elem.get("members", [])
        outer_rings = []
        for member in members:
            if member.get("role") == "outer" and member.get("type") == "way":
                geom = member.get("geometry", [])
                if len(geom) >= 3:
                    coords = [[n["lon"], n["lat"]] for n in geom]
                    if coords[0] != coords[-1]:
                        coords.append(coords[0])
                    outer_rings.append(coords)
        if outer_rings:
            geom = {"type": "MultiPolygon", "coordinates": [[ring] for ring in outer_rings]}
            features.append({
                "type": "Feature",
                "geometry": geom,
                "properties": {
                    "osm_id": elem.get("id"),
                    "name": tags.get("name", ""),
                    "leisure": tags.get("leisure", ""),
                    "access": tags.get("access", "public")
                }
            })

geojson = {"type": "FeatureCollection", "features": features}
with open("/home/ga/GIS_Data/portland_parks_osm.geojson", "w") as f:
    json.dump(geojson, f)
print(f"Portland parks: {len(features)} features")
PYEOF

PARK_COUNT=$(python3 -c "import json; d=json.load(open('$GIS_DIR/portland_parks_osm.geojson')); print(len(d.get('features',[])))" 2>/dev/null || echo "0")
echo "Portland parks: $PARK_COUNT features"

if [ "$PARK_COUNT" -lt "10" ]; then
    echo "ERROR: Too few park features ($PARK_COUNT). Check Overpass API."
    exit 1
fi

echo "Downloading Portland Census tracts (Multnomah County, OR)..."
# Census TIGER 2020 tracts for Oregon (FIPS: 41) - Multnomah County (FIPS: 051)
cd /tmp
wget -q --timeout=90 --tries=3 \
    "https://www2.census.gov/geo/tiger/TIGER2020/TRACT/tl_2020_41_tract.zip" \
    -O tl_2020_41_tract.zip || {
    echo "ERROR: Failed to download Census TIGER tracts"
    exit 1
}
unzip -q -o tl_2020_41_tract.zip -d /tmp/or_tracts/

# Filter to Multnomah County (FIPS: 41051) and convert to GeoJSON
ogr2ogr -f GeoJSON \
    -where "COUNTYFP='051'" \
    /tmp/multnomah_tracts_raw.geojson \
    /tmp/or_tracts/tl_2020_41_tract.shp \
    -select "GEOID,COUNTYFP,TRACTCE,NAMELSAD" 2>/dev/null || {
    echo "ERROR: ogr2ogr failed for Census tracts"
    exit 1
}
rm -rf /tmp/or_tracts/ /tmp/tl_2020_41_tract.zip

# Add 2020 population estimates from Census API
python3 << 'PYEOF'
import json
import urllib.request

# Census 2020 PL94-171 population for Multnomah County tracts
# Use Census API to get P1_001N (total population) by tract
census_api_url = (
    "https://api.census.gov/data/2020/dec/pl"
    "?get=P1_001N,NAME&for=tract:*&in=state:41%20county:051"
)

try:
    req = urllib.request.Request(census_api_url)
    req.add_header('User-Agent', 'GymAnything-QGISTask/1.0')
    with urllib.request.urlopen(req, timeout=30) as resp:
        data = json.loads(resp.read().decode())

    # data[0] is header: ['P1_001N', 'NAME', 'state', 'county', 'tract']
    pop_by_tract = {}
    for row in data[1:]:
        pop = int(row[0]) if row[0] else 0
        state_fips = row[2]
        county_fips = row[3]
        tract_fips = row[4]
        geoid = f"{state_fips}{county_fips}{tract_fips}"
        pop_by_tract[geoid] = pop

    print(f"Population data fetched for {len(pop_by_tract)} tracts")

except Exception as e:
    print(f"WARNING: Census API failed ({e}), using estimated population")
    pop_by_tract = {}

# Merge population into GeoJSON
with open("/tmp/multnomah_tracts_raw.geojson") as f:
    tracts = json.load(f)

for feat in tracts.get("features", []):
    props = feat.get("properties", {})
    geoid = props.get("GEOID", "")
    props["pop20"] = pop_by_tract.get(geoid, 0)

with open("/home/ga/GIS_Data/portland_census_tracts.geojson", "w") as f:
    json.dump(tracts, f)

feat_count = len(tracts.get("features", []))
print(f"Multnomah County census tracts: {feat_count}")
PYEOF

rm -f /tmp/multnomah_tracts_raw.geojson

TRACT_COUNT=$(python3 -c "import json; d=json.load(open('$GIS_DIR/portland_census_tracts.geojson')); print(len(d.get('features',[])))" 2>/dev/null || echo "0")
echo "Census tracts: $TRACT_COUNT features"

if [ "$TRACT_COUNT" -lt "30" ]; then
    echo "ERROR: Too few census tracts ($TRACT_COUNT). Expected ~100+ for Multnomah County."
    exit 1
fi

# ── GT-IN-SETUP: compute expected park coverage per tract ─────────────────────
echo "Computing ground-truth park coverage..."
python3 << 'PYEOF'
import json
import sys

try:
    from shapely.geometry import shape
    from shapely.ops import transform, unary_union
    import pyproj
    from functools import partial
    HAS_SHAPELY = True
except ImportError:
    HAS_SHAPELY = False
    print("WARNING: shapely/pyproj not available", file=sys.stderr)

with open("/home/ga/GIS_Data/portland_parks_osm.geojson") as f:
    parks_data = json.load(f)
with open("/home/ga/GIS_Data/portland_census_tracts.geojson") as f:
    tracts_data = json.load(f)

gt_results = {}

if HAS_SHAPELY:
    # Project to EPSG:2269 (Oregon State Plane North, ft) or EPSG:32610 (UTM 10N, meters)
    # Using EPSG:32610 for meters
    wgs84 = pyproj.CRS("EPSG:4326")
    utm10n = pyproj.CRS("EPSG:32610")
    project = pyproj.Transformer.from_crs(wgs84, utm10n, always_xy=True).transform

    # Build park geometries in projected CRS
    park_geoms = []
    for feat in parks_data.get("features", []):
        try:
            g = shape(feat["geometry"])
            if g.is_valid and not g.is_empty:
                g_proj = transform(project, g)
                if g_proj.is_valid and not g_proj.is_empty:
                    park_geoms.append(g_proj)
        except Exception:
            pass

    print(f"Valid park geometries: {len(park_geoms)}", file=sys.stderr)

    # Union all parks for faster intersection
    try:
        parks_union = unary_union(park_geoms)
    except Exception as e:
        print(f"WARNING: unary_union failed ({e}), using loop", file=sys.stderr)
        parks_union = None

    for feat in tracts_data.get("features", []):
        props = feat.get("properties", {})
        geoid = props.get("GEOID", "")
        pop = int(props.get("pop20", 0) or 0)
        try:
            tract_geom = shape(feat["geometry"])
            if not tract_geom.is_valid:
                tract_geom = tract_geom.buffer(0)
            tract_proj = transform(project, tract_geom)
            if not tract_proj.is_valid:
                tract_proj = tract_proj.buffer(0)
            tract_area = tract_proj.area  # m²

            if parks_union:
                intersection = tract_proj.intersection(parks_union)
            else:
                intersection_area = 0
                for pg in park_geoms:
                    try:
                        intersection_area += tract_proj.intersection(pg).area
                    except Exception:
                        pass
                intersection = None
                park_area = min(intersection_area, tract_area)

            if intersection is not None:
                park_area = intersection.area
            park_area = min(park_area, tract_area)  # cap at tract area

            park_pct = round(100.0 * park_area / tract_area, 2) if tract_area > 0 else 0.0

            if park_pct >= 10.0:
                tier = "adequate"
            elif park_pct >= 5.0:
                tier = "marginal"
            else:
                tier = "deficient"

            gt_results[geoid] = {
                "park_area_sqm": round(park_area, 1),
                "tract_area_sqm": round(tract_area, 1),
                "park_pct": park_pct,
                "greenspace_tier": tier,
                "pop20": pop
            }
        except Exception as e:
            print(f"  Skipping tract {geoid}: {e}", file=sys.stderr)

print(f"GT computed for {len(gt_results)} tracts", file=sys.stderr)

tier_counts = {}
tier_pop = {}
for v in gt_results.values():
    t = v["greenspace_tier"]
    tier_counts[t] = tier_counts.get(t, 0) + 1
    tier_pop[t] = tier_pop.get(t, 0) + v["pop20"]
print(f"Tier distribution: {tier_counts}", file=sys.stderr)

gt_output = {
    "tract_stats": gt_results,
    "tier_distribution": tier_counts,
    "expected_tract_count": len(gt_results)
}

with open("/tmp/gt_park_coverage.json", "w") as f:
    json.dump(gt_output, f, indent=2)
print(f"GT saved: {len(gt_results)} tracts")
PYEOF

if [ ! -f /tmp/gt_park_coverage.json ]; then
    echo "ERROR: GT computation failed"
    exit 1
fi

GT_TRACTS=$(python3 -c "import json; d=json.load(open('/tmp/gt_park_coverage.json')); print(d.get('expected_tract_count',0))" 2>/dev/null || echo "0")
echo "GT computed: $GT_TRACTS tracts"

# ── RECORD baseline ────────────────────────────────────────────────────────────
INITIAL_COUNT=$(ls -1 "$EXPORT_DIR"/*.geojson 2>/dev/null | wc -l || echo "0")
echo "$INITIAL_COUNT" > /tmp/park_initial_export_count

# Record task start timestamp
date +%s > /tmp/park_coverage_start_ts

chown -R ga:ga "$GIS_DIR" 2>/dev/null || true
chmod 644 /tmp/gt_park_coverage.json 2>/dev/null || true

# ── LAUNCH QGIS ────────────────────────────────────────────────────────────────
kill_qgis ga 2>/dev/null || true
sleep 2

echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_park.log 2>&1 &"
sleep 6
wait_for_window "QGIS" 40 || echo "Warning: QGIS window not detected"
sleep 3

take_screenshot /tmp/task_start_park.png
echo "=== Setup Complete ==="
