#!/bin/bash
# Setup script for Aggregate Data CSV Import task

echo "=== Setting up Aggregate Data CSV Import Task ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type dhis2_query &>/dev/null; then
    dhis2_query() {
        docker exec dhis2-db psql -U dhis -d dhis2 -t -c "$1" 2>/dev/null
    }
fi

if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

# 1. Wait for DHIS2 Health
echo "Checking DHIS2 health..."
check_dhis2_health || echo "Waiting for DHIS2..."
sleep 5

# 2. Record Task Start Time
date +%s > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# 3. Prepare Import Directory
IMPORT_DIR="/home/ga/Documents/pending_import"
mkdir -p "$IMPORT_DIR"
# Clear previous results if any
rm -f "$IMPORT_DIR/import_result.txt"

# 4. Generate Real CSV Data using Database UIDs
echo "Querying database for valid UIDs..."

# Get 5 facilities from Kailahun district (level 4 usually, or just children of Kailahun)
# We find Kailahun's UID first, then find children
KAILAHUN_UID=$(dhis2_query "SELECT uid FROM organisationunit WHERE name LIKE 'Kailahun%' AND hierarchylevel=3 LIMIT 1" | tr -d ' \n')
echo "District UID: $KAILAHUN_UID"

if [ -z "$KAILAHUN_UID" ]; then
    # Fallback to any org unit if Kailahun not found
    KAILAHUN_UID=$(dhis2_query "SELECT uid FROM organisationunit WHERE hierarchylevel=3 LIMIT 1" | tr -d ' \n')
fi

# Get 5 facility UIDs
FACILITY_UIDS=$(dhis2_query "SELECT uid FROM organisationunit WHERE path LIKE '%${KAILAHUN_UID}%' AND hierarchylevel=4 LIMIT 5")

# Get 3 Aggregate Data Element UIDs (e.g., OPD, Malaria)
# Using 'int' domain type (aggregate)
DE_UIDS=$(dhis2_query "SELECT uid FROM dataelement WHERE domaintype='AGGREGATE' AND valuetype='INTEGER' LIMIT 3")

# Get Default Category Option Combo UID
COC_UID=$(dhis2_query "SELECT uid FROM categoryoptioncombo WHERE name='default' LIMIT 1" | tr -d ' \n')

# Create the CSV file
CSV_FILE="$IMPORT_DIR/kailahun_nov2023_data.csv"
echo "dataElement,period,orgUnit,categoryOptionCombo,attributeOptionCombo,value" > "$CSV_FILE"

# Generate rows: Permutation of Facilities x DataElements
PERIOD="202311"
ROW_COUNT=0

for facility in $FACILITY_UIDS; do
    facility=$(echo "$facility" | tr -d ' ')
    for de in $DE_UIDS; do
        de=$(echo "$de" | tr -d ' ')
        # Random value between 10 and 100
        val=$((10 + RANDOM % 90))
        # attributeOptionCombo is usually same as categoryOptionCombo for default
        echo "$de,$PERIOD,$facility,$COC_UID,$COC_UID,$val" >> "$CSV_FILE"
        ROW_COUNT=$((ROW_COUNT + 1))
    done
done

echo "Generated $ROW_COUNT rows in $CSV_FILE"
chmod 644 "$CSV_FILE"
chown ga:ga "$CSV_FILE"

# Create a README
cat > "$IMPORT_DIR/README.txt" << EOF
Data Import Batch: November 2023
District: Kailahun
Type: Aggregate Data
Format: DHIS2 Standard CSV

Contains backlog data for facilities recovered from paper tally sheets.
Please import using the DHIS2 Import/Export app.
EOF
chown ga:ga "$IMPORT_DIR/README.txt"

# 5. Record Initial DB State
# Count how many data values exist for these specific params (should be 0)
echo "Recording initial data value count..."
# Construct SQL list for data elements and org units
DE_LIST=$(echo $DE_UIDS | sed "s/ /','/g")
FAC_LIST=$(echo $FACILITY_UIDS | sed "s/ /','/g")

INITIAL_DV_COUNT=$(dhis2_query "
    SELECT COUNT(*) FROM datavalue dv
    JOIN dataelement de ON dv.dataelementid = de.dataelementid
    JOIN organisationunit ou ON dv.sourceid = ou.organisationunitid
    JOIN period pe ON dv.periodid = pe.periodid
    WHERE de.uid IN ('$DE_LIST')
    AND ou.uid IN ('$FAC_LIST')
    AND pe.iso = '$PERIOD'
" | tr -d ' ')

echo "$INITIAL_DV_COUNT" > /tmp/initial_dv_count
echo "Initial Data Values in DB (Target Scope): $INITIAL_DV_COUNT"

# 6. Ensure Firefox is open
echo "Launching Firefox..."
DHIS2_URL="http://localhost:8080/dhis-web-commons/security/login.action"
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /tmp/firefox.log 2>&1 &"
    wait_for_window "firefox" 20
fi

# Maximize
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 7. Initial Screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="