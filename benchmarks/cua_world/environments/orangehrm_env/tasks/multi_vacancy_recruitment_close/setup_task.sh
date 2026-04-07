#!/bin/bash
# Pre-task setup for multi_vacancy_recruitment_close.
# Creates 2 job vacancies (Senior Data Analyst - Q2 2025, Clinical Coordinator - Q2 2025)
# with 2 shortlisted candidates each, then places the hiring decisions memo on the Desktop.

set -euo pipefail
echo "=== Setting up multi_vacancy_recruitment_close task ==="

source /workspace/scripts/task_utils.sh

wait_for_http "$ORANGEHRM_URL" 60

# -------------------------------------------------------
# 1. Clean up prior run artifacts
# -------------------------------------------------------
rm -f /tmp/multi_vacancy_recruitment_close_result.json 2>/dev/null || true

log "Cleaning up prior task data..."
# Delete candidate-vacancy links first (FK constraint), then candidates and vacancies
orangehrm_db_query "
    DELETE jcv FROM ohrm_job_candidate_vacancy jcv
    JOIN ohrm_job_candidate jc ON jcv.candidate_id = jc.id
    WHERE jc.first_name IN ('Marcus','Priya','Danielle','Felix')
      AND jc.last_name IN ('Webb','Sharma','Osei','Braun');
" 2>/dev/null || true
orangehrm_db_query "DELETE FROM ohrm_job_candidate WHERE first_name IN ('Marcus','Priya','Danielle','Felix') AND last_name IN ('Webb','Sharma','Osei','Braun');" 2>/dev/null || true
orangehrm_db_query "DELETE FROM ohrm_job_vacancy WHERE name IN ('Senior Data Analyst - Q2 2025','Clinical Coordinator - Q2 2025');" 2>/dev/null || true

# -------------------------------------------------------
# 2. Ensure required job titles exist
# -------------------------------------------------------
log "Ensuring job titles exist..."

DS_JT=$(orangehrm_db_query "SELECT id FROM ohrm_job_title WHERE job_title='Data Scientist' AND is_deleted=0 LIMIT 1;" | tr -d '[:space:]')
if [ -z "$DS_JT" ]; then
    orangehrm_db_query "INSERT INTO ohrm_job_title (job_title, is_deleted) VALUES ('Data Scientist', 0);"
    DS_JT=$(orangehrm_db_query "SELECT LAST_INSERT_ID();" | tr -d '[:space:]')
fi

HR_JT=$(orangehrm_db_query "SELECT id FROM ohrm_job_title WHERE job_title='HR Manager' AND is_deleted=0 LIMIT 1;" | tr -d '[:space:]')
if [ -z "$HR_JT" ]; then
    orangehrm_db_query "INSERT INTO ohrm_job_title (job_title, is_deleted) VALUES ('HR Manager', 0);"
    HR_JT=$(orangehrm_db_query "SELECT LAST_INSERT_ID();" | tr -d '[:space:]')
fi

log "Job title IDs: Data Scientist=$DS_JT, HR Manager=$HR_JT"

# -------------------------------------------------------
# 3. Determine hiring manager (use first available employee)
# -------------------------------------------------------
ADMIN_EMP=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE purged_at IS NULL ORDER BY emp_number LIMIT 1;" | tr -d '[:space:]')
HM_ID="${ADMIN_EMP:-1}"
log "Using hiring manager emp_number=$HM_ID"

# -------------------------------------------------------
# 4. Create the two job vacancies
#    Both defined_time AND updated_time are required NOT NULL columns.
# -------------------------------------------------------
log "Creating job vacancies..."
orangehrm_db_query "
    INSERT INTO ohrm_job_vacancy (name, job_title_code, hiring_manager_id, no_of_positions, status, defined_time, updated_time)
    VALUES ('Senior Data Analyst - Q2 2025', ${DS_JT}, ${HM_ID}, 1, 1, NOW(), NOW());
"
VACANCY1_ID=$(orangehrm_db_query "SELECT LAST_INSERT_ID();" | tr -d '[:space:]')
log "Created vacancy 1 (Senior Data Analyst - Q2 2025) ID=$VACANCY1_ID"

orangehrm_db_query "
    INSERT INTO ohrm_job_vacancy (name, job_title_code, hiring_manager_id, no_of_positions, status, defined_time, updated_time)
    VALUES ('Clinical Coordinator - Q2 2025', ${HR_JT}, ${HM_ID}, 1, 1, NOW(), NOW());
"
VACANCY2_ID=$(orangehrm_db_query "SELECT LAST_INSERT_ID();" | tr -d '[:space:]')
log "Created vacancy 2 (Clinical Coordinator - Q2 2025) ID=$VACANCY2_ID"

# -------------------------------------------------------
# 5. Create candidates
#    Note: ohrm_job_candidate has NO vacancy_id column in this schema.
#    The candidate↔vacancy link is stored in ohrm_job_candidate_vacancy.
# -------------------------------------------------------
log "Creating shortlisted candidates..."

orangehrm_db_query "
    INSERT INTO ohrm_job_candidate (first_name, last_name, email, contact_number, status, mode_of_application, date_of_application)
    VALUES ('Marcus', 'Webb', 'marcus.webb@apexanalytics.com', '555-0231', 1, 1, DATE_SUB(NOW(), INTERVAL 10 DAY));
"
MARCUS_ID=$(orangehrm_db_query "SELECT LAST_INSERT_ID();" | tr -d '[:space:]')

orangehrm_db_query "
    INSERT INTO ohrm_job_candidate (first_name, last_name, email, contact_number, status, mode_of_application, date_of_application)
    VALUES ('Priya', 'Sharma', 'priya.sharma@jobseeker.com', '555-0232', 1, 1, DATE_SUB(NOW(), INTERVAL 10 DAY));
"
PRIYA_ID=$(orangehrm_db_query "SELECT LAST_INSERT_ID();" | tr -d '[:space:]')

orangehrm_db_query "
    INSERT INTO ohrm_job_candidate (first_name, last_name, email, contact_number, status, mode_of_application, date_of_application)
    VALUES ('Danielle', 'Osei', 'danielle.osei@careerjobs.com', '555-0233', 1, 1, DATE_SUB(NOW(), INTERVAL 8 DAY));
"
DANIELLE_ID=$(orangehrm_db_query "SELECT LAST_INSERT_ID();" | tr -d '[:space:]')

orangehrm_db_query "
    INSERT INTO ohrm_job_candidate (first_name, last_name, email, contact_number, status, mode_of_application, date_of_application)
    VALUES ('Felix', 'Braun', 'felix.braun@jobportal.com', '555-0234', 1, 1, DATE_SUB(NOW(), INTERVAL 8 DAY));
"
FELIX_ID=$(orangehrm_db_query "SELECT LAST_INSERT_ID();" | tr -d '[:space:]')

log "Candidates created: Marcus=$MARCUS_ID Priya=$PRIYA_ID Danielle=$DANIELLE_ID Felix=$FELIX_ID"

# -------------------------------------------------------
# 6. Link candidates to vacancies with SHORTLISTED status
#    status is a VARCHAR field in ohrm_job_candidate_vacancy.
# -------------------------------------------------------
log "Linking candidates to vacancies..."

orangehrm_db_query "
    INSERT INTO ohrm_job_candidate_vacancy (candidate_id, vacancy_id, status, applied_date)
    VALUES (${MARCUS_ID}, ${VACANCY1_ID}, 'SHORTLISTED', DATE_SUB(NOW(), INTERVAL 10 DAY));
"
orangehrm_db_query "
    INSERT INTO ohrm_job_candidate_vacancy (candidate_id, vacancy_id, status, applied_date)
    VALUES (${PRIYA_ID}, ${VACANCY1_ID}, 'SHORTLISTED', DATE_SUB(NOW(), INTERVAL 10 DAY));
"
orangehrm_db_query "
    INSERT INTO ohrm_job_candidate_vacancy (candidate_id, vacancy_id, status, applied_date)
    VALUES (${DANIELLE_ID}, ${VACANCY2_ID}, 'SHORTLISTED', DATE_SUB(NOW(), INTERVAL 8 DAY));
"
orangehrm_db_query "
    INSERT INTO ohrm_job_candidate_vacancy (candidate_id, vacancy_id, status, applied_date)
    VALUES (${FELIX_ID}, ${VACANCY2_ID}, 'SHORTLISTED', DATE_SUB(NOW(), INTERVAL 8 DAY));
"
log "Candidate-vacancy links created"

# -------------------------------------------------------
# 7. Record IDs for reference
# -------------------------------------------------------
date +%s > /tmp/task_start_timestamp
cat > /tmp/multi_vacancy_ids.txt << EOF
VACANCY1=${VACANCY1_ID}
VACANCY2=${VACANCY2_ID}
MARCUS=${MARCUS_ID}
PRIYA=${PRIYA_ID}
DANIELLE=${DANIELLE_ID}
FELIX=${FELIX_ID}
EOF

# -------------------------------------------------------
# 8. Create the hiring decisions memo on the Desktop
# -------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/q2_hiring_decisions.txt" << 'MEMO'
APEX ANALYTICS GROUP — Q2 2025 FINAL HIRING DECISIONS
======================================================
From:  Sarah Mitchell, VP Talent Acquisition
To:    Talent Acquisition Manager
Date:  2025-06-30
Re:    Final Candidate Decisions — Q2 2025 Hiring Cycle

The hiring panel has completed evaluations. Please update each candidate's
status in OrangeHRM Recruitment module immediately so we can proceed with
offer letters and rejections.

Navigate to: Recruitment > Vacancies → select vacancy → view candidates

----------------------------------------------------------------------
VACANCY: Senior Data Analyst - Q2 2025
----------------------------------------------------------------------
  Marcus Webb         → OFFER   (advance to "Job Offered" status)
  Priya Sharma        → REJECT  (mark as "Rejected")

----------------------------------------------------------------------
VACANCY: Clinical Coordinator - Q2 2025
----------------------------------------------------------------------
  Danielle Osei       → OFFER   (advance to "Job Offered" status)
  Felix Braun         → REJECT  (mark as "Rejected")

----------------------------------------------------------------------
NOTE: All four candidates are currently in "Shortlisted" status.
Update each one per the decision above. HR will follow up with
offer letter generation and rejection emails once statuses are updated.
----------------------------------------------------------------------
MEMO

chown ga:ga "$DESKTOP_DIR/q2_hiring_decisions.txt" 2>/dev/null || true
chmod 644 "$DESKTOP_DIR/q2_hiring_decisions.txt"
log "Created hiring decisions memo at $DESKTOP_DIR/q2_hiring_decisions.txt"

# -------------------------------------------------------
# 9. Navigate to Recruitment module
# -------------------------------------------------------
TARGET_URL="${ORANGEHRM_URL}/web/index.php/recruitment/viewCandidates"
ensure_orangehrm_logged_in "$TARGET_URL"

sleep 2
take_screenshot /tmp/task_start_state.png

echo "=== multi_vacancy_recruitment_close task setup complete ==="
echo "Vacancies: $VACANCY1_ID (Senior Data Analyst), $VACANCY2_ID (Clinical Coordinator)"
echo "Candidates: Marcus(OFFER)=$MARCUS_ID, Priya(REJECT)=$PRIYA_ID, Danielle(OFFER)=$DANIELLE_ID, Felix(REJECT)=$FELIX_ID"
