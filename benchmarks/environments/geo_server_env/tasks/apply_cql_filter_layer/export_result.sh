#!/bin/bash
set -e
echo "=== Exporting apply_cql_filter_layer result ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# ============================================================
# 1. Check REST API Configuration
# ============================================================
echo "Checking REST API config..."
FT_JSON=$(gs_rest_get "workspaces/ne/datastores/postgis_ne/featuretypes/ne_countries.json")
CQL_CONFIG=$(echo "$FT_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('featureType', {}).get('cqlFilter', ''))" 2>/dev/null || echo "")

# ============================================================
# 2. Check WFS Output (The Real Test)
# ============================================================
echo "Querying WFS..."
WFS_RESPONSE=$(curl -s "${GS_URL}/ne/ows?service=WFS&version=1.0.0&request=GetFeature&typeName=ne:ne_countries&outputFormat=application/json")

# Analyze WFS response with Python
# We extract: count, valid_continent_ratio, and a sample list of countries
ANALYSIS=$(echo "$WFS_RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    features = data.get('features', [])
    count = len(features)
    
    # Check if features are strictly South America
    # Allow small variations in spelling if data source varies, but usually it's 'South America'
    sa_count = 0
    continents = set()
    countries = []
    
    for f in features:
        props = f.get('properties', {})
        cont = props.get('continent', 'Unknown')
        continents.add(cont)
        countries.append(props.get('name', 'Unknown'))
        if cont == 'South America':
            sa_count += 1
            
    ratio = 1.0
    if count > 0:
        ratio = sa_count / count
        
    print(json.dumps({
        'count': count,
        'sa_ratio': ratio,
        'continents': list(continents),
        'sample_countries': countries[:5],
        'error': None
    }))
except Exception as e:
    print(json.dumps({'count': 0, 'sa_ratio': 0, 'continents': [], 'sample_countries': [], 'error': str(e)}))
")

# ============================================================
# 3. Check State Change
# ============================================================
INITIAL_COUNT=$(cat /tmp/initial_feature_count.txt 2>/dev/null || echo "0")
GUI_INTERACTION=$(check_gui_interaction)

# ============================================================
# 4. Generate Result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_feature_count": $INITIAL_COUNT,
    "cql_config_value": "$(json_escape "$CQL_CONFIG")",
    "wfs_analysis": $ANALYSIS,
    "gui_interaction_detected": $GUI_INTERACTION,
    "screenshot_path": "/tmp/task_final.png",
    "result_nonce": "$(generate_result_nonce)"
}
EOF

safe_write_result "$TEMP_JSON" "/tmp/task_result.json"

echo "Export complete. Result:"
cat /tmp/task_result.json