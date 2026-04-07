#!/bin/bash
# OrangeHRM Post-Start Hook: Start containers, run CLI installer, seed data, configure browser
set -euo pipefail

echo "=== Setting up OrangeHRM ==="

ORANGEHRM_DIR="/home/ga/orangehrm"
ORANGEHRM_URL="http://localhost:8000"
ORANGEHRM_LOGIN_URL="${ORANGEHRM_URL}/web/index.php/auth/login"
DB_HOST="orangehrm-db"
DB_NAME="orangehrm"
DB_USER="orangeuser"
DB_PASS="orangepass123"
DB_ROOT_PASS="rootpass123"
ADMIN_USER="admin"
ADMIN_PASS="Admin@OHrm2024!"
ADMIN_PASS_INSTALL="Admin1234!"  # Installer requires this; we change it post-install

# ============================================================
# Helper: poll HTTP endpoint
# ============================================================
wait_for_http() {
    local url="$1"
    local timeout_sec="${2:-600}"
    local elapsed=0
    echo "Waiting for HTTP: $url (timeout ${timeout_sec}s)"
    while [ "$elapsed" -lt "$timeout_sec" ]; do
        local code
        code=$(curl -sk -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || true)
        [ -z "$code" ] && code="000"
        if [ "$code" = "200" ] || [ "$code" = "302" ] || [ "$code" = "301" ]; then
            echo "HTTP ready after ${elapsed}s (HTTP $code)"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        echo "  waiting... ${elapsed}s (HTTP $code)"
    done
    echo "ERROR: Timeout waiting for HTTP at $url"
    return 1
}

# ============================================================
# Helper: run a DB query via docker exec
# ============================================================
db_root_query() {
    local query="$1"
    docker exec orangehrm-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" \
        -N -e "$query" 2>/dev/null
}

# ============================================================
# 1. Set up Docker Compose
# ============================================================
echo "Setting up Docker Compose..."
mkdir -p "$ORANGEHRM_DIR"
cp /workspace/config/docker-compose.yml "$ORANGEHRM_DIR/"
chown -R ga:ga "$ORANGEHRM_DIR"

# Authenticate with Docker Hub if credentials file exists
if [ -f /workspace/config/.dockerhub_credentials ]; then
    source /workspace/config/.dockerhub_credentials
    docker login -u "$DOCKERHUB_USER" -p "$DOCKERHUB_TOKEN" 2>/dev/null || true
fi

# ============================================================
# 2. Pull images and start containers
# ============================================================
cd "$ORANGEHRM_DIR"
echo "Pulling OrangeHRM images..."
docker compose pull

echo "Starting containers..."
docker compose up -d

echo "Container status:"
docker compose ps

# ============================================================
# 3. Wait for MariaDB to be healthy
# ============================================================
echo "Waiting for MariaDB..."
MARIADB_READY=false
for i in $(seq 1 60); do
    if docker exec orangehrm-db mysqladmin ping -h localhost -u root -p"$DB_ROOT_PASS" >/dev/null 2>&1; then
        echo "MariaDB ready after ${i}s"
        MARIADB_READY=true
        break
    fi
    sleep 2
done
if [ "$MARIADB_READY" != "true" ]; then
    echo "ERROR: MariaDB did not become ready"
    exit 1
fi

# Give MariaDB a moment to finish initialization
sleep 5

# ============================================================
# 4. Wait for OrangeHRM web server to respond
# ============================================================
# OrangeHRM starts Apache immediately; shows installer page initially
wait_for_http "$ORANGEHRM_URL" 120

# Extra wait for PHP/Apache to fully initialize
sleep 10

# ============================================================
# 5. Run OrangeHRM console installer
# ============================================================
echo "Running OrangeHRM CLI installer (console command approach)..."
INSTALL_LOG="/tmp/orangehrm_install.log"

# Check if already installed (idempotency)
EXISTING_TABLES=$(docker exec orangehrm-db mysql -u root -p"${DB_ROOT_PASS}" "${DB_NAME}" \
    -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}';" \
    2>/dev/null | tr -d '[:space:]' || echo "0")
echo "Existing tables in DB: ${EXISTING_TABLES}"

if [ "${EXISTING_TABLES:-0}" -ge 10 ]; then
    echo "OrangeHRM already installed (${EXISTING_TABLES} tables), skipping installer"
else
    echo "Running install:on-existing-database (${EXISTING_TABLES} tables in DB)..."
    # Pipe answers to each interactive prompt in order:
    #  1. License accept ("yes")
    #  2. DB hostname
    #  3. DB port (3306)
    #  4. DB name
    #  5. DB username (root for full DDL privileges during install)
    #  6. DB password
    #  7. Enable data encryption (empty = no/default)
    #  8. Organization name
    #  9. Country (must be lowercase full name)
    # 10. Language (empty = skip/default)
    # 11. Timezone group (empty = skip/default)
    # 12. Timezone (empty = skip/default)
    # 13. Admin first name
    # 14. Admin last name
    # 15. Admin email
    # 16. Contact number (empty = skip)
    # 17. Admin username
    # 18. Admin password
    # 19. Confirm admin password
    # 20. Registration consent ("no")
    # 21. Start installer (empty = yes/default)
    INSTALL_EXIT=0
    printf '%s\n' \
        "yes" \
        "${DB_HOST}" \
        "3306" \
        "${DB_NAME}" \
        "root" \
        "${DB_ROOT_PASS}" \
        "" \
        "GymAnything Corp" \
        "united states" \
        "" \
        "" \
        "" \
        "Admin" \
        "User" \
        "admin@gymhrcorp.com" \
        "" \
        "${ADMIN_USER}" \
        "${ADMIN_PASS_INSTALL}" \
        "${ADMIN_PASS_INSTALL}" \
        "no" \
        "" | \
    timeout 600 docker exec -i orangehrm bash -c \
        'cd /var/www/html && php installer/console install:on-existing-database' \
        > "$INSTALL_LOG" 2>&1 || INSTALL_EXIT=$?

    echo "CLI installer exit code: ${INSTALL_EXIT}"
    echo "--- Installer log (last 50 lines) ---"
    tail -n 50 "$INSTALL_LOG" || true

    # Verify installation: DB should now have tables
    TABLE_COUNT=$(docker exec orangehrm-db mysql -u root -p"${DB_ROOT_PASS}" "${DB_NAME}" \
        -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}';" \
        2>/dev/null | tr -d '[:space:]' || echo "0")
    echo "Tables in DB after install: ${TABLE_COUNT}"

    if [ "${TABLE_COUNT:-0}" -lt 10 ]; then
        echo "ERROR: OrangeHRM installation failed (only ${TABLE_COUNT} tables found)"
        echo "--- Full installer log ---"
        cat "$INSTALL_LOG" || true
        exit 1
    fi
    echo "OrangeHRM installation successful (${TABLE_COUNT} tables)"
fi

# Wait for OrangeHRM to finalize after install
sleep 15

# Change admin password to a strong one (installer uses weak "Admin1234!" which OrangeHRM
# flags as weak; we update to ADMIN_PASS and clear the forced-change entries).
# IMPORTANT: bcrypt hashes contain '$' chars that get expanded in shell double-quotes.
# Use a PHP script inside the container to avoid the quoting issue.
echo "Updating admin password to strong password..."
docker exec orangehrm php -r "
\$pdo = new PDO('mysql:host=orangehrm-db;dbname=${DB_NAME}', '${DB_USER}', '${DB_PASS}');
\$hash = password_hash('${ADMIN_PASS}', PASSWORD_BCRYPT);
\$stmt = \$pdo->prepare(\"UPDATE ohrm_user SET user_password=? WHERE user_name='${ADMIN_USER}'\");
\$stmt->execute([\$hash]);
echo 'Admin password updated: ' . \$stmt->rowCount() . \" rows\n\";
\$pdo->exec('DELETE FROM ohrm_enforce_password');
echo \"Cleared ohrm_enforce_password\n\";
" 2>/dev/null || echo "WARNING: Password update PHP command failed; login may require password change"

# Verify HTTP access
echo "Verifying HTTP access..."
INSTALL_OK=false
for i in $(seq 1 30); do
    code=$(curl -sk -o /dev/null -w "%{http_code}" "$ORANGEHRM_LOGIN_URL" 2>/dev/null || true)
    if [ "$code" = "200" ]; then
        echo "OrangeHRM login page accessible (HTTP $code)"
        INSTALL_OK=true
        break
    fi
    echo "  attempt $i: HTTP $code, waiting..."
    sleep 5
done

if [ "$INSTALL_OK" != "true" ]; then
    echo "WARNING: OrangeHRM login page not accessible - proceeding anyway"
fi

# ============================================================
# 6. Seed realistic HR data via direct SQL
# ============================================================
echo "Seeding HR data via direct SQL..."
CURRENT_YEAR=$(date +%Y)

# Write seed SQL (unquoted heredoc delimiter so bash expands CURRENT_YEAR;
# MySQL @variables are evaluated server-side and are not bash variables)
cat > /tmp/orangehrm_seed.sql << SQLEOF
-- =====================
-- Job Titles (8 titles)
-- Soft-delete any OrangeHRM defaults first to avoid duplicates, then insert ours.
-- =====================
UPDATE ohrm_job_title SET is_deleted=1 WHERE is_deleted=0;
INSERT INTO ohrm_job_title (job_title, is_deleted) VALUES ('Software Engineer', 0);
SET @jt_se = LAST_INSERT_ID();
INSERT INTO ohrm_job_title (job_title, is_deleted) VALUES ('HR Manager', 0);
SET @jt_hr = LAST_INSERT_ID();
INSERT INTO ohrm_job_title (job_title, is_deleted) VALUES ('Financial Analyst', 0);
SET @jt_fa = LAST_INSERT_ID();
INSERT INTO ohrm_job_title (job_title, is_deleted) VALUES ('Marketing Specialist', 0);
SET @jt_ms = LAST_INSERT_ID();
INSERT INTO ohrm_job_title (job_title, is_deleted) VALUES ('Operations Manager', 0);
SET @jt_om = LAST_INSERT_ID();
INSERT INTO ohrm_job_title (job_title, is_deleted) VALUES ('Product Manager', 0);
SET @jt_pm = LAST_INSERT_ID();
INSERT INTO ohrm_job_title (job_title, is_deleted) VALUES ('Data Scientist', 0);
SET @jt_ds = LAST_INSERT_ID();
INSERT INTO ohrm_job_title (job_title, is_deleted) VALUES ('UX Designer', 0);
SET @jt_ux = LAST_INSERT_ID();

-- =====================
-- Leave Types (5 types)
-- =====================
INSERT INTO ohrm_leave_type (name, deleted) VALUES ('Annual Leave', 0);
SET @lt_annual = LAST_INSERT_ID();
INSERT INTO ohrm_leave_type (name, deleted) VALUES ('Sick Leave', 0);
INSERT INTO ohrm_leave_type (name, deleted) VALUES ('Personal Leave', 0);
INSERT INTO ohrm_leave_type (name, deleted) VALUES ('Maternity Leave', 0);
INSERT INTO ohrm_leave_type (name, deleted) VALUES ('Paternity Leave', 0);

-- =====================
-- Subunits: 6 departments, flat under root (id=1, lft=1)
-- =====================
UPDATE ohrm_subunit SET rgt = 14 WHERE lft = 1;
INSERT INTO ohrm_subunit (name, unit_id, description, level, lft, rgt) VALUES
  ('Engineering',        'ENG', NULL, 1,  2,  3),
  ('Human Resources',    'HR',  NULL, 1,  4,  5),
  ('Finance',            'FIN', NULL, 1,  6,  7),
  ('Marketing',          'MKT', NULL, 1,  8,  9),
  ('Operations',         'OPS', NULL, 1, 10, 11),
  ('Product Management', 'PM',  NULL, 1, 12, 13);

-- =====================
-- Employees (20 employees; admin is emp_number=1)
-- =====================
INSERT INTO hs_hr_employee (employee_id, emp_lastname, emp_firstname, emp_work_email, emp_work_telephone, job_title_code, purged_at)
  VALUES ('EMP001', 'Anderson', 'James', 'james.anderson@gymhrco.com', '212-555-0101', @jt_se, NULL);
SET @e1 = LAST_INSERT_ID();

INSERT INTO hs_hr_employee (employee_id, emp_lastname, emp_firstname, emp_work_email, emp_work_telephone, job_title_code, purged_at)
  VALUES ('EMP002', 'Mitchell', 'Sarah', 'sarah.mitchell@gymhrco.com', '212-555-0102', @jt_hr, NULL);
SET @e2 = LAST_INSERT_ID();

INSERT INTO hs_hr_employee (employee_id, emp_lastname, emp_firstname, emp_work_email, emp_work_telephone, job_title_code, purged_at)
  VALUES ('EMP003', 'Nguyen', 'David', 'david.nguyen@gymhrco.com', '212-555-0103', @jt_fa, NULL);
SET @e3 = LAST_INSERT_ID();

INSERT INTO hs_hr_employee (employee_id, emp_lastname, emp_firstname, emp_work_email, emp_work_telephone, job_title_code, purged_at)
  VALUES ('EMP004', 'Rodriguez', 'Emily', 'emily.rodriguez@gymhrco.com', '212-555-0104', @jt_ms, NULL);
SET @e4 = LAST_INSERT_ID();

INSERT INTO hs_hr_employee (employee_id, emp_lastname, emp_firstname, emp_work_email, emp_work_telephone, job_title_code, purged_at)
  VALUES ('EMP005', 'Thompson', 'Michael', 'michael.thompson@gymhrco.com', '212-555-0105', @jt_om, NULL);
SET @e5 = LAST_INSERT_ID();

INSERT INTO hs_hr_employee (employee_id, emp_lastname, emp_firstname, emp_work_email, emp_work_telephone, job_title_code, purged_at)
  VALUES ('EMP006', 'Liu', 'Jessica', 'jessica.liu@gymhrco.com', '415-555-0106', @jt_pm, NULL);
SET @e6 = LAST_INSERT_ID();

INSERT INTO hs_hr_employee (employee_id, emp_lastname, emp_firstname, emp_work_email, emp_work_telephone, job_title_code, purged_at)
  VALUES ('EMP007', 'Patel', 'Robert', 'robert.patel@gymhrco.com', '415-555-0107', @jt_ds, NULL);
SET @e7 = LAST_INSERT_ID();

INSERT INTO hs_hr_employee (employee_id, emp_lastname, emp_firstname, emp_work_email, emp_work_telephone, job_title_code, purged_at)
  VALUES ('EMP008', 'Johnson', 'Ashley', 'ashley.johnson@gymhrco.com', '415-555-0108', @jt_ux, NULL);
SET @e8 = LAST_INSERT_ID();

INSERT INTO hs_hr_employee (employee_id, emp_lastname, emp_firstname, emp_work_email, emp_work_telephone, job_title_code, purged_at)
  VALUES ('EMP009', 'Williams', 'Christopher', 'christopher.williams@gymhrco.com', '212-555-0109', @jt_se, NULL);
SET @e9 = LAST_INSERT_ID();

INSERT INTO hs_hr_employee (employee_id, emp_lastname, emp_firstname, emp_work_email, emp_work_telephone, job_title_code, purged_at)
  VALUES ('EMP010', 'Davis', 'Amanda', 'amanda.davis@gymhrco.com', '212-555-0110', @jt_fa, NULL);
SET @e10 = LAST_INSERT_ID();

INSERT INTO hs_hr_employee (employee_id, emp_lastname, emp_firstname, emp_work_email, emp_work_telephone, job_title_code, purged_at)
  VALUES ('EMP011', 'Garcia', 'Matthew', 'matthew.garcia@gymhrco.com', '415-555-0111', @jt_ms, NULL);
SET @e11 = LAST_INSERT_ID();

INSERT INTO hs_hr_employee (employee_id, emp_lastname, emp_firstname, emp_work_email, emp_work_telephone, job_title_code, purged_at)
  VALUES ('EMP012', 'Martinez', 'Jennifer', 'jennifer.martinez@gymhrco.com', '212-555-0112', @jt_hr, NULL);
SET @e12 = LAST_INSERT_ID();

INSERT INTO hs_hr_employee (employee_id, emp_lastname, emp_firstname, emp_work_email, emp_work_telephone, job_title_code, purged_at)
  VALUES ('EMP013', 'Wilson', 'Daniel', 'daniel.wilson@gymhrco.com', '415-555-0113', @jt_se, NULL);
SET @e13 = LAST_INSERT_ID();

INSERT INTO hs_hr_employee (employee_id, emp_lastname, emp_firstname, emp_work_email, emp_work_telephone, job_title_code, purged_at)
  VALUES ('EMP014', 'Brown', 'Stephanie', 'stephanie.brown@gymhrco.com', '212-555-0114', @jt_om, NULL);
SET @e14 = LAST_INSERT_ID();

INSERT INTO hs_hr_employee (employee_id, emp_lastname, emp_firstname, emp_work_email, emp_work_telephone, job_title_code, purged_at)
  VALUES ('EMP015', 'Hernandez', 'Kevin', 'kevin.hernandez@gymhrco.com', '415-555-0115', @jt_pm, NULL);
SET @e15 = LAST_INSERT_ID();

INSERT INTO hs_hr_employee (employee_id, emp_lastname, emp_firstname, emp_work_email, emp_work_telephone, job_title_code, purged_at)
  VALUES ('EMP016', 'Lee', 'Rachel', 'rachel.lee@gymhrco.com', '415-555-0116', @jt_ds, NULL);
SET @e16 = LAST_INSERT_ID();

INSERT INTO hs_hr_employee (employee_id, emp_lastname, emp_firstname, emp_work_email, emp_work_telephone, job_title_code, purged_at)
  VALUES ('EMP017', 'Taylor', 'Brian', 'brian.taylor@gymhrco.com', '212-555-0117', @jt_fa, NULL);
SET @e17 = LAST_INSERT_ID();

INSERT INTO hs_hr_employee (employee_id, emp_lastname, emp_firstname, emp_work_email, emp_work_telephone, job_title_code, purged_at)
  VALUES ('EMP018', 'Anderson', 'Nicole', 'nicole.anderson@gymhrco.com', '415-555-0118', @jt_ux, NULL);
SET @e18 = LAST_INSERT_ID();

INSERT INTO hs_hr_employee (employee_id, emp_lastname, emp_firstname, emp_work_email, emp_work_telephone, job_title_code, purged_at)
  VALUES ('EMP019', 'Moore', 'Tyler', 'tyler.moore@gymhrco.com', '212-555-0119', @jt_ms, NULL);
SET @e19 = LAST_INSERT_ID();

INSERT INTO hs_hr_employee (employee_id, emp_lastname, emp_firstname, emp_work_email, emp_work_telephone, job_title_code, purged_at)
  VALUES ('EMP020', 'Jackson', 'Lauren', 'lauren.jackson@gymhrco.com', '212-555-0120', @jt_hr, NULL);
SET @e20 = LAST_INSERT_ID();

-- =====================
-- Leave Entitlements: Annual Leave (15 days) for all 20 employees
-- entitlement_type=1 means "Added"
-- Schema: emp_number, no_of_days, leave_type_id, from_date, to_date,
--         credited_date, days_used, entitlement_type, deleted, created_by_id
-- =====================
INSERT INTO ohrm_leave_entitlement
  (emp_number, no_of_days, leave_type_id, from_date, to_date, credited_date, days_used, entitlement_type, deleted, created_by_id)
VALUES
  (@e1,  15, @lt_annual, '${CURRENT_YEAR}-01-01', '${CURRENT_YEAR}-12-31', '${CURRENT_YEAR}-01-01', 0, 1, 0, 1),
  (@e2,  15, @lt_annual, '${CURRENT_YEAR}-01-01', '${CURRENT_YEAR}-12-31', '${CURRENT_YEAR}-01-01', 0, 1, 0, 1),
  (@e3,  15, @lt_annual, '${CURRENT_YEAR}-01-01', '${CURRENT_YEAR}-12-31', '${CURRENT_YEAR}-01-01', 0, 1, 0, 1),
  (@e4,  15, @lt_annual, '${CURRENT_YEAR}-01-01', '${CURRENT_YEAR}-12-31', '${CURRENT_YEAR}-01-01', 0, 1, 0, 1),
  (@e5,  15, @lt_annual, '${CURRENT_YEAR}-01-01', '${CURRENT_YEAR}-12-31', '${CURRENT_YEAR}-01-01', 0, 1, 0, 1),
  (@e6,  15, @lt_annual, '${CURRENT_YEAR}-01-01', '${CURRENT_YEAR}-12-31', '${CURRENT_YEAR}-01-01', 0, 1, 0, 1),
  (@e7,  15, @lt_annual, '${CURRENT_YEAR}-01-01', '${CURRENT_YEAR}-12-31', '${CURRENT_YEAR}-01-01', 0, 1, 0, 1),
  (@e8,  15, @lt_annual, '${CURRENT_YEAR}-01-01', '${CURRENT_YEAR}-12-31', '${CURRENT_YEAR}-01-01', 0, 1, 0, 1),
  (@e9,  15, @lt_annual, '${CURRENT_YEAR}-01-01', '${CURRENT_YEAR}-12-31', '${CURRENT_YEAR}-01-01', 0, 1, 0, 1),
  (@e10, 15, @lt_annual, '${CURRENT_YEAR}-01-01', '${CURRENT_YEAR}-12-31', '${CURRENT_YEAR}-01-01', 0, 1, 0, 1),
  (@e11, 15, @lt_annual, '${CURRENT_YEAR}-01-01', '${CURRENT_YEAR}-12-31', '${CURRENT_YEAR}-01-01', 0, 1, 0, 1),
  (@e12, 15, @lt_annual, '${CURRENT_YEAR}-01-01', '${CURRENT_YEAR}-12-31', '${CURRENT_YEAR}-01-01', 0, 1, 0, 1),
  (@e13, 15, @lt_annual, '${CURRENT_YEAR}-01-01', '${CURRENT_YEAR}-12-31', '${CURRENT_YEAR}-01-01', 0, 1, 0, 1),
  (@e14, 15, @lt_annual, '${CURRENT_YEAR}-01-01', '${CURRENT_YEAR}-12-31', '${CURRENT_YEAR}-01-01', 0, 1, 0, 1),
  (@e15, 15, @lt_annual, '${CURRENT_YEAR}-01-01', '${CURRENT_YEAR}-12-31', '${CURRENT_YEAR}-01-01', 0, 1, 0, 1),
  (@e16, 15, @lt_annual, '${CURRENT_YEAR}-01-01', '${CURRENT_YEAR}-12-31', '${CURRENT_YEAR}-01-01', 0, 1, 0, 1),
  (@e17, 15, @lt_annual, '${CURRENT_YEAR}-01-01', '${CURRENT_YEAR}-12-31', '${CURRENT_YEAR}-01-01', 0, 1, 0, 1),
  (@e18, 15, @lt_annual, '${CURRENT_YEAR}-01-01', '${CURRENT_YEAR}-12-31', '${CURRENT_YEAR}-01-01', 0, 1, 0, 1),
  (@e19, 15, @lt_annual, '${CURRENT_YEAR}-01-01', '${CURRENT_YEAR}-12-31', '${CURRENT_YEAR}-01-01', 0, 1, 0, 1),
  (@e20, 15, @lt_annual, '${CURRENT_YEAR}-01-01', '${CURRENT_YEAR}-12-31', '${CURRENT_YEAR}-01-01', 0, 1, 0, 1);
SQLEOF

echo "Running SQL seed script..."
SEED_EXIT=0
docker exec -i orangehrm-db mysql --force -u root -p"$DB_ROOT_PASS" "$DB_NAME" < /tmp/orangehrm_seed.sql || SEED_EXIT=$?
echo "SQL seed exit code: $SEED_EXIT"

# Verify seeding
EMPC=$(docker exec orangehrm-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" \
    -N -e "SELECT COUNT(*) FROM hs_hr_employee WHERE purged_at IS NULL;" 2>/dev/null | tr -d '[:space:]' || echo "?")
JTC=$(docker exec orangehrm-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" \
    -N -e "SELECT COUNT(*) FROM ohrm_job_title WHERE is_deleted=0;" 2>/dev/null | tr -d '[:space:]' || echo "?")
LTC=$(docker exec orangehrm-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" \
    -N -e "SELECT COUNT(*) FROM ohrm_leave_type WHERE deleted=0;" 2>/dev/null | tr -d '[:space:]' || echo "?")
ENTC=$(docker exec orangehrm-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" \
    -N -e "SELECT COUNT(*) FROM ohrm_leave_entitlement WHERE deleted=0;" 2>/dev/null | tr -d '[:space:]' || echo "?")
echo "Seeding verification: employees=$EMPC, job_titles=$JTC, leave_types=$LTC, entitlements=$ENTC"

echo "HR data seeding complete"

# ============================================================
# 6b. Configure Leave Period (required for leave assignment to work)
# ============================================================
echo "Configuring leave period..."
CURRENT_YEAR=$(date +%Y)
docker exec orangehrm-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" -e "
  -- Set leave_period_defined to Yes (required for LeaveAssignmentService)
  INSERT INTO hs_hr_config (name, value) VALUES ('leave_period_defined', 'Yes')
    ON DUPLICATE KEY UPDATE value='Yes';
  -- Insert leave period history (Jan 1 as start of leave year)
  INSERT IGNORE INTO ohrm_leave_period_history (leave_period_start_month, leave_period_start_day, created_at)
    VALUES (1, 1, CURDATE());
" 2>/dev/null || echo "WARNING: Leave period configuration failed"
echo "Leave period configured"

# ============================================================
# 7. Configure Firefox profile
# ============================================================
echo "Configuring Firefox profile..."

PROFILE_ROOT="/home/ga/.mozilla/firefox"
PROFILE_DIR="$PROFILE_ROOT/default.profile"
sudo -u ga mkdir -p "$PROFILE_DIR"

cat > "$PROFILE_ROOT/profiles.ini" << 'FFPROFILE'
[Profile0]
Name=default
IsRelative=1
Path=default.profile
Default=1

[General]
StartWithLastProfile=1
Version=2
FFPROFILE

cat > "$PROFILE_DIR/user.js" << 'USERJS'
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.rights.3.shown", true);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.shell.didSkipDefaultBrowserCheckOnFirstRun", true);
user_pref("app.update.enabled", false);
user_pref("app.update.auto", false);
user_pref("browser.vpn_promo.enabled", false);
user_pref("browser.uitour.enabled", false);
user_pref("extensions.pocket.enabled", false);
user_pref("identity.fxaccounts.enabled", false);
user_pref("signon.rememberSignons", false);
user_pref("signon.autofillForms", false);
USERJS

chown -R ga:ga "$PROFILE_ROOT"

# ============================================================
# 8. Warm-up Firefox
# ============================================================

# Ensure OrangeHRM is actually responding before launching Firefox.
# This prevents the race condition where Firefox opens before Docker
# containers are ready, causing a file manager or blank page instead.
echo "Verifying OrangeHRM is accessible before launching Firefox..."
HTTP_READY=false
for i in $(seq 1 60); do
    code=$(curl -sk -o /dev/null -w "%{http_code}" "$ORANGEHRM_LOGIN_URL" 2>/dev/null || true)
    if [ "$code" = "200" ]; then
        HTTP_READY=true
        echo "OrangeHRM login page verified accessible (HTTP $code) after ${i}s"
        break
    fi
    sleep 2
done
if [ "$HTTP_READY" != "true" ]; then
    echo "WARNING: OrangeHRM login page not accessible, launching Firefox anyway"
fi

echo "Launching Firefox..."
# Kill any stale Firefox processes first
pkill -f firefox 2>/dev/null || true
sleep 2

# Launch Firefox with full environment for GUI session
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus firefox '${ORANGEHRM_LOGIN_URL}' > /tmp/firefox_warmup.log 2>&1 &"

# Wait for Firefox window with increased timeout (60s instead of 30s)
FF_STARTED=false
for i in $(seq 1 60); do
    if DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla"; then
        FF_STARTED=true
        echo "Firefox window detected after ${i}s"
        break
    fi
    sleep 1
done

if [ "$FF_STARTED" = "true" ]; then
    sleep 2
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    echo "Firefox warm-up complete"
else
    echo "WARNING: Firefox window not detected within 60s, retrying launch..."
    # Retry: kill and relaunch
    pkill -f firefox 2>/dev/null || true
    sleep 3
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus firefox '${ORANGEHRM_LOGIN_URL}' > /tmp/firefox_warmup2.log 2>&1 &"
    for i in $(seq 1 30); do
        if DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla"; then
            FF_STARTED=true
            echo "Firefox window detected on retry after ${i}s"
            sleep 2
            DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
            break
        fi
        sleep 1
    done
    if [ "$FF_STARTED" != "true" ]; then
        echo "ERROR: Firefox failed to start after retry"
    fi
fi

echo ""
echo "=== OrangeHRM setup complete ==="
echo "URL: $ORANGEHRM_LOGIN_URL"
echo "Admin: $ADMIN_USER / $ADMIN_PASS"
