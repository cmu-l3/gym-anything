#!/bin/bash
set -e
echo "=== Setting up Metadata Package Import Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Fallback definitions if utils not available
if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        curl -s -u admin:district "http://localhost:8080/api/$1"
    }
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

# Wait for DHIS2 to be ready
echo "Checking DHIS2 health..."
for i in $(seq 1 12); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/api/system/info" 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "401" ]; then
        echo "DHIS2 is responsive (HTTP $HTTP_CODE)"
        break
    fi
    echo "DHIS2 not ready (HTTP $HTTP_CODE), waiting 5s..."
    sleep 5
done

# Record task start time
date +%s > /tmp/task_start_time.txt
date -Iseconds > /tmp/task_start_iso.txt

# --- PREPARE METADATA FILE ---
# We need a valid CategoryOptionCombo ID for the data elements to be valid.
# Try to fetch 'default' from API, fallback to Sierra Leone demo ID.

echo "Fetching default CategoryCombo ID..."
DEFAULT_CAT_COMBO=$(dhis2_api "categoryCombos?filter=name:eq:default&fields=id" | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print(d['categoryCombos'][0]['id'] if d.get('categoryCombos') else 'p0KHi8d4ti2')" 2>/dev/null)

if [ -z "$DEFAULT_CAT_COMBO" ] || [ "$DEFAULT_CAT_COMBO" == "null" ]; then
    DEFAULT_CAT_COMBO="p0KHi8d4ti2" # Fallback for Sierra Leone demo
fi
echo "Using CategoryCombo ID: $DEFAULT_CAT_COMBO"

METADATA_FILE="/home/ga/Documents/community_health_metadata.json"
mkdir -p /home/ga/Documents

# Defined UIDs for the task (Agent must import these specific IDs)
# Anti-gaming: If agent creates DEs manually, they will get random UIDs and fail verification.
UID_1="CommHlth001"
UID_2="CommHlth002"
UID_3="CommHlth003"

cat > "$METADATA_FILE" <<EOF
{
  "date": "$(date -I)",
  "dataElements": [
    {
      "code": "COMM_VISIT",
      "name": "Comm Health Visit",
      "shortName": "CH Visit",
      "id": "$UID_1",
      "domainType": "AGGREGATE",
      "valueType": "INTEGER_ZERO_OR_POSITIVE",
      "aggregationType": "SUM",
      "categoryCombo": {
        "id": "$DEFAULT_CAT_COMBO"
      },
      "zeroIsSignificant": false
    },
    {
      "code": "COMM_REFERRAL",
      "name": "Comm Health Referral",
      "shortName": "CH Referral",
      "id": "$UID_2",
      "domainType": "AGGREGATE",
      "valueType": "INTEGER_ZERO_OR_POSITIVE",
      "aggregationType": "SUM",
      "categoryCombo": {
        "id": "$DEFAULT_CAT_COMBO"
      },
      "zeroIsSignificant": false
    },
    {
      "code": "COMM_EDU",
      "name": "Comm Health Education Session",
      "shortName": "CH Edu",
      "id": "$UID_3",
      "domainType": "AGGREGATE",
      "valueType": "INTEGER_ZERO_OR_POSITIVE",
      "aggregationType": "SUM",
      "categoryCombo": {
        "id": "$DEFAULT_CAT_COMBO"
      },
      "zeroIsSignificant": false
    }
  ]
}
EOF

chown -R ga:ga /home/ga/Documents
chmod 644 "$METADATA_FILE"
echo "Metadata file created at: $METADATA_FILE"

# --- LAUNCH APPLICATION ---
DHIS2_IMPORT_URL="http://localhost:8080/dhis-web-import-export/index.action"

echo "Starting Firefox..."
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_IMPORT_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
else
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_IMPORT_URL' > /dev/null 2>&1 &" 2>/dev/null || true
    sleep 4
fi

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla"; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
done

# Maximize and focus
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla" | awk '{print $1; exit}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Clean up any previous run artifacts
rm -f /tmp/metadata_import_result.json 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="