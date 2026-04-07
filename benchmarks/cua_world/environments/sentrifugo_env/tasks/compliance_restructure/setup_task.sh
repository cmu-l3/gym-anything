#!/bin/bash
echo "=== Setting up compliance_restructure task ==="

source /workspace/scripts/task_utils.sh
wait_for_http "$SENTRIFUGO_URL" 60
date +%s > /tmp/task_start_timestamp

# ---- Clean up any prior run artifacts and ensure consistent starting state ----
log "Restoring initial state for compliance_restructure..."

# 1. Reset Department Name if it was renamed previously
sentrifugo_db_root_query "UPDATE main_departments SET deptname='DevOps & Infrastructure' WHERE deptname='Infrastructure & Cloud Operations';" 2>/dev/null || true

# 2. Delete Environmental Health & Safety if it exists from a prior run
sentrifugo_db_root_query "DELETE FROM main_departments WHERE deptcode='EHS';" 2>/dev/null || true

# 3. Reactivate Maintenance & Support if it was deactivated
sentrifugo_db_root_query "UPDATE main_departments SET isactive=1 WHERE deptname='Maintenance & Support';" 2>/dev/null || true

# 4. Scramble the Job Title Codes so the agent is forced to correct them
sentrifugo_db_root_query "UPDATE main_jobtitles SET jobtitlecode='SYS-ENG-00' WHERE jobtitlename='Systems Engineer';" 2>/dev/null || true
sentrifugo_db_root_query "UPDATE main_jobtitles SET jobtitlecode='NET-ADM-00' WHERE jobtitlename='Network Administrator';" 2>/dev/null || true
sentrifugo_db_root_query "UPDATE main_jobtitles SET jobtitlecode='MKT-SPC-00' WHERE jobtitlename='Marketing Specialist';" 2>/dev/null || true

# 5. Move target employees into Maintenance & Support
DEPT_MS_ID=$(sentrifugo_db_query "SELECT id FROM main_departments WHERE deptname='Maintenance & Support' LIMIT 1;" | tr -d '[:space:]')

if [ -n "$DEPT_MS_ID" ]; then
    for EMP in EMP009 EMP010 EMP014 EMP017; do
        UID=$(sentrifugo_db_query "SELECT id FROM main_users WHERE employeeId='${EMP}' LIMIT 1;" | tr -d '[:space:]')
        if [ -n "$UID" ]; then
            sentrifugo_db_root_query "UPDATE main_users SET department_id=${DEPT_MS_ID} WHERE id=${UID};" 2>/dev/null || true
            sentrifugo_db_root_query "UPDATE main_employees_summary SET department_id=${DEPT_MS_ID}, department_name='Maintenance & Support' WHERE user_id=${UID};" 2>/dev/null || true
            sentrifugo_db_root_query "UPDATE main_employees SET department_id=${DEPT_MS_ID} WHERE user_id=${UID};" 2>/dev/null || true
        fi
    done
    log "Moved EMP009, EMP010, EMP014, EMP017 to Maintenance & Support"
else
    log "ERROR: Could not find Maintenance & Support department ID."
fi

# ---- Create the Corrective Action Notice on the Desktop ----
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/compliance_corrective_action.txt << 'NOTICE'
DEPARTMENT OF ENERGY — REGULATORY COMPLIANCE DIVISION
CORRECTIVE ACTION NOTICE — CA-2026-00417

Facility: GreenPower Biomass Energy Plant
Inspection Date: January 15, 2026
Response Deadline: February 15, 2026

FINDINGS AND REQUIRED ACTIONS:

1. DEPARTMENT NOMENCLATURE (DOE Reg. §4.2.1)
   The "DevOps & Infrastructure" department must be renamed exactly to 
   "Infrastructure & Cloud Operations" to align with DOE facility 
   classification standards for energy sector IT operations.

2. MANDATORY SAFETY DEPARTMENT (DOE Reg. §7.1.3)
   All Category-B energy facilities must maintain a dedicated 
   "Environmental Health & Safety" department (code: EHS). 
   This department must be created immediately.

3. DEPARTMENT CONSOLIDATION (DOE Reg. §4.2.5)
   The "Maintenance & Support" department does not meet minimum 
   staffing thresholds for standalone classification. This department 
   must be dissolved and its personnel reassigned as follows:
   
   - Kevin Brown (EMP009) → Infrastructure & Cloud Operations
   - Amanda Davis (EMP010) → Infrastructure & Cloud Operations  
   - Andrew Thomas (EMP017) → Environmental Health & Safety
   - Christopher Lee (EMP014) → Engineering

   After all personnel are reassigned, deactivate (do not delete) 
   the Maintenance & Support department for recordkeeping purposes.

4. JOB TITLE CODE STANDARDIZATION (DOE Reg. §5.3.2)
   The following job titles must use Standard Occupational 
   Classification (SOC) codes. Update them to match exactly:
   
   - Systems Engineer → code: 17-2199
   - Network Administrator → code: 15-1244
   - Marketing Specialist → code: 13-1161

All changes must be reflected in the facility's Human Resource 
Management System within the compliance deadline.

Issued by: Regional Compliance Officer, DOE Western Division
NOTICE

chown ga:ga /home/ga/Desktop/compliance_corrective_action.txt
log "Compliance Corrective Action Notice created at ~/Desktop/compliance_corrective_action.txt"

# ---- Navigate to Departments page ----
ensure_sentrifugo_logged_in "${SENTRIFUGO_URL}/departments"
sleep 3

# Take an initial screenshot proving the setup
take_screenshot /tmp/task_start_screenshot.png

log "Task ready: Start state initialized."
echo "=== compliance_restructure task setup complete ==="