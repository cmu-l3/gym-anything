#!/bin/bash
# Export recruitment candidate statuses for verification.

set -euo pipefail
echo "=== Exporting multi_vacancy_recruitment_close results ==="

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/multi_vacancy_recruitment_close_result.json"
rm -f "$RESULT_FILE" 2>/dev/null || true

# -------------------------------------------------------
# Get candidate status from ohrm_job_candidate_vacancy
# Status is stored as VARCHAR: 'SHORTLISTED', 'OFFERED', 'REJECTED'
# ohrm_job_candidate_status table does NOT exist in OrangeHRM 5.8
# -------------------------------------------------------
get_candidate_status() {
    local first="$1" last="$2"
    local cand_id
    cand_id=$(orangehrm_db_query "SELECT id FROM ohrm_job_candidate WHERE first_name='${first}' AND last_name='${last}' ORDER BY id DESC LIMIT 1;" | tr -d '[:space:]')
    [ -z "$cand_id" ] && { echo ""; return; }
    orangehrm_db_query "
        SELECT status FROM ohrm_job_candidate_vacancy
        WHERE candidate_id=${cand_id}
        ORDER BY id DESC
        LIMIT 1;
    " 2>/dev/null | tr -d '\n' | xargs
}

MARCUS_STATUS=$(get_candidate_status "Marcus" "Webb")
PRIYA_STATUS=$(get_candidate_status "Priya" "Sharma")
DANIELLE_STATUS=$(get_candidate_status "Danielle" "Osei")
FELIX_STATUS=$(get_candidate_status "Felix" "Braun")

# Use the VARCHAR status string as the label — verifier checks 'offer' / 'reject' in label.lower()
MARCUS_LABEL=$(echo "$MARCUS_STATUS" | tr '[:upper:]' '[:lower:]')
PRIYA_LABEL=$(echo "$PRIYA_STATUS" | tr '[:upper:]' '[:lower:]')
DANIELLE_LABEL=$(echo "$DANIELLE_STATUS" | tr '[:upper:]' '[:lower:]')
FELIX_LABEL=$(echo "$FELIX_STATUS" | tr '[:upper:]' '[:lower:]')

log "Marcus Webb   status=$MARCUS_STATUS  label=$MARCUS_LABEL"
log "Priya Sharma  status=$PRIYA_STATUS   label=$PRIYA_LABEL"
log "Danielle Osei status=$DANIELLE_STATUS label=$DANIELLE_LABEL"
log "Felix Braun   status=$FELIX_STATUS   label=$FELIX_LABEL"

# -------------------------------------------------------
# Vacancy statuses
# -------------------------------------------------------
V1_STATUS=$(orangehrm_db_query "SELECT status FROM ohrm_job_vacancy WHERE name='Senior Data Analyst - Q2 2025' LIMIT 1;" | tr -d '[:space:]')
V2_STATUS=$(orangehrm_db_query "SELECT status FROM ohrm_job_vacancy WHERE name='Clinical Coordinator - Q2 2025' LIMIT 1;" | tr -d '[:space:]')

log "Vacancy 1 status=$V1_STATUS, Vacancy 2 status=$V2_STATUS"

# -------------------------------------------------------
# Write result
# offer_status_id / reject_status_id set to dummy values (6/4);
# verifier primarily uses label matching ('offer'/'reject' in label.lower()).
# -------------------------------------------------------
safe_write_result "{
  \"offer_status_id\": 6,
  \"reject_status_id\": 4,
  \"marcus_status\": \"${MARCUS_STATUS}\",
  \"marcus_label\": \"${MARCUS_LABEL}\",
  \"priya_status\": \"${PRIYA_STATUS}\",
  \"priya_label\": \"${PRIYA_LABEL}\",
  \"danielle_status\": \"${DANIELLE_STATUS}\",
  \"danielle_label\": \"${DANIELLE_LABEL}\",
  \"felix_status\": \"${FELIX_STATUS}\",
  \"felix_label\": \"${FELIX_LABEL}\",
  \"vacancy1_status\": \"${V1_STATUS}\",
  \"vacancy2_status\": \"${V2_STATUS}\"
}" "$RESULT_FILE"

echo "=== Export complete: $RESULT_FILE ==="
cat "$RESULT_FILE"
