#!/bin/bash
echo "=== Exporting WFS-T Insert Feature result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Load timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_feature_count.txt 2>/dev/null || echo "0")

# ============================================================
# Check PostGIS State
# ============================================================
echo "Checking PostGIS database..."
POSTGIS_CHECK=$(docker exec -e PGPASSWORD=geoserver123 gs-postgis psql -U geoserver -h localhost -d gis -t -A -c "
SELECT 
    count(*) as count,
    MAX(adm0name) as adm0,
    MAX(pop_max) as pop,
    MAX(featurecla) as fcla,
    MAX(ST_X(geom)) as lon,
    MAX(ST_Y(geom)) as lat
FROM ne_populated_places 
WHERE name = 'Nova Cartografia';
" 2>/dev/null || echo "0|Error|0|Error|0|0")

# Parse PostGIS result (format: count|adm0|pop|fcla|lon|lat)
FEATURE_COUNT=$(echo "$POSTGIS_CHECK" | cut -d'|' -f1)
ADM0=$(echo "$POSTGIS_CHECK" | cut -d'|' -f2)
POP_MAX=$(echo "$POSTGIS_CHECK" | cut -d'|' -f3)
FEATURE_CLA=$(echo "$POSTGIS_CHECK" | cut -d'|' -f4)
LON=$(echo "$POSTGIS_CHECK" | cut -d'|' -f5)
LAT=$(echo "$POSTGIS_CHECK" | cut -d'|' -f6)

# Get total final count
FINAL_TOTAL_COUNT=$(postgis_query "SELECT count(*) FROM ne_populated_places;" 2>/dev/null | tr -d '[:space:]')

# ============================================================
# Check WFS Availability
# ============================================================
echo "Checking WFS GetFeature..."
WFS_RESPONSE=$(curl -s "${GS_URL}/ne/wfs?service=WFS&version=1.1.0&request=GetFeature&typeName=ne:ne_populated_places&CQL_FILTER=name='Nova%20Cartografia'&outputFormat=application/json" 2>/dev/null)

WFS_RETRIEVABLE="false"
if echo "$WFS_RESPONSE" | grep -q "\"features\":.*\[.*\]" && echo "$WFS_RESPONSE" | grep -q "Nova Cartografia"; then
    WFS_RETRIEVABLE="true"
fi

# ============================================================
# Check File Artifacts
# ============================================================
INSERT_XML_EXISTS="false"
INSERT_XML_VALID="false"
RESPONSE_XML_EXISTS="false"
RESPONSE_SUCCESS="false"

if [ -f "/home/ga/wfst_insert.xml" ]; then
    INSERT_XML_EXISTS="true"
    if grep -qi "Transaction\|Insert\|wfs:Insert" "/home/ga/wfst_insert.xml"; then
        INSERT_XML_VALID="true"
    fi
fi

if [ -f "/home/ga/wfst_response.xml" ]; then
    RESPONSE_XML_EXISTS="true"
    if grep -qi "totalInserted.*1\|SUCCESS\|TransactionResponse" "/home/ga/wfst_response.xml"; then
        RESPONSE_SUCCESS="true"
    fi
fi

# ============================================================
# Create Result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_count": ${INITIAL_COUNT},
    "final_count": ${FINAL_TOTAL_COUNT},
    "feature_found_postgis": ${FEATURE_COUNT},
    "attributes": {
        "adm0name": "$(json_escape "$ADM0")",
        "pop_max": "$(json_escape "$POP_MAX")",
        "featurecla": "$(json_escape "$FEATURE_CLA")"
    },
    "geometry": {
        "lon": "${LON}",
        "lat": "${LAT}"
    },
    "wfs_retrievable": ${WFS_RETRIEVABLE},
    "files": {
        "insert_xml_exists": ${INSERT_XML_EXISTS},
        "insert_xml_valid": ${INSERT_XML_VALID},
        "response_xml_exists": ${RESPONSE_XML_EXISTS},
        "response_success": ${RESPONSE_SUCCESS}
    },
    "task_start_time": ${TASK_START},
    "timestamp": "$(date -Iseconds)",
    "result_nonce": "$(get_result_nonce)"
}
EOF

safe_write_result "$TEMP_JSON" "/tmp/task_result.json"

echo "=== Export complete ==="