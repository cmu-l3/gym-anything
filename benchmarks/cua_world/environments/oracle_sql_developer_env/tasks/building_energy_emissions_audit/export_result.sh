#!/bin/bash
# Export results for Municipal Building Energy Emissions Audit task
echo "=== Exporting Building Energy Emissions Audit results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Initialize flags
PIVOT_VW_EXISTS="false"
PIVOT_USED="false"
EMISSIONS_VW_EXISTS="false"
PROC_EXISTS="false"
NOTICES_GENERATED=0
CSV_EXISTS="false"
CSV_SIZE=0

# --- Check Views ---
VW_CHECK1=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'ENV_AUDITOR' AND view_name = 'ANNUAL_ENERGY_PIVOT_VW';" "system" | tr -d '[:space:]')
if [ "${VW_CHECK1:-0}" -gt 0 ] 2>/dev/null; then
    PIVOT_VW_EXISTS="true"
    # Check for PIVOT keyword in source
    SRC_TEXT=$(oracle_query_raw "SELECT text FROM all_views WHERE owner = 'ENV_AUDITOR' AND view_name = 'ANNUAL_ENERGY_PIVOT_VW';" "system" 2>/dev/null)
    if echo "$SRC_TEXT" | grep -qiE "\bPIVOT\b" 2>/dev/null; then
        PIVOT_USED="true"
    fi
fi

VW_CHECK2=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'ENV_AUDITOR' AND view_name = 'BUILDING_EMISSIONS_VW';" "system" | tr -d '[:space:]')
if [ "${VW_CHECK2:-0}" -gt 0 ] 2>/dev/null; then
    EMISSIONS_VW_EXISTS="true"
fi

# --- Check Procedure & Notices Table ---
PROC_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_procedures WHERE owner = 'ENV_AUDITOR' AND object_name = 'PROC_GENERATE_NOTICES';" "system" | tr -d '[:space:]')
if [ "${PROC_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    PROC_EXISTS="true"
fi

NOTICES_GENERATED=$(oracle_query_raw "SELECT COUNT(*) FROM env_auditor.emission_notices;" "system" | tr -d '[:space:]')
NOTICES_GENERATED=${NOTICES_GENERATED:-0}

# --- Check CSV export ---
CSV_PATH="/home/ga/Documents/top_50_penalties.csv"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c%s "$CSV_PATH" 2>/dev/null || echo "0")
fi

# ==============================================================================
# PRIMARY ANTI-GAMING VERIFICATION: DYNAMIC DATA INJECTION
# We inject a highly specific mock building with specific meter readings.
# Then we query the agent's BUILDING_EMISSIONS_VW to see if it correctly
# applies the complex math to THIS specific mock data dynamically.
#
# Expected Math:
# Sqft: 100,000.  Property: Office (limit: 0.00846). Limit = 846 tons.
# Elec: 500,000 * 0.00028896 = 144.48 tons
# Gas:  150,000 * 0.0053     = 795.00 tons
# Steam: 1,500  * 0.0449     = 67.35 tons
# Total GHG = 1006.83 tons.
# Is Compliant: N.
# Penalty: (1006.83 - 846.00) * 268 = 160.83 * 268 = 43102.44
# ==============================================================================

MOCK_GHG=""
MOCK_LIMIT=""
MOCK_COMPLIANT=""
MOCK_PENALTY=""
MOCK_EVAL_SUCCESS="false"
MOCK_ERROR=""

if [ "$EMISSIONS_VW_EXISTS" = "true" ]; then
    echo "Running dynamic math verification against agent's view..."
    
    # Insert mock data
    sudo docker exec -i oracle-xe sqlplus -s env_auditor/EnvAudit2024@//localhost:1521/XEPDB1 << 'EOSQL'
    SET ECHO OFF FEEDBACK OFF
    INSERT INTO buildings VALUES (999999999, '9999', 'Mock Auditor LLC', 'Office', 100000);
    INSERT INTO meter_readings VALUES (reading_seq.NEXTVAL, 999999999, 'Electricity', 500000, SYSDATE);
    INSERT INTO meter_readings VALUES (reading_seq.NEXTVAL, 999999999, 'Natural Gas', 150000, SYSDATE);
    INSERT INTO meter_readings VALUES (reading_seq.NEXTVAL, 999999999, 'District Steam', 1500, SYSDATE);
    COMMIT;
    EXIT;
EOSQL

    # Query the agent's view for the mock building
    # Use a delimiter (pipe) for safe parsing
    MOCK_RESULT=$(oracle_query_raw "SELECT ROUND(total_ghg_emissions, 2) || '|' || ROUND(emissions_limit, 2) || '|' || is_compliant || '|' || ROUND(penalty_amount, 2) FROM env_auditor.building_emissions_vw WHERE bbl_id = 999999999;" "system" 2>&1)
    
    if echo "$MOCK_RESULT" | grep -q "ORA-"; then
        MOCK_ERROR=$(echo "$MOCK_RESULT" | grep "ORA-" | head -1 | tr -d '\n' | sed 's/"/\\"/g')
    else
        # Parse the pipe-delimited output
        MOCK_GHG=$(echo "$MOCK_RESULT" | cut -d'|' -f1 | tr -d '[:space:]')
        MOCK_LIMIT=$(echo "$MOCK_RESULT" | cut -d'|' -f2 | tr -d '[:space:]')
        MOCK_COMPLIANT=$(echo "$MOCK_RESULT" | cut -d'|' -f3 | tr -d '[:space:]')
        MOCK_PENALTY=$(echo "$MOCK_RESULT" | cut -d'|' -f4 | tr -d '[:space:]')
        MOCK_EVAL_SUCCESS="true"
    fi
fi

# Collect GUI Evidence
GUI_EVIDENCE=$(collect_gui_evidence)

# Export JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "pivot_vw_exists": $PIVOT_VW_EXISTS,
    "pivot_used": $PIVOT_USED,
    "emissions_vw_exists": $EMISSIONS_VW_EXISTS,
    "proc_exists": $PROC_EXISTS,
    "notices_generated": $NOTICES_GENERATED,
    "csv_exists": $CSV_EXISTS,
    "csv_size_bytes": $CSV_SIZE,
    "mock_eval_success": $MOCK_EVAL_SUCCESS,
    "mock_eval_error": "$MOCK_ERROR",
    "mock_results": {
        "ghg": "$MOCK_GHG",
        "limit": "$MOCK_LIMIT",
        "compliant": "$MOCK_COMPLIANT",
        "penalty": "$MOCK_PENALTY"
    },
    $GUI_EVIDENCE
}
EOF

# Move securely
rm -f /tmp/building_emissions_result.json 2>/dev/null || sudo rm -f /tmp/building_emissions_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/building_emissions_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/building_emissions_result.json
chmod 666 /tmp/building_emissions_result.json 2>/dev/null || sudo chmod 666 /tmp/building_emissions_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved."
cat /tmp/building_emissions_result.json
echo "=== Export Complete ==="