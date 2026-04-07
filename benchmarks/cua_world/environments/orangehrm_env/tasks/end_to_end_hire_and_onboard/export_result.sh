#!/bin/bash
# Export end-to-end hire and onboard task results for verification.
# Queries: vacancy, candidates, candidate statuses, employee record,
# job title, department, work email, emergency contact, pay grade,
# salary, leave entitlements, performance review.

set -euo pipefail
echo "=== Exporting end_to_end_hire_and_onboard results ==="

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/end_to_end_hire_and_onboard_result.json"
rm -f "$RESULT_FILE" 2>/dev/null || true

# -------------------------------------------------------
# 1. Vacancy check
# -------------------------------------------------------
VACANCY_COUNT=$(orangehrm_db_query "SELECT COUNT(*) FROM ohrm_job_vacancy WHERE name LIKE '%Senior DevOps Engineer%';" | tr -d '[:space:]')
log "Vacancy count: $VACANCY_COUNT"

# -------------------------------------------------------
# 2. Candidate existence checks
# -------------------------------------------------------
RAJESH_CAND=$(orangehrm_db_query "SELECT COUNT(*) FROM ohrm_job_candidate WHERE first_name='Rajesh' AND last_name='Krishnamurthy';" | tr -d '[:space:]')
ELENA_CAND=$(orangehrm_db_query "SELECT COUNT(*) FROM ohrm_job_candidate WHERE first_name='Elena' AND last_name='Vasquez-Torres';" | tr -d '[:space:]')
THOMAS_CAND=$(orangehrm_db_query "SELECT COUNT(*) FROM ohrm_job_candidate WHERE first_name='Thomas' AND last_name='Andersson';" | tr -d '[:space:]')
log "Candidates: Rajesh=$RAJESH_CAND Elena=$ELENA_CAND Thomas=$THOMAS_CAND"

# -------------------------------------------------------
# 3. Candidate-vacancy status
# -------------------------------------------------------
RAJESH_CV_STATUS=$(orangehrm_db_query "
    SELECT cv.status FROM ohrm_job_candidate_vacancy cv
    INNER JOIN ohrm_job_candidate c ON cv.candidate_id=c.id
    WHERE c.first_name='Rajesh' AND c.last_name='Krishnamurthy'
    ORDER BY cv.id DESC LIMIT 1;
" 2>/dev/null | tr -d '[:space:]' || echo "NONE")

ELENA_CV_STATUS=$(orangehrm_db_query "
    SELECT cv.status FROM ohrm_job_candidate_vacancy cv
    INNER JOIN ohrm_job_candidate c ON cv.candidate_id=c.id
    WHERE c.first_name='Elena' AND c.last_name='Vasquez-Torres'
    ORDER BY cv.id DESC LIMIT 1;
" 2>/dev/null | tr -d '[:space:]' || echo "NONE")

# Also check the candidate-level status (int field in ohrm_job_candidate)
RAJESH_STATUS_LABEL=$(orangehrm_db_query "
    SELECT COALESCE(c.status, 0)
    FROM ohrm_job_candidate c
    WHERE c.first_name='Rajesh' AND c.last_name='Krishnamurthy'
    LIMIT 1;
" 2>/dev/null | tr -d '\n' || echo "0")

log "Rajesh CV status: $RAJESH_CV_STATUS (label: $RAJESH_STATUS_LABEL)"
log "Elena CV status: $ELENA_CV_STATUS"

# -------------------------------------------------------
# 4. Employee record for Rajesh
# -------------------------------------------------------
RAJESH_EMP_EXISTS=$(orangehrm_db_query "SELECT COUNT(*) FROM hs_hr_employee WHERE emp_firstname='Rajesh' AND emp_lastname='Krishnamurthy' AND purged_at IS NULL;" | tr -d '[:space:]')
RAJESH_EMP_NUM=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE emp_firstname='Rajesh' AND emp_lastname='Krishnamurthy' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]' || echo "")

log "Rajesh employee exists: $RAJESH_EMP_EXISTS (emp_number=$RAJESH_EMP_NUM)"

# Initialize defaults
RAJESH_JOB_TITLE=""
RAJESH_DEPT=""
RAJESH_WORK_EMAIL=""
RAJESH_WORK_PHONE=""
RAJESH_EC_COUNT="0"
RAJESH_EC_NAME=""
RAJESH_EC_RELATIONSHIP=""
RAJESH_EC_PHONE=""
RAJESH_SALARY="0"
RAJESH_PAY_GRADE=""
RAJESH_AL_DAYS="0"
RAJESH_SL_DAYS="0"
RAJESH_REVIEW_COUNT="0"
RAJESH_REVIEW_REVIEWER_EMPID=""
RAJESH_REVIEW_START=""
RAJESH_REVIEW_END=""
RAJESH_REVIEW_DUE=""

if [ -n "$RAJESH_EMP_NUM" ] && [ "$RAJESH_EMP_NUM" != "0" ]; then
    # 5. Job title and department
    RAJESH_JOB_TITLE=$(orangehrm_db_query "
        SELECT COALESCE(jt.job_title, '')
        FROM hs_hr_employee e
        LEFT JOIN ohrm_job_title jt ON e.job_title_code=jt.id
        WHERE e.emp_number=$RAJESH_EMP_NUM;
    " 2>/dev/null | tr -d '\n' || echo "")

    RAJESH_DEPT=$(orangehrm_db_query "
        SELECT COALESCE(s.name, '')
        FROM hs_hr_employee e
        LEFT JOIN ohrm_subunit s ON e.work_unit=s.id
        WHERE e.emp_number=$RAJESH_EMP_NUM;
    " 2>/dev/null | tr -d '\n' || echo "")

    # 6. Work contact details
    RAJESH_WORK_EMAIL=$(orangehrm_db_query "SELECT COALESCE(emp_work_email, '') FROM hs_hr_employee WHERE emp_number=$RAJESH_EMP_NUM;" 2>/dev/null | tr -d '\n' || echo "")
    RAJESH_WORK_PHONE=$(orangehrm_db_query "SELECT COALESCE(emp_work_telephone, '') FROM hs_hr_employee WHERE emp_number=$RAJESH_EMP_NUM;" 2>/dev/null | tr -d '\n' || echo "")

    # 7. Emergency contact
    RAJESH_EC_COUNT=$(orangehrm_db_query "SELECT COUNT(*) FROM hs_hr_emp_emergency_contacts WHERE emp_number=$RAJESH_EMP_NUM;" | tr -d '[:space:]')
    RAJESH_EC_NAME=$(orangehrm_db_query "SELECT COALESCE(eec_name, '') FROM hs_hr_emp_emergency_contacts WHERE emp_number=$RAJESH_EMP_NUM LIMIT 1;" 2>/dev/null | tr -d '\n' || echo "")
    RAJESH_EC_RELATIONSHIP=$(orangehrm_db_query "SELECT COALESCE(eec_relationship, '') FROM hs_hr_emp_emergency_contacts WHERE emp_number=$RAJESH_EMP_NUM LIMIT 1;" 2>/dev/null | tr -d '\n' || echo "")
    RAJESH_EC_PHONE=$(orangehrm_db_query "SELECT COALESCE(eec_home_no, '') FROM hs_hr_emp_emergency_contacts WHERE emp_number=$RAJESH_EMP_NUM LIMIT 1;" 2>/dev/null | tr -d '\n' || echo "")

    # 8. Pay grade and salary
    RAJESH_SALARY=$(orangehrm_db_query "SELECT COALESCE(ebsal_basic_salary, 0) FROM hs_hr_emp_basicsalary WHERE emp_number=$RAJESH_EMP_NUM LIMIT 1;" 2>/dev/null | tr -d '[:space:]' || echo "0")
    RAJESH_PAY_GRADE=$(orangehrm_db_query "
        SELECT COALESCE(pg.name, '')
        FROM hs_hr_emp_basicsalary bs
        LEFT JOIN ohrm_pay_grade pg ON bs.sal_grd_code=pg.id
        WHERE bs.emp_number=$RAJESH_EMP_NUM
        LIMIT 1;
    " 2>/dev/null | tr -d '\n' || echo "")

    # 9. Leave entitlements
    AL_TYPE_ID=$(orangehrm_db_query "SELECT id FROM ohrm_leave_type WHERE name='Annual Leave' AND deleted=0 LIMIT 1;" | tr -d '[:space:]')
    SL_TYPE_ID=$(orangehrm_db_query "SELECT id FROM ohrm_leave_type WHERE name='Sick Leave' AND deleted=0 LIMIT 1;" | tr -d '[:space:]')
    CURRENT_YEAR=$(date +%Y)

    if [ -n "$AL_TYPE_ID" ]; then
        RAJESH_AL_DAYS=$(orangehrm_db_query "
            SELECT COALESCE(SUM(no_of_days), 0)
            FROM ohrm_leave_entitlement
            WHERE emp_number=$RAJESH_EMP_NUM
              AND leave_type_id=$AL_TYPE_ID
              AND deleted=0
              AND to_date >= '${CURRENT_YEAR}-01-01'
              AND from_date <= '${CURRENT_YEAR}-12-31';
        " | tr -d '[:space:]')
    fi

    if [ -n "$SL_TYPE_ID" ]; then
        RAJESH_SL_DAYS=$(orangehrm_db_query "
            SELECT COALESCE(SUM(no_of_days), 0)
            FROM ohrm_leave_entitlement
            WHERE emp_number=$RAJESH_EMP_NUM
              AND leave_type_id=$SL_TYPE_ID
              AND deleted=0
              AND to_date >= '${CURRENT_YEAR}-01-01'
              AND from_date <= '${CURRENT_YEAR}-12-31';
        " | tr -d '[:space:]')
    fi

    # 10. Performance review
    RAJESH_REVIEW_COUNT=$(orangehrm_db_query "SELECT COUNT(*) FROM ohrm_performance_review WHERE employee_number=$RAJESH_EMP_NUM;" | tr -d '[:space:]')
    RAJESH_REVIEW_REVIEWER_EMPID=$(orangehrm_db_query "
        SELECT COALESCE(e.employee_id, '')
        FROM ohrm_performance_review pr
        INNER JOIN ohrm_reviewer rv ON rv.review_id=pr.id
        INNER JOIN hs_hr_employee e ON rv.employee_number=e.emp_number
        WHERE pr.employee_number=$RAJESH_EMP_NUM
        LIMIT 1;
    " 2>/dev/null | tr -d '\n' || echo "")
    RAJESH_REVIEW_START=$(orangehrm_db_query "
        SELECT COALESCE(work_period_start, '')
        FROM ohrm_performance_review
        WHERE employee_number=$RAJESH_EMP_NUM
        LIMIT 1;
    " 2>/dev/null | tr -d '\n' || echo "")
    RAJESH_REVIEW_END=$(orangehrm_db_query "
        SELECT COALESCE(work_period_end, '')
        FROM ohrm_performance_review
        WHERE employee_number=$RAJESH_EMP_NUM
        LIMIT 1;
    " 2>/dev/null | tr -d '\n' || echo "")
    RAJESH_REVIEW_DUE=$(orangehrm_db_query "
        SELECT COALESCE(due_date, '')
        FROM ohrm_performance_review
        WHERE employee_number=$RAJESH_EMP_NUM
        LIMIT 1;
    " 2>/dev/null | tr -d '\n' || echo "")
fi

# -------------------------------------------------------
# 11. Pay grade existence and range
# -------------------------------------------------------
PAY_GRADE_EXISTS=$(orangehrm_db_query "SELECT COUNT(*) FROM ohrm_pay_grade WHERE name='Grade D - DevOps Senior';" | tr -d '[:space:]')
PAY_GRADE_MIN="0"
PAY_GRADE_MAX="0"
PG_ID=$(orangehrm_db_query "SELECT id FROM ohrm_pay_grade WHERE name='Grade D - DevOps Senior' LIMIT 1;" | tr -d '[:space:]')
if [ -n "$PG_ID" ]; then
    PG_RANGE=$(orangehrm_db_query "
        SELECT COALESCE(min_salary, 0), COALESCE(max_salary, 0)
        FROM ohrm_pay_grade_currency
        WHERE pay_grade_id=$PG_ID AND currency_id='USD'
        LIMIT 1;
    " 2>/dev/null | tr '\t' '|' | tr -d '\n')
    PAY_GRADE_MIN=$(echo "$PG_RANGE" | cut -d'|' -f1 | xargs)
    PAY_GRADE_MAX=$(echo "$PG_RANGE" | cut -d'|' -f2 | xargs)
fi

log "Pay grade: exists=$PAY_GRADE_EXISTS min=$PAY_GRADE_MIN max=$PAY_GRADE_MAX"

# -------------------------------------------------------
# 12. Take final screenshot
# -------------------------------------------------------
take_screenshot /tmp/end_to_end_hire_and_onboard_final.png 2>/dev/null || true

# -------------------------------------------------------
# 13. Build and write result JSON
# -------------------------------------------------------
safe_write_result "{
  \"vacancy_exists\": ${VACANCY_COUNT:-0},
  \"rajesh_candidate_exists\": ${RAJESH_CAND:-0},
  \"elena_candidate_exists\": ${ELENA_CAND:-0},
  \"thomas_candidate_exists\": ${THOMAS_CAND:-0},
  \"rajesh_cv_status\": \"${RAJESH_CV_STATUS}\",
  \"rajesh_status_label\": \"${RAJESH_STATUS_LABEL}\",
  \"elena_cv_status\": \"${ELENA_CV_STATUS}\",
  \"rajesh_employee_exists\": ${RAJESH_EMP_EXISTS:-0},
  \"rajesh_job_title\": \"${RAJESH_JOB_TITLE}\",
  \"rajesh_department\": \"${RAJESH_DEPT}\",
  \"rajesh_work_email\": \"${RAJESH_WORK_EMAIL}\",
  \"rajesh_work_phone\": \"${RAJESH_WORK_PHONE}\",
  \"rajesh_ec_count\": ${RAJESH_EC_COUNT:-0},
  \"rajesh_ec_name\": \"${RAJESH_EC_NAME}\",
  \"rajesh_ec_relationship\": \"${RAJESH_EC_RELATIONSHIP}\",
  \"rajesh_ec_phone\": \"${RAJESH_EC_PHONE}\",
  \"rajesh_salary\": \"${RAJESH_SALARY:-0}\",
  \"rajesh_pay_grade\": \"${RAJESH_PAY_GRADE}\",
  \"rajesh_al_days\": \"${RAJESH_AL_DAYS:-0}\",
  \"rajesh_sl_days\": \"${RAJESH_SL_DAYS:-0}\",
  \"rajesh_review_count\": ${RAJESH_REVIEW_COUNT:-0},
  \"rajesh_review_reviewer_empid\": \"${RAJESH_REVIEW_REVIEWER_EMPID}\",
  \"rajesh_review_start\": \"${RAJESH_REVIEW_START}\",
  \"rajesh_review_end\": \"${RAJESH_REVIEW_END}\",
  \"rajesh_review_due\": \"${RAJESH_REVIEW_DUE}\",
  \"pay_grade_exists\": ${PAY_GRADE_EXISTS:-0},
  \"pay_grade_min\": \"${PAY_GRADE_MIN:-0}\",
  \"pay_grade_max\": \"${PAY_GRADE_MAX:-0}\",
  \"screenshot_path\": \"/tmp/end_to_end_hire_and_onboard_final.png\"
}" "$RESULT_FILE"

echo "=== Export complete: $RESULT_FILE ==="
cat "$RESULT_FILE"
