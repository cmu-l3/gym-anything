#!/bin/bash
# Export script for IP Punch Restriction task
# Queries the database and saves results to JSON for the host verifier to read

echo "=== Exporting IP Punch Restriction Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# CRITICAL: Ensure Docker containers are running for verification
echo "Ensuring Docker containers are running (required for verification)..."
if ! ensure_docker_containers; then
    echo "WARNING: Failed to verify containers, trying recovery..."
    for attempt in {1..3}; do
        sleep 5
        if ensure_docker_containers; then break; fi
    done
fi

# Final database accessibility check
if ! docker exec timetrex-postgres pg_isready -U timetrex -d timetrex 2>/dev/null; then
    echo "FATAL: Database not accessible. Generating failure result."
    cat > /tmp/ip_restriction_result.json << EOF
{
    "error": "Docker containers not running or database inaccessible",
    "export_timestamp": "$(date -Iseconds)"
}
EOF
    chmod 666 /tmp/ip_restriction_result.json 2>/dev/null || true
    exit 0
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Load start state
INITIAL_COUNT=$(cat /tmp/initial_station_count 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
CURRENT_COUNT=$(timetrex_query "SELECT COUNT(*) FROM station WHERE deleted=0" 2>/dev/null || echo "0")

echo "Station count: initial=$INITIAL_COUNT, current=$CURRENT_COUNT"

# Extract Headquarters Station Data
HQ_FOUND="false"
HQ_EXISTS=$(timetrex_query "SELECT COUNT(*) FROM station WHERE source LIKE '%204.174.1.100%' AND deleted=0" 2>/dev/null || echo "0")

if [ "$HQ_EXISTS" -gt 0 ]; then
    HQ_FOUND="true"
    HQ_STATION_ID=$(docker exec timetrex-postgres psql -U timetrex -d timetrex -t -A -c "SELECT station_id FROM station WHERE source LIKE '%204.174.1.100%' AND deleted=0 ORDER BY created_date DESC LIMIT 1" | tr -d '\n' | tr -d '\r')
    HQ_DESC=$(docker exec timetrex-postgres psql -U timetrex -d timetrex -t -A -c "SELECT description FROM station WHERE source LIKE '%204.174.1.100%' AND deleted=0 ORDER BY created_date DESC LIMIT 1" | tr -d '\n' | tr -d '\r')
    HQ_TYPE=$(docker exec timetrex-postgres psql -U timetrex -d timetrex -t -A -c "SELECT type_id FROM station WHERE source LIKE '%204.174.1.100%' AND deleted=0 ORDER BY created_date DESC LIMIT 1" | tr -d '\n' | tr -d '\r')
    HQ_CREATED=$(docker exec timetrex-postgres psql -U timetrex -d timetrex -t -A -c "SELECT created_date FROM station WHERE source LIKE '%204.174.1.100%' AND deleted=0 ORDER BY created_date DESC LIMIT 1" | tr -d '\n' | tr -d '\r')
fi

# Extract Warehouse Station Data
WH_FOUND="false"
WH_EXISTS=$(timetrex_query "SELECT COUNT(*) FROM station WHERE source LIKE '%204.174.1.105%' AND deleted=0" 2>/dev/null || echo "0")

if [ "$WH_EXISTS" -gt 0 ]; then
    WH_FOUND="true"
    WH_STATION_ID=$(docker exec timetrex-postgres psql -U timetrex -d timetrex -t -A -c "SELECT station_id FROM station WHERE source LIKE '%204.174.1.105%' AND deleted=0 ORDER BY created_date DESC LIMIT 1" | tr -d '\n' | tr -d '\r')
    WH_DESC=$(docker exec timetrex-postgres psql -U timetrex -d timetrex -t -A -c "SELECT description FROM station WHERE source LIKE '%204.174.1.105%' AND deleted=0 ORDER BY created_date DESC LIMIT 1" | tr -d '\n' | tr -d '\r')
    WH_TYPE=$(docker exec timetrex-postgres psql -U timetrex -d timetrex -t -A -c "SELECT type_id FROM station WHERE source LIKE '%204.174.1.105%' AND deleted=0 ORDER BY created_date DESC LIMIT 1" | tr -d '\n' | tr -d '\r')
    WH_CREATED=$(docker exec timetrex-postgres psql -U timetrex -d timetrex -t -A -c "SELECT created_date FROM station WHERE source LIKE '%204.174.1.105%' AND deleted=0 ORDER BY created_date DESC LIMIT 1" | tr -d '\n' | tr -d '\r')
fi

# Escape quotes for JSON (if the agent put quotes in the description)
HQ_DESC_ESC=$(echo "$HQ_DESC" | sed 's/"/\\"/g')
WH_DESC_ESC=$(echo "$WH_DESC" | sed 's/"/\\"/g')
HQ_STATION_ID_ESC=$(echo "$HQ_STATION_ID" | sed 's/"/\\"/g')
WH_STATION_ID_ESC=$(echo "$WH_STATION_ID" | sed 's/"/\\"/g')

# Generate Result JSON safely
TEMP_JSON=$(mktemp /tmp/ip_restriction_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": ${TASK_START:-0},
    "initial_station_count": ${INITIAL_COUNT:-0},
    "current_station_count": ${CURRENT_COUNT:-0},
    "hq_station": {
        "found": $HQ_FOUND,
        "station_id": "$HQ_STATION_ID_ESC",
        "description": "$HQ_DESC_ESC",
        "type_id": "$HQ_TYPE",
        "created_date": ${HQ_CREATED:-0}
    },
    "wh_station": {
        "found": $WH_FOUND,
        "station_id": "$WH_STATION_ID_ESC",
        "description": "$WH_DESC_ESC",
        "type_id": "$WH_TYPE",
        "created_date": ${WH_CREATED:-0}
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move temp file to final destination
rm -f /tmp/ip_restriction_result.json 2>/dev/null || sudo rm -f /tmp/ip_restriction_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/ip_restriction_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/ip_restriction_result.json
chmod 666 /tmp/ip_restriction_result.json 2>/dev/null || sudo chmod 666 /tmp/ip_restriction_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "JSON output saved to /tmp/ip_restriction_result.json"
cat /tmp/ip_restriction_result.json
echo ""
echo "=== Export Complete ==="