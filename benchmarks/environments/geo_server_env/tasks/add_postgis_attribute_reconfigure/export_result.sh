#!/bin/bash
echo "=== Exporting add_postgis_attribute_reconfigure result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# ==============================================================================
# 1. PostGIS Verification
# ==============================================================================
echo "Verifying PostGIS state..."

# Check if column exists
COLUMN_EXISTS=$(postgis_query "SELECT EXISTS (SELECT FROM information_schema.columns WHERE table_name = 'ne_countries' AND column_name = 'pop_density');")

# Check population stats (if column exists)
DB_STATS_JSON="{}"
if [ "$COLUMN_EXISTS" = "t" ]; then
    # Get count of non-null, count of > 0, avg value
    STATS=$(postgis_query "SELECT count(*), count(pop_density), avg(pop_density) FROM ne_countries WHERE pop_density IS NOT NULL;")
    ROW_COUNT=$(echo "$STATS" | cut -d'|' -f1)
    NON_NULL_COUNT=$(echo "$STATS" | cut -d'|' -f2)
    AVG_VAL=$(echo "$STATS" | cut -d'|' -f3)
    
    # Check for plausible values (sample a known country, e.g., India or USA)
    # Using a generic check: max value should not be absurd (e.g. > 1,000,000 implies map units wrong)
    MAX_VAL=$(postgis_query "SELECT max(pop_density) FROM ne_countries;")
    
    DB_STATS_JSON="{\"row_count\": $ROW_COUNT, \"non_null_count\": $NON_NULL_COUNT, \"avg_val\": ${AVG_VAL:-0}, \"max_val\": ${MAX_VAL:-0}}"
else
    COLUMN_EXISTS="f"
fi

# ==============================================================================
# 2. GeoServer Configuration Verification (REST API)
# ==============================================================================
echo "Verifying GeoServer feature type..."

# Get the feature type details
FT_JSON=$(gs_rest_get "workspaces/ne/datastores/postgis_ne/featuretypes/ne_countries.json")

# Check if pop_density is in the attributes list
# Note: GeoServer REST representation of attributes varies slightly by version, usually under "attributes": {"attribute": [...]}
GS_ATTRIBUTE_FOUND=$(echo "$FT_JSON" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    attrs = d.get('featureType', {}).get('attributes', {}).get('attribute', [])
    if isinstance(attrs, dict): attrs = [attrs]
    found = any(a.get('name') == 'pop_density' for a in attrs)
    print('true' if found else 'false')
except Exception as e:
    print('false')
")

# ==============================================================================
# 3. WFS Service Verification (Live)
# ==============================================================================
echo "Verifying WFS response..."

# Perform a live WFS GetFeature request
WFS_RESPONSE=$(curl -s "http://localhost:8080/geoserver/ne/wfs?service=WFS&version=2.0.0&request=GetFeature&typeNames=ne:ne_countries&count=1&outputFormat=application/json")

WFS_ATTRIBUTE_FOUND=$(echo "$WFS_RESPONSE" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    feats = d.get('features', [])
    if len(feats) > 0:
        props = feats[0].get('properties', {})
        print('true' if 'pop_density' in props else 'false')
    else:
        print('false')
except:
    print('false')
")

# ==============================================================================
# 4. Output File Verification
# ==============================================================================
OUTPUT_FILE="/home/ga/output/wfs_countries_with_density.json"
FILE_EXISTS="false"
FILE_VALID="false"
FILE_HAS_DENSITY="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    # Validate JSON content
    FILE_CHECK=$(cat "$OUTPUT_FILE" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    valid = True
    has_density = False
    features = d.get('features', [])
    if len(features) >= 3:
        # Check first 3 features
        has_density = all('pop_density' in f.get('properties', {}) for f in features[:3])
    print(f'{valid}|{has_density}')
except:
    print('False|False')
")
    FILE_VALID=$(echo "$FILE_CHECK" | cut -d'|' -f1)
    FILE_HAS_DENSITY=$(echo "$FILE_CHECK" | cut -d'|' -f2)
fi

# ==============================================================================
# 5. Export JSON
# ==============================================================================
GUI_INTERACTION=$(check_gui_interaction)

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "db_column_exists": $([ "$COLUMN_EXISTS" = "t" ] && echo "true" || echo "false"),
    "db_stats": $DB_STATS_JSON,
    "gs_attribute_configured": $GS_ATTRIBUTE_FOUND,
    "wfs_serving_attribute": $WFS_ATTRIBUTE_FOUND,
    "output_file_exists": $FILE_EXISTS,
    "output_file_valid": $FILE_VALID,
    "output_file_has_content": $FILE_HAS_DENSITY,
    "gui_interaction_detected": $GUI_INTERACTION,
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" "/tmp/task_result.json"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="