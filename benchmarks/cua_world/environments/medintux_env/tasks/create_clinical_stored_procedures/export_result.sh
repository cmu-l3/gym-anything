#!/bin/bash
echo "=== Exporting create_clinical_stored_procedures result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
DEMO_FILE="/home/ga/medintux_stored_procedures_demo.txt"

# Take final screenshot
take_screenshot /tmp/task_final.png

# ==============================================================================
# 1. CHECK DEMO FILE
# ==============================================================================
DEMO_EXISTS="false"
DEMO_CONTENT=""
DEMO_SIZE=0
FILE_CREATED_DURING_TASK="false"

if [ -f "$DEMO_FILE" ]; then
    DEMO_EXISTS="true"
    DEMO_SIZE=$(stat -c %s "$DEMO_FILE")
    DEMO_MTIME=$(stat -c %Y "$DEMO_FILE")
    
    if [ "$DEMO_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Read first 2KB of content for verification (safe size)
    DEMO_CONTENT=$(head -c 2048 "$DEMO_FILE" | base64 -w 0)
fi

# ==============================================================================
# 2. INTROSPECT DATABASE ROUTINES
# ==============================================================================
# Helper to execute SQL and output JSON string
sql_json() {
    local query="$1"
    mysql -u root DrTuxTest -N -B -e "$query" 2>/dev/null
}

echo "Introspecting routines..."

# Check existence
ROUTINES_EXIST=$(sql_json "SELECT JSON_ARRAYAGG(JSON_OBJECT('name', ROUTINE_NAME, 'type', ROUTINE_TYPE)) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA='DrTuxTest'")

# ==============================================================================
# 3. EXECUTE ROUTINES FOR VERIFICATION
# ==============================================================================
# We execute the agent's routines to verify they work and produce correct output.
# If execution fails, we record the error.

# --- Test 1: fn_patient_age ---
# Use the known test patient created in setup (Born 2000-01-01)
TEST_GUID="TEST-PATIENT-GUID-001"
AGE_RESULT=$(mysql -u root DrTuxTest -N -e "SELECT fn_patient_age('$TEST_GUID')" 2>/dev/null || echo "ERROR")
# Calculate expected age in SQL for comparison
EXPECTED_AGE=$(mysql -u root DrTuxTest -N -e "SELECT TIMESTAMPDIFF(YEAR, '2000-01-01', CURDATE())" 2>/dev/null)

# --- Test 2: sp_search_patients ---
# Search for 'TESTER'
SEARCH_RESULT=$(mysql -u root DrTuxTest -e "CALL sp_search_patients('TESTER')" 2>/dev/null | head -n 5 | base64 -w 0 || echo "ERROR")

# --- Test 3: sp_age_pyramid ---
PYRAMID_RESULT=$(mysql -u root DrTuxTest -e "CALL sp_age_pyramid()" 2>/dev/null | head -n 20 | base64 -w 0 || echo "ERROR")

# --- Test 4: sp_practice_summary ---
SUMMARY_RESULT=$(mysql -u root DrTuxTest -e "CALL sp_practice_summary()" 2>/dev/null | base64 -w 0 || echo "ERROR")

# Get Ground Truth for Summary (Direct Query)
GT_SUMMARY=$(mysql -u root DrTuxTest -N -e "
SELECT CONCAT_WS(',', 
    (SELECT COUNT(*) FROM IndexNomPrenom WHERE FchGnrl_Type='Dossier'),
    (SELECT COUNT(*) FROM fchpat WHERE FchPat_Sexe IN ('H','M')),
    (SELECT COUNT(*) FROM fchpat WHERE FchPat_Sexe = 'F')
)" 2>/dev/null)

# ==============================================================================
# 4. CONSTRUCT RESULT JSON
# ==============================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "demo_file": {
        "exists": $DEMO_EXISTS,
        "created_during_task": $FILE_CREATED_DURING_TASK,
        "size": $DEMO_SIZE,
        "content_b64": "$DEMO_CONTENT"
    },
    "routines_list": ${ROUTINES_EXIST:-"[]"},
    "execution_results": {
        "fn_patient_age": {
            "output": "$AGE_RESULT",
            "expected": "$EXPECTED_AGE",
            "test_guid": "$TEST_GUID"
        },
        "sp_search_patients": {
            "output_b64": "$SEARCH_RESULT"
        },
        "sp_age_pyramid": {
            "output_b64": "$PYRAMID_RESULT"
        },
        "sp_practice_summary": {
            "output_b64": "$SUMMARY_RESULT",
            "ground_truth_csv": "$GT_SUMMARY"
        }
    }
}
EOF

# Save to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="