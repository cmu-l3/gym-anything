#!/bin/bash
set -euo pipefail
echo "=== Setting up seismic_risk_country_exposure task ==="

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

# ── CLEAN ──────────────────────────────────────────────────────────────────────
echo "Cleaning previous outputs..."
EXPORT_DIR="/home/ga/GIS_Data/exports"
GIS_DIR="/home/ga/GIS_Data"
mkdir -p "$GIS_DIR" "$EXPORT_DIR"
rm -f "$EXPORT_DIR/country_seismic_exposure.geojson" 2>/dev/null || true
rm -f "$GIS_DIR/earthquakes_month.geojson" 2>/dev/null || true
rm -f "$GIS_DIR/world_countries.geojson" 2>/dev/null || true
rm -f /tmp/gt_seismic.json 2>/dev/null || true

# ── SEED (download real data) ───────────────────────────────────────────────────
echo "Downloading USGS earthquake feed (M2.5+, last 30 days)..."
wget -q --timeout=60 --tries=3 \
    "https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/2.5_month.geojson" \
    -O "$GIS_DIR/earthquakes_month.geojson" || {
    echo "ERROR: Failed to download USGS earthquake feed"
    exit 1
}

EQ_COUNT=$(python3 -c "import json; d=json.load(open('$GIS_DIR/earthquakes_month.geojson')); print(len(d.get('features',[])))" 2>/dev/null || echo "0")
echo "Downloaded $EQ_COUNT earthquake features"

if [ "$EQ_COUNT" -lt "10" ]; then
    echo "ERROR: Too few earthquakes downloaded ($EQ_COUNT). Check network access."
    exit 1
fi

echo "Downloading Natural Earth country boundaries..."
wget -q --timeout=60 --tries=3 \
    "https://raw.githubusercontent.com/datasets/geo-countries/master/data/countries.geojson" \
    -O "$GIS_DIR/world_countries.geojson" || {
    echo "ERROR: Failed to download Natural Earth countries"
    exit 1
}

COUNTRY_COUNT=$(python3 -c "import json; d=json.load(open('$GIS_DIR/world_countries.geojson')); print(len(d.get('features',[])))" 2>/dev/null || echo "0")
echo "Downloaded $COUNTRY_COUNT country features"

# ── GT-IN-SETUP: compute expected results ─────────────────────────────────────
echo "Computing ground-truth expected results..."
python3 << 'PYEOF'
import json
import sys

try:
    from shapely.geometry import shape, Point
    HAS_SHAPELY = True
except ImportError:
    HAS_SHAPELY = False
    print("WARNING: shapely not available, GT will be approximate", file=sys.stderr)

eq_path = "/home/ga/GIS_Data/earthquakes_month.geojson"
countries_path = "/home/ga/GIS_Data/world_countries.geojson"
gt_path = "/tmp/gt_seismic.json"

with open(eq_path) as f:
    eq_data = json.load(f)
with open(countries_path) as f:
    countries_data = json.load(f)

# Extract earthquake points with magnitudes
eq_points = []
for feat in eq_data.get("features", []):
    geom = feat.get("geometry")
    props = feat.get("properties", {})
    if geom and geom.get("type") == "Point":
        coords = geom["coordinates"]
        mag = props.get("mag")
        if mag is not None and len(coords) >= 2:
            eq_points.append((float(coords[0]), float(coords[1]), float(mag)))

print(f"Total earthquake points to process: {len(eq_points)}", file=sys.stderr)

gt_results = {}

if HAS_SHAPELY:
    # Build spatial index for efficiency
    country_geoms = []
    for feat in countries_data.get("features", []):
        props = feat.get("properties", {})
        name = (props.get("ADMIN") or props.get("admin") or
                props.get("NAME") or props.get("name") or "Unknown")
        iso = props.get("ISO_A3") or props.get("iso_a3") or ""
        try:
            geom = shape(feat["geometry"])
            country_geoms.append((name, iso, geom))
        except Exception:
            pass

    for (name, iso, geom) in country_geoms:
        quakes_in = []
        for lon, lat, mag in eq_points:
            pt = Point(lon, lat)
            try:
                if geom.contains(pt):
                    quakes_in.append(mag)
            except Exception:
                pass
        if quakes_in:
            count = len(quakes_in)
            mean_mag = round(sum(quakes_in) / count, 2)
            max_mag = round(max(quakes_in), 2)
            if count < 5:
                risk_tier = "low"
            elif count < 15:
                risk_tier = "medium"
            else:
                risk_tier = "high"
            gt_results[name] = {
                "quake_count": count,
                "mean_mag": mean_mag,
                "max_mag": max_mag,
                "risk_tier": risk_tier,
                "iso_a3": iso
            }

print(f"GT: {len(gt_results)} countries with earthquakes", file=sys.stderr)

# Compute expected total
total_quakes_accounted = sum(v["quake_count"] for v in gt_results.values())
expected_feature_count = len(gt_results)

gt_output = {
    "country_stats": gt_results,
    "expected_feature_count": expected_feature_count,
    "total_earthquake_points": len(eq_points),
    "total_quakes_accounted": total_quakes_accounted
}

with open(gt_path, "w") as f:
    json.dump(gt_output, f, indent=2)

print(f"GT saved: {expected_feature_count} countries, {total_quakes_accounted}/{len(eq_points)} quakes accounted")
PYEOF

if [ ! -f /tmp/gt_seismic.json ]; then
    echo "ERROR: GT computation failed"
    exit 1
fi

GT_FEATURES=$(python3 -c "import json; d=json.load(open('/tmp/gt_seismic.json')); print(d.get('expected_feature_count',0))" 2>/dev/null || echo "0")
echo "GT computed: $GT_FEATURES countries with earthquakes"

# ── RECORD baseline ────────────────────────────────────────────────────────────
INITIAL_COUNT=$(ls -1 "$EXPORT_DIR"/*.geojson 2>/dev/null | wc -l || echo "0")
echo "$INITIAL_COUNT" > /tmp/seismic_initial_export_count
echo "Initial export count: $INITIAL_COUNT"

# Record task start timestamp (AFTER cleanup and seeding, before agent starts)
date +%s > /tmp/seismic_start_ts

# Fix permissions
chown -R ga:ga "$GIS_DIR" 2>/dev/null || true
chmod 644 /tmp/gt_seismic.json 2>/dev/null || true

# ── LAUNCH QGIS ────────────────────────────────────────────────────────────────
kill_qgis ga 2>/dev/null || true
sleep 2

echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_seismic.log 2>&1 &"
sleep 6
wait_for_window "QGIS" 40 || echo "Warning: QGIS window not detected"
sleep 3

take_screenshot /tmp/task_start_seismic.png
echo "=== Setup Complete ==="
