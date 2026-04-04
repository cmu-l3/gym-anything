#!/bin/bash
echo "=== Exporting topological_coloring_world_map result ==="

source /workspace/scripts/task_utils.sh

# Capture final visual state
take_screenshot /tmp/task_end.png

# Paths
GEOJSON_PATH="/home/ga/GIS_Data/exports/world_colored.geojson"
PROJECT_PATH="/home/ga/GIS_Data/projects/world_map_colored.qgz"

# Timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# ==============================================================================
# ANALYSIS: Check Output Files and Geometry (Python)
# We run heavy geometric checks here since the environment has geopandas/shapely
# ==============================================================================

# Create a Python analysis script
cat > /tmp/analyze_results.py << 'PYEOF'
import json
import os
import sys
import zipfile
import xml.etree.ElementTree as ET

result = {
    "geojson_exists": False,
    "geojson_valid": False,
    "has_color_id": False,
    "unique_colors": 0,
    "adjacency_violations": 0,
    "total_borders_checked": 0,
    "project_exists": False,
    "project_renderer": "none",
    "project_renderer_attr": "none"
}

geojson_path = "/home/ga/GIS_Data/exports/world_colored.geojson"
project_path = "/home/ga/GIS_Data/projects/world_map_colored.qgz"

# 1. Analyze GeoJSON
if os.path.exists(geojson_path):
    result["geojson_exists"] = True
    try:
        import geopandas as gpd
        gdf = gpd.read_file(geojson_path)
        result["geojson_valid"] = True
        
        # Check field
        if "color_id" in gdf.columns:
            result["has_color_id"] = True
            result["unique_colors"] = int(gdf["color_id"].nunique())
            
            # ADJACENCY CHECK
            # Create spatial weights / adjacency graph
            # Note: 'touches' can be slow on complex geometries, use sindex
            violations = 0
            checked = 0
            
            # Optimize: only check touching polygons
            # Using spatial index to find candidates
            sindex = gdf.sindex
            
            # Iterate through features
            for idx, row in gdf.iterrows():
                geom = row.geometry
                cid = row.color_id
                
                # Candidates
                possible_idx = list(sindex.intersection(geom.bounds))
                possible = gdf.iloc[possible_idx]
                
                # Real neighbors
                neighbors = possible[possible.geometry.touches(geom)]
                
                for n_idx, n_row in neighbors.iterrows():
                    if idx >= n_idx: continue # Check pairs only once
                    
                    checked += 1
                    if n_row.color_id == cid:
                        violations += 1
            
            result["adjacency_violations"] = violations
            result["total_borders_checked"] = checked
            
    except Exception as e:
        result["error_geojson"] = str(e)

# 2. Analyze Project File (QGZ)
if os.path.exists(project_path):
    result["project_exists"] = True
    try:
        with zipfile.ZipFile(project_path, 'r') as z:
            qgs_files = [f for f in z.namelist() if f.endswith('.qgs')]
            if qgs_files:
                with z.open(qgs_files[0]) as f:
                    tree = ET.parse(f)
                    root = tree.getroot()
                    
                    # Find maplayer with color_id renderer
                    for layer in root.findall(".//maplayer"):
                        renderer = layer.find("renderer-v2")
                        if renderer is not None:
                            rtype = renderer.get("type")
                            attr = renderer.get("attr")
                            
                            # We look for the layer that was colored
                            if attr == "color_id":
                                result["project_renderer"] = rtype
                                result["project_renderer_attr"] = attr
                                break
                            
                            # Fallback: capture any categorized renderer
                            if rtype == "categorizedSymbol":
                                result["project_renderer"] = rtype
                                result["project_renderer_attr"] = attr
                                
    except Exception as e:
        result["error_project"] = str(e)

print(json.dumps(result))
PYEOF

# Run analysis
echo "Running result analysis..."
ANALYSIS_JSON=$(python3 /tmp/analyze_results.py 2>/dev/null || echo '{"error": "Analysis script failed"}')

# Check timestamps
FILE_CREATED="false"
if [ -f "$GEOJSON_PATH" ]; then
    MTIME=$(stat -c %Y "$GEOJSON_PATH")
    if [ "$MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED="true"
    fi
fi

# Close QGIS
if is_qgis_running; then
    su - ga -c "DISPLAY=:1 xdotool key ctrl+q" 2>/dev/null || true
    sleep 2
    kill_qgis ga 2>/dev/null || true
fi

# Create Output JSON
cat > /tmp/task_result.json << EOF
{
    "analysis": $ANALYSIS_JSON,
    "file_created_during_task": $FILE_CREATED,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Permission fix
chmod 666 /tmp/task_result.json

echo "Result:"
cat /tmp/task_result.json
echo "=== Export Complete ==="