#!/bin/bash
echo "=== Setting up enter_test_results task ==="

# Source shared utilities (also checks service readiness)
source /workspace/scripts/task_utils.sh

# Record initial state for delta verification
INITIAL_RESULT_COUNT=$(openelis_db_query_count \
    "SELECT COUNT(*) FROM clinlims.result;" 2>/dev/null)
echo "Initial result count: $INITIAL_RESULT_COUNT"
echo "$INITIAL_RESULT_COUNT" > /tmp/initial_result_count

# Ensure there is a sample with pending Glucose and Creatinine analyses.
# If the add_patient_order task was run, there should already be pending samples.
# If not, we create one via the database to guarantee the task is doable.
PENDING_ANALYSIS_COUNT=$(openelis_db_query_count \
    "SELECT COUNT(*) FROM clinlims.analysis a
     JOIN clinlims.test t ON a.test_id = t.id
     WHERE a.status_id = (SELECT id FROM clinlims.status_of_sample WHERE name = 'Not Started' OR name = 'Technical Acceptance' LIMIT 1)
     AND LOWER(t.name) LIKE '%glucose%';" 2>/dev/null)

echo "Pending Glucose analyses: $PENDING_ANALYSIS_COUNT"

if [ "$PENDING_ANALYSIS_COUNT" = "0" ] || [ -z "$PENDING_ANALYSIS_COUNT" ]; then
    echo "No pending analyses found. Creating a sample order via database..."

    # Find required IDs from the test catalog
    GLUCOSE_TEST_ID=$(openelis_db_query \
        "SELECT id FROM clinlims.test WHERE LOWER(name) LIKE '%glucose%' AND is_active = 'Y' LIMIT 1;" 2>/dev/null)
    CREATININE_TEST_ID=$(openelis_db_query \
        "SELECT id FROM clinlims.test WHERE LOWER(name) LIKE '%creatinine%' AND is_active = 'Y' LIMIT 1;" 2>/dev/null)
    SERUM_TYPE_ID=$(openelis_db_query \
        "SELECT id FROM clinlims.type_of_sample WHERE LOWER(description) LIKE '%serum%' AND is_active = 'Y' LIMIT 1;" 2>/dev/null)
    BIOCHEM_SECTION_ID=$(openelis_db_query \
        "SELECT id FROM clinlims.test_section WHERE LOWER(name) LIKE '%biochem%' AND is_active = 'Y' LIMIT 1;" 2>/dev/null)

    # Get a patient ID (use Amina Ochieng from seed data)
    PATIENT_ID=$(openelis_db_query \
        "SELECT p.id FROM clinlims.patient p
         JOIN clinlims.person per ON p.person_id = per.id
         WHERE per.first_name = 'Amina' AND per.last_name = 'Ochieng' LIMIT 1;" 2>/dev/null)

    if [ -n "$GLUCOSE_TEST_ID" ] && [ -n "$PATIENT_ID" ] && [ -n "$SERUM_TYPE_ID" ]; then
        echo "  Creating sample order: Glucose=$GLUCOSE_TEST_ID, Creatinine=$CREATININE_TEST_ID, Patient=$PATIENT_ID"

        # Get next IDs
        SAMPLE_ID=$(openelis_db_query "SELECT COALESCE(MAX(id), 0) + 1 FROM clinlims.sample;" 2>/dev/null)
        SAMPLE_ITEM_ID=$(openelis_db_query "SELECT COALESCE(MAX(id), 0) + 1 FROM clinlims.sample_item;" 2>/dev/null)
        ANALYSIS_ID=$(openelis_db_query "SELECT COALESCE(MAX(id), 0) + 1 FROM clinlims.analysis;" 2>/dev/null)
        SAMPLE_HUMAN_ID=$(openelis_db_query "SELECT COALESCE(MAX(id), 0) + 1 FROM clinlims.sample_human;" 2>/dev/null)
        NOT_STARTED_ID=$(openelis_db_query \
            "SELECT id FROM clinlims.status_of_sample WHERE name = 'Not Started' LIMIT 1;" 2>/dev/null)
        ACCESSION=$(printf "%s-%04d" "$(date +%Y%m%d)" "$SAMPLE_ID")

        # Create sample
        openelis_db_query \
            "INSERT INTO clinlims.sample (id, accession_number, status_id, entered_date, received_date, lastupdated)
             VALUES ($SAMPLE_ID, '$ACCESSION', $NOT_STARTED_ID, NOW(), NOW(), NOW());" 2>/dev/null

        # Create sample_item (links sample to sample type)
        openelis_db_query \
            "INSERT INTO clinlims.sample_item (id, sample_id, type_of_sample_id, sort_order, status_id, lastupdated)
             VALUES ($SAMPLE_ITEM_ID, $SAMPLE_ID, $SERUM_TYPE_ID, 1, $NOT_STARTED_ID, NOW());" 2>/dev/null

        # Create analysis for Glucose
        openelis_db_query \
            "INSERT INTO clinlims.analysis (id, sample_item_id, test_id, test_section_id, status_id, lastupdated, revision)
             VALUES ($ANALYSIS_ID, $SAMPLE_ITEM_ID, $GLUCOSE_TEST_ID, $BIOCHEM_SECTION_ID, $NOT_STARTED_ID, NOW(), 0);" 2>/dev/null

        # Create analysis for Creatinine (if test exists)
        if [ -n "$CREATININE_TEST_ID" ]; then
            ANALYSIS_ID2=$((ANALYSIS_ID + 1))
            openelis_db_query \
                "INSERT INTO clinlims.analysis (id, sample_item_id, test_id, test_section_id, status_id, lastupdated, revision)
                 VALUES ($ANALYSIS_ID2, $SAMPLE_ITEM_ID, $CREATININE_TEST_ID, $BIOCHEM_SECTION_ID, $NOT_STARTED_ID, NOW(), 0);" 2>/dev/null
        fi

        # Link sample to patient
        openelis_db_query \
            "INSERT INTO clinlims.sample_human (id, sample_id, patient_id, lastupdated)
             VALUES ($SAMPLE_HUMAN_ID, $SAMPLE_ID, $PATIENT_ID, NOW());" 2>/dev/null

        echo "  Sample order created: $ACCESSION"
    else
        echo "  WARNING: Could not find required test/patient IDs. Task may need manual order creation."
        echo "    GLUCOSE_TEST_ID=$GLUCOSE_TEST_ID PATIENT_ID=$PATIENT_ID SERUM_TYPE_ID=$SERUM_TYPE_ID"
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

# Log in and navigate to dashboard
ensure_logged_in "$OPENELIS_BASE_URL/"
wait_for_page_load 5

take_screenshot "/tmp/task_enter_results_start.png"

echo "=== Task setup complete ==="
echo "Agent should see the OpenELIS dashboard."
echo "Task: Navigate to Results > By Unit, select Biochemistry, and enter Glucose (126) and Creatinine (7.0) results."
