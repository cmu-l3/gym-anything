#!/bin/bash
echo "=== Exporting post_vacancy_add_candidate results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Target Data
VACANCY_NAME="HR Manager - East Regional Office"
CANDIDATE_EMAIL="rebecca.martinez@email.com"
EXPECTED_HM_ID=$(cat /tmp/expected_hm_id.txt 2>/dev/null || echo "")

# ==============================================================================
# Query Database for Vacancy
# ==============================================================================
# Fetch Vacancy details
# Columns: id, name, job_title_code, hiring_manager_id, no_of_positions, status, defined_time (creation)
# Note: job_title_code in ohrm_job_vacancy is an ID linking to ohrm_job_title.id in newer versions
VACANCY_JSON=$(docker exec orangehrm-db mysql -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -B -e \
    "SELECT id, name, job_title_code, hiring_manager_id, no_of_positions, status 
     FROM ohrm_job_vacancy 
     WHERE name LIKE '${VACANCY_NAME}' 
     LIMIT 1;" 2>/dev/null | \
    awk '{printf "{\"id\": \"%s\", \"name\": \"%s\", \"job_title_id\": \"%s\", \"hiring_manager_id\": \"%s\", \"positions\": \"%s\", \"status\": \"%s\"}", $1, $2, $3, $4, $5, $6}' || echo "{}")

VACANCY_ID=$(echo "$VACANCY_JSON" | grep -o '"id": "[^"]*"' | cut -d'"' -f4)

# Get Job Title Name if Vacancy exists
JOB_TITLE_NAME=""
if [ -n "$VACANCY_ID" ]; then
    JT_ID=$(echo "$VACANCY_JSON" | grep -o '"job_title_id": "[^"]*"' | cut -d'"' -f4)
    if [ -n "$JT_ID" ]; then
        JOB_TITLE_NAME=$(orangehrm_db_query "SELECT job_title FROM ohrm_job_title WHERE id=${JT_ID};" 2>/dev/null)
    fi
fi

# ==============================================================================
# Query Database for Candidate
# ==============================================================================
# Fetch Candidate details
# Columns: id, first_name, last_name, email, date_of_application
CANDIDATE_JSON=$(docker exec orangehrm-db mysql -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -B -e \
    "SELECT id, first_name, last_name, email, consent_to_keep_data 
     FROM ohrm_job_candidate 
     WHERE email='${CANDIDATE_EMAIL}' 
     LIMIT 1;" 2>/dev/null | \
    awk '{printf "{\"id\": \"%s\", \"first_name\": \"%s\", \"last_name\": \"%s\", \"email\": \"%s\", \"consent\": \"%s\"}", $1, $2, $3, $4, $5}' || echo "{}")

CANDIDATE_ID=$(echo "$CANDIDATE_JSON" | grep -o '"id": "[^"]*"' | cut -d'"' -f4)

# ==============================================================================
# Check Linkage (Candidate -> Vacancy)
# ==============================================================================
IS_LINKED="false"
if [ -n "$VACANCY_ID" ] && [ -n "$CANDIDATE_ID" ]; then
    LINK_COUNT=$(orangehrm_db_query "SELECT COUNT(*) FROM ohrm_job_candidate_vacancy WHERE candidate_id=${CANDIDATE_ID} AND vacancy_id=${VACANCY_ID};" 2>/dev/null | tr -d '[:space:]')
    if [ "${LINK_COUNT:-0}" -gt 0 ]; then
        IS_LINKED="true"
    fi
fi

# ==============================================================================
# State Comparison
# ==============================================================================
FINAL_VACANCY_COUNT=$(orangehrm_count "ohrm_job_vacancy" "status=1")
FINAL_CANDIDATE_COUNT=$(orangehrm_count "ohrm_job_candidate" "is_deleted=0")
INITIAL_VACANCY_COUNT=$(cat /tmp/initial_vacancy_count.txt 2>/dev/null || echo "0")
INITIAL_CANDIDATE_COUNT=$(cat /tmp/initial_candidate_count.txt 2>/dev/null || echo "0")

VACANCY_COUNT_INCREASE=$((FINAL_VACANCY_COUNT - INITIAL_VACANCY_COUNT))
CANDIDATE_COUNT_INCREASE=$((FINAL_CANDIDATE_COUNT - INITIAL_CANDIDATE_COUNT))

# ==============================================================================
# Construct Result JSON
# ==============================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "vacancy": $VACANCY_JSON,
    "candidate": $CANDIDATE_JSON,
    "job_title_name": "$JOB_TITLE_NAME",
    "expected_hm_id": "$EXPECTED_HM_ID",
    "is_linked": $IS_LINKED,
    "vacancy_count_increase": $VACANCY_COUNT_INCREASE,
    "candidate_count_increase": $CANDIDATE_COUNT_INCREASE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON content:"
cat /tmp/task_result.json
echo "=== Export complete ==="