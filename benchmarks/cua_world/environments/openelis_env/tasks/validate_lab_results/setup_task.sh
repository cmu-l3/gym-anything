#!/bin/bash
echo "=== Setting up validate_lab_results task ==="

# Source shared utilities (also checks service readiness)
source /workspace/scripts/task_utils.sh

rm -f /tmp/task_start.png 2>/dev/null || true
date +%s > /tmp/task_start_timestamp

# Verify OpenELIS API is reachable
if ! wait_for_openelis 900; then
    echo "ERROR: OpenELIS is not reachable"
    exit 1
fi

# Record initial validation state
INITIAL_VALIDATED_COUNT=$(openelis_db_query_count \
    "SELECT COUNT(*) FROM clinlims.analysis WHERE status_id = (SELECT id FROM clinlims.status_of_sample WHERE name = 'Finalized' LIMIT 1);" \
    2>/dev/null)
echo "Initial finalized analysis count: $INITIAL_VALIDATED_COUNT"
echo "$INITIAL_VALIDATED_COUNT" > /tmp/initial_validated_count

# Ensure there are results awaiting validation.
# Check for analyses in "Technical Acceptance" status (results entered, pending validation)
PENDING_VALIDATION_COUNT=$(openelis_db_query_count \
    "SELECT COUNT(*) FROM clinlims.analysis
     WHERE status_id = (SELECT id FROM clinlims.status_of_sample WHERE name = 'Technical Acceptance' LIMIT 1);" \
    2>/dev/null)
echo "Pending validation count: $PENDING_VALIDATION_COUNT"

if [ "$PENDING_VALIDATION_COUNT" = "0" ] || [ -z "$PENDING_VALIDATION_COUNT" ]; then
    echo "No results pending validation. Creating pre-entered results..."

    # Find IDs
    GLUCOSE_TEST_ID=$(openelis_db_query \
        "SELECT id FROM clinlims.test WHERE LOWER(name) LIKE '%glucose%' AND is_active = 'Y' LIMIT 1;" 2>/dev/null)
    SERUM_TYPE_ID=$(openelis_db_query \
        "SELECT id FROM clinlims.type_of_sample WHERE LOWER(description) LIKE '%serum%' AND is_active = 'Y' LIMIT 1;" 2>/dev/null)
    BIOCHEM_SECTION_ID=$(openelis_db_query \
        "SELECT id FROM clinlims.test_section WHERE LOWER(name) LIKE '%biochem%' AND is_active = 'Y' LIMIT 1;" 2>/dev/null)
    PATIENT_ID=$(openelis_db_query \
        "SELECT p.id FROM clinlims.patient p
         JOIN clinlims.person per ON p.person_id = per.id
         WHERE per.first_name = 'James' AND per.last_name = 'Mwangi' LIMIT 1;" 2>/dev/null)
    TECH_ACCEPT_ID=$(openelis_db_query \
        "SELECT id FROM clinlims.status_of_sample WHERE name = 'Technical Acceptance' LIMIT 1;" 2>/dev/null)

    if [ -n "$GLUCOSE_TEST_ID" ] && [ -n "$PATIENT_ID" ] && [ -n "$TECH_ACCEPT_ID" ]; then
        SAMPLE_ID=$(openelis_db_query "SELECT COALESCE(MAX(id), 0) + 1 FROM clinlims.sample;" 2>/dev/null)
        SAMPLE_ITEM_ID=$(openelis_db_query "SELECT COALESCE(MAX(id), 0) + 1 FROM clinlims.sample_item;" 2>/dev/null)
        ANALYSIS_ID=$(openelis_db_query "SELECT COALESCE(MAX(id), 0) + 1 FROM clinlims.analysis;" 2>/dev/null)
        RESULT_ID=$(openelis_db_query "SELECT COALESCE(MAX(id), 0) + 1 FROM clinlims.result;" 2>/dev/null)
        SAMPLE_HUMAN_ID=$(openelis_db_query "SELECT COALESCE(MAX(id), 0) + 1 FROM clinlims.sample_human;" 2>/dev/null)
        ACCESSION=$(printf "VAL-%s-%04d" "$(date +%Y%m%d)" "$SAMPLE_ID")

        openelis_db_query \
            "INSERT INTO clinlims.sample (id, accession_number, status_id, entered_date, received_date, lastupdated)
             VALUES ($SAMPLE_ID, '$ACCESSION', $TECH_ACCEPT_ID, NOW(), NOW(), NOW());" 2>/dev/null

        openelis_db_query \
            "INSERT INTO clinlims.sample_item (id, sample_id, type_of_sample_id, sort_order, status_id, lastupdated)
             VALUES ($SAMPLE_ITEM_ID, $SAMPLE_ID, $SERUM_TYPE_ID, 1, $TECH_ACCEPT_ID, NOW());" 2>/dev/null

        openelis_db_query \
            "INSERT INTO clinlims.analysis (id, sample_item_id, test_id, test_section_id, status_id, lastupdated, revision)
             VALUES ($ANALYSIS_ID, $SAMPLE_ITEM_ID, $GLUCOSE_TEST_ID, $BIOCHEM_SECTION_ID, $TECH_ACCEPT_ID, NOW(), 0);" 2>/dev/null

        openelis_db_query \
            "INSERT INTO clinlims.result (id, analysis_id, result_type, value, lastupdated)
             VALUES ($RESULT_ID, $ANALYSIS_ID, 'N', '95', NOW());" 2>/dev/null

        openelis_db_query \
            "INSERT INTO clinlims.sample_human (id, sample_id, patient_id, lastupdated)
             VALUES ($SAMPLE_HUMAN_ID, $SAMPLE_ID, $PATIENT_ID, NOW());" 2>/dev/null

        echo "  Created sample $ACCESSION with pre-entered Glucose result (95 mg/dL) awaiting validation"
    else
        echo "  WARNING: Could not create validation data. Task may need manual result entry first."
    fi
fi

# Start Firefox at OpenELIS login page
if ! start_browser "$OPENELIS_LOGIN_URL" 4; then
    echo "ERROR: Browser failed to start cleanly"
    DISPLAY=:1 wmctrl -l 2>/dev/null || true
    exit 1
fi

focus_browser || true
sleep 2

take_screenshot /tmp/task_start.png

echo "Task start screenshot: /tmp/task_start.png"
echo "=== Task setup complete ==="
echo "Agent should see the OpenELIS login page."
echo "Task: Log in, navigate to Validation section, and validate pending lab results."
