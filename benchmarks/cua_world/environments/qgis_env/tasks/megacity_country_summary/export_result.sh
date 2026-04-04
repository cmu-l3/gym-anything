#!/bin/bash
echo "=== Exporting megacity_country_summary result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

OUTPUT_FILE="/home/ga/GIS_Data/exports/megacity_stats_by_country.geojson"
COUNTRIES_FILE="/home/ga/GIS_Data/ne_110m_admin_0_countries.geojson"
PLACES_FILE="/home/ga/GIS_Data/ne_110m_populated_places.geojson"

# 1. Basic File Checks
FILE_EXISTS="false"
FILE_SIZE=0
if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || echo "0")
fi

# 2. Advanced Python Analysis (Ground Truth vs Agent Output)
# We calculate the ground truth here to ensure we use the exact data version present
PYTHON_ANALYSIS=$(python3 << 'PYEOF'
import json
import sys
from shapely.geometry import shape, Point
from shapely.prepared import prep

try:
    # ---------------------------------------------------------
    # 1. CALCULATE GROUND TRUTH
    # ---------------------------------------------------------
    with open("/home/ga/GIS_Data/ne_110m_admin_0_countries.geojson", 'r') as f:
        countries_data = json.load(f)
    
    with open("/home/ga/GIS_Data/ne_110m_populated_places.geojson", 'r') as f:
        places_data = json.load(f)

    # Filter megacities (> 5,000,000)
    megacities = []
    for feat in places_data['features']:
        pop = feat['properties'].get('POP_MAX', 0)
        if pop > 5000000:
            megacities.append({
                'geom': Point(feat['geometry']['coordinates']),
                'pop': pop
            })
    
    # Aggregate by country
    # Note: Spatial join can be slow in pure python without spatial index, 
    # but for 110m data (small) it's instantaneous.
    gt_stats = {} # ADMIN name -> {'count': 0, 'sum_pop': 0}
    
    for country in countries_data['features']:
        c_name = country['properties'].get('ADMIN', 'Unknown')
        c_geom = shape(country['geometry'])
        prepared_c_geom = prep(c_geom)
        
        count = 0
        sum_pop = 0
        
        for city in megacities:
            if prepared_c_geom.intersects(city['geom']):
                count += 1
                sum_pop += city['pop']
        
        gt_stats[c_name] = {'count': count, 'sum_pop': sum_pop}

    # ---------------------------------------------------------
    # 2. ANALYZE AGENT OUTPUT
    # ---------------------------------------------------------
    try:
        with open("/home/ga/GIS_Data/exports/megacity_stats_by_country.geojson", 'r') as f:
            agent_data = json.load(f)
    except FileNotFoundError:
        print(json.dumps({"file_exists": False}))
        sys.exit(0)

    agent_features = agent_data.get('features', [])
    feature_count = len(agent_features)
    
    # Check key countries
    check_list = ["China", "United States of America", "Japan", "India", "Brazil"]
    results = {}
    
    # Find agent's field names (they might vary, e.g., 'count', 'NUMPOINTS', 'POP_MAX_sum')
    # We will try to sniff them out by looking at values for a country we know has megacities (e.g., Japan)
    
    # First, map agent features by ADMIN name
    agent_by_name = {}
    for feat in agent_features:
        name = feat['properties'].get('ADMIN')
        if name:
            agent_by_name[name] = feat['properties']

    matches = 0
    total_checks = 0
    
    country_details = []

    for name in check_list:
        if name not in gt_stats: continue # Should not happen with standard data
        
        gt = gt_stats[name]
        agent_props = agent_by_name.get(name, {})
        
        # Heuristic to find the count field: look for integer field matching GT count
        # Heuristic for sum field: look for numeric field matching GT sum (approx)
        
        agent_count = -1
        agent_sum = -1
        
        # Try to find matching values in properties
        found_count = False
        found_sum = False
        
        for k, v in agent_props.items():
            # Check count
            if isinstance(v, (int, float)) and int(v) == gt['count']:
                # Exclude commonly matching small integers like scalerank if possible, 
                # but exact match on specific megacity count is strong signal
                agent_count = int(v)
                found_count = True
            
            # Check sum (allow small diff for floating point)
            if isinstance(v, (int, float)) and abs(v - gt['sum_pop']) < 1000:
                agent_sum = v
                found_sum = True
                
        # If strict match not found, take the closest or look for keywords
        if not found_count:
             # Fallback: look for "count" or "NUMPOINTS"
             for k, v in agent_props.items():
                 if "count" in k.lower() or "num" in k.lower():
                     agent_count = v
                     break
        
        country_res = {
            "name": name,
            "gt_count": gt['count'],
            "gt_sum": gt['sum_pop'],
            "agent_count": agent_count,
            "agent_sum": agent_sum,
            "count_ok": (agent_count == gt['count']),
            "sum_ok": abs((agent_sum or 0) - gt['sum_pop']) < 1000000  # 1M tolerance for population sum
        }
        country_details.append(country_res)

    print(json.dumps({
        "file_exists": True,
        "is_geojson": True,
        "feature_count": feature_count,
        "countries_checked": country_details
    }))

except Exception as e:
    print(json.dumps({"error": str(e), "file_exists": False}))
PYEOF
)

# Close QGIS
if is_qgis_running; then
    su - ga -c "DISPLAY=:1 xdotool key ctrl+q" 2>/dev/null || true
    sleep 2
    kill_qgis ga 2>/dev/null || true
fi

# Create result JSON
cat > /tmp/task_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size_bytes": $FILE_SIZE,
    "analysis": $PYTHON_ANALYSIS,
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result:"
cat /tmp/task_result.json
echo "=== Export Complete ==="