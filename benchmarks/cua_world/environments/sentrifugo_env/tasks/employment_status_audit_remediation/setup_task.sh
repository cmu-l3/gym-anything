#!/bin/bash
echo "=== Setting up employment_status_audit_remediation task ==="

source /workspace/scripts/task_utils.sh

# Wait for application to be ready
wait_for_http "$SENTRIFUGO_URL" 60

# Record task start timestamp (anti-gaming check)
date +%s > /tmp/task_start_time.txt

# =====================================================================
# Clean up prior run artifacts to ensure clean initial state
# =====================================================================

# 1. Remove the four target employment statuses if they exist
for STATUS in "Part-Time Regular" "Contract - Fixed Term" "Seasonal Worker" "Intern - Paid"; do
    sentrifugo_db_root_query "DELETE FROM main_employmentstatus WHERE workcodename='${STATUS}';" 2>/dev/null || true
done
log "Cleaned up target employment statuses."

# 2. Reset the 6 target employees to a default employment type (1 = Full Time / Confirmed)
for EMPID in EMP005 EMP008 EMP010 EMP014 EMP016 EMP019; do
    sentrifugo_db_root_query "UPDATE main_users SET employementtype=1 WHERE employeeId='${EMPID}';" 2>/dev/null || true
done
log "Reset employment types for target employees."

# 3. Remove the 'Unpaid Personal Leave' type if it exists
sentrifugo_db_root_query "UPDATE main_employeeleavetypes SET isactive=0 WHERE leavecode='UPL' OR leavetype='Unpaid Personal Leave';" 2>/dev/null || true
log "Cleaned up Unpaid Personal Leave artifact."

# =====================================================================
# Prepare task environment
# =====================================================================

# Drop the manifest document on the Desktop
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/dol_classification_manifest.txt << 'MANIFEST'
=========================================================
DEPARTMENT OF LABOR - WORKFORCE CLASSIFICATION MANIFEST
Company: Sentrifugo Corp
Audit Reference: DOL-2026-0417
Prepared by: Regional Compliance Office
=========================================================

SECTION A: REQUIRED EMPLOYMENT STATUS TYPES
-------------------------------------------
The HRMS must contain the following active employment statuses.
Create any that do not already exist:

  1. Full-Time (may already exist)
  2. Part-Time Regular (NEW - create this)
  3. Contract - Fixed Term (NEW - create this)
  4. Seasonal Worker (NEW - create this)
  5. Intern - Paid (NEW - create this)

SECTION B: EMPLOYEE CLASSIFICATION CORRECTIONS
-----------------------------------------------
The following employees are currently misclassified.
Update their employment status to match:

  EMP005 - David Kim          -> Part-Time Regular
  EMP008 - Robert Chen        -> Contract - Fixed Term
  EMP010 - Michelle White     -> Part-Time Regular
  EMP014 - Brandon Lee        -> Seasonal Worker
  EMP016 - Aisha Patel        -> Intern - Paid
  EMP019 - Tyler Moore        -> Contract - Fixed Term

SECTION C: LEAVE TYPE REQUIREMENT
-------------------------------------------
Create the following leave type for contract/seasonal workers:

  Name: Unpaid Personal Leave
  Leave Code: UPL
  Number of Days: 0

This zero-day leave type is required for audit trail purposes
to formally document that contract and seasonal workers have
no paid personal leave entitlement.

=========================================================
DEADLINE: Immediate - Complete before audit date
=========================================================
MANIFEST
chown ga:ga /home/ga/Desktop/dol_classification_manifest.txt
log "Created dol_classification_manifest.txt on Desktop."

# Ensure Firefox is open and logged in to Sentrifugo dashboard
ensure_sentrifugo_logged_in "${SENTRIFUGO_URL}/dashboard"
sleep 3

# Take an initial screenshot to confirm starting state
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="