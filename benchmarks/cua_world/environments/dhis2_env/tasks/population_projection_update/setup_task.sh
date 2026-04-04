#!/bin/bash
# Setup script for Population Projection Update task

echo "=== Setting up Population Projection Update Task ==="

source /workspace/scripts/task_utils.sh

# Define helper for SQL since we need to clear data directly in DB
dhis2_sql() {
    docker exec dhis2-db psql -U dhis -d dhis2 -t -c "$1" 2>/dev/null | sed 's/^[ \t]*//;s/[ \t]*$//'
}

# Verify DHIS2 is running
echo "Checking DHIS2 health..."
if ! check_dhis2_health; then
    echo "Waiting for DHIS2..."
    sleep 20
    check_dhis2_health || echo "Warning: DHIS2 slow to respond"
fi

# 1. Identify IDs for clean-up
echo "Identifying UIDs..."
ORG_UNIT_ID=$(dhis2_sql "SELECT organisationunitid FROM organisationunit WHERE name='Bo'")
POP_DE_ID=$(dhis2_sql "SELECT dataelementid FROM dataelement WHERE name='Population'")
POP_U1_DE_ID=$(dhis2_sql "SELECT dataelementid FROM dataelement WHERE name='Population under 1 year'")
PERIOD_2024_ID=$(dhis2_sql "SELECT periodid FROM period WHERE iso='2024'")

# 2. Clear any existing data for 2024 for Bo (Clean Slate)
echo "Clearing existing 2024 data for Bo District..."
if [ -n "$ORG_UNIT_ID" ] && [ -n "$PERIOD_2024_ID" ]; then
    # Delete values for Population
    if [ -n "$POP_DE_ID" ]; then
        dhis2_sql "DELETE FROM datavalue WHERE sourceid=$ORG_UNIT_ID AND periodid=$PERIOD_2024_ID AND dataelementid=$POP_DE_ID"
    fi
    # Delete values for Population < 1
    if [ -n "$POP_U1_DE_ID" ]; then
        dhis2_sql "DELETE FROM datavalue WHERE sourceid=$ORG_UNIT_ID AND periodid=$PERIOD_2024_ID AND dataelementid=$POP_U1_DE_ID"
    fi
    
    # Remove completion record
    DATASET_ID=$(dhis2_sql "SELECT datasetid FROM dataset WHERE name='Population'")
    if [ -n "$DATASET_ID" ]; then
        dhis2_sql "DELETE FROM completedatasetregistration WHERE sourceid=$ORG_UNIT_ID AND periodid=$PERIOD_2024_ID AND datasetid=$DATASET_ID"
    fi
else
    echo "WARNING: Could not identify IDs for cleanup. DB might be empty."
fi

# 3. Ensure 2022 Data Exists (Baseline)
echo "Verifying 2022 baseline data..."
PERIOD_2022_ID=$(dhis2_sql "SELECT periodid FROM period WHERE iso='2022'")

if [ -n "$ORG_UNIT_ID" ] && [ -n "$PERIOD_2022_ID" ]; then
    # Check Population
    VAL_POP=$(dhis2_sql "SELECT value FROM datavalue WHERE sourceid=$ORG_UNIT_ID AND periodid=$PERIOD_2022_ID AND dataelementid=$POP_DE_ID")
    if [ -z "$VAL_POP" ]; then
        echo "Injecting baseline Population for 2022..."
        # Insert a realistic value if missing (e.g., ~180,000)
        CAT_OPT_COMBO=$(dhis2_sql "SELECT categoryoptioncomboid FROM categoryoptioncombo LIMIT 1")
        dhis2_sql "INSERT INTO datavalue (dataelementid, periodid, sourceid, categoryoptioncomboid, attributeoptioncomboid, value, storedby, created, lastupdated) VALUES ($POP_DE_ID, $PERIOD_2022_ID, $ORG_UNIT_ID, $CAT_OPT_COMBO, $CAT_OPT_COMBO, '185400', 'admin', now(), now())"
    fi

    # Check Population < 1
    VAL_POP_U1=$(dhis2_sql "SELECT value FROM datavalue WHERE sourceid=$ORG_UNIT_ID AND periodid=$PERIOD_2022_ID AND dataelementid=$POP_U1_DE_ID")
    if [ -z "$VAL_POP_U1" ]; then
        echo "Injecting baseline Population <1 for 2022..."
        # Insert a realistic value (~4% of pop)
        CAT_OPT_COMBO=$(dhis2_sql "SELECT categoryoptioncomboid FROM categoryoptioncombo LIMIT 1")
        dhis2_sql "INSERT INTO datavalue (dataelementid, periodid, sourceid, categoryoptioncomboid, attributeoptioncomboid, value, storedby, created, lastupdated) VALUES ($POP_U1_DE_ID, $PERIOD_2022_ID, $ORG_UNIT_ID, $CAT_OPT_COMBO, $CAT_OPT_COMBO, '7416', 'admin', now(), now())"
    fi
fi

# 4. Prepare Firefox
echo "Starting Firefox..."
DHIS2_URL="http://localhost:8080"
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /dev/null 2>&1 &"
    sleep 5
fi

# Wait for window
wait_for_window "firefox\|mozilla\|DHIS" 30

# Focus and maximize
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Record start time
date +%s > /tmp/task_start_timestamp

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="