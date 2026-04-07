#!/bin/bash
# Note: no set -euo pipefail — commands need to be fault-tolerant

source /workspace/scripts/task_utils.sh

date +%s > /tmp/task_start_timestamp
rm -f /tmp/public_health_zone_result.json

# Create GIS data directories
su - ga -c "mkdir -p /home/ga/GIS_Data/exports"

# Create census tract GeoJSON with 20 polygon features
python3 << 'PYEOF'
import json, os

# Grid layout: 4 columns x 5 rows = 20 tracts
# Positioned in North Carolina (35-36°N, 79-80°W)
base_lat = 35.20
base_lon = -79.80
lat_step = 0.06
lon_step = 0.08

def make_polygon(row, col):
    """Create a rectangular polygon for a grid cell."""
    lat_min = base_lat + row * lat_step
    lat_max = lat_min + lat_step
    lon_min = base_lon + col * lon_step
    lon_max = lon_min + lon_step
    return {
        "type": "Polygon",
        "coordinates": [[
            [round(lon_min, 6), round(lat_min, 6)],
            [round(lon_max, 6), round(lat_min, 6)],
            [round(lon_max, 6), round(lat_max, 6)],
            [round(lon_min, 6), round(lat_max, 6)],
            [round(lon_min, 6), round(lat_min, 6)]
        ]]
    }

# Tract data: (tract_id, tract_name, aqi, pop_density, dist_hospital_km)
# HIGH-RISK tracts (AQI>75 AND pop_density>3500 AND dist_hospital>7.5): CT-003, CT-007, CT-011, CT-014, CT-016, CT-018, CT-020
tract_data = [
    # row 0 (tracts 1-4)
    ("CT-001", "Riverside North",        82,  2800, 9.2),   # FAIL: pop_density too low
    ("CT-002", "Elmwood Heights",        68,  4200, 8.5),   # FAIL: AQI too low
    ("CT-003", "Industrial Corridor",    89,  5100, 10.3),  # PASS: all three criteria met
    ("CT-004", "Millbrook East",         91,  3800, 5.5),   # FAIL: hospital too close
    # row 1 (tracts 5-8)
    ("CT-005", "Green Valley",           72,  1900, 12.1),  # FAIL: AQI and pop too low
    ("CT-006", "South Forks",            95,  4500, 6.8),   # FAIL: hospital too close
    ("CT-007", "Port District",          88,  6200, 9.7),   # PASS: all three criteria met
    ("CT-008", "Northgate Commons",      65,  5000, 11.5),  # FAIL: AQI too low
    # row 2 (tracts 9-12)
    ("CT-009", "Cedar Park",             78,  3000, 8.9),   # FAIL: pop_density too low
    ("CT-010", "Market Square",          85,  4100, 4.2),   # FAIL: hospital too close
    ("CT-011", "Eastside Flats",         92,  7300, 12.8),  # PASS: all three criteria met
    ("CT-012", "Lakeview West",          76,  3200, 9.1),   # FAIL: pop_density too low (3200<3500)
    # row 3 (tracts 13-16)
    ("CT-013", "Sherwood Terrace",       73,  4800, 8.3),   # FAIL: AQI too low
    ("CT-014", "Factory Row",            86,  4600, 8.2),   # PASS: all three criteria met
    ("CT-015", "Birchwood Estates",      79,  3100, 10.5),  # FAIL: pop_density too low
    ("CT-016", "Chemical Plant Zone",    94,  5800, 11.0),  # PASS: all three criteria met
    # row 4 (tracts 17-20)
    ("CT-017", "Sunset Ridge",           83,  2500, 7.9),   # FAIL: pop_density too low
    ("CT-018", "Harbor District",        81,  3900, 7.8),   # PASS: all three criteria met
    ("CT-019", "Western Hills",          90,  3400, 8.7),   # FAIL: pop_density too low (3400<3500)
    ("CT-020", "Downtown Core",          96,  4400, 9.5),   # PASS: all three criteria met
]

features = []
for idx, (tract_id, tract_name, aqi, pop_density, dist_hospital) in enumerate(tract_data):
    row = idx // 4
    col = idx % 4
    features.append({
        "type": "Feature",
        "id": idx + 1,
        "geometry": make_polygon(row, col),
        "properties": {
            "tract_id": tract_id,
            "tract_name": tract_name,
            "aqi": aqi,
            "pop_density": pop_density,
            "dist_hospital_km": dist_hospital
        }
    })

geojson = {
    "type": "FeatureCollection",
    "name": "census_tracts",
    "crs": {"type": "name", "properties": {"name": "urn:ogc:def:crs:OGC:1.3:CRS84"}},
    "features": features
}

os.makedirs('/home/ga/GIS_Data', exist_ok=True)
with open('/home/ga/GIS_Data/census_tracts.geojson', 'w') as f:
    json.dump(geojson, f, indent=2)

print(f"Created census_tracts.geojson with {len(features)} features")
qualifying = [t[0] for t in tract_data if t[2]>75 and t[3]>3500 and t[4]>7.5]
print(f"Qualifying tracts ({len(qualifying)}): {', '.join(qualifying)}")
PYEOF

# Create designation criteria document
cat > /home/ga/GIS_Data/designation_criteria.txt << 'CRITERIA'
HIGH-RISK HEALTH ZONE DESIGNATION CRITERIA
City Department of Public Health — Environmental Justice Division
Document: PHD-EJ-2024-07 | Effective: January 1, 2024

OVERVIEW
A census tract qualifies for High-Risk Health Zone designation if it demonstrates
compounding environmental, demographic, and healthcare access burdens. Designated
zones receive priority allocation for community health center funding, mobile health
units, and targeted air quality improvement programs.

DESIGNATION CRITERIA
A census tract must meet ALL THREE of the following conditions simultaneously:

  CONDITION 1 — Air Quality Burden:
    Annual average Air Quality Index (AQI) exceeds 75 micrograms per cubic meter (µg/m³)
    Data field: "aqi"

  CONDITION 2 — Population Density Threshold:
    Residential population density exceeds 3,500 persons per square kilometer
    Data field: "pop_density"

  CONDITION 3 — Healthcare Access Gap:
    Distance to the nearest licensed hospital facility exceeds 7.5 kilometers
    Data field: "dist_hospital_km"

NOTE: Tracts meeting only one or two conditions do NOT qualify. All three conditions
must be satisfied for designation. Use "Select by Expression" in QGIS or equivalent
GIS software to apply filters.

OUTPUT REQUIREMENTS
Export qualifying tracts as a GeoJSON file preserving all original attributes.
File must be saved to: /home/ga/GIS_Data/exports/high_risk_zones.geojson
CRITERIA

chown -R ga:ga /home/ga/GIS_Data

# Record initial export state (for anti-gaming)
INITIAL_EXPORT_COUNT=$(ls /home/ga/GIS_Data/exports/*.geojson 2>/dev/null | wc -l || echo "0")
echo "${INITIAL_EXPORT_COUNT}" > /tmp/initial_export_count

# Launch QGIS
kill_qgis 2>/dev/null || true
sleep 1

su - ga -c "DISPLAY=:1 qgis /home/ga/GIS_Data/census_tracts.geojson > /tmp/qgis.log 2>&1 &"
sleep 10

WID=$(get_qgis_window_id 2>/dev/null || echo "")
if [ -n "$WID" ]; then
    wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

take_screenshot "/tmp/public_health_zone_start.png" || true

echo "=== Setup complete ==="
echo "Input: /home/ga/GIS_Data/census_tracts.geojson (20 census tracts)"
echo "Criteria: /home/ga/GIS_Data/designation_criteria.txt"
echo "Output expected: /home/ga/GIS_Data/exports/high_risk_zones.geojson"
echo "Task: Read criteria, filter qualifying tracts, export as GeoJSON"
