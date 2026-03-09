#!/bin/bash
# Export script for Population Projection Update task

echo "=== Exporting Population Projection Result ==="

source /workspace/scripts/task_utils.sh

# Helper for SQL
dhis2_sql() {
    docker exec dhis2-db psql -U dhis -d dhis2 -t -c "$1" 2>/dev/null | sed 's/^[ \t]*//;s/[ \t]*$//'
}

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

echo "Collecting verification data..."

# 1. Get IDs again to ensure we query correct elements
ORG_UNIT_ID=$(dhis2_sql "SELECT organisationunitid FROM organisationunit WHERE name='Bo'")
POP_DE_ID=$(dhis2_sql "SELECT dataelementid FROM dataelement WHERE name='Population'")
POP_U1_DE_ID=$(dhis2_sql "SELECT dataelementid FROM dataelement WHERE name='Population under 1 year'")
PERIOD_2022_ID=$(dhis2_sql "SELECT periodid FROM period WHERE iso='2022'")
PERIOD_2024_ID=$(dhis2_sql "SELECT periodid FROM period WHERE iso='2024'")
DATASET_ID=$(dhis2_sql "SELECT datasetid FROM dataset WHERE name='Population'")

# 2. Fetch Baseline Values (2022)
BASE_POP=$(dhis2_sql "SELECT value FROM datavalue WHERE sourceid=$ORG_UNIT_ID AND periodid=$PERIOD_2022_ID AND dataelementid=$POP_DE_ID")
BASE_POP_U1=$(dhis2_sql "SELECT value FROM datavalue WHERE sourceid=$ORG_UNIT_ID AND periodid=$PERIOD_2022_ID AND dataelementid=$POP_U1_DE_ID")

echo "Baseline 2022: Pop=$BASE_POP, Pop<1=$BASE_POP_U1"

# 3. Fetch Agent's Entered Values (2024)
ENTERED_POP=$(dhis2_sql "SELECT value FROM datavalue WHERE sourceid=$ORG_UNIT_ID AND periodid=$PERIOD_2024_ID AND dataelementid=$POP_DE_ID")
ENTERED_POP_U1=$(dhis2_sql "SELECT value FROM datavalue WHERE sourceid=$ORG_UNIT_ID AND periodid=$PERIOD_2024_ID AND dataelementid=$POP_U1_DE_ID")

echo "Entered 2024: Pop=$ENTERED_POP, Pop<1=$ENTERED_POP_U1"

# 4. Check Dataset Completeness
IS_COMPLETE="false"
COMPLETE_CHECK=$(dhis2_sql "SELECT COUNT(*) FROM completedatasetregistration WHERE sourceid=$ORG_UNIT_ID AND periodid=$PERIOD_2024_ID AND datasetid=$DATASET_ID")
if [ "$COMPLETE_CHECK" -gt "0" ]; then
    IS_COMPLETE="true"
fi

echo "Dataset Complete: $IS_COMPLETE"

# 5. Get Metadata for robustness
POP_NAME=$(dhis2_sql "SELECT name FROM dataelement WHERE dataelementid=$POP_DE_ID")
POP_U1_NAME=$(dhis2_sql "SELECT name FROM dataelement WHERE dataelementid=$POP_U1_DE_ID")

# Generate JSON Result
cat > /tmp/population_projection_result.json << EOF
{
    "baseline_2022": {
        "population": "${BASE_POP:-0}",
        "population_under_1": "${BASE_POP_U1:-0}"
    },
    "entered_2024": {
        "population": "${ENTERED_POP:-0}",
        "population_under_1": "${ENTERED_POP_U1:-0}"
    },
    "metadata": {
        "population_element_name": "$POP_NAME",
        "population_u1_element_name": "$POP_U1_NAME",
        "org_unit": "Bo"
    },
    "is_dataset_complete": $IS_COMPLETE,
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/population_projection_result.json 2>/dev/null || true
echo "Result exported to /tmp/population_projection_result.json"
cat /tmp/population_projection_result.json

echo "=== Export Complete ==="