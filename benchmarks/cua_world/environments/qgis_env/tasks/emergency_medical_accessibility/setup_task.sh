#!/bin/bash
set -euo pipefail
echo "=== Setting up emergency_medical_accessibility task ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
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

# ── CLEAN ──
echo "Cleaning previous outputs..."
DATA_DIR="/home/ga/GIS_Data/east_africa"
EXPORT_DIR="/home/ga/GIS_Data/exports"
mkdir -p "$DATA_DIR" "$EXPORT_DIR"
rm -f "$EXPORT_DIR/community_accessibility.geojson" 2>/dev/null || true
rm -f "$EXPORT_DIR/priority_summary.csv" 2>/dev/null || true
rm -f /tmp/gt_accessibility.json 2>/dev/null || true

# ── SEED: Download and prepare data ──

# 1. Communities — Natural Earth 10m populated places, filtered to EAC
echo "Downloading Natural Earth populated places..."
NE_URL="https://naciscdn.org/naturalearth/10m/cultural/ne_10m_populated_places_simple.zip"
NE_FALLBACK="https://github.com/nvkelso/natural-earth-vector/raw/master/10m_cultural/ne_10m_populated_places_simple.zip"
rm -rf /tmp/ne_places /tmp/ne_places.zip
wget -q --timeout=60 --tries=3 "$NE_URL" -O /tmp/ne_places.zip || \
    wget -q --timeout=60 --tries=3 "$NE_FALLBACK" -O /tmp/ne_places.zip || {
    echo "ERROR: Failed to download populated places"; exit 1
}
unzip -qo /tmp/ne_places.zip -d /tmp/ne_places/

# Filter to EAC countries and rename fields for clean output
python3 << 'PYEOF'
import json, sys

shp_dir = "/tmp/ne_places"
out_path = "/home/ga/GIS_Data/east_africa/communities.geojson"

# Try ogr2ogr first to convert shp to geojson
import subprocess
tmp_geojson = "/tmp/ne_places_all.geojson"
subprocess.run([
    "ogr2ogr", "-f", "GeoJSON", tmp_geojson,
    f"{shp_dir}/ne_10m_populated_places_simple.shp",
    "-where", "adm0name IN ('Kenya','Tanzania','Uganda','Rwanda','Burundi')"
], check=True)

with open(tmp_geojson) as f:
    data = json.load(f)

# Rename fields for clarity: pop_max -> population, adm0name -> country
features = []
for feat in data.get("features", []):
    props = feat.get("properties", {})
    new_props = {
        "name": props.get("name", "Unknown"),
        "population": int(props.get("pop_max", 0)),
        "country": props.get("adm0name", ""),
        "latitude": float(props.get("latitude", 0)),
        "longitude": float(props.get("longitude", 0))
    }
    features.append({
        "type": "Feature",
        "geometry": feat["geometry"],
        "properties": new_props
    })

geojson = {"type": "FeatureCollection", "features": features}
with open(out_path, "w") as f:
    json.dump(geojson, f, indent=2)

print(f"Communities: {len(features)} features written")
if len(features) < 20:
    print("ERROR: Too few communities", file=sys.stderr)
    sys.exit(1)
PYEOF

echo "Communities prepared."

# 2. Health Facilities — OSM Overpass API with deterministic fallback
echo "Downloading health facilities from OSM..."
python3 << 'PYEOF'
import json, urllib.request, sys, os

DATA_DIR = "/home/ga/GIS_Data/east_africa"
out_path = f"{DATA_DIR}/health_facilities.geojson"

# EAC bounding box: 28.5E to 42E, -12S to 5N
bbox = "-12.0,28.5,5.0,42.0"

query = f"""[out:json][timeout:120];
(
  node["amenity"="hospital"]({bbox});
  way["amenity"="hospital"]({bbox});
  relation["amenity"="hospital"]({bbox});
);
out center;"""

features = []
try:
    req = urllib.request.Request(
        "https://overpass-api.de/api/interpreter",
        data=f"data={urllib.request.quote(query)}".encode(),
        method="POST"
    )
    with urllib.request.urlopen(req, timeout=180) as resp:
        data = json.loads(resp.read().decode())

    for el in data.get("elements", []):
        lat = el.get("lat") or el.get("center", {}).get("lat")
        lon = el.get("lon") or el.get("center", {}).get("lon")
        if lat and lon:
            tags = el.get("tags", {})
            features.append({
                "type": "Feature",
                "geometry": {"type": "Point", "coordinates": [float(lon), float(lat)]},
                "properties": {
                    "name": tags.get("name", "Hospital"),
                    "type": "hospital"
                }
            })
    print(f"Overpass returned {len(features)} hospitals")
except Exception as e:
    print(f"Overpass API failed: {e}", file=sys.stderr)

# Deterministic fallback: place hospitals at large communities
if len(features) < 30:
    print("Using deterministic hospital generation from communities", file=sys.stderr)
    features = []
    with open(f"{DATA_DIR}/communities.geojson") as f:
        communities = json.load(f)

    # Sort by name for determinism
    sorted_feats = sorted(communities["features"],
                          key=lambda x: x["properties"].get("name", ""))

    for i, feat in enumerate(sorted_feats):
        pop = feat["properties"].get("population", 0)
        coords = feat["geometry"]["coordinates"]
        name = feat["properties"].get("name", "Unknown")

        if pop > 500000:
            # Major city: 3 hospitals at fixed offsets
            offsets = [(0.01, 0.01), (-0.01, 0.02), (0.02, -0.01)]
            for j, (dx, dy) in enumerate(offsets):
                features.append({
                    "type": "Feature",
                    "geometry": {"type": "Point",
                                 "coordinates": [coords[0] + dx, coords[1] + dy]},
                    "properties": {"name": f"{name} Hospital {j+1}",
                                   "type": "hospital"}
                })
        elif pop > 100000:
            # District hospital at city location
            features.append({
                "type": "Feature",
                "geometry": {"type": "Point", "coordinates": list(coords)},
                "properties": {"name": f"{name} District Hospital",
                               "type": "hospital"}
            })
        elif pop > 20000 and i % 5 == 0:
            # Every 5th small town: health center (deterministic)
            features.append({
                "type": "Feature",
                "geometry": {"type": "Point", "coordinates": list(coords)},
                "properties": {"name": f"{name} Health Center",
                               "type": "clinic"}
            })

geojson = {"type": "FeatureCollection", "features": features}
with open(out_path, "w") as f:
    json.dump(geojson, f, indent=2)

print(f"Health facilities: {len(features)} features written")
if len(features) < 5:
    print("ERROR: Too few health facilities", file=sys.stderr)
    sys.exit(1)
PYEOF

echo "Health facilities prepared."

# 3. Major Roads — Natural Earth 10m roads, clipped to EAC
echo "Downloading Natural Earth roads..."
ROAD_URL="https://naciscdn.org/naturalearth/10m/cultural/ne_10m_roads.zip"
ROAD_FALLBACK="https://github.com/nvkelso/natural-earth-vector/raw/master/10m_cultural/ne_10m_roads.zip"
rm -rf /tmp/ne_roads /tmp/ne_roads.zip
wget -q --timeout=120 --tries=3 "$ROAD_URL" -O /tmp/ne_roads.zip || \
    wget -q --timeout=120 --tries=3 "$ROAD_FALLBACK" -O /tmp/ne_roads.zip || {
    echo "ERROR: Failed to download roads"; exit 1
}
unzip -qo /tmp/ne_roads.zip -d /tmp/ne_roads/

# Clip to EAC bounding box
ogr2ogr -f GeoJSON "$DATA_DIR/major_roads.geojson" \
    /tmp/ne_roads/ne_10m_roads.shp \
    -clipsrc 28.5 -12.0 42.0 5.0 \
    -select "name,type,sov_a3"

ROAD_COUNT=$(python3 -c "
import json
with open('$DATA_DIR/major_roads.geojson') as f:
    d = json.load(f)
print(len(d['features']))
" 2>/dev/null || echo "0")
echo "Roads: $ROAD_COUNT features"

if [ "$ROAD_COUNT" -lt "5" ]; then
    echo "ERROR: Too few road features ($ROAD_COUNT)"
    exit 1
fi

# ── GROUND TRUTH COMPUTATION ──
echo "Computing ground truth..."
python3 << 'PYEOF'
import json, math, sys

DATA_DIR = "/home/ga/GIS_Data/east_africa"
GT_PATH = "/tmp/gt_accessibility.json"

with open(f"{DATA_DIR}/communities.geojson") as f:
    communities = json.load(f)
with open(f"{DATA_DIR}/health_facilities.geojson") as f:
    hospitals = json.load(f)
with open(f"{DATA_DIR}/major_roads.geojson") as f:
    roads = json.load(f)

# Project to EPSG:32737 using pyproj
try:
    import pyproj
    transformer = pyproj.Transformer.from_crs("EPSG:4326", "EPSG:32737", always_xy=True)

    def project_point(lon, lat):
        return transformer.transform(lon, lat)
except ImportError:
    print("WARNING: pyproj not available, using approximate projection", file=sys.stderr)
    # Approximate UTM zone 37S projection (central meridian 39E)
    import math
    def project_point(lon, lat):
        # Simple Transverse Mercator approximation
        k0 = 0.9996
        a = 6378137.0  # WGS84 semi-major
        lon0 = 39.0
        lat_rad = math.radians(lat)
        lon_rad = math.radians(lon - lon0)
        x = 500000 + k0 * a * lon_rad * math.cos(lat_rad)
        y = 10000000 + k0 * a * lat_rad
        return (x, y)

def point_to_segment_dist(px, py, x1, y1, x2, y2):
    """Minimum distance from point (px,py) to line segment (x1,y1)-(x2,y2)."""
    dx, dy = x2 - x1, y2 - y1
    len_sq = dx * dx + dy * dy
    if len_sq == 0:
        return math.sqrt((px - x1)**2 + (py - y1)**2)
    t = max(0.0, min(1.0, ((px - x1) * dx + (py - y1) * dy) / len_sq))
    proj_x = x1 + t * dx
    proj_y = y1 + t * dy
    return math.sqrt((px - proj_x)**2 + (py - proj_y)**2)

def point_to_line_dist(px, py, line_coords_proj):
    """Minimum distance from point to polyline."""
    min_d = float('inf')
    for i in range(len(line_coords_proj) - 1):
        x1, y1 = line_coords_proj[i]
        x2, y2 = line_coords_proj[i + 1]
        d = point_to_segment_dist(px, py, x1, y1, x2, y2)
        min_d = min(min_d, d)
    return min_d

# Project hospital locations
hosp_proj = []
for feat in hospitals["features"]:
    c = feat["geometry"]["coordinates"]
    try:
        hosp_proj.append(project_point(c[0], c[1]))
    except Exception:
        pass

# Project road segments
road_segs_proj = []
for feat in roads["features"]:
    geom = feat["geometry"]
    gtype = geom.get("type", "")
    coords_list = []
    if gtype == "LineString":
        coords_list = [geom["coordinates"]]
    elif gtype == "MultiLineString":
        coords_list = geom["coordinates"]
    for coords in coords_list:
        try:
            proj_line = [project_point(c[0], c[1]) for c in coords]
            if len(proj_line) >= 2:
                road_segs_proj.append(proj_line)
        except Exception:
            pass

# Compute metrics for each community
gt_stats = {}
summary = {}
for cls in ["critical", "high", "moderate", "low"]:
    summary[cls] = {"count": 0, "total_population": 0}

for feat in communities["features"]:
    c = feat["geometry"]["coordinates"]
    props = feat["properties"]
    name = props.get("name", "")
    pop = int(props.get("population", 0))
    country = props.get("country", "")

    try:
        cx, cy = project_point(c[0], c[1])
    except Exception:
        continue

    # Nearest hospital distance (meters)
    min_hosp_m = float('inf')
    for hx, hy in hosp_proj:
        d = math.sqrt((cx - hx)**2 + (cy - hy)**2)
        min_hosp_m = min(min_hosp_m, d)
    nearest_facility_km = round(min_hosp_m / 1000.0, 2)

    # Nearest road distance (meters)
    min_road_m = float('inf')
    for seg in road_segs_proj:
        d = point_to_line_dist(cx, cy, seg)
        min_road_m = min(min_road_m, d)
    nearest_road_km = round(min_road_m / 1000.0, 2)

    isolation_score = round(nearest_facility_km * nearest_road_km, 2)

    # Classification
    if nearest_facility_km > 30 and pop > 10000:
        priority_class = "critical"
    elif isolation_score > 50:
        priority_class = "high"
    elif isolation_score > 5:
        priority_class = "moderate"
    else:
        priority_class = "low"

    gt_stats[name] = {
        "country": country,
        "population": pop,
        "nearest_facility_km": nearest_facility_km,
        "nearest_road_km": nearest_road_km,
        "isolation_score": isolation_score,
        "priority_class": priority_class
    }
    summary[priority_class]["count"] += 1
    summary[priority_class]["total_population"] += pop

gt_output = {
    "community_stats": gt_stats,
    "priority_summary": summary,
    "total_communities": len(gt_stats),
    "total_hospitals": len(hosp_proj),
    "total_road_segments": len(road_segs_proj)
}

with open(GT_PATH, "w") as f:
    json.dump(gt_output, f, indent=2)

print(f"Ground truth: {len(gt_stats)} communities, {len(hosp_proj)} hospitals, {len(road_segs_proj)} road segments")
for cls, stats in summary.items():
    if stats["count"] > 0:
        print(f"  {cls}: {stats['count']} communities, pop {stats['total_population']}")
PYEOF

if [ ! -f /tmp/gt_accessibility.json ]; then
    echo "ERROR: Ground truth computation failed"
    exit 1
fi

# ── RECORD BASELINE ──
date +%s > /tmp/task_start_timestamp

# Fix permissions
chown -R ga:ga "/home/ga/GIS_Data" 2>/dev/null || true
chmod 644 /tmp/gt_accessibility.json 2>/dev/null || true

# ── LAUNCH QGIS ──
kill_qgis ga 2>/dev/null || true
sleep 2

echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis --noversioncheck > /tmp/qgis_task.log 2>&1 &"
sleep 6
wait_for_window "QGIS" 45 || echo "Warning: QGIS window not detected"
sleep 3

# Maximize window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "QGIS" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz
    DISPLAY=:1 wmctrl -ia "$WID"
fi

take_screenshot /tmp/task_start_accessibility.png
echo "=== Setup Complete ==="
