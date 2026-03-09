#!/bin/bash
# Setup script for Org Unit Redistricting task

echo "=== Setting up Org Unit Redistricting Task ==="

source /workspace/scripts/task_utils.sh

# Inline fallbacks
if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        local endpoint="$1"
        local method="${2:-GET}"
        local data="${3:-}"
        if [ -n "$data" ]; then
             curl -s -u admin:district -X "$method" -H "Content-Type: application/json" -d "$data" "http://localhost:8080/api/$endpoint"
        else
             curl -s -u admin:district -X "$method" "http://localhost:8080/api/$endpoint"
        fi
    }
    take_screenshot() {
        local output_file="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 import -window root "$output_file" 2>/dev/null || \
        DISPLAY=:1 scrot "$output_file" 2>/dev/null || true
    }
fi

# Verify DHIS2 is running
echo "Checking DHIS2 health..."
for i in $(seq 1 6); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/api/system/info" 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "401" ]; then
        echo "DHIS2 is responsive (HTTP $HTTP_CODE)"
        break
    fi
    echo "Waiting 10s..."
    sleep 10
done

# Record task start time
date +%s > /tmp/task_start_timestamp

# ==============================================================================
# CLEANUP & RESET STATE
# We need to ensure Tikonko North does NOT exist and facilities are in original place
# ==============================================================================

echo "Resetting environment state..."

# 1. Find IDs of relevant objects
# Bo District (Parent)
BO_ID=$(dhis2_api "organisationUnits?filter=name:eq:Bo&paging=false&fields=id" | jq -r '.organisationUnits[0].id')
# Original Tikonko Chiefdom (Original Parent)
TIKONKO_ID=$(dhis2_api "organisationUnits?filter=name:eq:Tikonko&filter=level:eq:3&paging=false&fields=id" | jq -r '.organisationUnits[0].id')
# Tikonko North (Target to remove if exists)
TARGET_ID=$(dhis2_api "organisationUnits?filter=name:eq:Tikonko%20North&paging=false&fields=id" | jq -r '.organisationUnits[0].id')
# Facilities
TIKONKO_CHC_ID=$(dhis2_api "organisationUnits?filter=name:eq:Tikonko%20CHC&paging=false&fields=id" | jq -r '.organisationUnits[0].id')
GONDAMA_MCHP_ID=$(dhis2_api "organisationUnits?filter=name:eq:Gondama%20MCHP&paging=false&fields=id" | jq -r '.organisationUnits[0].id')

echo "IDs identified:"
echo "  Bo: $BO_ID"
echo "  Tikonko (Original): $TIKONKO_ID"
echo "  Tikonko North (To Delete): $TARGET_ID"
echo "  Tikonko CHC: $TIKONKO_CHC_ID"
echo "  Gondama MCHP: $GONDAMA_MCHP_ID"

# 2. Move facilities back to original parent (Tikonko) if needed
if [ "$TIKONKO_ID" != "null" ]; then
    if [ "$TIKONKO_CHC_ID" != "null" ]; then
        echo "Resetting Tikonko CHC to parent: Tikonko..."
        dhis2_api "organisationUnits/$TIKONKO_CHC_ID" "PUT" "{\"id\":\"$TIKONKO_CHC_ID\",\"name\":\"Tikonko CHC\",\"shortName\":\"Tikonko CHC\",\"openingDate\":\"2010-01-01\",\"parent\":{\"id\":\"$TIKONKO_ID\"}}" > /dev/null
    fi
    if [ "$GONDAMA_MCHP_ID" != "null" ]; then
        echo "Resetting Gondama MCHP to parent: Tikonko..."
        dhis2_api "organisationUnits/$GONDAMA_MCHP_ID" "PUT" "{\"id\":\"$GONDAMA_MCHP_ID\",\"name\":\"Gondama MCHP\",\"shortName\":\"Gondama MCHP\",\"openingDate\":\"2010-01-01\",\"parent\":{\"id\":\"$TIKONKO_ID\"}}" > /dev/null
    fi
fi

# 3. Delete Tikonko North if it exists
if [ "$TARGET_ID" != "null" ]; then
    echo "Deleting existing Tikonko North ($TARGET_ID)..."
    dhis2_api "organisationUnits/$TARGET_ID" "DELETE"
fi

# ==============================================================================
# BROWSER SETUP
# ==============================================================================

# Ensure Firefox is running
echo "Ensuring Firefox is running..."
DHIS2_URL="http://localhost:8080/dhis-web-commons/security/login.action"

if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
else
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /dev/null 2>&1 &" 2>/dev/null || true
    sleep 4
fi

for i in $(seq 1 10); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|DHIS"; then
        break
    fi
    sleep 2
done

WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla' | awk '{print $1; exit}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

take_screenshot /tmp/task_start_screenshot.png

echo "=== Org Unit Redistricting Task Setup Complete ==="