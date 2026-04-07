#!/bin/bash
echo "=== Setting up international_payroll_config task ==="

source /workspace/scripts/task_utils.sh
wait_for_http "$SENTRIFUGO_URL" 60

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# ---- Clean up prior run artifacts to ensure clean slate ----
log "Cleaning up any prior run artifacts..."

# Remove employees
for EMPID in EMP021 EMP022 EMP023; do
    UID_VAL=$(sentrifugo_db_query "SELECT id FROM main_users WHERE employeeId='${EMPID}' LIMIT 1;" | tr -d '[:space:]')
    if [ -n "$UID_VAL" ]; then
        sentrifugo_db_root_query "DELETE FROM main_employees_summary WHERE user_id=${UID_VAL};" 2>/dev/null || true
        sentrifugo_db_root_query "DELETE FROM main_employees WHERE user_id=${UID_VAL};" 2>/dev/null || true
        sentrifugo_db_root_query "DELETE FROM main_users WHERE id=${UID_VAL};" 2>/dev/null || true
    fi
done

# Remove department
sentrifugo_db_root_query "DELETE FROM main_departments WHERE deptname='International Programs';" 2>/dev/null || true

# Remove job titles
sentrifugo_db_root_query "DELETE FROM main_jobtitles WHERE jobtitlename IN ('Country Director', 'Regional Coordinator');" 2>/dev/null || true

# Remove currencies
sentrifugo_db_root_query "DELETE FROM main_currencies WHERE currencycode IN ('JPY', 'BRL', 'INR');" 2>/dev/null || true

# Remove pay frequencies
sentrifugo_db_root_query "DELETE FROM main_payfrequency WHERE payfrequency IN ('Semi-Monthly', 'Quarterly');" 2>/dev/null || true

# Remove prefixes
sentrifugo_db_root_query "DELETE FROM main_prefix WHERE prefix IN ('Dr.', 'Sra.', 'Sri');" 2>/dev/null || true

log "Cleanup complete"

# ---- Drop configuration document on Desktop ----
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/intl_payroll_config.txt << 'CONFIGDOC'
=============================================================
INTERNATIONAL EXPANSION - PAYROLL INFRASTRUCTURE CONFIGURATION
Prepared by: Finance & HR Joint Committee
Effective: FY2026-Q1
=============================================================

SECTION 1: CURRENCY CONFIGURATION
-----------------------------------
Navigate to Organization > Currencies and add:

| Currency Name          | Code | Symbol |
|------------------------|------|--------|
| Japanese Yen           | JPY  | ¥      |
| Brazilian Real         | BRL  | R$     |
| Indian Rupee           | INR  | ₹      |

SECTION 2: PAY FREQUENCY CONFIGURATION
-----------------------------------------
Navigate to Organization > Pay Frequency and add:
1. Semi-Monthly
2. Quarterly

SECTION 3: PREFIX CONFIGURATION
---------------------------------
Navigate to Organization > Prefix and add:
1. Dr.
2. Sra.
3. Sri

SECTION 4: DEPARTMENT CREATION
--------------------------------
Navigate to Organization > Departments and create:
  Department Name: International Programs

SECTION 5: JOB TITLE CREATION
--------------------------------
Navigate to Organization > Job Titles and create:
1. Country Director
2. Regional Coordinator

SECTION 6: NEW EMPLOYEE REGISTRATION
---------------------------------------
Navigate to Employees and register the following staff:

Employee 1:
  - Employee ID: EMP021
  - First Name: Yuki
  - Last Name: Tanaka
  - Prefix: Ms.
  - Department: International Programs
  - Job Title: Country Director
  - Email: yuki.tanaka@orgname.org

Employee 2:
  - Employee ID: EMP022
  - First Name: Fernanda
  - Last Name: Costa
  - Prefix: Sra.
  - Department: International Programs
  - Job Title: Regional Coordinator
  - Email: fernanda.costa@orgname.org

Employee 3:
  - Employee ID: EMP023
  - First Name: Arjun
  - Last Name: Mehta
  - Prefix: Sri
  - Department: International Programs
  - Job Title: Country Director
  - Email: arjun.mehta@orgname.org

=============================================================
END OF CONFIGURATION SPECIFICATION
=============================================================
CONFIGDOC

chown ga:ga /home/ga/Desktop/intl_payroll_config.txt
log "Configuration specification created at ~/Desktop/intl_payroll_config.txt"

# ---- Navigate to Sentrifugo Dashboard ----
ensure_sentrifugo_logged_in "${SENTRIFUGO_URL}/dashboard"
sleep 3
take_screenshot /tmp/task_initial.png

log "Task ready: Admin logged in, clean state verified, config file on desktop."
echo "=== Setup complete ==="