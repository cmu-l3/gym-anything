#!/bin/bash
set -euo pipefail
echo "=== Setting up chicago_hospital_access_equity task ==="

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
echo "Cleaning previous outputs..."
EXPORT_DIR="/home/ga/GIS_Data/exports"
GIS_DIR="/home/ga/GIS_Data"
mkdir -p "$GIS_DIR" "$EXPORT_DIR"
rm -f "$EXPORT_DIR/hospital_access_equity.geojson" 2>/dev/null || true
rm -f "$EXPORT_DIR/access_tier_summary.csv" 2>/dev/null || true
rm -f "$GIS_DIR/chicago_hospitals.geojson" 2>/dev/null || true
rm -f "$GIS_DIR/chicago_community_areas.geojson" 2>/dev/null || true
rm -f /tmp/gt_hospital_access.json 2>/dev/null || true

# ── SEED: download real Chicago open data ─────────────────────────────────────
echo "Downloading Chicago community area boundaries..."
# Chicago Community Areas GeoJSON from Chicago Data Portal (very stable)
wget -q --timeout=60 --tries=3 \
    "https://data.cityofchicago.org/api/geospatial/cauq-8yn6?method=export&type=GeoJSON" \
    -O "$GIS_DIR/chicago_community_areas_raw.geojson" || {
    echo "ERROR: Failed to download Chicago community areas"
    exit 1
}

# Normalize community areas - add pop_2020 field using Python
python3 << 'PYEOF'
import json

# 2020 ACS population estimates for Chicago's 77 community areas
# Source: US Census Bureau / CMAP 2020 ACS 5-year estimates
pop_data = {
    "ROGERS PARK": 54991, "WEST RIDGE": 71942, "UPTOWN": 56362, "LINCOLN SQUARE": 39419,
    "NORTH CENTER": 35682, "LAKE VIEW": 98208, "LINCOLN PARK": 67732, "NEAR NORTH SIDE": 105481,
    "EDISON PARK": 11525, "NORWOOD PARK": 36314, "JEFFERSON PARK": 26774, "FOREST GLEN": 18634,
    "NORTH PARK": 17873, "ALBANY PARK": 50686, "PORTAGE PARK": 64324, "IRVING PARK": 55249,
    "DUNNING": 41263, "MONTCLARE": 13937, "BELMONT CRAGIN": 79152, "HERMOSA": 26185,
    "AVONDALE": 43083, "LOGAN SQUARE": 73595, "HUMBOLDT PARK": 56115, "WEST TOWN": 86199,
    "AUSTIN": 96557, "WEST GARFIELD PARK": 17433, "EAST GARFIELD PARK": 20567, "NEAR WEST SIDE": 54881,
    "NORTH LAWNDALE": 34794, "SOUTH LAWNDALE": 77148, "LOWER WEST SIDE": 35669, "LOOP": 42298,
    "NEAR SOUTH SIDE": 27294, "ARMOUR SQUARE": 13391, "DOUGLAS": 18238, "OAKLAND": 6799,
    "FULLER PARK": 2876, "GRAND BOULEVARD": 22183, "KENWOOD": 17841, "WASHINGTON PARK": 11717,
    "HYDE PARK": 29456, "WOODLAWN": 25983, "SOUTH SHORE": 49767, "CHATHAM": 32028,
    "AVALON PARK": 10158, "SOUTH CHICAGO": 29302, "BURNSIDE": 2974, "CALUMET HEIGHTS": 13061,
    "ROSELAND": 45467, "PULLMAN": 7325, "SOUTH DEERING": 16093, "EAST SIDE": 22858,
    "WEST PULLMAN": 28821, "RIVERDALE": 8031, "HEGEWISCH": 9724, "GARFIELD RIDGE": 35786,
    "ARCHER HEIGHTS": 13390, "BRIGHTON PARK": 46177, "MCKINLEY PARK": 16938, "BRIDGEPORT": 33702,
    "NEW CITY": 44377, "WEST ELSDON": 20394, "GAGE PARK": 39405, "CLEARING": 25222,
    "WEST LAWN": 36765, "CHICAGO LAWN": 58448, "WEST ENGLEWOOD": 30781, "ENGLEWOOD": 25275,
    "GREATER GRAND CROSSING": 32006, "ASHBURN": 41576, "AUBURN GRESHAM": 47041,
    "BEVERLY": 22331, "WASHINGTON HEIGHTS": 26614, "MOUNT GREENWOOD": 18419, "MORGAN PARK": 23916,
    "OHARE": 12756, "EDGEWATER": 56282
}

with open("/home/ga/GIS_Data/chicago_community_areas_raw.geojson") as f:
    data = json.load(f)

for feat in data.get("features", []):
    props = feat.get("properties", {})
    # Chicago Data Portal uses 'community' field
    comm_name = (props.get("community") or props.get("COMMUNITY") or "").upper().strip()
    pop = pop_data.get(comm_name, 0)
    props["pop_2020"] = pop
    # Ensure community field exists and is lowercase-friendly
    if "community" not in props and "COMMUNITY" in props:
        props["community"] = props["COMMUNITY"]

with open("/home/ga/GIS_Data/chicago_community_areas.geojson", "w") as f:
    json.dump(data, f)

feat_count = len(data.get("features", []))
print(f"Community areas processed: {feat_count}")
PYEOF

rm -f "$GIS_DIR/chicago_community_areas_raw.geojson"

CA_COUNT=$(python3 -c "import json; d=json.load(open('$GIS_DIR/chicago_community_areas.geojson')); print(len(d.get('features',[])))" 2>/dev/null || echo "0")
echo "Community areas: $CA_COUNT features"

if [ "$CA_COUNT" -lt "70" ]; then
    echo "ERROR: Expected ~77 community areas, got $CA_COUNT"
    exit 1
fi

echo "Downloading HIFLD US hospitals (Illinois)..."
# HIFLD hospitals REST API - filter for Illinois (STATE_ID=IL)
wget -q --timeout=90 --tries=3 \
    "https://opendata.arcgis.com/api/v3/datasets/6ac5e325468c4cb9b905f1728d6fbf0f_0/downloads/data?format=geojson&spatialRefId=4326" \
    -O /tmp/us_hospitals_all.geojson || {
    echo "WARNING: HIFLD download failed, trying alternative source..."
    # Fallback: use Overpass API to get Chicago-area hospitals
    python3 << 'OVPYEOF'
import urllib.request
import json

# Overpass query for hospitals in Chicago metro area
overpass_url = "https://overpass-api.de/api/interpreter"
query = """
[out:json][timeout:60];
(
  node["amenity"="hospital"](41.6,-88.0,42.1,-87.5);
  way["amenity"="hospital"](41.6,-88.0,42.1,-87.5);
);
out center;
"""
import urllib.parse
data_encoded = urllib.parse.urlencode({"data": query}).encode()
req = urllib.request.Request(overpass_url, data=data_encoded)
req.add_header('User-Agent', 'GymAnything-QGISTask/1.0')
try:
    with urllib.request.urlopen(req, timeout=60) as resp:
        result = json.loads(resp.read().decode())
    features = []
    for elem in result.get("elements", []):
        tags = elem.get("tags", {})
        if elem.get("type") == "node":
            lon, lat = elem.get("lon"), elem.get("lat")
        elif elem.get("type") == "way":
            center = elem.get("center", {})
            lon, lat = center.get("lon"), center.get("lat")
        else:
            continue
        if lon and lat:
            features.append({
                "type": "Feature",
                "geometry": {"type": "Point", "coordinates": [lon, lat]},
                "properties": {
                    "NAME": tags.get("name", "Unknown Hospital"),
                    "STATE": "IL",
                    "CITY": tags.get("addr:city", "Chicago"),
                    "TYPE": tags.get("healthcare:speciality", "GENERAL ACUTE CARE")
                }
            })
    geojson = {"type": "FeatureCollection", "features": features}
    with open("/tmp/us_hospitals_all.geojson", "w") as f:
        json.dump(geojson, f)
    print(f"Overpass: {len(features)} hospitals downloaded")
except Exception as e:
    print(f"ERROR: Overpass also failed: {e}")
    # Create minimal fallback with known major Chicago hospitals
    import sys; sys.exit(1)
OVPYEOF
}

# Filter to Illinois/Chicago hospitals
python3 << 'PYEOF'
import json

input_path = "/tmp/us_hospitals_all.geojson"
output_path = "/home/ga/GIS_Data/chicago_hospitals.geojson"

# Chicago bounding box (generous)
LON_MIN, LON_MAX = -88.0, -87.5
LAT_MIN, LAT_MAX = 41.6, 42.1

with open(input_path) as f:
    data = json.load(f)

il_features = []
for feat in data.get("features", []):
    props = feat.get("properties", {})
    geom = feat.get("geometry", {})
    state = str(props.get("STATE", props.get("state", ""))).upper()

    # Filter by state or bounding box
    in_illinois = state in ("IL", "ILLINOIS", "17")
    if geom.get("type") == "Point":
        coords = geom.get("coordinates", [])
        if len(coords) >= 2:
            lon, lat = float(coords[0]), float(coords[1])
            in_bbox = LON_MIN <= lon <= LON_MAX and LAT_MIN <= lat <= LAT_MAX
            if in_illinois or in_bbox:
                il_features.append(feat)

output = {"type": "FeatureCollection", "features": il_features}
with open(output_path, "w") as f:
    json.dump(output, f)
print(f"Chicago-area hospitals: {len(il_features)}")
PYEOF

rm -f /tmp/us_hospitals_all.geojson

HOSP_COUNT=$(python3 -c "import json; d=json.load(open('$GIS_DIR/chicago_hospitals.geojson')); print(len(d.get('features',[])))" 2>/dev/null || echo "0")
echo "Chicago hospitals: $HOSP_COUNT features"

if [ "$HOSP_COUNT" -lt "5" ]; then
    echo "ERROR: Too few hospitals downloaded ($HOSP_COUNT). Need at least 5 for a meaningful task."
    exit 1
fi

# ── GT-IN-SETUP ───────────────────────────────────────────────────────────────
echo "Computing ground-truth hospital access metrics..."
python3 << 'PYEOF'
import json
import math
import sys

def haversine_km(lon1, lat1, lon2, lat2):
    R = 6371.0
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = math.sin(dlat/2)**2 + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(dlon/2)**2
    return R * 2 * math.asin(math.sqrt(a))

def polygon_centroid(coords):
    """Compute centroid of a polygon ring."""
    ring = coords[0]
    n = len(ring)
    if n == 0:
        return None, None
    cx = sum(p[0] for p in ring) / n
    cy = sum(p[1] for p in ring) / n
    return cx, cy

def feature_centroid(geom):
    gtype = geom.get("type", "")
    coords = geom.get("coordinates", [])
    if gtype == "Point":
        return float(coords[0]), float(coords[1])
    elif gtype == "Polygon":
        return polygon_centroid(coords)
    elif gtype == "MultiPolygon":
        # Use centroid of largest polygon
        best = None
        best_area = -1
        for poly in coords:
            ring = poly[0]
            n = len(ring)
            cx = sum(p[0] for p in ring) / n
            cy = sum(p[1] for p in ring) / n
            area = n  # rough proxy
            if area > best_area:
                best_area = area
                best = (cx, cy)
        return best if best else (None, None)
    return None, None

with open("/home/ga/GIS_Data/chicago_hospitals.geojson") as f:
    hosp_data = json.load(f)
with open("/home/ga/GIS_Data/chicago_community_areas.geojson") as f:
    ca_data = json.load(f)

# Build hospital point list
hospitals = []
for feat in hosp_data.get("features", []):
    geom = feat.get("geometry", {})
    if geom.get("type") == "Point":
        coords = geom.get("coordinates", [])
        if len(coords) >= 2:
            hospitals.append((float(coords[0]), float(coords[1])))

print(f"Hospital points: {len(hospitals)}", file=sys.stderr)

gt_results = {}
tier_stats = {"high": {"count": 0, "pop": 0}, "medium": {"count": 0, "pop": 0}, "low": {"count": 0, "pop": 0}}

for feat in ca_data.get("features", []):
    props = feat.get("properties", {})
    geom = feat.get("geometry", {})
    name = (props.get("community") or props.get("COMMUNITY") or "Unknown").upper().strip()
    pop = int(props.get("pop_2020", 0) or 0)

    cx, cy = feature_centroid(geom)
    if cx is None:
        continue

    distances = [haversine_km(cx, cy, hlon, hlat) for hlon, hlat in hospitals]
    distances.sort()

    nearest = round(distances[0], 2) if distances else 999.0
    count_5km = sum(1 for d in distances if d <= 5.0)

    if count_5km >= 3:
        tier = "high"
    elif count_5km >= 1:
        tier = "medium"
    else:
        tier = "low"

    gt_results[name] = {
        "nearest_hosp_km": nearest,
        "hosp_count_5km": count_5km,
        "access_tier": tier,
        "pop_2020": pop
    }
    tier_stats[tier]["count"] += 1
    tier_stats[tier]["pop"] += pop

print(f"GT computed for {len(gt_results)} community areas", file=sys.stderr)
print(f"Tier distribution: {tier_stats}", file=sys.stderr)

gt_output = {
    "community_stats": gt_results,
    "tier_stats": tier_stats,
    "total_hospitals": len(hospitals),
    "expected_community_count": len(gt_results)
}

with open("/tmp/gt_hospital_access.json", "w") as f:
    json.dump(gt_output, f, indent=2)

print(f"GT saved. Low access: {tier_stats['low']['count']} areas")
PYEOF

if [ ! -f /tmp/gt_hospital_access.json ]; then
    echo "ERROR: GT computation failed"
    exit 1
fi

# ── RECORD baseline ────────────────────────────────────────────────────────────
INITIAL_COUNT=$(ls -1 "$EXPORT_DIR"/*.geojson 2>/dev/null | wc -l || echo "0")
echo "$INITIAL_COUNT" > /tmp/hospital_initial_export_count

# Record task start timestamp
date +%s > /tmp/hospital_start_ts

chown -R ga:ga "$GIS_DIR" 2>/dev/null || true
chmod 644 /tmp/gt_hospital_access.json 2>/dev/null || true

# ── LAUNCH QGIS ────────────────────────────────────────────────────────────────
kill_qgis ga 2>/dev/null || true
sleep 2

echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_hospital.log 2>&1 &"
sleep 6
wait_for_window "QGIS" 40 || echo "Warning: QGIS window not detected"
sleep 3

take_screenshot /tmp/task_start_hospital.png
echo "=== Setup Complete ==="
