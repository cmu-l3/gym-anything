#!/bin/bash
# Setup script for Metadata Dependency Cleanup task
# Creates a specific Data Element, Dataset, and Group, and links them together.

echo "=== Setting up Metadata Dependency Cleanup Task ==="

source /workspace/scripts/task_utils.sh

# Inline API helper if needed
if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        local endpoint="$1"
        local method="${2:-GET}"
        local data="${3:-}"
        if [ -n "$data" ]; then
            curl -s -u admin:district -X "$method" -H "Content-Type: application/json" -d "$data" "http://localhost:8080/api/$endpoint"
        else
            curl -s -u admin:district -X "$method" -H "Content-Type: application/json" "http://localhost:8080/api/$endpoint"
        fi
    }
fi

# Wait for DHIS2
echo "Checking DHIS2 health..."
for i in $(seq 1 12); do
    if curl -s -u admin:district "http://localhost:8080/api/system/info" | grep -q "version"; then
        echo "DHIS2 is ready."
        break
    fi
    echo "Waiting for DHIS2..."
    sleep 5
done

# 1. Create Data Element
echo "Creating Data Element..."
DE_PAYLOAD='{
  "name": "Cholera Suspected (Duplicate)",
  "shortName": "Cholera Susp (Dup)",
  "aggregationType": "SUM",
  "domainType": "AGGREGATE",
  "valueType": "INTEGER_ZERO_OR_POSITIVE",
  "zeroIsSignificant": false
}'

DE_RESP=$(dhis2_api "dataElements" "POST" "$DE_PAYLOAD")
DE_ID=$(echo "$DE_RESP" | jq -r '.response.uid')

if [ -z "$DE_ID" ] || [ "$DE_ID" == "null" ]; then
    echo "Failed to create Data Element"
    echo "$DE_RESP"
    exit 1
fi
echo "Created Data Element: $DE_ID"

# 2. Create Dataset
echo "Creating Dataset..."
DS_PAYLOAD='{
  "name": "IDSR Supplemental Reporting",
  "shortName": "IDSR Supp",
  "periodType": "Monthly",
  "openFuturePeriods": 0,
  "expiryDays": 0
}'

DS_RESP=$(dhis2_api "dataSets" "POST" "$DS_PAYLOAD")
DS_ID=$(echo "$DS_RESP" | jq -r '.response.uid')

if [ -z "$DS_ID" ] || [ "$DS_ID" == "null" ]; then
    echo "Failed to create Dataset"
    echo "$DS_RESP"
    exit 1
fi
echo "Created Dataset: $DS_ID"

# 3. Create Data Element Group
echo "Creating Data Element Group..."
GRP_PAYLOAD='{
  "name": "Disease Surveillance"
}'

GRP_RESP=$(dhis2_api "dataElementGroups" "POST" "$GRP_PAYLOAD")
GRP_ID=$(echo "$GRP_RESP" | jq -r '.response.uid')

if [ -z "$GRP_ID" ] || [ "$GRP_ID" == "null" ]; then
    echo "Failed to create Group"
    echo "$GRP_RESP"
    exit 1
fi
echo "Created Group: $GRP_ID"

# 4. Link Data Element to Dataset
echo "Linking DE to Dataset..."
# We need to GET the dataset, add the DE, and PUT it back, or use the specific association endpoint
# Easy way: Update the dataset with the data element
LINK_DS_RESP=$(dhis2_api "dataSets/$DS_ID/dataElements/$DE_ID" "POST")
echo "Link DS response: $(echo "$LINK_DS_RESP" | jq -r '.httpStatus')"

# 5. Link Data Element to Group
echo "Linking DE to Group..."
LINK_GRP_RESP=$(dhis2_api "dataElementGroups/$GRP_ID/members/$DE_ID" "POST")
echo "Link Group response: $(echo "$LINK_GRP_RESP" | jq -r '.httpStatus')"

# Verify Setup
VERIFY_DE=$(dhis2_api "dataElements/$DE_ID")
if echo "$VERIFY_DE" | grep -q "$DE_ID"; then
    echo "Verification: Data Element exists."
else
    echo "ERROR: Data Element not found after creation."
fi

# Save IDs for export script to check later
cat > /tmp/task_metadata_ids.json <<EOF
{
  "de_id": "$DE_ID",
  "ds_id": "$DS_ID",
  "grp_id": "$GRP_ID",
  "setup_timestamp": $(date +%s)
}
EOF

chmod 644 /tmp/task_metadata_ids.json

# Launch Firefox to Maintenance App
echo "Launching Firefox..."
DHIS2_MAINTENANCE_URL="http://localhost:8080/dhis-web-maintenance/index.html#/list/dataElement"

if pgrep -f firefox > /dev/null; then
    pkill -f firefox
    sleep 2
fi

su - ga -c "DISPLAY=:1 firefox '$DHIS2_MAINTENANCE_URL' > /dev/null 2>&1 &"

# Wait for window and maximize
wait_for_window "firefox" 30
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="