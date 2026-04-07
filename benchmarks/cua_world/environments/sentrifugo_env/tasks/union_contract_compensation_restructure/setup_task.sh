#!/bin/bash
echo "=== Setting up union_contract_compensation_restructure task ==="

source /workspace/scripts/task_utils.sh
wait_for_http "$SENTRIFUGO_URL" 60
date +%s > /tmp/task_start_time.txt

# Clean up prior runs
docker exec sentrifugo-db mysql -u sentrifugo -psentrifugo123 sentrifugo -N -B -e "
UPDATE main_paygrades SET isactive=0 WHERE paygradename='Technician - Tier 2';
UPDATE main_salarycomponents SET isactive=0 WHERE componentname IN ('Shift Differential', 'Union Dues - Local 104');
" 2>/dev/null || true

# Identify user IDs and column name to safely reset employee salary profiles
PAYGRADE_COL=$(docker exec sentrifugo-db mysql -u sentrifugo -psentrifugo123 sentrifugo -N -B -e "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME='main_empsalary' AND COLUMN_NAME LIKE '%paygrade%' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
if [ -z "$PAYGRADE_COL" ]; then PAYGRADE_COL="paygrade_id"; fi

EMP013_UID=$(docker exec sentrifugo-db mysql -u sentrifugo -psentrifugo123 sentrifugo -N -B -e "SELECT id FROM main_users WHERE employeeId='EMP013' AND isactive=1 LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
EMP018_UID=$(docker exec sentrifugo-db mysql -u sentrifugo -psentrifugo123 sentrifugo -N -B -e "SELECT id FROM main_users WHERE employeeId='EMP018' AND isactive=1 LIMIT 1;" 2>/dev/null | tr -d '[:space:]')

# Clear previous compensation linkages to allow the agent to set them up
if [ -n "$EMP013_UID" ] && [ -n "$EMP018_UID" ]; then
    docker exec sentrifugo-db mysql -u sentrifugo -psentrifugo123 sentrifugo -N -B -e "DELETE FROM main_empsalary WHERE user_id IN (${EMP013_UID}, ${EMP018_UID});" 2>/dev/null || true
fi

# Write CBA configuration file
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/cba_summary_2026.txt << 'EOF'
============================================================
COLLECTIVE BARGAINING AGREEMENT (CBA) SUMMARY - 2026
============================================================

TO:       HR Administration
FROM:     Plant Operations Manager
DATE:     January 15, 2026
SUBJECT:  New Technician Pay Structure & Union Dues

Please update the HRMS with the new compensation structure 
agreed upon in the recent CBA.

1. NEW PAY GRADE
   Name: Technician - Tier 2
   Minimum Salary: $50,000
   Maximum Salary: $70,000

2. NEW SALARY COMPONENTS
   Create the following new components in the system:
   
   a) Shift Differential
      Type: Earning
      Description: Additional pay for night/weekend shifts

   b) Union Dues - Local 104
      Type: Deduction
      Description: Monthly union dues deduction

3. EMPLOYEE REASSIGNMENT
   The following employees have been promoted to the new 
   "Technician - Tier 2" pay grade. Please update their 
   salary profiles immediately.

   - Daniel Wilson (EMP013)
   - Nicole Anderson (EMP018)

============================================================
EOF
chown ga:ga /home/ga/Desktop/cba_summary_2026.txt

# Navigate to Dashboard
ensure_sentrifugo_logged_in "${SENTRIFUGO_URL}/dashboard"
sleep 3
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="