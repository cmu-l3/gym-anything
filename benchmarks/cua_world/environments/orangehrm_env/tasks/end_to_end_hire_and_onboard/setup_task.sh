#!/bin/bash
# Pre-task setup for end_to_end_hire_and_onboard.
# - Ensures "Senior DevOps Engineer" job title exists
# - Cleans up stale recruitment, employee, pay grade, leave, review data
# - Creates the hiring directive document on the Desktop
# - Navigates browser to OrangeHRM Recruitment module

set -euo pipefail
echo "=== Setting up end_to_end_hire_and_onboard task ==="

source /workspace/scripts/task_utils.sh

wait_for_http "$ORANGEHRM_URL" 60

# -------------------------------------------------------
# 1. Clean stale result files BEFORE recording timestamp
# -------------------------------------------------------
RESULT_FILE="/tmp/end_to_end_hire_and_onboard_result.json"
SCREENSHOT="/tmp/end_to_end_hire_and_onboard_screenshot.png"
rm -f "$RESULT_FILE" "$SCREENSHOT" 2>/dev/null || true

# -------------------------------------------------------
# 2. Record task start timestamp
# -------------------------------------------------------
date +%s > /tmp/end_to_end_hire_and_onboard_started

# -------------------------------------------------------
# 3. Ensure "Senior DevOps Engineer" job title exists
# -------------------------------------------------------
JT_EXISTS=$(orangehrm_db_query "SELECT COUNT(*) FROM ohrm_job_title WHERE job_title='Senior DevOps Engineer' AND is_deleted=0;" | tr -d '[:space:]')
if [ "${JT_EXISTS:-0}" -eq "0" ]; then
    orangehrm_db_query "INSERT INTO ohrm_job_title (job_title, job_description, is_deleted) VALUES ('Senior DevOps Engineer', 'Lead cloud infrastructure and CI/CD pipeline development', 0);"
    log "Created job title 'Senior DevOps Engineer'"
else
    log "Job title 'Senior DevOps Engineer' already exists"
fi

# -------------------------------------------------------
# 4. Clean up stale recruitment data from prior runs
# -------------------------------------------------------
log "Cleaning up stale recruitment data..."

# Remove vacancy and linked data
VACANCY_IDS=$(orangehrm_db_query "SELECT id FROM ohrm_job_vacancy WHERE name LIKE '%Senior DevOps Engineer%';" | tr -d '[:space:]' | tr '\n' ' ')
for VID in $VACANCY_IDS; do
    if [ -n "$VID" ]; then
        orangehrm_db_query "DELETE FROM ohrm_job_candidate_history WHERE vacancy_id=$VID;" 2>/dev/null || true
        orangehrm_db_query "DELETE FROM ohrm_job_candidate_vacancy WHERE vacancy_id=$VID;" 2>/dev/null || true
        orangehrm_db_query "DELETE FROM ohrm_job_vacancy WHERE id=$VID;" 2>/dev/null || true
        log "Removed vacancy id=$VID"
    fi
done

# Remove candidates by name
for NAME_PAIR in "Rajesh:Krishnamurthy" "Elena:Vasquez-Torres" "Thomas:Andersson"; do
    FIRST=$(echo "$NAME_PAIR" | cut -d: -f1)
    LAST=$(echo "$NAME_PAIR" | cut -d: -f2)
    CAND_IDS=$(orangehrm_db_query "SELECT id FROM ohrm_job_candidate WHERE first_name='$FIRST' AND last_name='$LAST';" | tr -d '[:space:]' | tr '\n' ' ')
    for CID in $CAND_IDS; do
        if [ -n "$CID" ]; then
            orangehrm_db_query "DELETE FROM ohrm_job_candidate_history WHERE candidate_id=$CID;" 2>/dev/null || true
            orangehrm_db_query "DELETE FROM ohrm_job_candidate_vacancy WHERE candidate_id=$CID;" 2>/dev/null || true
            orangehrm_db_query "DELETE FROM ohrm_job_candidate WHERE id=$CID;" 2>/dev/null || true
            log "Removed candidate '$FIRST $LAST' id=$CID"
        fi
    done
done

# -------------------------------------------------------
# 5. Clean up stale employee record from prior hire
# -------------------------------------------------------
log "Cleaning up stale employee data for Rajesh Krishnamurthy..."
EMP_NUM=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE emp_firstname='Rajesh' AND emp_lastname='Krishnamurthy' LIMIT 1;" | tr -d '[:space:]')
if [ -n "$EMP_NUM" ]; then
    orangehrm_db_query "DELETE FROM hs_hr_emp_emergency_contacts WHERE emp_number=$EMP_NUM;" 2>/dev/null || true
    orangehrm_db_query "DELETE FROM hs_hr_emp_passport WHERE emp_number=$EMP_NUM;" 2>/dev/null || true
    orangehrm_db_query "DELETE FROM hs_hr_emp_basicsalary WHERE emp_number=$EMP_NUM;" 2>/dev/null || true
    orangehrm_db_query "DELETE FROM ohrm_leave_entitlement WHERE emp_number=$EMP_NUM;" 2>/dev/null || true
    orangehrm_db_query "DELETE FROM ohrm_performance_review WHERE employee_number=$EMP_NUM;" 2>/dev/null || true
    orangehrm_db_query "DELETE FROM ohrm_user WHERE emp_number=$EMP_NUM;" 2>/dev/null || true
    orangehrm_db_query "DELETE FROM hs_hr_employee WHERE emp_number=$EMP_NUM;" 2>/dev/null || true
    log "Removed employee record emp_number=$EMP_NUM"
fi

# -------------------------------------------------------
# 6. Clean up stale pay grade from prior runs
# -------------------------------------------------------
log "Cleaning up stale pay grade 'Grade D - DevOps Senior'..."
PG_ID=$(orangehrm_db_query "SELECT id FROM ohrm_pay_grade WHERE name='Grade D - DevOps Senior' LIMIT 1;" | tr -d '[:space:]')
if [ -n "$PG_ID" ]; then
    orangehrm_db_query "DELETE FROM hs_hr_emp_basicsalary WHERE sal_grd_code=$PG_ID;" 2>/dev/null || true
    orangehrm_db_query "DELETE FROM ohrm_pay_grade_currency WHERE pay_grade_id=$PG_ID;" 2>/dev/null || true
    orangehrm_db_query "DELETE FROM ohrm_pay_grade WHERE id=$PG_ID;" 2>/dev/null || true
    log "Removed pay grade id=$PG_ID"
fi

# -------------------------------------------------------
# 7. Ensure USD currency exists (table is hs_hr_currency_type in OrangeHRM 5.x)
# -------------------------------------------------------
USD_EXISTS=$(orangehrm_db_query "SELECT COUNT(*) FROM hs_hr_currency_type WHERE currency_id='USD';" | tr -d '[:space:]')
if [ "${USD_EXISTS:-0}" -eq "0" ]; then
    orangehrm_db_query "INSERT INTO hs_hr_currency_type (code, currency_id, currency_name) VALUES (840, 'USD', 'United States Dollar');" 2>/dev/null || true
    log "Added USD currency"
else
    log "USD currency already exists"
fi

# -------------------------------------------------------
# 8. Record baseline counts for anti-gaming checks
# -------------------------------------------------------
BASELINE_VACANCIES=$(orangehrm_db_query "SELECT COUNT(*) FROM ohrm_job_vacancy;" | tr -d '[:space:]')
BASELINE_CANDIDATES=$(orangehrm_db_query "SELECT COUNT(*) FROM ohrm_job_candidate;" | tr -d '[:space:]')
BASELINE_EMPLOYEES=$(orangehrm_db_query "SELECT COUNT(*) FROM hs_hr_employee WHERE purged_at IS NULL;" | tr -d '[:space:]')
echo "${BASELINE_VACANCIES:-0}" > /tmp/initial_vacancy_count.txt
echo "${BASELINE_CANDIDATES:-0}" > /tmp/initial_candidate_count.txt
echo "${BASELINE_EMPLOYEES:-0}" > /tmp/initial_employee_count.txt
log "Baselines: vacancies=$BASELINE_VACANCIES candidates=$BASELINE_CANDIDATES employees=$BASELINE_EMPLOYEES"

# -------------------------------------------------------
# 9. Create the hiring directive file on the Desktop
# -------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/devops_hiring_directive.txt" << 'DIRECTIVE'
═══════════════════════════════════════════════════════════════════
                    ENGINEERING HIRING DIRECTIVE
                        Q2 2025 — CONFIDENTIAL
═══════════════════════════════════════════════════════════════════

FROM: Victoria Chen, VP of Engineering
TO:   HR Operations
DATE: March 15, 2025
RE:   Senior DevOps Engineer — Authorized Hire

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SECTION 1 — VACANCY DETAILS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Position Title:   Senior DevOps Engineer
  Vacancy Name:     Senior DevOps Engineer - Q2 2025
  Department:       Engineering
  Hiring Manager:   Admin User (System Administrator)
  Positions:        1
  Description:      Lead cloud infrastructure and CI/CD pipeline
                    development for the engineering division.
                    Requires 5+ years of experience with
                    Kubernetes, Terraform, and AWS/GCP.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SECTION 2 — CANDIDATE POOL
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

The following candidates have applied for this position:

  1. Rajesh Krishnamurthy
     Email:  rajesh.k@techhire.com
     Phone:  555-0147
     Notes:  8 years DevOps experience, AWS Solutions Architect
             certified, led migration of 200+ microservices to
             Kubernetes at previous employer. Strong candidate.

  2. Elena Vasquez-Torres
     Email:  elena.vt@techhire.com
     Phone:  555-0283
     Notes:  6 years DevOps experience, strong Terraform
             background, GCP Professional Cloud Architect
             certified, experience with multi-cloud deployments.

  3. Thomas Andersson
     Email:  thomas.a@techhire.com
     Phone:  555-0391
     Notes:  3 years junior DevOps experience, Docker proficient,
             currently completing AWS Solutions Architect
             certification. Does not meet 5-year minimum.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SECTION 3 — SCREENING & INTERVIEW DECISIONS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

After resume review, advance Rajesh Krishnamurthy and
Elena Vasquez-Torres to the shortlist. Thomas Andersson
does not meet the minimum 5-year experience requirement
and should not be shortlisted.

Schedule an interview for Rajesh Krishnamurthy with
James Anderson (Engineering Lead) as the interviewer,
date March 24, 2025.

FINAL HIRING DECISION:
  • OFFER — Rajesh Krishnamurthy
    Rationale: Rajesh's Kubernetes migration experience is
    critical for our upcoming platform overhaul. His 8 years
    of hands-on DevOps work and AWS certification make him
    the strongest candidate.

  • REJECT — Elena Vasquez-Torres
    Rationale: While her profile was strong and her GCP
    expertise is valuable, Rajesh's specific Kubernetes
    migration experience is the priority for this role.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SECTION 4 — ONBOARDING DETAILS (RAJESH KRISHNAMURTHY)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

After the hire is completed in the system and Rajesh becomes
an employee, configure the following in his OrangeHRM profile:

  Job & Department
  ─────────────────
    Job Title:    Senior DevOps Engineer
    Department:   Engineering

  Work Contact Details
  ─────────────────────
    Work Email:   rajesh.krishnamurthy@gymcorp.com
    Work Phone:   646-555-0147

  Emergency Contact
  ─────────────────
    Name:         Priya Krishnamurthy
    Relationship: Spouse
    Home Phone:   646-555-0148

  Compensation
  ─────────────────
    Pay Grade:    Grade D - DevOps Senior
                  (Create this grade if it does not exist)
                  USD Minimum: $95,000
                  USD Maximum: $145,000
    Salary:       $120,000.00 USD

  Leave Entitlements (Current Calendar Year)
  ───────────────────────────────────────────
    Annual Leave:   20 days
    Sick Leave:     10 days

  Performance Review (90-Day Probationary)
  ────────────────────────────────────────
    Reviewer:       James Anderson (EMP001)
    Review Period:  April 1, 2025 – June 30, 2025
    Due Date:       July 15, 2025

═══════════════════════════════════════════════════════════════════
  END OF DIRECTIVE — Please complete all steps in sequence.
═══════════════════════════════════════════════════════════════════
DIRECTIVE

chown ga:ga "$DESKTOP_DIR/devops_hiring_directive.txt" 2>/dev/null || true
chmod 644 "$DESKTOP_DIR/devops_hiring_directive.txt"
log "Created hiring directive at $DESKTOP_DIR/devops_hiring_directive.txt"

# -------------------------------------------------------
# 10. Navigate browser to OrangeHRM Recruitment module
# -------------------------------------------------------
TARGET_URL="${ORANGEHRM_URL}/web/index.php/recruitment/viewCandidates"
ensure_orangehrm_logged_in "$TARGET_URL"

sleep 3
take_screenshot "$SCREENSHOT"

echo "=== end_to_end_hire_and_onboard task setup complete ==="
echo "Vacancy, candidate, employee, pay grade, and leave data cleared."
echo "Directive file created on Desktop. Browser navigated to Recruitment."
