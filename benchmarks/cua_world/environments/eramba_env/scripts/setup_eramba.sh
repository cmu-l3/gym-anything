#!/bin/bash
set -e

echo "=== Setting up Eramba GRC ==="

# Wait for desktop to be ready
sleep 5

# ---------------------------------------------------------------
# 1. Prepare Eramba directory and configuration
# ---------------------------------------------------------------
echo "--- Preparing Eramba configuration ---"
mkdir -p /home/ga/eramba
cp /workspace/config/docker-compose.yml /home/ga/eramba/docker-compose.yml
chown -R ga:ga /home/ga/eramba

# ---------------------------------------------------------------
# 2. Authenticate with Docker Hub (for MySQL/Redis images)
# ---------------------------------------------------------------
echo "--- Docker Hub authentication ---"
if [ -f /workspace/config/.dockerhub_credentials ]; then
    source /workspace/config/.dockerhub_credentials
    echo "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USERNAME" --password-stdin 2>/dev/null || true
    echo "Docker Hub login attempted"
fi

# ---------------------------------------------------------------
# 3. Pull and start Docker containers
# ---------------------------------------------------------------
echo "--- Starting Docker containers ---"
cd /home/ga/eramba
# Use full path to compose plugin in case 'docker compose' subcommand isn't found
# (Ubuntu docker.io package may need symlink to /usr/lib/docker/cli-plugins/)
COMPOSE_CMD="docker compose"
if ! docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD="/usr/local/lib/docker/cli-plugins/docker-compose"
fi
$COMPOSE_CMD pull 2>&1 | tail -5
$COMPOSE_CMD up -d

# ---------------------------------------------------------------
# 4. Wait for MySQL (eramba-db) to be healthy
# ---------------------------------------------------------------
echo "--- Waiting for MySQL to be ready ---"
for i in $(seq 1 60); do
    if docker exec eramba-db mysqladmin ping -h localhost -u root -peramba_root_pass 2>/dev/null | grep -q "alive"; then
        echo "MySQL is ready (attempt $i)"
        break
    fi
    echo "  Waiting for MySQL... (attempt $i/60)"
    sleep 5
done

# ---------------------------------------------------------------
# 5. Wait for Eramba web application to respond
# ---------------------------------------------------------------
echo "--- Waiting for Eramba web application ---"
# Poll HTTP port 8080 (more reliable than HTTPS 8443 on first start)
for i in $(seq 1 60); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/ 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "301" ] || [ "$HTTP_CODE" = "303" ]; then
        echo "Eramba is ready (HTTP $HTTP_CODE) (attempt $i)"
        break
    fi
    echo "  Waiting for Eramba... (attempt $i/60, HTTP $HTTP_CODE)"
    sleep 10
done

# Give eramba a bit more time to fully initialize
sleep 15

# ---------------------------------------------------------------
# 5b. Dismiss the first-run welcome screen via database
# ---------------------------------------------------------------
echo "--- Dismissing first-run welcome screen via database ---"
# Eramba's welcome screen (UsersController::welcome) checks if user_account_requirements
# table has any rows. If it does, /welcome redirects to /. Insert a row to bypass it.
# Eramba uses user_account_requirements to track account setup steps.
# Three steps must be marked complete to bypass ALL setup flows:
# 1. 'welcome' - PHP UsersController::welcome() checks find()->count() > 0
# 2. 'App.ResetPassword' - Vue /system-api/login returns welcome=true without this (for local users)
# 3. 'CommunityPack.Verification' - Email token verification required for admin users in Community
# 4. 'AdvancedFilters.AdvancedFilters' - Universal requirement for all users
for STEP in 'welcome' 'App.ResetPassword' 'CommunityPack.Verification' 'AdvancedFilters.AdvancedFilters'; do
    docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -e \
        "INSERT INTO user_account_requirements (user_id, step, completed, created) \
         SELECT 1, '${STEP}', 1, NOW() WHERE NOT EXISTS \
         (SELECT 1 FROM user_account_requirements WHERE user_id=1 AND step='${STEP}');" 2>/dev/null || true
done
echo "  All 4 user_account_requirements steps marked complete (welcome bypass applied)"

# ---------------------------------------------------------------
# 6. Handle first-run setup wizard via database
# ---------------------------------------------------------------
echo "--- Handling first-run setup wizard ---"

# Generate a bcrypt hash for admin password (Admin2024!)
# Use PHP inside the eramba container (CakePHP uses password_hash BCRYPT)
echo "  Generating bcrypt password hash..."
HASH=$(docker exec eramba-app php -r 'echo password_hash("Admin2024!", PASSWORD_DEFAULT);' 2>/dev/null || echo "")

if [ -n "$HASH" ]; then
    echo "  Password hash generated: ${HASH:0:30}..."
    # Write password + email update via temp file to avoid shell expansion of $ in bcrypt hash (pattern #21)
    # Note: users table uses 'login' not 'username'
    TEMP_SQL=$(mktemp /tmp/eramba_hash.XXXXXX.sql)
    cat > "$TEMP_SQL" << SQLEOF
UPDATE users SET password='${HASH}', email='admin@eramba.local', default_password=0, account_ready=1 WHERE login='admin' OR id=1;
SQLEOF
    docker cp "$TEMP_SQL" eramba-db:/tmp/update_admin_hash.sql
    docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -e "source /tmp/update_admin_hash.sql" 2>/dev/null || true
    docker exec eramba-db rm -f /tmp/update_admin_hash.sql
    rm -f "$TEMP_SQL"
    echo "  Admin user updated (login=admin, password=Admin2024!, email=admin@eramba.local)"
else
    echo "  WARNING: Could not generate password hash, setup wizard may need manual completion"
fi

echo "  Admin user updated successfully"

# ---------------------------------------------------------------
# 7. Seed prerequisite GRC data
# ---------------------------------------------------------------

# ---------------------------------------------------------------
# Seed prerequisite GRC data via direct DB
# ---------------------------------------------------------------
echo "--- Seeding prerequisite GRC data ---"

# ---- 7a. Configure risk calculation and appetite methods ----
# isSectionReady() in RisksTable checks that risk_calculations.method and
# risk_appetites.method are non-NULL. Without this, the Risk Management section
# fails to load (BadMethodCallException on findClassifications finder).
docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -e \
    "UPDATE risk_calculations SET method='eramba', modified=NOW() WHERE model='Risks' AND method IS NULL;
     UPDATE risk_calculations SET method='eramba', modified=NOW() WHERE model='ThirdPartyRisks' AND method IS NULL;
     UPDATE risk_calculations SET method='eramba', modified=NOW() WHERE model='BusinessContinuities' AND method IS NULL;
     UPDATE risk_appetites SET method=0, risk_appetite=3, modified=NOW() WHERE model='Risks' AND method IS NULL;
     UPDATE risk_appetites SET method=0, risk_appetite=3, modified=NOW() WHERE model='ThirdPartyRisks' AND method IS NULL;
     UPDATE risk_appetites SET method=0, risk_appetite=3, modified=NOW() WHERE model='BusinessContinuities' AND method IS NULL;" 2>/dev/null || true
echo "  Risk calculation methods configured (eramba method, integer appetite)"

# ---- 7b. Seed risks ----
# The risk_mitigation_strategies table: 1=Accept, 2=Avoid, 3=Mitigate, 4=Transfer
PHISHING_RISK_COUNT=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT COUNT(*) FROM risks WHERE title='Phishing Attacks on Employees' AND deleted=0;" 2>/dev/null || echo "0")
if [ "$PHISHING_RISK_COUNT" = "0" ]; then
    docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -e \
        "INSERT INTO risks (title, threats, vulnerabilities, description, residual_score, risk_score, risk_score_formula, residual_risk, residual_risk_formula, review, created, modified) VALUES ('Phishing Attacks on Employees', 'Social engineering, email-based attacks', 'Lack of user security awareness, weak email filtering', 'Employees may be targeted by phishing emails leading to credential theft and unauthorized access to company systems.', 0, 0.0, 'likelihood * impact', 0.0, 'likelihood * impact', '2026-01-01', NOW(), NOW());" 2>/dev/null || true
    echo "  'Phishing Attacks on Employees' risk seeded"
else
    echo "  'Phishing Attacks on Employees' risk already exists"
fi

# Seed 2 additional background risks for a realistic non-empty environment
docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -e \
    "INSERT INTO risks (title, threats, vulnerabilities, description, residual_score, risk_score, risk_score_formula, residual_risk, residual_risk_formula, review, risk_mitigation_strategy_id, created, modified)
     SELECT 'Ransomware Attack on Corporate Network', 'Malicious encryption of critical files', 'Unpatched systems, lack of endpoint protection', 'Ransomware could encrypt business-critical data and demand payment for decryption keys.', 2, 6.0, 'likelihood * impact', 2.0, 'likelihood * impact', '2026-01-01', 3, NOW(), NOW()
     WHERE NOT EXISTS (SELECT 1 FROM risks WHERE title='Ransomware Attack on Corporate Network' AND deleted=0);
     INSERT INTO risks (title, threats, vulnerabilities, description, residual_score, risk_score, risk_score_formula, residual_risk, residual_risk_formula, review, risk_mitigation_strategy_id, created, modified)
     SELECT 'Insider Threat - Unauthorized Data Exfiltration', 'Malicious or negligent employee actions', 'Insufficient DLP controls, excessive access privileges', 'Employees with privileged access may intentionally or accidentally expose sensitive company data.', 1, 4.0, 'likelihood * impact', 1.0, 'likelihood * impact', '2026-01-01', 1, NOW(), NOW()
     WHERE NOT EXISTS (SELECT 1 FROM risks WHERE title='Insider Threat - Unauthorized Data Exfiltration' AND deleted=0);" 2>/dev/null || true
echo "  Background risks seeded (3 total risks in environment)"

# ---- 7c. Seed security policies for realism ----
# Use temp file to avoid backtick-in-double-quote issues in bash heredoc.
POLICIES_SQL=$(mktemp /tmp/eramba_policies.XXXXXX.sql)
cat > "$POLICIES_SQL" << 'POLEOF'
INSERT INTO security_policies (`index`, short_description, description, document_type, security_policy_document_type_id, version, published_date, next_review_date, permission, status, created, modified)
SELECT "Acceptable Use Policy", "Defines acceptable use of company IT resources and systems", "This policy establishes guidelines for appropriate use of company IT infrastructure, networks, devices, and data by all employees and contractors.", "Policy", 3, "1.0", "2025-01-01", "2026-01-01", "private", 1, NOW(), NOW()
WHERE NOT EXISTS (SELECT 1 FROM security_policies WHERE `index`="Acceptable Use Policy" AND deleted=0);
INSERT INTO security_policies (`index`, short_description, description, document_type, security_policy_document_type_id, version, published_date, next_review_date, permission, status, created, modified)
SELECT "Password Management Policy", "Establishes password complexity and rotation requirements", "All user accounts must adhere to minimum password complexity rules. Passwords must be at least 12 characters and changed every 90 days.", "Policy", 3, "2.1", "2025-03-01", "2026-03-01", "private", 1, NOW(), NOW()
WHERE NOT EXISTS (SELECT 1 FROM security_policies WHERE `index`="Password Management Policy" AND deleted=0);
POLEOF
docker cp "$POLICIES_SQL" eramba-db:/tmp/seed_policies.sql
docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -e "source /tmp/seed_policies.sql" 2>/dev/null || true
docker exec eramba-db rm -f /tmp/seed_policies.sql
rm -f "$POLICIES_SQL"
echo "  Background security policies seeded"

# ---- 7d. Seed third parties for realism ----
docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -e \
    "INSERT INTO third_parties (name, description, third_party_type_id, created, modified)
     SELECT 'AWS (Amazon Web Services)', 'Cloud infrastructure provider hosting primary production workloads', 2, NOW(), NOW()
     WHERE NOT EXISTS (SELECT 1 FROM third_parties WHERE name='AWS (Amazon Web Services)' AND deleted=0);
     INSERT INTO third_parties (name, description, third_party_type_id, created, modified)
     SELECT 'Salesforce Inc.', 'CRM platform used by the sales and customer success teams', 2, NOW(), NOW()
     WHERE NOT EXISTS (SELECT 1 FROM third_parties WHERE name='Salesforce Inc.' AND deleted=0);" 2>/dev/null || true
echo "  Background third parties seeded"

# ---- 7e. Seed security services (internal controls) for realism ----
# Note: audits_all_done and related counter columns have no default values, must be supplied explicitly.
SERVICES_SQL=$(mktemp /tmp/eramba_services.XXXXXX.sql)
cat > "$SERVICES_SQL" << 'SVCEOF'
INSERT INTO security_services (name, objective, documentation_url, audit_metric_description, audit_success_criteria, maintenance_metric_description, audits_all_done, audits_not_all_done, audits_last_missing, audits_last_passed, audits_improvements, audits_status, maintenances_all_done, maintenances_not_all_done, maintenances_last_missing, maintenances_last_passed, security_incident_open_count, created, modified)
SELECT "Endpoint Detection and Response (EDR)", "Deploy and maintain EDR agents on all endpoints to detect and respond to threats in real time. Coverage must reach 100% of managed devices.", "", "EDR coverage percentage across managed endpoints", "100% endpoint coverage with no critical gaps", "Monthly agent health checks and signature updates", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, NOW(), NOW()
WHERE NOT EXISTS (SELECT 1 FROM security_services WHERE name="Endpoint Detection and Response (EDR)" AND deleted=0);
INSERT INTO security_services (name, objective, documentation_url, audit_metric_description, audit_success_criteria, maintenance_metric_description, audits_all_done, audits_not_all_done, audits_last_missing, audits_last_passed, audits_improvements, audits_status, maintenances_all_done, maintenances_not_all_done, maintenances_last_missing, maintenances_last_passed, security_incident_open_count, created, modified)
SELECT "Vulnerability Management Program", "Conduct regular vulnerability scans across all infrastructure and remediate Critical findings within 7 days and High within 30 days.", "", "Vulnerability scan coverage and remediation SLA compliance", "Zero open Critical vulnerabilities older than 7 days", "Weekly scan execution and monthly SLA reporting", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, NOW(), NOW()
WHERE NOT EXISTS (SELECT 1 FROM security_services WHERE name="Vulnerability Management Program" AND deleted=0);
SVCEOF
docker cp "$SERVICES_SQL" eramba-db:/tmp/seed_services.sql
docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -e "source /tmp/seed_services.sql" 2>/dev/null || true
docker exec eramba-db rm -f /tmp/seed_services.sql
rm -f "$SERVICES_SQL"
echo "  Background security services seeded"

# ---- 7f. Seed advanced_filters for all GRC models, Users, and Assets ----
# The Vue SPA reads the `filters` table (not `advanced_filters`).
# Without filters, GRC pages render blank (no table rows visible).
# Steps: seed advanced_filters → run FilterMigrationService → Vue SPA works.
echo "  Seeding advanced_filters for GRC models..."
docker exec eramba-app bash -c "cd /var/www/eramba/app/upgrade && bin/cake advanced_filters seed --table Risks,SecurityPolicies,SecurityServices,SecurityIncidents,ThirdParties,Projects,PolicyExceptions 2>&1 | tail -2" || true
docker exec eramba-app bash -c "cd /var/www/eramba/app/upgrade && bin/cake advanced_filters seed --table Users 2>&1 | tail -2" || true
docker exec eramba-app bash -c "cd /var/www/eramba/app/upgrade && bin/cake advanced_filters seed --table Assets 2>&1 | tail -2" || true
echo "  Advanced filters seeded"

# ---- 7g. Migrate advanced_filters → filters table (Laravel/Vue SPA layer) ----
echo "  Migrating to Vue SPA filters table..."
cat > /tmp/migrate_all_filters.php << 'PHPEOF'
<?php
if (!defined('ROOT')) {
    define('ROOT', '/var/www/eramba/app/upgrade');
}
chdir(ROOT);
require ROOT . '/vendor/autoload.php';
$_SERVER['argv'] = ['cake'];
require ROOT . '/config/bootstrap.php';
bootstrapLaravel();

use Eramba\Filters\Services\FilterMigrationService;
use Illuminate\Support\Facades\DB;

$migrationService = new FilterMigrationService();
$models = ['Risks', 'SecurityPolicies', 'SecurityServices', 'SecurityIncidents',
           'ThirdParties', 'Projects', 'PolicyExceptions', 'Users', 'Assets'];
$advancedFilters = DB::table('advanced_filters')->whereIn('model', $models)->get();
$migrated = 0;
$skipped = 0;
foreach ($advancedFilters as $af) {
    try {
        $filter = $migrationService->migrate($af->id, false);
        if ($filter !== null) {
            $migrated++;
        } else {
            $skipped++;
        }
    } catch (Exception $e) {
        echo "ERROR for ID {$af->id}: " . $e->getMessage() . "\n";
    }
}
echo "Migrated: $migrated, Skipped (already exist): $skipped\n";
PHPEOF
docker cp /tmp/migrate_all_filters.php eramba-app:/tmp/migrate_all_filters.php
docker exec eramba-app bash -c "php /tmp/migrate_all_filters.php 2>&1 | grep -v 'Warning'" || true
rm -f /tmp/migrate_all_filters.php
echo "  Filters migrated to Vue SPA filters table"

# ---- 7h. Sync access control ----
echo "  Syncing access control..."
docker exec eramba-app bash -c "cd /var/www/eramba/app/upgrade && bin/cake access_control sync 2>&1 | tail -3" || true
echo "  Access control synced"

# ---- 7i. Fix MultipleRiskMatrixChart null classification handling ----
# The default dashboard report has a Risk Matrix chart. When risk_classification_types
# is empty (fresh install), getByType('default') returns null → array_values(null) crash.
# Patch: add null guard so the dashboard queue job completes successfully.
echo "  Patching MultipleRiskMatrixChart.php for null classification handling..."
docker exec eramba-app bash -c "
CHART_FILE='/var/www/eramba/app/upgrade/src/Lib/Reports/Chart/MultipleRiskMatrixChart.php'
OLD_LINE='\$classificationTypes = array_values(\$classificationCollection->getByType(\"default\"));'
NEW_LINES='\$classificationData = \$classificationCollection->getByType(\"default\");'
NEW_LINES2='            if (empty(\$classificationData)) { return; }'
NEW_LINES3='\$classificationTypes = array_values(\$classificationData);'
if grep -q 'classificationData' \"\$CHART_FILE\" 2>/dev/null; then
    echo 'Already patched'
else
    sed -i 's/\\\$classificationTypes = array_values(\\\$classificationCollection->getByType(.default.));/\$classificationData = \$classificationCollection->getByType(\"default\"); if (empty(\$classificationData)) { return; } \$classificationTypes = array_values(\$classificationData);/' \"\$CHART_FILE\" 2>/dev/null || true
    echo 'Patch applied'
fi
" 2>/dev/null || true
echo "  MultipleRiskMatrixChart.php patched"

# ---- 7j. Disable MySQL ONLY_FULL_GROUP_BY for dashboard cron tasks ----
echo "  Adjusting MySQL sql_mode for Eramba compatibility..."
docker exec eramba-db bash -c "mysql -uroot -peramba_root_pass -e \"SET GLOBAL sql_mode = (SELECT REPLACE(@@sql_mode, 'ONLY_FULL_GROUP_BY,', ''));\" 2>&1" 2>/dev/null || true
echo "  MySQL sql_mode adjusted (ONLY_FULL_GROUP_BY removed)"

# ---------------------------------------------------------------
# 8. Create helper scripts for database interaction
# ---------------------------------------------------------------
echo "--- Creating database query helper ---"
cat > /usr/local/bin/eramba-db-query << 'DBEOF'
#!/bin/bash
# Execute SQL query against Eramba database
docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e "$1" 2>/dev/null
DBEOF
chmod +x /usr/local/bin/eramba-db-query

# Save admin credentials for tasks
cat > /home/ga/eramba/credentials.txt << 'CREDEOF'
URL: http://localhost:8080
Admin Username: admin
Admin Password: Admin2024!
CREDEOF
chown ga:ga /home/ga/eramba/credentials.txt

# ---------------------------------------------------------------
# 9. Extract Eramba TLS certificate for Firefox
# ---------------------------------------------------------------
echo "--- Extracting Eramba TLS certificate ---"
sleep 5

# Extract self-signed certificate from eramba
for i in $(seq 1 10); do
    openssl s_client -connect localhost:8443 -showcerts </dev/null 2>/dev/null | \
        openssl x509 -outform PEM > /tmp/eramba-cert.pem 2>/dev/null && break
    echo "  Waiting for TLS cert to be available... (attempt $i)"
    sleep 5
done

if [ -s /tmp/eramba-cert.pem ]; then
    echo "  TLS certificate extracted"
    # Add to system trust store
    cp /tmp/eramba-cert.pem /usr/local/share/ca-certificates/eramba.crt
    update-ca-certificates 2>/dev/null || true
    echo "  Certificate added to system trust store"
else
    echo "  WARNING: Could not extract TLS certificate"
fi

# ---------------------------------------------------------------
# 10. Setup Firefox with self-signed certificate acceptance
# ---------------------------------------------------------------
echo "--- Setting up Firefox ---"

# Warm-up Firefox to create profile directory (snap Firefox pattern)
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority firefox --headless https://localhost:8443 &"
sleep 12
pkill -f firefox || true
sleep 3

# Find Firefox profile directory (snap or non-snap location)
SNAP_PROFILE_DIR=$(find /home/ga/snap/firefox/common/.mozilla/firefox/ -maxdepth 1 -name '*.default*' -type d 2>/dev/null | head -1)
if [ -z "$SNAP_PROFILE_DIR" ]; then
    SNAP_PROFILE_DIR=$(find /home/ga/.mozilla/firefox/ -maxdepth 1 -name '*.default*' -type d 2>/dev/null | head -1)
fi

if [ -n "$SNAP_PROFILE_DIR" ]; then
    echo "  Found Firefox profile at: $SNAP_PROFILE_DIR"

    # Inject self-signed cert into Firefox's cert database using certutil
    if [ -s /tmp/eramba-cert.pem ]; then
        # certutil uses NSS format
        certutil -A -n "eramba-self-signed" -t "CT,," -i /tmp/eramba-cert.pem \
            -d sql:"$SNAP_PROFILE_DIR" 2>/dev/null && echo "  Cert injected into Firefox cert store" || \
            echo "  WARNING: certutil injection failed (will try enterprise roots approach)"
    fi

    # Write Firefox user preferences
    cat > "$SNAP_PROFILE_DIR/user.js" << 'FFEOF'
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutConfig.showWarning", false);
user_pref("browser.startup.homepage", "https://localhost:8443");
user_pref("browser.newtabpage.enabled", false);
user_pref("browser.startup.page", 1);
user_pref("signon.rememberSignons", false);
user_pref("browser.tabs.warnOnClose", false);
user_pref("browser.tabs.warnOnCloseOtherTabs", false);
user_pref("browser.sessionstore.resume_from_crash", false);
user_pref("toolkit.telemetry.enabled", false);
user_pref("browser.rights.3.shown", true);
user_pref("browser.startup.firstrunSkipsHomepage", true);
user_pref("browser.feeds.showFirstRunUI", false);
user_pref("browser.uitour.enabled", false);
user_pref("security.enterprise_roots.enabled", true);
user_pref("network.stricttransportsecurity.preloadlist", false);
user_pref("sidebar.revamp", false);
user_pref("sidebar.verticalTabs", false);
user_pref("browser.vpn_promo.enabled", false);
FFEOF
    chown ga:ga "$SNAP_PROFILE_DIR/user.js"
    echo "  Firefox preferences configured"
else
    echo "  WARNING: Could not find Firefox profile directory"
fi

# Create desktop shortcut
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/Eramba.desktop << 'DSKEOF'
[Desktop Entry]
Name=Eramba GRC
Comment=Governance Risk and Compliance
Exec=firefox https://localhost:8443
Icon=firefox
Terminal=false
Type=Application
Categories=Network;WebBrowser;
DSKEOF
chmod +x /home/ga/Desktop/Eramba.desktop
chown ga:ga /home/ga/Desktop/Eramba.desktop

# ---------------------------------------------------------------
# 11. Launch Firefox with Eramba
# ---------------------------------------------------------------
echo "--- Launching Firefox ---"
pkill -f firefox || true
sleep 2

su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid firefox --new-instance http://localhost:8080 > /tmp/firefox.log 2>&1 &"

# Wait for Firefox window to appear
echo "--- Waiting for Firefox window ---"
for i in $(seq 1 20); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iq "firefox\|eramba\|mozilla"; then
        echo "Firefox window detected (attempt $i)"
        break
    fi
    sleep 3
done

# Maximize Firefox window
sleep 2
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

echo "=== Eramba setup complete ==="
echo "  URL: http://localhost:8080"
echo "  Admin: admin / Admin2024!"
