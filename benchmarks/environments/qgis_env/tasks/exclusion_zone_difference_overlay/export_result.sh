#!/bin/bash
echo "=== Exporting exclusion_zone_difference_overlay result ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type is_qgis_running &>/dev/null; then
    is_qgis_running() { pgrep -f "qgis" > /dev/null; }
fi
if ! type kill_qgis &>/dev/null; then
    kill_qgis() { pkill -u "${1:-ga}" -f qgis 2>/dev/null || true; sleep 1; }
fi

# Take final screenshot
take_screenshot /tmp/task_end.png

EXPORT_DIR="/home/ga/GIS_Data/exports"
EXPECTED_FILE="$EXPORT_DIR/developable_areas.geojson"
INPUT_POLY="/home/ga/GIS_Data/sample_polygon.geojson"
INPUT_POINTS="/home/ga/GIS_Data/sample_points.geojson"

FILE_EXISTS="false"
FILE_SIZE=0
ANALYSIS_JSON='{}'

# Check if expected file exists (or recently modified alternative)
TARGET_FILE=""
if [ -f "$EXPECTED_FILE" ]; then
    TARGET_FILE="$EXPECTED_FILE"
else
    # Look for likely alternatives created recently
    ALT=$(find "$EXPORT_DIR" -name "*.geojson" -mmin -15 ! -name "sample_*" 2>/dev/null | head -1)
    if [ -n "$ALT" ]; then
        TARGET_FILE="$ALT"
    fi
fi

if [ -n "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$TARGET_FILE" 2>/dev/null || echo "0")

    # Run Python analysis using shapely/geopandas (installed in qgis_env)
    # This performs the geometric verification logic
    ANALYSIS_JSON=$(python3 << PYEOF
import json
import sys
import math

try:
    from shapely.geometry import shape, shape, Point
    from shapely.ops import transform
    import pyproj
    # Mocking geopandas logic with raw shapely/fiona if needed, 
    # but environment has geopandas, so let's try pure json/shapely for speed/stability without heavier deps if possible,
    # or rely on basic shapely which is robust.
except ImportError:
    print(json.dumps({"error": "Shapely not installed"}))
    sys.exit(0)

def calculate_area_reduction():
    try:
        # Load Input Polygons
        with open("$INPUT_POLY") as f:
            in_poly_data = json.load(f)
        
        # Load Input Points
        with open("$INPUT_POINTS") as f:
            in_point_data = json.load(f)

        # Load Output
        with open("$TARGET_FILE") as f:
            out_data = json.load(f)

        if out_data.get("type") != "FeatureCollection":
            return {"valid_geojson": False, "error": "Not a FeatureCollection"}

        # Setup Reprojection to UTM 10N (EPSG:32610) for area calcs
        # Source is WGS84 (EPSG:4326)
        wgs84 = pyproj.CRS('EPSG:4326')
        utm10n = pyproj.CRS('EPSG:32610')
        project = pyproj.Transformer.from_crs(wgs84, utm10n, always_xy=True).transform

        # 1. Calculate Input Area (Reprojected)
        input_area = 0.0
        for feat in in_poly_data['features']:
            geom = shape(feat['geometry'])
            geom_utm = transform(project, geom)
            input_area += geom_utm.area
        
        # 2. Calculate Output Area (Reprojected if needed)
        # Note: Output might already be in UTM or WGS84 depending on export settings.
        # We try to detect or just blindly reproject if coordinates look like degrees.
        output_area = 0.0
        output_feature_count = len(out_data['features'])
        has_polygons = True
        attributes_retained = False
        
        first_feat = out_data['features'][0] if output_feature_count > 0 else None
        
        # Check attributes (looking for 'name' or 'id' from input)
        if first_feat:
            props = first_feat.get('properties', {})
            if 'name' in props and ('Area A' in str(props.values()) or 'Area B' in str(props.values()) or props['name'] in ['Area A', 'Area B']):
                attributes_retained = True
            
            # Check geometry type
            if first_feat['geometry']['type'] not in ['Polygon', 'MultiPolygon']:
                has_polygons = False

            # Check Coordinate System roughly
            # If x coordinate is < 180, it's likely degrees. If > 100000, likely meters.
            coords = first_feat['geometry']['coordinates'][0][0]
            while isinstance(coords[0], list): # Handle MultiPolygon nesting
                coords = coords[0]
            
            is_degrees = abs(coords[0]) <= 180
            
            for feat in out_data['features']:
                geom = shape(feat['geometry'])
                if is_degrees:
                    geom_utm = transform(project, geom)
                    output_area += geom_utm.area
                else:
                    output_area += geom.area # Assume it's already UTM/Metric

        # 3. Validation Logic
        # Expected reduction: 3 points * pi * (1000m)^2 ~= 3 * 3.14 * 1,000,000 ~= 9.4 sq km
        # Note: Point A and B overlap with Area A. Point C is near Area B.
        # Depending on exact placement, the reduction might be less if buffer extends outside polygon.
        # Area A is ~10.5 sq km. Area B is ~8.2 sq km.
        # 1km radius circle is ~3.14 sq km.
        
        area_diff = input_area - output_area
        
        # Check exclusion constraint
        # Reconstruct buffers and check intersection with output
        constraint_violated = False
        
        for pt_feat in in_point_data['features']:
            pt_geom = shape(pt_feat['geometry'])
            pt_utm = transform(project, pt_geom)
            # Create 1km buffer (slightly smaller to allow for curve approximation error)
            # We use 990m to be conservative about "violations"
            buffer_utm = pt_utm.buffer(990) 
            
            for out_feat in out_data['features']:
                out_geom = shape(out_feat['geometry'])
                if is_degrees:
                    out_geom_utm = transform(project, out_geom)
                else:
                    out_geom_utm = out_geom
                
                if buffer_utm.intersects(out_geom_utm):
                    constraint_violated = True
                    break
            if constraint_violated:
                break

        return {
            "valid_geojson": True,
            "feature_count": output_feature_count,
            "has_polygons": has_polygons,
            "input_area_sqkm": input_area / 1e6,
            "output_area_sqkm": output_area / 1e6,
            "area_removed_sqkm": area_diff / 1e6,
            "attributes_retained": attributes_retained,
            "constraint_respected": not constraint_violated
        }

    except Exception as e:
        return {"error": str(e), "valid_geojson": False}

print(json.dumps(calculate_area_reduction()))
PYEOF
    )
else
    ANALYSIS_JSON='{"valid_geojson": false, "file_exists": false}'
fi

# Close QGIS cleanly
if is_qgis_running; then
    su - ga -c "DISPLAY=:1 xdotool key ctrl+q" 2>/dev/null || true
    sleep 2
    kill_qgis ga 2>/dev/null || true
fi

# Create result JSON
cat > /tmp/task_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_path": "$TARGET_FILE",
    "file_size_bytes": $FILE_SIZE,
    "analysis": $ANALYSIS_JSON,
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result:"
cat /tmp/task_result.json
echo "=== Export Complete ==="