#!/bin/bash
echo "=== Setting up reporting_realignment task ==="

source /workspace/scripts/task_utils.sh
wait_for_http "$SENTRIFUGO_URL" 60
date +%s > /tmp/task_start_time

# Helper to cleanly get IDs
get_uid() {
    sentrifugo_db_query "SELECT id FROM main_users WHERE employeeId='$1' LIMIT 1;" | tr -d '[:space:]'
}

# ---- Clean up prior run artifacts ----
sentrifugo_db_root_query "UPDATE main_jobtitles SET isactive=0 WHERE jobtitlename='Team Lead';" 2>/dev/null || true

# ---- Reset Managers to baseline ----
UID_001=$(get_uid 'EMP001')
UID_006=$(get_uid 'EMP006')

for EMP in EMP007 EMP009; do
    UID=$(get_uid "$EMP")
    if [ -n "$UID" ] && [ -n "$UID_001" ]; then
        sentrifugo_db_root_query "UPDATE main_employees_summary SET reporting_manager=${UID_001} WHERE user_id=${UID};" 2>/dev/null || true
    fi
done

for EMP in EMP011 EMP014; do
    UID=$(get_uid "$EMP")
    if [ -n "$UID" ] && [ -n "$UID_006" ]; then
        sentrifugo_db_root_query "UPDATE main_employees_summary SET reporting_manager=${UID_006} WHERE user_id=${UID};" 2>/dev/null || true
    fi
done

# ---- Reset Departments to baseline ----
DEPT_QA=$(sentrifugo_db_query "SELECT id FROM main_departments WHERE deptname='Quality Assurance' LIMIT 1;" | tr -d '[:space:]')
DEPT_FIN=$(sentrifugo_db_query "SELECT id FROM main_departments WHERE deptname='Finance & Accounting' LIMIT 1;" | tr -d '[:space:]')
UID_010=$(get_uid 'EMP010')
UID_016=$(get_uid 'EMP016')

if [ -n "$UID_010" ] && [ -n "$DEPT_QA" ]; then
    sentrifugo_db_root_query "UPDATE main_users SET department_id=${DEPT_QA} WHERE id=${UID_010};" 2>/dev/null || true
    sentrifugo_db_root_query "UPDATE main_employees_summary SET department_id=${DEPT_QA}, department_name='Quality Assurance' WHERE user_id=${UID_010};" 2>/dev/null || true
fi

if [ -n "$UID_016" ] && [ -n "$DEPT_FIN" ]; then
    sentrifugo_db_root_query "UPDATE main_users SET department_id=${DEPT_FIN} WHERE id=${UID_016};" 2>/dev/null || true
    sentrifugo_db_root_query "UPDATE main_employees_summary SET department_id=${DEPT_FIN}, department_name='Finance & Accounting' WHERE user_id=${UID_016};" 2>/dev/null || true
fi

# ---- Reset Job Title to baseline ----
JT_SWE_SR=$(sentrifugo_db_query "SELECT id FROM main_jobtitles WHERE jobtitlename='Senior Software Engineer' LIMIT 1;" | tr -d '[:space:]')
UID_017=$(get_uid 'EMP017')

if [ -n "$UID_017" ] && [ -n "$JT_SWE_SR" ]; then
    sentrifugo_db_root_query "UPDATE main_users SET jobtitle_id=${JT_SWE_SR} WHERE id=${UID_017};" 2>/dev/null || true
    sentrifugo_db_root_query "UPDATE main_employees_summary SET jobtitle_id=${JT_SWE_SR}, jobtitle_name='Senior Software Engineer' WHERE user_id=${UID_017};" 2>/dev/null || true
fi

# ---- Drop the restructuring memo on the Desktop ----
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/restructuring_memo.txt << 'EOF'
============================================================
  CONFIDENTIAL — Q3 2026 MANAGEMENT RESTRUCTURING DIRECTIVE
============================================================

TO:   HR Administration
FROM: VP of Operations
DATE: 2026-07-01
RE:   Immediate reporting and departmental changes

Please implement the following changes in Sentrifugo HRMS
effective immediately.

--- SECTION A: REPORTING MANAGER REASSIGNMENTS ---

1. Robert Taylor (EMP007, Data Science)
   Current manager: James Anderson (EMP001)
   New manager:     Michael Chen (EMP003)

2. Christopher Lee (EMP009, DevOps & Infrastructure)
   Current manager: James Anderson (EMP001)
   New manager:     Kevin Robinson (EMP015)

3. Ryan Garcia (EMP011, Marketing)
   Current manager: Jessica Liu (EMP006)
   New manager:     David Kim (EMP005)

4. Stephanie Thomas (EMP014, Sales)
   Current manager: Jessica Liu (EMP006)
   New manager:     Amanda White (EMP008)

--- SECTION B: DEPARTMENT TRANSFERS ---

5. Melissa Brown (EMP010)
   Current department: Quality Assurance
   New department:     Engineering

6. Ashley Harris (EMP016)
   Current department: Finance & Accounting
   New department:     Data Science

--- SECTION C: TITLE CHANGES ---

7. Create the new job title "Team Lead" in the system.

8. Brandon Clark (EMP017)
   Current title: Senior Software Engineer
   New title:     Team Lead

============================================================
Please confirm all changes are reflected in the system.
============================================================
EOF
chown ga:ga /home/ga/Desktop/restructuring_memo.txt

# Record initial db state for anti-gaming checks
docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -B -e "
SELECT u.employeeId, es.reporting_manager, u.department_id, u.jobtitle_id 
FROM main_users u JOIN main_employees_summary es ON u.id = es.user_id 
WHERE u.employeeId IN ('EMP007', 'EMP009', 'EMP011', 'EMP014', 'EMP010', 'EMP016', 'EMP017');
" > /tmp/initial_db_state.txt 2>/dev/null || true

# ---- Navigate to employee list and take start screenshot ----
ensure_sentrifugo_logged_in "${SENTRIFUGO_URL}/index.php/employee"
sleep 3
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="