#!/bin/bash
echo "=== Setting up expat_immigration_compliance task ==="

source /workspace/scripts/task_utils.sh
wait_for_http "$SENTRIFUGO_URL" 60

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# =====================================================================
# 1. Clean up any existing immigration records for target employees
# =====================================================================
log "Cleaning up prior run artifacts..."

for EMPID in EMP012 EMP018 EMP019; do
    UID_VAL=$(docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -B -e "SELECT id FROM main_users WHERE employeeId='${EMPID}' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
    if [ -n "$UID_VAL" ]; then
        docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -e "DELETE FROM main_empimmigration WHERE user_id=${UID_VAL};" 2>/dev/null || true
        log "Removed existing immigration records for ${EMPID} (UID: ${UID_VAL})"
    fi
done

# =====================================================================
# 2. Create the HR Audit Document on the Desktop
# =====================================================================
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/expat_immigration_audit.txt << 'EOF'
====================================================================
GLOBAL MOBILITY & IMMIGRATION AUDIT - Q1 2026
CONFIDENTIAL HR DATA
====================================================================
Instructions: Update the HRMS Immigration records for the following 
expatriate personnel. Both Passport and Visa records must be created 
for each employee.

1. Employee: Jennifer Martinez (EMP012)
   [PASSPORT]
   Document Number: P8832910
   Issue Date: 2021-05-10
   Expiry Date: 2031-05-09
   Issued By: Mexico
   
   [VISA]
   Document Number: V9942011
   Issue Date: 2024-01-15
   Expiry Date: 2027-01-14
   Issued By: United States

2. Employee: Nicole Anderson (EMP018)
   [PASSPORT]
   Document Number: P7729102
   Issue Date: 2019-11-20
   Expiry Date: 2029-11-19
   Issued By: Canada
   
   [VISA]
   Document Number: V8810293
   Issue Date: 2025-06-01
   Expiry Date: 2028-05-31
   Issued By: United States

3. Employee: Tyler Moore (EMP019)
   [PASSPORT]
   Document Number: P6610293
   Issue Date: 2020-03-14
   Expiry Date: 2030-03-13
   Issued By: United Kingdom
   
   [VISA]
   Document Number: V7729304
   Issue Date: 2023-09-01
   Expiry Date: 2026-08-31
   Issued By: United States
====================================================================
EOF
chown ga:ga /home/ga/Desktop/expat_immigration_audit.txt
log "Audit document created at ~/Desktop/expat_immigration_audit.txt"

# =====================================================================
# 3. Launch Application
# =====================================================================
# Navigate to the Employee list page
ensure_sentrifugo_logged_in "${SENTRIFUGO_URL}/employee"
sleep 4

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

log "Task ready: Clean DB state, Audit document on Desktop, App running."
echo "=== expat_immigration_compliance task setup complete ==="