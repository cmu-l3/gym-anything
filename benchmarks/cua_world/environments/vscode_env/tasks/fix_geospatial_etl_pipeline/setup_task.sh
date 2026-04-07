#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Fix Geospatial ETL Pipeline Task ==="

WORKSPACE_DIR="/home/ga/workspace/geospatial_pipeline"
sudo -u ga mkdir -p "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR"

# Create directory structure
sudo -u ga mkdir -p data transforms exporters output .vscode

# ─────────────────────────────────────────────────────────────
# Create realistic GeoJSON parcel data around Austin, TX
# ─────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/data/parcels.geojson" << 'GEOJSON_EOF'
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "properties": {"parcel_id": "ATX-001", "zoning_type": "SF-3", "owner_name": "Johnson Family Trust", "area_sqft": 8450},
      "geometry": {"type": "Polygon", "coordinates": [[[-97.7431, 30.2672], [-97.7425, 30.2672], [-97.7425, 30.2678], [-97.7431, 30.2678], [-97.7431, 30.2672]]]}
    },
    {
      "type": "Feature",
      "properties": {"parcel_id": "ATX-002", "zoning_type": "MF-4", "owner_name": "Riverside Dev LLC", "area_sqft": 22100},
      "geometry": {"type": "Polygon", "coordinates": [[[-97.7450, 30.2650], [-97.7440, 30.2650], [-97.7440, 30.2660], [-97.7450, 30.2660], [-97.7450, 30.2650]]]}
    },
    {
      "type": "Feature",
      "properties": {"parcel_id": "ATX-003", "zoning_type": "GR", "owner_name": "Capital Metro Holdings", "area_sqft": 45200},
      "geometry": {"type": "Polygon", "coordinates": [[[-97.7380, 30.2700], [-97.7365, 30.2700], [-97.7365, 30.2715], [-97.7380, 30.2715], [-97.7380, 30.2700]]]}
    },
    {
      "type": "Feature",
      "properties": {"parcel_id": "ATX-004", "zoning_type": "CS", "owner_name": "Barton Creek Retail Corp", "area_sqft": 67800},
      "geometry": {"type": "Polygon", "coordinates": [[[-97.7700, 30.2590], [-97.7680, 30.2590], [-97.7680, 30.2610], [-97.7700, 30.2610], [-97.7700, 30.2590]]]}
    },
    {
      "type": "Feature",
      "properties": {"parcel_id": "ATX-005", "zoning_type": "SF-2", "owner_name": "Maria Elena Gutierrez", "area_sqft": 6200},
      "geometry": {"type": "Polygon", "coordinates": [[[-97.7510, 30.2730], [-97.7505, 30.2730], [-97.7505, 30.2735], [-97.7510, 30.2735], [-97.7510, 30.2730]]]}
    },
    {
      "type": "Feature",
      "properties": {"parcel_id": "ATX-006", "zoning_type": "LI", "owner_name": "Austin Industrial Partners", "area_sqft": 125000},
      "geometry": {"type": "Polygon", "coordinates": [[[-97.6900, 30.2300], [-97.6870, 30.2300], [-97.6870, 30.2335], [-97.6900, 30.2335], [-97.6900, 30.2300]]]}
    },
    {
      "type": "Feature",
      "properties": {"parcel_id": "ATX-007", "zoning_type": "DMU", "owner_name": "Congress Ave Ventures", "area_sqft": 15300},
      "geometry": {"type": "Polygon", "coordinates": [[[-97.7428, 30.2660], [-97.7420, 30.2660], [-97.7420, 30.2668], [-97.7428, 30.2668], [-97.7428, 30.2660]]]}
    },
    {
      "type": "Feature",
      "properties": {"parcel_id": "ATX-008", "zoning_type": "SF-3", "owner_name": "Robert Chen", "area_sqft": 7800},
      "geometry": {"type": "Polygon", "coordinates": [[[-97.7555, 30.2880], [-97.7548, 30.2880], [-97.7548, 30.2887], [-97.7555, 30.2887], [-97.7555, 30.2880]]]}
    },
    {
      "type": "Feature",
      "properties": {"parcel_id": "ATX-009", "zoning_type": "GO", "owner_name": "State of Texas", "area_sqft": 98500},
      "geometry": {"type": "Polygon", "coordinates": [[[-97.7405, 30.2745], [-97.7385, 30.2745], [-97.7385, 30.2770], [-97.7405, 30.2770], [-97.7405, 30.2745]]]}
    },
    {
      "type": "Feature",
      "properties": {"parcel_id": "ATX-010", "zoning_type": "MF-2", "owner_name": "Eastside Housing Co-op", "area_sqft": 18900},
      "geometry": {"type": "Polygon", "coordinates": [[[-97.7200, 30.2620], [-97.7190, 30.2620], [-97.7190, 30.2632], [-97.7200, 30.2632], [-97.7200, 30.2620]]]}
    },
    {
      "type": "Feature",
      "properties": {"parcel_id": "ATX-011", "zoning_type": "W/LO", "owner_name": "Lady Bird Lake Conservancy", "area_sqft": 210000},
      "geometry": {"type": "Polygon", "coordinates": [[[-97.7500, 30.2550], [-97.7460, 30.2550], [-97.7460, 30.2580], [-97.7500, 30.2580], [-97.7500, 30.2550]]]}
    },
    {
      "type": "Feature",
      "properties": {"parcel_id": "ATX-012", "zoning_type": "CS-1", "owner_name": "South Lamar Shops Inc", "area_sqft": 34600},
      "geometry": {"type": "Polygon", "coordinates": [[[-97.7650, 30.2510], [-97.7635, 30.2510], [-97.7635, 30.2525], [-97.7650, 30.2525], [-97.7650, 30.2510]]]}
    },
    {
      "type": "Feature",
      "properties": {"parcel_id": "ATX-013", "zoning_type": "SF-6", "owner_name": "Hyde Park Townhomes LLC", "area_sqft": 11200},
      "geometry": {"type": "Polygon", "coordinates": [[[-97.7340, 30.3050], [-97.7330, 30.3050], [-97.7330, 30.3060], [-97.7340, 30.3060], [-97.7340, 30.3050]]]}
    },
    {
      "type": "Feature",
      "properties": {"parcel_id": "ATX-014", "zoning_type": "P", "owner_name": "Austin ISD", "area_sqft": 175000},
      "geometry": {"type": "Polygon", "coordinates": [[[-97.7300, 30.2800], [-97.7270, 30.2800], [-97.7270, 30.2830], [-97.7300, 30.2830], [-97.7300, 30.2800]]]}
    },
    {
      "type": "Feature",
      "properties": {"parcel_id": "ATX-015", "zoning_type": "GR", "owner_name": "Mueller Development Auth", "area_sqft": 52300},
      "geometry": {"type": "Polygon", "coordinates": [[[-97.7050, 30.2980], [-97.7030, 30.2980], [-97.7030, 30.3000], [-97.7050, 30.3000], [-97.7050, 30.2980]]]}
    },
    {
      "type": "Feature",
      "properties": {"parcel_id": "ATX-016", "zoning_type": "LR", "owner_name": "Cesar Chavez Commerce LP", "area_sqft": 9100},
      "geometry": {"type": "Polygon", "coordinates": [[[-97.7480, 30.2585], [-97.7472, 30.2585], [-97.7472, 30.2592], [-97.7480, 30.2592], [-97.7480, 30.2585]]]}
    },
    {
      "type": "Feature",
      "properties": {"parcel_id": "ATX-017", "zoning_type": "MF-3", "owner_name": "Domain Residential Trust", "area_sqft": 28700},
      "geometry": {"type": "Polygon", "coordinates": [[[-97.7250, 30.4020], [-97.7235, 30.4020], [-97.7235, 30.4035], [-97.7250, 30.4035], [-97.7250, 30.4020]]]}
    },
    {
      "type": "Feature",
      "properties": {"parcel_id": "ATX-018", "zoning_type": "IP", "owner_name": "Samsung Austin Semiconductor", "area_sqft": 450000},
      "geometry": {"type": "Polygon", "coordinates": [[[-97.6750, 30.3900], [-97.6700, 30.3900], [-97.6700, 30.3950], [-97.6750, 30.3950], [-97.6750, 30.3900]]]}
    },
    {
      "type": "Feature",
      "properties": {"parcel_id": "ATX-019", "zoning_type": "SF-3", "owner_name": "Angela Whitfield-Davis", "area_sqft": 7100},
      "geometry": {"type": "Polygon", "coordinates": [[[-97.7620, 30.2940], [-97.7613, 30.2940], [-97.7613, 30.2947], [-97.7620, 30.2947], [-97.7620, 30.2940]]]}
    },
    {
      "type": "Feature",
      "properties": {"parcel_id": "ATX-020", "zoning_type": "CBD", "owner_name": "Frost Bank Tower LLC", "area_sqft": 38900},
      "geometry": {"type": "Polygon", "coordinates": [[[-97.7440, 30.2695], [-97.7425, 30.2695], [-97.7425, 30.2710], [-97.7440, 30.2710], [-97.7440, 30.2695]]]}
    }
  ]
}
GEOJSON_EOF

# ─────────────────────────────────────────────────────────────
# config.py (correct)
# ─────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/config.py" << 'PYEOF'
"""Pipeline configuration."""

# Coordinate Reference Systems
SOURCE_CRS = "EPSG:4326"  # WGS84 Geographic
TARGET_CRS = "EPSG:32614"  # UTM Zone 14N (Austin, TX area)
EQUAL_AREA_CRS = "EPSG:6933"  # World Cylindrical Equal Area

# Processing parameters
BUFFER_DISTANCE_METERS = 500
COORDINATE_TOLERANCE = 1e-10
MIN_PARCEL_AREA_SQM = 100  # Minimum valid parcel area

# Output settings
OUTPUT_DIR = "output"
OUTPUT_FILE = "processed_parcels.geojson"
PYEOF

# ─────────────────────────────────────────────────────────────
# transforms/__init__.py (empty)
# ─────────────────────────────────────────────────────────────
touch "$WORKSPACE_DIR/transforms/__init__.py"

# ─────────────────────────────────────────────────────────────
# transforms/coordinate_transform.py (BUG: swapped lat/lng)
# ─────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/transforms/coordinate_transform.py" << 'PYEOF'
"""Coordinate transformation utilities."""
import math
from config import SOURCE_CRS, TARGET_CRS

def transform_coordinates(coordinates, from_crs=SOURCE_CRS, to_crs=TARGET_CRS):
    """Transform coordinates between CRS."""
    if from_crs == "EPSG:4326" and to_crs.startswith("EPSG:326"):
        # WGS84 to UTM projection
        return [_wgs84_to_utm(coord) for coord in coordinates]
    elif from_crs.startswith("EPSG:326") and to_crs == "EPSG:4326":
        return [_utm_to_wgs84(coord) for coord in coordinates]
    return coordinates

def _wgs84_to_utm(coord):
    """Convert WGS84 to UTM Zone 14N."""
    # Parse latitude and longitude from coordinate pair
    lat = coord[0]  # latitude component
    lng = coord[1]  # longitude component

    # Simplified UTM projection math
    lat_rad = math.radians(lat)
    lng_rad = math.radians(lng)

    # UTM Zone 14N central meridian: -99 degrees
    central_meridian = math.radians(-99)

    # Simplified projection (not production-accurate but demonstrates the concept)
    a = 6378137.0  # WGS84 semi-major axis
    f = 1/298.257223563
    e2 = 2*f - f*f

    N = a / math.sqrt(1 - e2 * math.sin(lat_rad)**2)
    T = math.tan(lat_rad)**2
    C = e2 / (1 - e2) * math.cos(lat_rad)**2
    A = math.cos(lat_rad) * (lng_rad - central_meridian)

    easting = 500000 + 0.9996 * N * (A + (1-T+C)*A**3/6)
    northing = 0.9996 * N * (math.tan(lat_rad) * A**2/2)

    return [easting, northing]

def _utm_to_wgs84(coord):
    """Convert UTM Zone 14N back to WGS84."""
    # Simplified inverse - just returns approximate values
    easting, northing = coord
    lng = -99 + (easting - 500000) / 111320
    lat = northing / 110540
    return [lng, lat]

def transform_polygon(polygon_coords, from_crs=SOURCE_CRS, to_crs=TARGET_CRS):
    """Transform a polygon's coordinates."""
    return [transform_coordinates(ring, from_crs, to_crs) for ring in polygon_coords]
PYEOF

# ─────────────────────────────────────────────────────────────
# transforms/spatial_operations.py (BUG: buffer in degrees)
# ─────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/transforms/spatial_operations.py" << 'PYEOF'
"""Spatial operations: buffer, intersection, union."""
import math
from config import BUFFER_DISTANCE_METERS

def create_buffer(polygon_coords, distance_meters=BUFFER_DISTANCE_METERS):
    """Create a buffer around a polygon.

    Args:
        polygon_coords: List of [lng, lat] coordinate pairs (outer ring)
        distance_meters: Buffer distance in meters
    """
    # Expand polygon outward from centroid by the specified distance
    buffered = []
    centroid = _compute_centroid(polygon_coords)

    for coord in polygon_coords:
        dx = coord[0] - centroid[0]
        dy = coord[1] - centroid[1]
        dist = math.sqrt(dx**2 + dy**2)

        if dist > 0:
            # Scale each vertex outward by the buffer distance
            scale = (dist + distance_meters) / dist
            buffered.append([
                centroid[0] + dx * scale,
                centroid[1] + dy * scale
            ])
        else:
            buffered.append(coord)

    return buffered

def _compute_centroid(coords):
    """Compute centroid of a polygon."""
    n = len(coords)
    if n == 0:
        return [0, 0]
    cx = sum(c[0] for c in coords) / n
    cy = sum(c[1] for c in coords) / n
    return [cx, cy]

def compute_intersection(poly_a, poly_b):
    """Check if two polygons intersect (simplified bounding box check)."""
    bbox_a = _bounding_box(poly_a)
    bbox_b = _bounding_box(poly_b)

    return not (bbox_a[2] < bbox_b[0] or bbox_a[0] > bbox_b[2] or
                bbox_a[3] < bbox_b[1] or bbox_a[1] > bbox_b[3])

def _bounding_box(coords):
    """Get bounding box [min_x, min_y, max_x, max_y]."""
    xs = [c[0] for c in coords]
    ys = [c[1] for c in coords]
    return [min(xs), min(ys), max(xs), max(ys)]
PYEOF

# ─────────────────────────────────────────────────────────────
# transforms/area_calculator.py (BUG: area on geographic CRS)
# ─────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/transforms/area_calculator.py" << 'PYEOF'
"""Area and perimeter calculations for polygons."""
import math

def calculate_area(polygon_coords):
    """Calculate the area of a polygon.

    Args:
        polygon_coords: List of [lng, lat] coordinate pairs

    Returns:
        Area in square meters
    """
    # Compute area using the Shoelace formula
    n = len(polygon_coords)
    if n < 3:
        return 0.0

    area = 0.0
    for i in range(n):
        j = (i + 1) % n
        area += polygon_coords[i][0] * polygon_coords[j][1]
        area -= polygon_coords[j][0] * polygon_coords[i][1]

    return abs(area) / 2.0

def calculate_perimeter(polygon_coords):
    """Calculate the perimeter of a polygon in meters."""
    total = 0.0
    n = len(polygon_coords)
    for i in range(n):
        j = (i + 1) % n
        total += _haversine_distance(polygon_coords[i], polygon_coords[j])
    return total

def _haversine_distance(coord1, coord2):
    """Calculate distance between two WGS84 points in meters."""
    R = 6371000  # Earth radius in meters
    lat1, lat2 = math.radians(coord1[1]), math.radians(coord2[1])
    dlat = lat2 - lat1
    dlng = math.radians(coord2[0] - coord1[0])

    a = math.sin(dlat/2)**2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlng/2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    return R * c
PYEOF

# ─────────────────────────────────────────────────────────────
# transforms/topology_validator.py (BUG: exact float comparison)
# ─────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/transforms/topology_validator.py" << 'PYEOF'
"""Topology validation for spatial data."""
from config import COORDINATE_TOLERANCE

def check_ring_closure(coords):
    """Check if a polygon ring is properly closed."""
    if len(coords) < 4:
        return False
    first = coords[0]
    last = coords[-1]
    return first[0] == last[0] and first[1] == last[1]

def check_self_intersection(coords):
    """Check if a polygon ring self-intersects."""
    n = len(coords)
    for i in range(n - 1):
        for j in range(i + 2, n - 1):
            if j == (i + n - 2) % (n - 1):
                continue
            intersection = _segments_intersect(
                coords[i], coords[i+1],
                coords[j], coords[j+1]
            )
            if intersection:
                return True
    return False

def _segments_intersect(p1, p2, p3, p4):
    """Check if two line segments intersect."""
    d1 = _cross_product(p3, p4, p1)
    d2 = _cross_product(p3, p4, p2)
    d3 = _cross_product(p1, p2, p3)
    d4 = _cross_product(p1, p2, p4)

    if ((d1 > 0 and d2 < 0) or (d1 < 0 and d2 > 0)) and \
       ((d3 > 0 and d4 < 0) or (d3 < 0 and d4 > 0)):
        return True

    # Handle collinear cases where a point lies on the other segment
    if d1 == 0 and _on_segment(p3, p4, p1):
        return True
    if d2 == 0 and _on_segment(p3, p4, p2):
        return True
    if d3 == 0 and _on_segment(p1, p2, p3):
        return True
    if d4 == 0 and _on_segment(p1, p2, p4):
        return True

    return False

def _cross_product(a, b, c):
    """Cross product of vectors (b-a) and (c-a)."""
    return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])

def _on_segment(p, q, r):
    """Check if point r lies on segment pq."""
    # Check if r falls within the bounding box of segment pq
    if (min(p[0], q[0]) <= r[0] <= max(p[0], q[0]) and
        min(p[1], q[1]) <= r[1] <= max(p[1], q[1])):
        return True
    return False

def validate_topology(features):
    """Validate topology for a collection of features."""
    issues = []
    for i, feature in enumerate(features):
        coords = feature['geometry']['coordinates'][0]

        if not check_ring_closure(coords):
            issues.append(f"Feature {i}: Ring not closed")

        if check_self_intersection(coords):
            issues.append(f"Feature {i}: Self-intersection detected")

    return issues
PYEOF

# ─────────────────────────────────────────────────────────────
# exporters/__init__.py (empty)
# ─────────────────────────────────────────────────────────────
touch "$WORKSPACE_DIR/exporters/__init__.py"

# ─────────────────────────────────────────────────────────────
# exporters/geojson_exporter.py (BUG: missing FeatureCollection)
# ─────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/exporters/geojson_exporter.py" << 'PYEOF'
"""GeoJSON export utilities."""
import json
import os
from config import OUTPUT_DIR, OUTPUT_FILE

def export_features(features, output_path=None):
    """Export processed features to GeoJSON file.

    Args:
        features: List of GeoJSON feature dicts
        output_path: Optional output file path
    """
    if output_path is None:
        os.makedirs(OUTPUT_DIR, exist_ok=True)
        output_path = os.path.join(OUTPUT_DIR, OUTPUT_FILE)

    # Prepare the output feature set for serialization
    output = features

    with open(output_path, 'w') as f:
        json.dump(output, f, indent=2)

    return output_path

def validate_geojson(filepath):
    """Basic GeoJSON validation."""
    with open(filepath, 'r') as f:
        data = json.load(f)

    if not isinstance(data, dict):
        return False, "Root must be an object"

    if 'type' not in data:
        return False, "Missing 'type' field"

    if data['type'] == 'FeatureCollection' and 'features' not in data:
        return False, "FeatureCollection missing 'features' array"

    return True, "Valid"
PYEOF

# ─────────────────────────────────────────────────────────────
# run_pipeline.py (correct orchestrator)
# ─────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/run_pipeline.py" << 'PYEOF'
"""Main geospatial ETL pipeline."""
import json
import sys
from transforms.coordinate_transform import transform_polygon
from transforms.spatial_operations import create_buffer
from transforms.area_calculator import calculate_area, calculate_perimeter
from transforms.topology_validator import validate_topology
from exporters.geojson_exporter import export_features

def load_parcels(filepath):
    """Load GeoJSON parcel data."""
    with open(filepath, 'r') as f:
        data = json.load(f)
    return data['features']

def process_pipeline(input_file, output_file=None):
    """Run the full ETL pipeline."""
    print("Loading parcel data...")
    features = load_parcels(input_file)
    print(f"Loaded {len(features)} parcels")

    # Validate topology
    print("Validating topology...")
    issues = validate_topology(features)
    if issues:
        print(f"Topology issues found: {len(issues)}")
        for issue in issues:
            print(f"  - {issue}")

    # Process each feature
    processed = []
    for feature in features:
        coords = feature['geometry']['coordinates'][0]

        # Calculate area
        area = calculate_area(coords)
        feature['properties']['calculated_area_sqm'] = area

        # Calculate perimeter
        perimeter = calculate_perimeter(coords)
        feature['properties']['perimeter_m'] = perimeter

        # Create buffer zone
        buffered = create_buffer(coords)
        feature['properties']['buffer_zone_coords'] = len(buffered)

        processed.append(feature)

    # Export
    print("Exporting processed data...")
    output = export_features(processed, output_file)
    print(f"Pipeline complete. Output: {output}")
    return processed

if __name__ == '__main__':
    input_file = 'data/parcels.geojson'
    process_pipeline(input_file)
PYEOF

# ─────────────────────────────────────────────────────────────
# requirements.txt
# ─────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/requirements.txt" << 'EOF'
# Geospatial ETL Pipeline Dependencies
# Note: This pipeline uses pure Python for portability.
# For production use, consider: pyproj, shapely, geopandas, fiona
EOF

# ─────────────────────────────────────────────────────────────
# .vscode/launch.json
# ─────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/.vscode/launch.json" << 'EOF'
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": "Run Pipeline",
            "type": "debugpy",
            "request": "launch",
            "program": "${workspaceFolder}/run_pipeline.py",
            "console": "integratedTerminal",
            "cwd": "${workspaceFolder}"
        }
    ]
}
EOF

# ─────────────────────────────────────────────────────────────
# Record baseline hashes for anti-gaming verification
# ─────────────────────────────────────────────────────────────
echo "Recording baseline file hashes..."
md5sum \
    "$WORKSPACE_DIR/transforms/coordinate_transform.py" \
    "$WORKSPACE_DIR/transforms/spatial_operations.py" \
    "$WORKSPACE_DIR/transforms/area_calculator.py" \
    "$WORKSPACE_DIR/transforms/topology_validator.py" \
    "$WORKSPACE_DIR/exporters/geojson_exporter.py" \
    > /tmp/geospatial_pipeline_initial_hashes.txt

# ─────────────────────────────────────────────────────────────
# Set ownership
# ─────────────────────────────────────────────────────────────
sudo chown -R ga:ga "$WORKSPACE_DIR"

# ─────────────────────────────────────────────────────────────
# Initialize git repository
# ─────────────────────────────────────────────────────────────
cd "$WORKSPACE_DIR"
sudo -u ga git init > /dev/null 2>&1 || true
sudo -u ga git config user.name "GA User" > /dev/null 2>&1 || true
sudo -u ga git config user.email "ga@localhost" > /dev/null 2>&1 || true
sudo -u ga git add . > /dev/null 2>&1 || true
sudo -u ga git commit -m "Initial commit: geospatial ETL pipeline" > /dev/null 2>&1 || true

# ─────────────────────────────────────────────────────────────
# Open VSCode with the workspace
# ─────────────────────────────────────────────────────────────
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code --no-sandbox --disable-workspace-trust '$WORKSPACE_DIR' '$WORKSPACE_DIR/run_pipeline.py'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Fix Geospatial ETL Pipeline Task Setup Complete ==="
echo "Instructions:"
echo "  The geospatial data processing pipeline has multiple bugs causing:"
echo "    - Misaligned map overlays"
echo "    - Incorrect area calculations"
echo "    - GeoJSON export validation failures"
echo "  Review and fix the code in:"
echo "    - transforms/coordinate_transform.py"
echo "    - transforms/spatial_operations.py"
echo "    - transforms/area_calculator.py"
echo "    - transforms/topology_validator.py"
echo "    - exporters/geojson_exporter.py"
echo ""
echo "Workspace: $WORKSPACE_DIR"
