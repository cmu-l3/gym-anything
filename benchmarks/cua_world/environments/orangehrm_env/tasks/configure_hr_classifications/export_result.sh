#!/bin/bash
set -e
echo "=== Exporting configure_hr_classifications results ==="

source /workspace/scripts/task_utils.sh

# ==============================================================================
# 1. Check Employment Statuses
# ==============================================================================
ES_1=$(orangehrm_db_query "SELECT COUNT(*) FROM ohrm_employment_status WHERE name='Intern - Paid';" | tr -d '[:space:]')
ES_2=$(orangehrm_db_query "SELECT COUNT(*) FROM ohrm_employment_status WHERE name='Intern - Unpaid';" | tr -d '[:space:]')
ES_3=$(orangehrm_db_query "SELECT COUNT(*) FROM ohrm_employment_status WHERE name='Contractor - Remote';" | tr -d '[:space:]')

# ==============================================================================
# 2. Check Job Categories
# ==============================================================================
JC_1=$(orangehrm_db_query "SELECT COUNT(*) FROM ohrm_job_category WHERE name='Remote Engineering';" | tr -d '[:space:]')
JC_2=$(orangehrm_db_query "SELECT COUNT(*) FROM ohrm_job_category WHERE name='Campus Recruitment';" | tr -d '[:space:]')

# ==============================================================================
# 3. Check Education Levels
# ==============================================================================
ED_1=$(orangehrm_db_query "SELECT COUNT(*) FROM ohrm_education WHERE name='Associates Degree - IT';" | tr -d '[:space:]')
ED_2=$(orangehrm_db_query "SELECT COUNT(*) FROM ohrm_education WHERE name='Coding Bootcamp Certificate';" | tr -d '[:space:]')

# ==============================================================================
# 4. Get Final Counts and Compare with Initial
# ==============================================================================
FINAL_EMP_STATUS_COUNT=$(orangehrm_db_query "SELECT COUNT(*) FROM ohrm_employment_status;" | tr -d '[:space:]')
FINAL_JOB_CAT_COUNT=$(orangehrm_db_query "SELECT COUNT(*) FROM ohrm_job_category;" | tr -d '[:space:]')
FINAL_EDU_COUNT=$(orangehrm_db_query "SELECT COUNT(*) FROM ohrm_education;" | tr -d '[:space:]')

# Read initial counts
INIT_EMP_STATUS_COUNT=$(jq -r '.emp_status_count' /tmp/initial_counts.json 2>/dev/null || echo "0")
INIT_JOB_CAT_COUNT=$(jq -r '.job_cat_count' /tmp/initial_counts.json 2>/dev/null || echo "0")
INIT_EDU_COUNT=$(jq -r '.edu_count' /tmp/initial_counts.json 2>/dev/null || echo "0")

# ==============================================================================
# 5. Capture Final Evidence
# ==============================================================================
take_screenshot /tmp/task_final.png

# ==============================================================================
# 6. Generate Result JSON
# ==============================================================================
RESULT_JSON="/tmp/task_result.json"

cat > "$RESULT_JSON" << EOF
{
  "employment_statuses": {
    "intern_paid": $((ES_1 > 0)),
    "intern_unpaid": $((ES_2 > 0)),
    "contractor_remote": $((ES_3 > 0))
  },
  "job_categories": {
    "remote_engineering": $((JC_1 > 0)),
    "campus_recruitment": $((JC_2 > 0))
  },
  "education_levels": {
    "associates_it": $((ED_1 > 0)),
    "coding_bootcamp": $((ED_2 > 0))
  },
  "counts": {
    "emp_status_delta": $((FINAL_EMP_STATUS_COUNT - INIT_EMP_STATUS_COUNT)),
    "job_cat_delta": $((FINAL_JOB_CAT_COUNT - INIT_JOB_CAT_COUNT)),
    "edu_delta": $((FINAL_EDU_COUNT - INIT_EDU_COUNT))
  },
  "timestamp": "$(date -Iseconds)"
}
EOF

# Set permissions for the python verifier to read
chmod 666 "$RESULT_JSON"

echo "Result exported to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export complete ==="