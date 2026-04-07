#!/bin/bash
# Sentrifugo Post-Start Hook: Start MySQL, import schema, configure app, seed data, setup browser
set -euo pipefail

echo "=== Setting up Sentrifugo ==="

SENTRIFUGO_DIR="/var/www/html/sentrifugo"
SENTRIFUGO_URL="http://localhost"
SENTRIFUGO_LOGIN_URL="${SENTRIFUGO_URL}"
DB_HOST="127.0.0.1"
DB_PORT="3306"
DB_NAME="sentrifugo"
DB_USER="sentrifugo"
DB_PASS="sentrifugo123"
DB_ROOT_PASS="rootpass123"
ADMIN_EMAIL="admin@sentrifugo.local"
ADMIN_PASS="Admin@Sfugo24"

# ============================================================
# Helper: poll HTTP endpoint
# ============================================================
wait_for_http() {
    local url="$1"
    local timeout_sec="${2:-300}"
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
# Helper: run DB query via docker exec
# ============================================================
db_root_query() {
    local query="$1"
    docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" \
        -N -e "$query" 2>/dev/null
}

# ============================================================
# 1. Set up Docker Compose for MySQL
# ============================================================
echo "Setting up Docker Compose for MySQL..."
DOCKER_DIR="/home/ga/sentrifugo_docker"
mkdir -p "$DOCKER_DIR"
cp /workspace/config/docker-compose.yml "$DOCKER_DIR/"
chown -R ga:ga "$DOCKER_DIR"

# Authenticate with Docker Hub if credentials file exists
if [ -f /workspace/config/.dockerhub_credentials ]; then
    source /workspace/config/.dockerhub_credentials
    docker login -u "$DOCKERHUB_USER" -p "$DOCKERHUB_TOKEN" 2>/dev/null || true
fi

# ============================================================
# 2. Pull and start MySQL container
# ============================================================
cd "$DOCKER_DIR"
echo "Pulling MySQL image..."
docker compose pull

echo "Starting MySQL container..."
docker compose up -d

echo "Container status:"
docker compose ps

# ============================================================
# 3. Wait for MySQL to be healthy
# ============================================================
echo "Waiting for MySQL..."
MYSQL_READY=false
for i in $(seq 1 60); do
    if docker exec sentrifugo-db mysqladmin ping -h localhost -u root -p"$DB_ROOT_PASS" >/dev/null 2>&1; then
        echo "MySQL ready after $((i * 2))s"
        MYSQL_READY=true
        break
    fi
    sleep 2
done
if [ "$MYSQL_READY" != "true" ]; then
    echo "ERROR: MySQL did not become ready"
    exit 1
fi
sleep 5

# Grant sentrifugo user full privileges
docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" -e \
    "GRANT ALL PRIVILEGES ON sentrifugo.* TO 'sentrifugo'@'%'; FLUSH PRIVILEGES;" 2>/dev/null

# ============================================================
# 4. Import Sentrifugo schema
# ============================================================
echo "Importing Sentrifugo schema..."
EXISTING_TABLES=$(docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" \
    -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$DB_NAME';" \
    2>/dev/null | tr -d '[:space:]' || echo "0")
echo "Existing tables in DB: ${EXISTING_TABLES}"

if [ "${EXISTING_TABLES:-0}" -ge 50 ]; then
    echo "Sentrifugo schema already imported (${EXISTING_TABLES} tables), skipping"
else
    # Import the hrms.sql from the Sentrifugo install directory
    HRMS_SQL="${SENTRIFUGO_DIR}/install/hrms.sql"
    if [ ! -f "$HRMS_SQL" ]; then
        echo "ERROR: hrms.sql not found at $HRMS_SQL"
        ls -la "${SENTRIFUGO_DIR}/install/" || true
        exit 1
    fi

    # Copy SQL file to Docker container and import
    docker cp "$HRMS_SQL" sentrifugo-db:/tmp/hrms.sql
    IMPORT_EXIT=0
    docker exec sentrifugo-db mysql --force -u root -p"$DB_ROOT_PASS" "$DB_NAME" \
        -e "source /tmp/hrms.sql" > /tmp/sentrifugo_import.log 2>&1 || IMPORT_EXIT=$?
    echo "SQL import exit code: $IMPORT_EXIT"

    TABLE_COUNT=$(docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" \
        -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$DB_NAME';" \
        2>/dev/null | tr -d '[:space:]' || echo "0")
    echo "Tables after import: $TABLE_COUNT"

    if [ "${TABLE_COUNT:-0}" -lt 50 ]; then
        echo "ERROR: Schema import failed (only $TABLE_COUNT tables found)"
        tail -n 50 /tmp/sentrifugo_import.log || true
        exit 1
    fi
    echo "Schema import successful ($TABLE_COUNT tables)"
fi

# ============================================================
# 5. Create application.ini config file
# ============================================================
echo "Creating application.ini..."
cat > "${SENTRIFUGO_DIR}/application/configs/application.ini" << APPINI
[production]
phpSettings.display_startup_errors = 0
phpSettings.display_errors = 0
phpSettings.error_reporting = E_All
bootstrap.path = APPLICATION_PATH "/modules/default/Bootstrap.php"
includePaths.library = APPLICATION_PATH "/modules/default/library"
bootstrap.class = "Default_Bootstrap"
appnamespace= "Default"
phpSettings.max_execution_time=0
autoloaderNamespaces[] ="Login_"
autoloaderNamespaces[] ="sapp_"
autoloaderNamespaces[] ="HTMLPurifier"

resources.frontController.params.displayExceptions = 0
resources.frontController.defaultModule = "default"
resources.frontController.params.prefixDefaultModule = "1"
resources.modules[]=
resources.frontController.moduleDirectory = APPLICATION_PATH "/modules"
resources.frontController.plugins[] = "Default_Plugin_SecurityCheck"
resources.layout.layout = "layout"
resources.layout.layoutPath = APPLICATION_PATH "/layouts/scripts/"
resources.frontController.plugins.accessControl = "Default_Plugin_AccessControl"

auth.salt= "xcNsdaAd73328aDs73oQw223hd"
auth.timeout= 60

resources.db.adapter = PDO_MYSQL
resources.db.params.host = ${DB_HOST}
resources.db.params.username = ${DB_USER}
resources.db.params.password = ${DB_PASS}
resources.db.params.dbname = ${DB_NAME}
resources.db.isDefaultTableAdapter = true

[staging : production]

[testing : production]
phpSettings.display_startup_errors = 0
phpSettings.display_errors = 0

[development : production]
phpSettings.display_startup_errors = 0
phpSettings.display_errors = 0
resources.frontController.params.displayExceptions = 0

resources.log.stream.writerName = "Stream"
resources.log.stream.writerParams.stream = APPLICATION_PATH "/../logs/application.log"
resources.log.stream.writerParams.mode = "a"
resources.log.stream.filterName = "Priority"
resources.log.stream.formatterName = "Simple"
resources.log.stream.filterParams.priority = 7
resources.log.stream.formatterParams.format = "%timestamp% %priorityName% (%priority%): %message% %info%"

phpSettings.error_reporting = E_ALL
phpSettings.log_errors = 1
phpSettings.error_log = APPLICATION_PATH "/../logs/application.log"
APPINI

# ============================================================
# 6. Create db_constants.php
# ============================================================
echo "Creating db_constants.php..."
cat > "${SENTRIFUGO_DIR}/public/db_constants.php" << DBCONST
<?php
define("SENTRIFUGO_HOST","${DB_HOST}");
define("SENTRIFUGO_DBNAME","${DB_NAME}");
define("SENTRIFUGO_USERNAME","${DB_USER}");
define("SENTRIFUGO_PASSWORD","${DB_PASS}");
define("ABOREDHOST","${DB_HOST}");
define("ABOREDUSER","${DB_USER}");
define("ABOREDPASSWORD","${DB_PASS}");
define("ABOREDDBNAME","${DB_NAME}");
?>
DBCONST

# ============================================================
# 7. Set file permissions
# ============================================================
echo "Setting file permissions..."
chown -R www-data:www-data "$SENTRIFUGO_DIR"
chmod -R 755 "$SENTRIFUGO_DIR"
chmod -R 777 "${SENTRIFUGO_DIR}/public/uploads" 2>/dev/null || true
chmod -R 777 "${SENTRIFUGO_DIR}/logs" 2>/dev/null || true
chmod 644 "${SENTRIFUGO_DIR}/application/configs/application.ini"
chmod 644 "${SENTRIFUGO_DIR}/public/db_constants.php"

# Remove install directory to suppress warnings
mv "${SENTRIFUGO_DIR}/install" "${SENTRIFUGO_DIR}/install_bak" 2>/dev/null || true

# Restart Apache to pick up changes
systemctl restart apache2
sleep 3

# ============================================================
# 8. Update admin credentials
# ============================================================
echo "Updating admin credentials..."
# The default admin from hrms.sql has emailaddress='admin@example.com' and MD5 password
# Sentrifugo Login/Auth.php uses plain md5(password) WITHOUT salt for authentication
AUTH_SALT="xcNsdaAd73328aDs73oQw223hd"
ADMIN_MD5=$(docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" -N -e \
    "SELECT MD5('${ADMIN_PASS}');" 2>/dev/null | tr -d '[:space:]')
docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" -e "
  UPDATE main_users SET
    emailaddress='${ADMIN_EMAIL}',
    emppassword='${ADMIN_MD5}',
    userfullname='Admin User',
    firstname='Admin',
    lastname='User',
    isactive=1,
    userstatus='old',
    tourflag=1
  WHERE id=1;
" 2>/dev/null
echo "Admin credentials updated: ${ADMIN_EMAIL}"

# ============================================================
# 9. Seed organization info
# ============================================================
echo "Seeding organization info..."
CURRENT_DATE=$(date +%Y-%m-%d)
CURRENT_YEAR=$(date +%Y)
CURRENT_DATETIME=$(date '+%Y-%m-%d %H:%M:%S')

docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" -e "
  INSERT INTO main_organisationinfo
    (organisationname, domain, website, orgdescription, totalemployees,
     org_startdate, phonenumber, email, country, state, city,
     address1, createdby, createddate, isactive)
  VALUES
    ('Acme Global Technologies', 'acmeglobe.com', 'https://www.acmeglobe.com',
     'Acme Global Technologies is a mid-size technology and consulting firm specializing in enterprise software, cloud solutions, and digital transformation services.',
     150, '2010-06-15', '212-555-1000', 'info@acmeglobe.com',
     231, 33, 5261, '350 Fifth Avenue, Suite 2100', 1, '${CURRENT_DATETIME}', 1);
" 2>/dev/null || echo "WARNING: Organisation info insert failed (may already exist)"

# ============================================================
# 10. Seed business units
# ============================================================
echo "Seeding business units..."
docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" -e "
  INSERT INTO main_businessunits (unitname, unitcode, description, startdate,
    country, state, city, address1, createdby, createddate, isactive)
  VALUES
    ('Technology Services', 'TS', 'Core technology and engineering division', '2010-06-15',
     231, 33, 5261, '350 Fifth Avenue, Suite 2100', 1, '${CURRENT_DATETIME}', 1),
    ('Corporate Services', 'CS', 'Finance, HR, and administrative functions', '2010-06-15',
     231, 33, 5261, '350 Fifth Avenue, Suite 2200', 1, '${CURRENT_DATETIME}', 1),
    ('Commercial Operations', 'CO', 'Sales, marketing, and business development', '2012-03-01',
     231, 33, 5261, '350 Fifth Avenue, Suite 2300', 1, '${CURRENT_DATETIME}', 1);
" 2>/dev/null

# Get business unit IDs
BU_TECH=$(docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" \
    -N -e "SELECT id FROM main_businessunits WHERE unitcode='TS' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
BU_CORP=$(docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" \
    -N -e "SELECT id FROM main_businessunits WHERE unitcode='CS' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
BU_COMM=$(docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" \
    -N -e "SELECT id FROM main_businessunits WHERE unitcode='CO' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
echo "Business units: Tech=$BU_TECH, Corp=$BU_CORP, Comm=$BU_COMM"

# ============================================================
# 11. Seed departments
# ============================================================
echo "Seeding departments..."
docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" -e "
  INSERT INTO main_departments (deptname, deptcode, description, startdate,
    country, state, city, address1, unitid, createdby, createddate, isactive)
  VALUES
    ('Software Engineering', 'SWE', 'Application development and architecture', '2010-06-15',
     231, 33, 5261, '350 Fifth Avenue', ${BU_TECH:-1}, 1, '${CURRENT_DATETIME}', 1),
    ('Data Science', 'DS', 'Analytics, machine learning, and data engineering', '2015-01-10',
     231, 33, 5261, '350 Fifth Avenue', ${BU_TECH:-1}, 1, '${CURRENT_DATETIME}', 1),
    ('DevOps & Infrastructure', 'DEVOPS', 'Cloud infrastructure and CI/CD pipelines', '2013-07-01',
     231, 33, 5261, '350 Fifth Avenue', ${BU_TECH:-1}, 1, '${CURRENT_DATETIME}', 1),
    ('Human Resources', 'HR', 'Talent management, recruitment, and employee relations', '2010-06-15',
     231, 33, 5261, '350 Fifth Avenue', ${BU_CORP:-2}, 1, '${CURRENT_DATETIME}', 1),
    ('Finance & Accounting', 'FIN', 'Financial planning, accounting, and compliance', '2010-06-15',
     231, 33, 5261, '350 Fifth Avenue', ${BU_CORP:-2}, 1, '${CURRENT_DATETIME}', 1),
    ('Marketing', 'MKT', 'Brand management, digital marketing, and communications', '2012-03-01',
     231, 33, 5261, '350 Fifth Avenue', ${BU_COMM:-3}, 1, '${CURRENT_DATETIME}', 1),
    ('Sales', 'SALES', 'Enterprise sales, account management, and partnerships', '2012-03-01',
     231, 33, 5261, '350 Fifth Avenue', ${BU_COMM:-3}, 1, '${CURRENT_DATETIME}', 1),
    ('Customer Success', 'CSUC', 'Customer support, onboarding, and retention', '2014-09-01',
     231, 33, 5261, '350 Fifth Avenue', ${BU_COMM:-3}, 1, '${CURRENT_DATETIME}', 1);
" 2>/dev/null

# Get department IDs
DEPT_SWE=$(docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" \
    -N -e "SELECT id FROM main_departments WHERE deptcode='SWE' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
DEPT_DS=$(docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" \
    -N -e "SELECT id FROM main_departments WHERE deptcode='DS' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
DEPT_DEVOPS=$(docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" \
    -N -e "SELECT id FROM main_departments WHERE deptcode='DEVOPS' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
DEPT_HR=$(docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" \
    -N -e "SELECT id FROM main_departments WHERE deptcode='HR' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
DEPT_FIN=$(docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" \
    -N -e "SELECT id FROM main_departments WHERE deptcode='FIN' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
DEPT_MKT=$(docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" \
    -N -e "SELECT id FROM main_departments WHERE deptcode='MKT' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
DEPT_SALES=$(docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" \
    -N -e "SELECT id FROM main_departments WHERE deptcode='SALES' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
DEPT_CSUC=$(docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" \
    -N -e "SELECT id FROM main_departments WHERE deptcode='CSUC' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
echo "Departments: SWE=$DEPT_SWE, DS=$DEPT_DS, DEVOPS=$DEPT_DEVOPS, HR=$DEPT_HR, FIN=$DEPT_FIN, MKT=$DEPT_MKT, SALES=$DEPT_SALES, CSUC=$DEPT_CSUC"

# ============================================================
# 11b. Seed pay frequencies (required for job title dropdown)
# ============================================================
echo "Seeding pay frequencies..."
docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" -e "
  INSERT INTO main_payfrequency (freqtype, freqcode, freqdescription, createdby, createddate, isactive)
  VALUES
    ('Annual', 'ANN', 'Annual salary', 1, '${CURRENT_DATETIME}', 1),
    ('Monthly', 'MON', 'Monthly salary', 1, '${CURRENT_DATETIME}', 1),
    ('Hourly', 'HRL', 'Hourly rate', 1, '${CURRENT_DATETIME}', 1);
" 2>/dev/null

# Get pay frequency ID for Annual
PF_ANNUAL=$(docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" \
    -N -e "SELECT id FROM main_payfrequency WHERE freqcode='ANN' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
echo "Pay frequency Annual ID: $PF_ANNUAL"

# ============================================================
# 12. Seed job titles
# ============================================================
echo "Seeding job titles..."
docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" -e "
  INSERT INTO main_jobtitles (jobtitlecode, jobtitlename, jobdescription,
    minexperiencerequired, jobpayfrequency, createdby, createddate, isactive)
  VALUES
    ('SWE-SR', 'Senior Software Engineer', 'Designs and implements complex software systems', 5, ${PF_ANNUAL:-1}, 1, '${CURRENT_DATETIME}', 1),
    ('SWE-JR', 'Software Engineer', 'Develops and maintains software applications', 1, ${PF_ANNUAL:-1}, 1, '${CURRENT_DATETIME}', 1),
    ('DS-SR', 'Senior Data Scientist', 'Leads ML initiatives and data strategy', 5, ${PF_ANNUAL:-1}, 1, '${CURRENT_DATETIME}', 1),
    ('DS-JR', 'Data Analyst', 'Analyzes data and creates reports', 1, ${PF_ANNUAL:-1}, 1, '${CURRENT_DATETIME}', 1),
    ('DEVOPS-SR', 'DevOps Lead', 'Manages infrastructure and deployment pipelines', 5, ${PF_ANNUAL:-1}, 1, '${CURRENT_DATETIME}', 1),
    ('DEVOPS-JR', 'Systems Engineer', 'Maintains cloud infrastructure', 2, ${PF_ANNUAL:-1}, 1, '${CURRENT_DATETIME}', 1),
    ('HR-MGR', 'HR Manager', 'Manages HR operations and employee relations', 5, ${PF_ANNUAL:-1}, 1, '${CURRENT_DATETIME}', 1),
    ('HR-SPEC', 'HR Specialist', 'Handles recruitment and onboarding', 2, ${PF_ANNUAL:-1}, 1, '${CURRENT_DATETIME}', 1),
    ('FIN-MGR', 'Finance Manager', 'Oversees financial planning and reporting', 5, ${PF_ANNUAL:-1}, 1, '${CURRENT_DATETIME}', 1),
    ('FIN-ANL', 'Financial Analyst', 'Performs financial analysis and forecasting', 2, ${PF_ANNUAL:-1}, 1, '${CURRENT_DATETIME}', 1),
    ('MKT-MGR', 'Marketing Manager', 'Leads marketing campaigns and brand strategy', 5, ${PF_ANNUAL:-1}, 1, '${CURRENT_DATETIME}', 1),
    ('MKT-SPEC', 'Marketing Specialist', 'Executes digital marketing initiatives', 2, ${PF_ANNUAL:-1}, 1, '${CURRENT_DATETIME}', 1),
    ('SALES-MGR', 'Sales Manager', 'Manages enterprise sales team', 5, ${PF_ANNUAL:-1}, 1, '${CURRENT_DATETIME}', 1),
    ('SALES-REP', 'Sales Representative', 'Manages client accounts and new business', 1, ${PF_ANNUAL:-1}, 1, '${CURRENT_DATETIME}', 1),
    ('CS-MGR', 'Customer Success Manager', 'Leads customer success and retention', 4, ${PF_ANNUAL:-1}, 1, '${CURRENT_DATETIME}', 1),
    ('CS-SPEC', 'Customer Support Specialist', 'Provides technical support to clients', 1, ${PF_ANNUAL:-1}, 1, '${CURRENT_DATETIME}', 1);
" 2>/dev/null

# ============================================================
# 13. Seed positions
# ============================================================
echo "Seeding positions..."
docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" -e "
  INSERT INTO main_positions (positionname, jobtitleid, description, createdby, createddate, isactive)
  SELECT 'Senior Software Engineer', id, 'Senior IC role in engineering', 1, '${CURRENT_DATETIME}', 1
    FROM main_jobtitles WHERE jobtitlecode='SWE-SR';
  INSERT INTO main_positions (positionname, jobtitleid, description, createdby, createddate, isactive)
  SELECT 'Software Engineer', id, 'IC role in engineering', 1, '${CURRENT_DATETIME}', 1
    FROM main_jobtitles WHERE jobtitlecode='SWE-JR';
  INSERT INTO main_positions (positionname, jobtitleid, description, createdby, createddate, isactive)
  SELECT 'Senior Data Scientist', id, 'Senior IC role in data science', 1, '${CURRENT_DATETIME}', 1
    FROM main_jobtitles WHERE jobtitlecode='DS-SR';
  INSERT INTO main_positions (positionname, jobtitleid, description, createdby, createddate, isactive)
  SELECT 'Data Analyst', id, 'IC role in data analytics', 1, '${CURRENT_DATETIME}', 1
    FROM main_jobtitles WHERE jobtitlecode='DS-JR';
  INSERT INTO main_positions (positionname, jobtitleid, description, createdby, createddate, isactive)
  SELECT 'HR Manager', id, 'HR department manager', 1, '${CURRENT_DATETIME}', 1
    FROM main_jobtitles WHERE jobtitlecode='HR-MGR';
  INSERT INTO main_positions (positionname, jobtitleid, description, createdby, createddate, isactive)
  SELECT 'Finance Manager', id, 'Finance department manager', 1, '${CURRENT_DATETIME}', 1
    FROM main_jobtitles WHERE jobtitlecode='FIN-MGR';
  INSERT INTO main_positions (positionname, jobtitleid, description, createdby, createddate, isactive)
  SELECT 'Marketing Manager', id, 'Marketing department manager', 1, '${CURRENT_DATETIME}', 1
    FROM main_jobtitles WHERE jobtitlecode='MKT-MGR';
  INSERT INTO main_positions (positionname, jobtitleid, description, createdby, createddate, isactive)
  SELECT 'Sales Manager', id, 'Sales department manager', 1, '${CURRENT_DATETIME}', 1
    FROM main_jobtitles WHERE jobtitlecode='SALES-MGR';
" 2>/dev/null

# ============================================================
# 14. Seed employment status types
# ============================================================
echo "Seeding employment status types..."
docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" -e "
  INSERT INTO main_employmentstatus (workcode, workcodename, description, createdby, createddate, isactive)
  VALUES
    ('FT', 1, 'Full-Time Employee', 1, '${CURRENT_DATETIME}', 1),
    ('PT', 2, 'Part-Time Employee', 1, '${CURRENT_DATETIME}', 1),
    ('CT', 3, 'Contractor', 1, '${CURRENT_DATETIME}', 1),
    ('IN', 4, 'Intern', 1, '${CURRENT_DATETIME}', 1);
" 2>/dev/null

# Get employment status ID for Full-Time
ES_FT=$(docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" \
    -N -e "SELECT id FROM main_employmentstatus WHERE workcode='FT' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')

# ============================================================
# 15. Seed employee data (20 employees)
# ============================================================
echo "Seeding employee data..."

# Get job title IDs
JT_SWE_SR=$(docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" \
    -N -e "SELECT id FROM main_jobtitles WHERE jobtitlecode='SWE-SR' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
JT_SWE_JR=$(docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" \
    -N -e "SELECT id FROM main_jobtitles WHERE jobtitlecode='SWE-JR' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
JT_DS_SR=$(docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" \
    -N -e "SELECT id FROM main_jobtitles WHERE jobtitlecode='DS-SR' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
JT_DS_JR=$(docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" \
    -N -e "SELECT id FROM main_jobtitles WHERE jobtitlecode='DS-JR' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
JT_DEVOPS_SR=$(docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" \
    -N -e "SELECT id FROM main_jobtitles WHERE jobtitlecode='DEVOPS-SR' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
JT_DEVOPS_JR=$(docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" \
    -N -e "SELECT id FROM main_jobtitles WHERE jobtitlecode='DEVOPS-JR' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
JT_HR_MGR=$(docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" \
    -N -e "SELECT id FROM main_jobtitles WHERE jobtitlecode='HR-MGR' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
JT_HR_SPEC=$(docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" \
    -N -e "SELECT id FROM main_jobtitles WHERE jobtitlecode='HR-SPEC' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
JT_FIN_MGR=$(docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" \
    -N -e "SELECT id FROM main_jobtitles WHERE jobtitlecode='FIN-MGR' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
JT_FIN_ANL=$(docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" \
    -N -e "SELECT id FROM main_jobtitles WHERE jobtitlecode='FIN-ANL' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
JT_MKT_MGR=$(docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" \
    -N -e "SELECT id FROM main_jobtitles WHERE jobtitlecode='MKT-MGR' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
JT_MKT_SPEC=$(docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" \
    -N -e "SELECT id FROM main_jobtitles WHERE jobtitlecode='MKT-SPEC' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
JT_SALES_MGR=$(docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" \
    -N -e "SELECT id FROM main_jobtitles WHERE jobtitlecode='SALES-MGR' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
JT_SALES_REP=$(docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" \
    -N -e "SELECT id FROM main_jobtitles WHERE jobtitlecode='SALES-REP' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
JT_CS_MGR=$(docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" \
    -N -e "SELECT id FROM main_jobtitles WHERE jobtitlecode='CS-MGR' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
JT_CS_SPEC=$(docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" \
    -N -e "SELECT id FROM main_jobtitles WHERE jobtitlecode='CS-SPEC' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')

# Default password hash - Sentrifugo uses plain md5(password) WITHOUT salt
EMP_PASS_HASH=$(docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" -N -e \
    "SELECT MD5('Employee@123');" 2>/dev/null | tr -d '[:space:]')

# Write employee seed SQL
cat > /tmp/sentrifugo_employees.sql << EMPSQL
-- Insert employees into main_users and main_employees_summary
-- Employee 1: James Anderson - Senior Software Engineer
INSERT INTO main_users (emprole, userstatus, firstname, lastname, userfullname, emailaddress,
  contactnumber, emppassword, createdby, createddate, isactive, employeeId, modeofentry, selecteddate)
VALUES (5, 'old', 'James', 'Anderson', 'James Anderson', 'james.anderson@acmeglobe.com',
  '212-555-0101', '${EMP_PASS_HASH}', 1, '${CURRENT_DATETIME}', 1, 'EMP001', 'Direct', '2018-03-15');
SET @u1 = LAST_INSERT_ID();
INSERT INTO main_employees_summary (user_id, date_of_joining, emp_status_id, emp_status_name,
  businessunit_id, businessunit_name, department_id, department_name, jobtitle_id, jobtitle_name,
  position_id, position_name, prefix_id, prefix_name, emprole, emprole_name,
  firstname, lastname, userfullname, emailaddress, contactnumber, employeeId, modeofentry,
  createdby, createddate, isactive)
VALUES (@u1, '2018-03-15', ${ES_FT:-1}, 'Full-Time Employee',
  ${BU_TECH:-1}, 'Technology Services', ${DEPT_SWE:-1}, 'Software Engineering',
  ${JT_SWE_SR:-1}, 'Senior Software Engineer', NULL, NULL,
  1, 'Mr', 5, 'Employee', 'James', 'Anderson', 'James Anderson',
  'james.anderson@acmeglobe.com', '212-555-0101', 'EMP001', 'Direct',
  1, '${CURRENT_DATETIME}', 1);

-- Employee 2: Sarah Mitchell - HR Manager
INSERT INTO main_users (emprole, userstatus, firstname, lastname, userfullname, emailaddress,
  contactnumber, emppassword, createdby, createddate, isactive, employeeId, modeofentry, selecteddate)
VALUES (4, 'old', 'Sarah', 'Mitchell', 'Sarah Mitchell', 'sarah.mitchell@acmeglobe.com',
  '212-555-0102', '${EMP_PASS_HASH}', 1, '${CURRENT_DATETIME}', 1, 'EMP002', 'Direct', '2017-06-01');
SET @u2 = LAST_INSERT_ID();
INSERT INTO main_employees_summary (user_id, date_of_joining, emp_status_id, emp_status_name,
  businessunit_id, businessunit_name, department_id, department_name, jobtitle_id, jobtitle_name,
  prefix_id, prefix_name, emprole, emprole_name,
  firstname, lastname, userfullname, emailaddress, contactnumber, employeeId, modeofentry,
  createdby, createddate, isactive)
VALUES (@u2, '2017-06-01', ${ES_FT:-1}, 'Full-Time Employee',
  ${BU_CORP:-2}, 'Corporate Services', ${DEPT_HR:-4}, 'Human Resources',
  ${JT_HR_MGR:-7}, 'HR Manager', 1, 'Mr',
  4, 'HR Manager', 'Sarah', 'Mitchell', 'Sarah Mitchell',
  'sarah.mitchell@acmeglobe.com', '212-555-0102', 'EMP002', 'Direct',
  1, '${CURRENT_DATETIME}', 1);

-- Employee 3: David Nguyen - Finance Manager
INSERT INTO main_users (emprole, userstatus, firstname, lastname, userfullname, emailaddress,
  contactnumber, emppassword, createdby, createddate, isactive, employeeId, modeofentry, selecteddate)
VALUES (5, 'old', 'David', 'Nguyen', 'David Nguyen', 'david.nguyen@acmeglobe.com',
  '212-555-0103', '${EMP_PASS_HASH}', 1, '${CURRENT_DATETIME}', 1, 'EMP003', 'Direct', '2016-09-12');
SET @u3 = LAST_INSERT_ID();
INSERT INTO main_employees_summary (user_id, date_of_joining, emp_status_id, emp_status_name,
  businessunit_id, businessunit_name, department_id, department_name, jobtitle_id, jobtitle_name,
  prefix_id, prefix_name, emprole, emprole_name,
  firstname, lastname, userfullname, emailaddress, contactnumber, employeeId, modeofentry,
  createdby, createddate, isactive)
VALUES (@u3, '2016-09-12', ${ES_FT:-1}, 'Full-Time Employee',
  ${BU_CORP:-2}, 'Corporate Services', ${DEPT_FIN:-5}, 'Finance & Accounting',
  ${JT_FIN_MGR:-9}, 'Finance Manager', 1, 'Mr',
  5, 'Employee', 'David', 'Nguyen', 'David Nguyen',
  'david.nguyen@acmeglobe.com', '212-555-0103', 'EMP003', 'Direct',
  1, '${CURRENT_DATETIME}', 1);

-- Employee 4: Emily Rodriguez - Marketing Manager
INSERT INTO main_users (emprole, userstatus, firstname, lastname, userfullname, emailaddress,
  contactnumber, emppassword, createdby, createddate, isactive, employeeId, modeofentry, selecteddate)
VALUES (5, 'old', 'Emily', 'Rodriguez', 'Emily Rodriguez', 'emily.rodriguez@acmeglobe.com',
  '212-555-0104', '${EMP_PASS_HASH}', 1, '${CURRENT_DATETIME}', 1, 'EMP004', 'Direct', '2019-01-07');
SET @u4 = LAST_INSERT_ID();
INSERT INTO main_employees_summary (user_id, date_of_joining, emp_status_id, emp_status_name,
  businessunit_id, businessunit_name, department_id, department_name, jobtitle_id, jobtitle_name,
  prefix_id, prefix_name, emprole, emprole_name,
  firstname, lastname, userfullname, emailaddress, contactnumber, employeeId, modeofentry,
  createdby, createddate, isactive)
VALUES (@u4, '2019-01-07', ${ES_FT:-1}, 'Full-Time Employee',
  ${BU_COMM:-3}, 'Commercial Operations', ${DEPT_MKT:-6}, 'Marketing',
  ${JT_MKT_MGR:-11}, 'Marketing Manager', 2, 'Ms',
  5, 'Employee', 'Emily', 'Rodriguez', 'Emily Rodriguez',
  'emily.rodriguez@acmeglobe.com', '212-555-0104', 'EMP004', 'Direct',
  1, '${CURRENT_DATETIME}', 1);

-- Employee 5: Michael Thompson - Sales Manager
INSERT INTO main_users (emprole, userstatus, firstname, lastname, userfullname, emailaddress,
  contactnumber, emppassword, createdby, createddate, isactive, employeeId, modeofentry, selecteddate)
VALUES (5, 'old', 'Michael', 'Thompson', 'Michael Thompson', 'michael.thompson@acmeglobe.com',
  '212-555-0105', '${EMP_PASS_HASH}', 1, '${CURRENT_DATETIME}', 1, 'EMP005', 'Direct', '2017-11-20');
SET @u5 = LAST_INSERT_ID();
INSERT INTO main_employees_summary (user_id, date_of_joining, emp_status_id, emp_status_name,
  businessunit_id, businessunit_name, department_id, department_name, jobtitle_id, jobtitle_name,
  prefix_id, prefix_name, emprole, emprole_name,
  firstname, lastname, userfullname, emailaddress, contactnumber, employeeId, modeofentry,
  createdby, createddate, isactive)
VALUES (@u5, '2017-11-20', ${ES_FT:-1}, 'Full-Time Employee',
  ${BU_COMM:-3}, 'Commercial Operations', ${DEPT_SALES:-7}, 'Sales',
  ${JT_SALES_MGR:-13}, 'Sales Manager', 1, 'Mr',
  5, 'Employee', 'Michael', 'Thompson', 'Michael Thompson',
  'michael.thompson@acmeglobe.com', '212-555-0105', 'EMP005', 'Direct',
  1, '${CURRENT_DATETIME}', 1);

-- Employee 6: Jessica Liu - Software Engineer
INSERT INTO main_users (emprole, userstatus, firstname, lastname, userfullname, emailaddress,
  contactnumber, emppassword, createdby, createddate, isactive, employeeId, modeofentry, selecteddate)
VALUES (5, 'old', 'Jessica', 'Liu', 'Jessica Liu', 'jessica.liu@acmeglobe.com',
  '415-555-0106', '${EMP_PASS_HASH}', 1, '${CURRENT_DATETIME}', 1, 'EMP006', 'Direct', '2020-02-10');
SET @u6 = LAST_INSERT_ID();
INSERT INTO main_employees_summary (user_id, date_of_joining, emp_status_id, emp_status_name,
  businessunit_id, businessunit_name, department_id, department_name, jobtitle_id, jobtitle_name,
  prefix_id, prefix_name, emprole, emprole_name,
  firstname, lastname, userfullname, emailaddress, contactnumber, employeeId, modeofentry,
  createdby, createddate, isactive)
VALUES (@u6, '2020-02-10', ${ES_FT:-1}, 'Full-Time Employee',
  ${BU_TECH:-1}, 'Technology Services', ${DEPT_SWE:-1}, 'Software Engineering',
  ${JT_SWE_JR:-2}, 'Software Engineer', 2, 'Ms',
  5, 'Employee', 'Jessica', 'Liu', 'Jessica Liu',
  'jessica.liu@acmeglobe.com', '415-555-0106', 'EMP006', 'Direct',
  1, '${CURRENT_DATETIME}', 1);

-- Employee 7: Robert Patel - Senior Data Scientist
INSERT INTO main_users (emprole, userstatus, firstname, lastname, userfullname, emailaddress,
  contactnumber, emppassword, createdby, createddate, isactive, employeeId, modeofentry, selecteddate)
VALUES (5, 'old', 'Robert', 'Patel', 'Robert Patel', 'robert.patel@acmeglobe.com',
  '415-555-0107', '${EMP_PASS_HASH}', 1, '${CURRENT_DATETIME}', 1, 'EMP007', 'Direct', '2019-05-22');
SET @u7 = LAST_INSERT_ID();
INSERT INTO main_employees_summary (user_id, date_of_joining, emp_status_id, emp_status_name,
  businessunit_id, businessunit_name, department_id, department_name, jobtitle_id, jobtitle_name,
  prefix_id, prefix_name, emprole, emprole_name,
  firstname, lastname, userfullname, emailaddress, contactnumber, employeeId, modeofentry,
  createdby, createddate, isactive)
VALUES (@u7, '2019-05-22', ${ES_FT:-1}, 'Full-Time Employee',
  ${BU_TECH:-1}, 'Technology Services', ${DEPT_DS:-2}, 'Data Science',
  ${JT_DS_SR:-3}, 'Senior Data Scientist', 1, 'Mr',
  5, 'Employee', 'Robert', 'Patel', 'Robert Patel',
  'robert.patel@acmeglobe.com', '415-555-0107', 'EMP007', 'Direct',
  1, '${CURRENT_DATETIME}', 1);

-- Employee 8: Ashley Johnson - HR Specialist
INSERT INTO main_users (emprole, userstatus, firstname, lastname, userfullname, emailaddress,
  contactnumber, emppassword, createdby, createddate, isactive, employeeId, modeofentry, selecteddate)
VALUES (5, 'old', 'Ashley', 'Johnson', 'Ashley Johnson', 'ashley.johnson@acmeglobe.com',
  '415-555-0108', '${EMP_PASS_HASH}', 1, '${CURRENT_DATETIME}', 1, 'EMP008', 'Direct', '2021-03-08');
SET @u8 = LAST_INSERT_ID();
INSERT INTO main_employees_summary (user_id, date_of_joining, emp_status_id, emp_status_name,
  businessunit_id, businessunit_name, department_id, department_name, jobtitle_id, jobtitle_name,
  prefix_id, prefix_name, emprole, emprole_name,
  firstname, lastname, userfullname, emailaddress, contactnumber, employeeId, modeofentry,
  createdby, createddate, isactive)
VALUES (@u8, '2021-03-08', ${ES_FT:-1}, 'Full-Time Employee',
  ${BU_CORP:-2}, 'Corporate Services', ${DEPT_HR:-4}, 'Human Resources',
  ${JT_HR_SPEC:-8}, 'HR Specialist', 2, 'Ms',
  5, 'Employee', 'Ashley', 'Johnson', 'Ashley Johnson',
  'ashley.johnson@acmeglobe.com', '415-555-0108', 'EMP008', 'Direct',
  1, '${CURRENT_DATETIME}', 1);

-- Employee 9: Christopher Williams - DevOps Lead
INSERT INTO main_users (emprole, userstatus, firstname, lastname, userfullname, emailaddress,
  contactnumber, emppassword, createdby, createddate, isactive, employeeId, modeofentry, selecteddate)
VALUES (5, 'old', 'Christopher', 'Williams', 'Christopher Williams', 'christopher.williams@acmeglobe.com',
  '212-555-0109', '${EMP_PASS_HASH}', 1, '${CURRENT_DATETIME}', 1, 'EMP009', 'Direct', '2018-08-14');
SET @u9 = LAST_INSERT_ID();
INSERT INTO main_employees_summary (user_id, date_of_joining, emp_status_id, emp_status_name,
  businessunit_id, businessunit_name, department_id, department_name, jobtitle_id, jobtitle_name,
  prefix_id, prefix_name, emprole, emprole_name,
  firstname, lastname, userfullname, emailaddress, contactnumber, employeeId, modeofentry,
  createdby, createddate, isactive)
VALUES (@u9, '2018-08-14', ${ES_FT:-1}, 'Full-Time Employee',
  ${BU_TECH:-1}, 'Technology Services', ${DEPT_DEVOPS:-3}, 'DevOps & Infrastructure',
  ${JT_DEVOPS_SR:-5}, 'DevOps Lead', 1, 'Mr',
  5, 'Employee', 'Christopher', 'Williams', 'Christopher Williams',
  'christopher.williams@acmeglobe.com', '212-555-0109', 'EMP009', 'Direct',
  1, '${CURRENT_DATETIME}', 1);

-- Employee 10: Amanda Davis - Financial Analyst
INSERT INTO main_users (emprole, userstatus, firstname, lastname, userfullname, emailaddress,
  contactnumber, emppassword, createdby, createddate, isactive, employeeId, modeofentry, selecteddate)
VALUES (5, 'old', 'Amanda', 'Davis', 'Amanda Davis', 'amanda.davis@acmeglobe.com',
  '212-555-0110', '${EMP_PASS_HASH}', 1, '${CURRENT_DATETIME}', 1, 'EMP010', 'Direct', '2020-07-01');
SET @u10 = LAST_INSERT_ID();
INSERT INTO main_employees_summary (user_id, date_of_joining, emp_status_id, emp_status_name,
  businessunit_id, businessunit_name, department_id, department_name, jobtitle_id, jobtitle_name,
  prefix_id, prefix_name, emprole, emprole_name,
  firstname, lastname, userfullname, emailaddress, contactnumber, employeeId, modeofentry,
  createdby, createddate, isactive)
VALUES (@u10, '2020-07-01', ${ES_FT:-1}, 'Full-Time Employee',
  ${BU_CORP:-2}, 'Corporate Services', ${DEPT_FIN:-5}, 'Finance & Accounting',
  ${JT_FIN_ANL:-10}, 'Financial Analyst', 2, 'Ms',
  5, 'Employee', 'Amanda', 'Davis', 'Amanda Davis',
  'amanda.davis@acmeglobe.com', '212-555-0110', 'EMP010', 'Direct',
  1, '${CURRENT_DATETIME}', 1);

-- Employee 11: Matthew Garcia - Marketing Specialist
INSERT INTO main_users (emprole, userstatus, firstname, lastname, userfullname, emailaddress,
  contactnumber, emppassword, createdby, createddate, isactive, employeeId, modeofentry, selecteddate)
VALUES (5, 'old', 'Matthew', 'Garcia', 'Matthew Garcia', 'matthew.garcia@acmeglobe.com',
  '415-555-0111', '${EMP_PASS_HASH}', 1, '${CURRENT_DATETIME}', 1, 'EMP011', 'Direct', '2021-01-18');
SET @u11 = LAST_INSERT_ID();
INSERT INTO main_employees_summary (user_id, date_of_joining, emp_status_id, emp_status_name,
  businessunit_id, businessunit_name, department_id, department_name, jobtitle_id, jobtitle_name,
  prefix_id, prefix_name, emprole, emprole_name,
  firstname, lastname, userfullname, emailaddress, contactnumber, employeeId, modeofentry,
  createdby, createddate, isactive)
VALUES (@u11, '2021-01-18', ${ES_FT:-1}, 'Full-Time Employee',
  ${BU_COMM:-3}, 'Commercial Operations', ${DEPT_MKT:-6}, 'Marketing',
  ${JT_MKT_SPEC:-12}, 'Marketing Specialist', 1, 'Mr',
  5, 'Employee', 'Matthew', 'Garcia', 'Matthew Garcia',
  'matthew.garcia@acmeglobe.com', '415-555-0111', 'EMP011', 'Direct',
  1, '${CURRENT_DATETIME}', 1);

-- Employee 12: Jennifer Martinez - Data Analyst
INSERT INTO main_users (emprole, userstatus, firstname, lastname, userfullname, emailaddress,
  contactnumber, emppassword, createdby, createddate, isactive, employeeId, modeofentry, selecteddate)
VALUES (5, 'old', 'Jennifer', 'Martinez', 'Jennifer Martinez', 'jennifer.martinez@acmeglobe.com',
  '212-555-0112', '${EMP_PASS_HASH}', 1, '${CURRENT_DATETIME}', 1, 'EMP012', 'Direct', '2020-11-02');
SET @u12 = LAST_INSERT_ID();
INSERT INTO main_employees_summary (user_id, date_of_joining, emp_status_id, emp_status_name,
  businessunit_id, businessunit_name, department_id, department_name, jobtitle_id, jobtitle_name,
  prefix_id, prefix_name, emprole, emprole_name,
  firstname, lastname, userfullname, emailaddress, contactnumber, employeeId, modeofentry,
  createdby, createddate, isactive)
VALUES (@u12, '2020-11-02', ${ES_FT:-1}, 'Full-Time Employee',
  ${BU_TECH:-1}, 'Technology Services', ${DEPT_DS:-2}, 'Data Science',
  ${JT_DS_JR:-4}, 'Data Analyst', 2, 'Ms',
  5, 'Employee', 'Jennifer', 'Martinez', 'Jennifer Martinez',
  'jennifer.martinez@acmeglobe.com', '212-555-0112', 'EMP012', 'Direct',
  1, '${CURRENT_DATETIME}', 1);

-- Employee 13: Daniel Wilson - Sales Representative
INSERT INTO main_users (emprole, userstatus, firstname, lastname, userfullname, emailaddress,
  contactnumber, emppassword, createdby, createddate, isactive, employeeId, modeofentry, selecteddate)
VALUES (5, 'old', 'Daniel', 'Wilson', 'Daniel Wilson', 'daniel.wilson@acmeglobe.com',
  '415-555-0113', '${EMP_PASS_HASH}', 1, '${CURRENT_DATETIME}', 1, 'EMP013', 'Direct', '2019-09-23');
SET @u13 = LAST_INSERT_ID();
INSERT INTO main_employees_summary (user_id, date_of_joining, emp_status_id, emp_status_name,
  businessunit_id, businessunit_name, department_id, department_name, jobtitle_id, jobtitle_name,
  prefix_id, prefix_name, emprole, emprole_name,
  firstname, lastname, userfullname, emailaddress, contactnumber, employeeId, modeofentry,
  createdby, createddate, isactive)
VALUES (@u13, '2019-09-23', ${ES_FT:-1}, 'Full-Time Employee',
  ${BU_COMM:-3}, 'Commercial Operations', ${DEPT_SALES:-7}, 'Sales',
  ${JT_SALES_REP:-14}, 'Sales Representative', 1, 'Mr',
  5, 'Employee', 'Daniel', 'Wilson', 'Daniel Wilson',
  'daniel.wilson@acmeglobe.com', '415-555-0113', 'EMP013', 'Direct',
  1, '${CURRENT_DATETIME}', 1);

-- Employee 14: Stephanie Brown - Customer Success Manager
INSERT INTO main_users (emprole, userstatus, firstname, lastname, userfullname, emailaddress,
  contactnumber, emppassword, createdby, createddate, isactive, employeeId, modeofentry, selecteddate)
VALUES (5, 'old', 'Stephanie', 'Brown', 'Stephanie Brown', 'stephanie.brown@acmeglobe.com',
  '212-555-0114', '${EMP_PASS_HASH}', 1, '${CURRENT_DATETIME}', 1, 'EMP014', 'Direct', '2018-04-16');
SET @u14 = LAST_INSERT_ID();
INSERT INTO main_employees_summary (user_id, date_of_joining, emp_status_id, emp_status_name,
  businessunit_id, businessunit_name, department_id, department_name, jobtitle_id, jobtitle_name,
  prefix_id, prefix_name, emprole, emprole_name,
  firstname, lastname, userfullname, emailaddress, contactnumber, employeeId, modeofentry,
  createdby, createddate, isactive)
VALUES (@u14, '2018-04-16', ${ES_FT:-1}, 'Full-Time Employee',
  ${BU_COMM:-3}, 'Commercial Operations', ${DEPT_CSUC:-8}, 'Customer Success',
  ${JT_CS_MGR:-15}, 'Customer Success Manager', 2, 'Ms',
  5, 'Employee', 'Stephanie', 'Brown', 'Stephanie Brown',
  'stephanie.brown@acmeglobe.com', '212-555-0114', 'EMP014', 'Direct',
  1, '${CURRENT_DATETIME}', 1);

-- Employee 15: Kevin Hernandez - Systems Engineer
INSERT INTO main_users (emprole, userstatus, firstname, lastname, userfullname, emailaddress,
  contactnumber, emppassword, createdby, createddate, isactive, employeeId, modeofentry, selecteddate)
VALUES (5, 'old', 'Kevin', 'Hernandez', 'Kevin Hernandez', 'kevin.hernandez@acmeglobe.com',
  '415-555-0115', '${EMP_PASS_HASH}', 1, '${CURRENT_DATETIME}', 1, 'EMP015', 'Direct', '2021-06-14');
SET @u15 = LAST_INSERT_ID();
INSERT INTO main_employees_summary (user_id, date_of_joining, emp_status_id, emp_status_name,
  businessunit_id, businessunit_name, department_id, department_name, jobtitle_id, jobtitle_name,
  prefix_id, prefix_name, emprole, emprole_name,
  firstname, lastname, userfullname, emailaddress, contactnumber, employeeId, modeofentry,
  createdby, createddate, isactive)
VALUES (@u15, '2021-06-14', ${ES_FT:-1}, 'Full-Time Employee',
  ${BU_TECH:-1}, 'Technology Services', ${DEPT_DEVOPS:-3}, 'DevOps & Infrastructure',
  ${JT_DEVOPS_JR:-6}, 'Systems Engineer', 1, 'Mr',
  5, 'Employee', 'Kevin', 'Hernandez', 'Kevin Hernandez',
  'kevin.hernandez@acmeglobe.com', '415-555-0115', 'EMP015', 'Direct',
  1, '${CURRENT_DATETIME}', 1);

-- Employee 16: Rachel Lee - Software Engineer
INSERT INTO main_users (emprole, userstatus, firstname, lastname, userfullname, emailaddress,
  contactnumber, emppassword, createdby, createddate, isactive, employeeId, modeofentry, selecteddate)
VALUES (5, 'old', 'Rachel', 'Lee', 'Rachel Lee', 'rachel.lee@acmeglobe.com',
  '415-555-0116', '${EMP_PASS_HASH}', 1, '${CURRENT_DATETIME}', 1, 'EMP016', 'Direct', '2022-01-10');
SET @u16 = LAST_INSERT_ID();
INSERT INTO main_employees_summary (user_id, date_of_joining, emp_status_id, emp_status_name,
  businessunit_id, businessunit_name, department_id, department_name, jobtitle_id, jobtitle_name,
  prefix_id, prefix_name, emprole, emprole_name,
  firstname, lastname, userfullname, emailaddress, contactnumber, employeeId, modeofentry,
  createdby, createddate, isactive)
VALUES (@u16, '2022-01-10', ${ES_FT:-1}, 'Full-Time Employee',
  ${BU_TECH:-1}, 'Technology Services', ${DEPT_SWE:-1}, 'Software Engineering',
  ${JT_SWE_JR:-2}, 'Software Engineer', 2, 'Ms',
  5, 'Employee', 'Rachel', 'Lee', 'Rachel Lee',
  'rachel.lee@acmeglobe.com', '415-555-0116', 'EMP016', 'Direct',
  1, '${CURRENT_DATETIME}', 1);

-- Employee 17: Brian Taylor - Financial Analyst
INSERT INTO main_users (emprole, userstatus, firstname, lastname, userfullname, emailaddress,
  contactnumber, emppassword, createdby, createddate, isactive, employeeId, modeofentry, selecteddate)
VALUES (5, 'old', 'Brian', 'Taylor', 'Brian Taylor', 'brian.taylor@acmeglobe.com',
  '212-555-0117', '${EMP_PASS_HASH}', 1, '${CURRENT_DATETIME}', 1, 'EMP017', 'Direct', '2020-04-20');
SET @u17 = LAST_INSERT_ID();
INSERT INTO main_employees_summary (user_id, date_of_joining, emp_status_id, emp_status_name,
  businessunit_id, businessunit_name, department_id, department_name, jobtitle_id, jobtitle_name,
  prefix_id, prefix_name, emprole, emprole_name,
  firstname, lastname, userfullname, emailaddress, contactnumber, employeeId, modeofentry,
  createdby, createddate, isactive)
VALUES (@u17, '2020-04-20', ${ES_FT:-1}, 'Full-Time Employee',
  ${BU_CORP:-2}, 'Corporate Services', ${DEPT_FIN:-5}, 'Finance & Accounting',
  ${JT_FIN_ANL:-10}, 'Financial Analyst', 1, 'Mr',
  5, 'Employee', 'Brian', 'Taylor', 'Brian Taylor',
  'brian.taylor@acmeglobe.com', '212-555-0117', 'EMP017', 'Direct',
  1, '${CURRENT_DATETIME}', 1);

-- Employee 18: Nicole Anderson - Marketing Specialist
INSERT INTO main_users (emprole, userstatus, firstname, lastname, userfullname, emailaddress,
  contactnumber, emppassword, createdby, createddate, isactive, employeeId, modeofentry, selecteddate)
VALUES (5, 'old', 'Nicole', 'Anderson', 'Nicole Anderson', 'nicole.anderson@acmeglobe.com',
  '415-555-0118', '${EMP_PASS_HASH}', 1, '${CURRENT_DATETIME}', 1, 'EMP018', 'Direct', '2021-09-06');
SET @u18 = LAST_INSERT_ID();
INSERT INTO main_employees_summary (user_id, date_of_joining, emp_status_id, emp_status_name,
  businessunit_id, businessunit_name, department_id, department_name, jobtitle_id, jobtitle_name,
  prefix_id, prefix_name, emprole, emprole_name,
  firstname, lastname, userfullname, emailaddress, contactnumber, employeeId, modeofentry,
  createdby, createddate, isactive)
VALUES (@u18, '2021-09-06', ${ES_FT:-1}, 'Full-Time Employee',
  ${BU_COMM:-3}, 'Commercial Operations', ${DEPT_MKT:-6}, 'Marketing',
  ${JT_MKT_SPEC:-12}, 'Marketing Specialist', 2, 'Ms',
  5, 'Employee', 'Nicole', 'Anderson', 'Nicole Anderson',
  'nicole.anderson@acmeglobe.com', '415-555-0118', 'EMP018', 'Direct',
  1, '${CURRENT_DATETIME}', 1);

-- Employee 19: Tyler Moore - Sales Representative
INSERT INTO main_users (emprole, userstatus, firstname, lastname, userfullname, emailaddress,
  contactnumber, emppassword, createdby, createddate, isactive, employeeId, modeofentry, selecteddate)
VALUES (5, 'old', 'Tyler', 'Moore', 'Tyler Moore', 'tyler.moore@acmeglobe.com',
  '212-555-0119', '${EMP_PASS_HASH}', 1, '${CURRENT_DATETIME}', 1, 'EMP019', 'Direct', '2022-05-15');
SET @u19 = LAST_INSERT_ID();
INSERT INTO main_employees_summary (user_id, date_of_joining, emp_status_id, emp_status_name,
  businessunit_id, businessunit_name, department_id, department_name, jobtitle_id, jobtitle_name,
  prefix_id, prefix_name, emprole, emprole_name,
  firstname, lastname, userfullname, emailaddress, contactnumber, employeeId, modeofentry,
  createdby, createddate, isactive)
VALUES (@u19, '2022-05-15', ${ES_FT:-1}, 'Full-Time Employee',
  ${BU_COMM:-3}, 'Commercial Operations', ${DEPT_SALES:-7}, 'Sales',
  ${JT_SALES_REP:-14}, 'Sales Representative', 1, 'Mr',
  5, 'Employee', 'Tyler', 'Moore', 'Tyler Moore',
  'tyler.moore@acmeglobe.com', '212-555-0119', 'EMP019', 'Direct',
  1, '${CURRENT_DATETIME}', 1);

-- Employee 20: Lauren Jackson - Customer Support Specialist
INSERT INTO main_users (emprole, userstatus, firstname, lastname, userfullname, emailaddress,
  contactnumber, emppassword, createdby, createddate, isactive, employeeId, modeofentry, selecteddate)
VALUES (5, 'old', 'Lauren', 'Jackson', 'Lauren Jackson', 'lauren.jackson@acmeglobe.com',
  '212-555-0120', '${EMP_PASS_HASH}', 1, '${CURRENT_DATETIME}', 1, 'EMP020', 'Direct', '2022-08-22');
SET @u20 = LAST_INSERT_ID();
INSERT INTO main_employees_summary (user_id, date_of_joining, emp_status_id, emp_status_name,
  businessunit_id, businessunit_name, department_id, department_name, jobtitle_id, jobtitle_name,
  prefix_id, prefix_name, emprole, emprole_name,
  firstname, lastname, userfullname, emailaddress, contactnumber, employeeId, modeofentry,
  createdby, createddate, isactive)
VALUES (@u20, '2022-08-22', ${ES_FT:-1}, 'Full-Time Employee',
  ${BU_COMM:-3}, 'Commercial Operations', ${DEPT_CSUC:-8}, 'Customer Success',
  ${JT_CS_SPEC:-16}, 'Customer Support Specialist', 2, 'Ms',
  5, 'Employee', 'Lauren', 'Jackson', 'Lauren Jackson',
  'lauren.jackson@acmeglobe.com', '212-555-0120', 'EMP020', 'Direct',
  1, '${CURRENT_DATETIME}', 1);
EMPSQL

echo "Running employee seed SQL..."
SEED_EXIT=0
docker exec -i sentrifugo-db mysql --force -u root -p"$DB_ROOT_PASS" "$DB_NAME" \
    < /tmp/sentrifugo_employees.sql || SEED_EXIT=$?
echo "Employee seed exit code: $SEED_EXIT"

# ============================================================
# 15b. Seed main_employees table (required for employee list view)
# Sentrifugo requires main_employees with is_orghead=1 for the employee grid to display
# ============================================================
echo "Seeding main_employees table..."

# Insert admin as org head
docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" -e "
  INSERT INTO main_employees (user_id, date_of_joining, emp_status_id, businessunit_id, department_id,
    jobtitle_id, position_id, prefix_id, is_orghead, createdby, createddate, isactive)
  VALUES (1, '2010-06-15', ${ES_FT:-1}, ${BU_TECH:-1}, ${DEPT_SWE:-1},
    ${JT_SWE_SR:-1}, 1, 1, 1, 1, '${CURRENT_DATETIME}', 1);
" 2>/dev/null

# Insert all other employees from main_employees_summary
docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" -e "
  INSERT INTO main_employees (user_id, date_of_joining, reporting_manager, emp_status_id,
    businessunit_id, department_id, jobtitle_id, prefix_id, is_orghead, createdby, createddate, isactive)
  SELECT s.user_id, s.date_of_joining, 1, s.emp_status_id,
    s.businessunit_id, s.department_id, s.jobtitle_id, s.prefix_id, 0, 1, '${CURRENT_DATETIME}', 1
  FROM main_employees_summary s
  WHERE s.user_id > 1 AND s.isactive = 1
  AND s.user_id NOT IN (SELECT user_id FROM main_employees WHERE user_id IS NOT NULL);
" 2>/dev/null

EMP_COUNT=$(docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" \
    -N -e "SELECT COUNT(*) FROM main_employees WHERE isactive=1;" 2>/dev/null | tr -d '[:space:]')
echo "main_employees seeded: $EMP_COUNT records"

# ============================================================
# 16. Seed leave types
# ============================================================
echo "Seeding leave types..."
docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" -e "
  INSERT INTO main_employeeleavetypes (leavetype, numberofdays, leavecode, description,
    leavepreallocated, leavepredeductable, createdby, createddate, isactive)
  VALUES
    ('Annual Leave', 20, 'AL', 'Paid annual vacation leave', 1, 2, 1, '${CURRENT_DATETIME}', 1),
    ('Sick Leave', 12, 'SL', 'Leave for medical reasons', 1, 2, 1, '${CURRENT_DATETIME}', 1),
    ('Personal Leave', 5, 'PL', 'Personal day off for family or personal matters', 1, 2, 1, '${CURRENT_DATETIME}', 1),
    ('Maternity Leave', 60, 'ML', 'Paid maternity leave per FMLA guidelines', 1, 2, 1, '${CURRENT_DATETIME}', 1),
    ('Paternity Leave', 10, 'PTL', 'Paid paternity leave', 1, 2, 1, '${CURRENT_DATETIME}', 1),
    ('Unpaid Leave', 0, 'UL', 'Leave without pay for extended absence', 2, 2, 1, '${CURRENT_DATETIME}', 1);
" 2>/dev/null

# ============================================================
# 17. Seed holiday group and holidays
# ============================================================
echo "Seeding holiday data..."
docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" -e "
  INSERT INTO main_holidaygroups (groupname, description, createdby, createddate, isactive)
  VALUES ('US Federal Holidays', 'Standard US federal holidays observed by Acme Global Technologies', 1, '${CURRENT_DATETIME}', 1);
" 2>/dev/null

HG_ID=$(docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" \
    -N -e "SELECT id FROM main_holidaygroups WHERE groupname='US Federal Holidays' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')

# Compute correct floating holiday dates for the current year
# nth_weekday(year, month, weekday, n) - weekday: 1=Mon..7=Sun; n=negative for "last"
nth_weekday() {
    python3 -c "
import calendar
y,m,wd,n = $1,$2,$3,$4
cal = calendar.monthcalendar(y, m)
days = [w[wd-1] for w in cal if w[wd-1] != 0]
d = days[n-1] if n > 0 else days[n]
print(f'{y}-{m:02d}-{d:02d}')
"
}
MLK_DATE=$(nth_weekday "$CURRENT_YEAR" 1 1 3)       # 3rd Monday of January
PRES_DATE=$(nth_weekday "$CURRENT_YEAR" 2 1 3)      # 3rd Monday of February
MEMORIAL_DATE=$(nth_weekday "$CURRENT_YEAR" 5 1 -1)  # Last Monday of May
LABOR_DATE=$(nth_weekday "$CURRENT_YEAR" 9 1 1)      # 1st Monday of September
THANKS_DATE=$(nth_weekday "$CURRENT_YEAR" 11 4 4)    # 4th Thursday of November

docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" -e "
  INSERT INTO main_holidaydates (holidayname, groupid, holidaydate, holidayyear, description,
    createdby, createddate, isactive)
  VALUES
    ('New Years Day', ${HG_ID:-1}, '${CURRENT_YEAR}-01-01', ${CURRENT_YEAR}, 'New Year celebration', 1, '${CURRENT_DATETIME}', 1),
    ('Martin Luther King Jr Day', ${HG_ID:-1}, '${MLK_DATE}', ${CURRENT_YEAR}, 'MLK Day', 1, '${CURRENT_DATETIME}', 1),
    ('Presidents Day', ${HG_ID:-1}, '${PRES_DATE}', ${CURRENT_YEAR}, 'Presidents Day', 1, '${CURRENT_DATETIME}', 1),
    ('Memorial Day', ${HG_ID:-1}, '${MEMORIAL_DATE}', ${CURRENT_YEAR}, 'Memorial Day', 1, '${CURRENT_DATETIME}', 1),
    ('Independence Day', ${HG_ID:-1}, '${CURRENT_YEAR}-07-04', ${CURRENT_YEAR}, 'Fourth of July', 1, '${CURRENT_DATETIME}', 1),
    ('Labor Day', ${HG_ID:-1}, '${LABOR_DATE}', ${CURRENT_YEAR}, 'Labor Day', 1, '${CURRENT_DATETIME}', 1),
    ('Thanksgiving Day', ${HG_ID:-1}, '${THANKS_DATE}', ${CURRENT_YEAR}, 'Thanksgiving', 1, '${CURRENT_DATETIME}', 1),
    ('Christmas Day', ${HG_ID:-1}, '${CURRENT_YEAR}-12-25', ${CURRENT_YEAR}, 'Christmas', 1, '${CURRENT_DATETIME}', 1);
" 2>/dev/null

# ============================================================
# 18. Seed site preferences (disable config wizard)
# ============================================================
echo "Configuring site preferences..."
docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" -e "
  UPDATE main_wizard SET iscomplete=1 WHERE id=1;
  UPDATE main_hr_wizard SET iscomplete=1 WHERE id=1;
" 2>/dev/null || echo "WARNING: Wizard disable may have failed"

# ============================================================
# 19. Verify data seeding
# ============================================================
echo "Verifying data seeding..."
EMPC=$(docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" \
    -N -e "SELECT COUNT(*) FROM main_users WHERE isactive=1;" 2>/dev/null | tr -d '[:space:]' || echo "?")
DEPTC=$(docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" \
    -N -e "SELECT COUNT(*) FROM main_departments WHERE isactive=1;" 2>/dev/null | tr -d '[:space:]' || echo "?")
JTC=$(docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" \
    -N -e "SELECT COUNT(*) FROM main_jobtitles WHERE isactive=1;" 2>/dev/null | tr -d '[:space:]' || echo "?")
LTC=$(docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" \
    -N -e "SELECT COUNT(*) FROM main_employeeleavetypes WHERE isactive=1;" 2>/dev/null | tr -d '[:space:]' || echo "?")
HOLC=$(docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" \
    -N -e "SELECT COUNT(*) FROM main_holidaydates WHERE isactive=1;" 2>/dev/null | tr -d '[:space:]' || echo "?")
echo "Seeding verification: users=$EMPC, departments=$DEPTC, job_titles=$JTC, leave_types=$LTC, holidays=$HOLC"

# ============================================================
# 20. Verify HTTP access
# ============================================================
echo "Verifying Sentrifugo HTTP access..."
wait_for_http "$SENTRIFUGO_URL" 60

# ============================================================
# 21. Configure Firefox profile
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
# 22. Warm-up Firefox at Sentrifugo login page
# ============================================================
echo "Launching Firefox warm-up..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus firefox '${SENTRIFUGO_LOGIN_URL}' > /tmp/firefox_warmup.log 2>&1 &"

FF_STARTED=false
for i in $(seq 1 30); do
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
    echo "WARNING: Firefox warm-up did not detect window within 30s"
fi

echo ""
echo "=== Sentrifugo setup complete ==="
echo "URL: $SENTRIFUGO_LOGIN_URL"
echo "Admin: $ADMIN_EMAIL / $ADMIN_PASS"
echo "Employee login: use employeeId (e.g. EMP001) as username, Employee@123 as password"
