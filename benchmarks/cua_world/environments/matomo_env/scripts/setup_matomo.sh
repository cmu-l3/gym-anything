#!/bin/bash
# Matomo Setup Script (post_start hook)
# Starts Matomo via Docker, creates database tables, and launches Firefox
#
# Default credentials (set during installation wizard):
#   Super User: admin
#   Password: Admin12345
#   Email: admin@localhost.test

echo "=== Setting up Matomo via Docker ==="

# Configuration
MATOMO_URL="http://localhost/"
ADMIN_USER="admin"
ADMIN_PASS="Admin12345"
ADMIN_EMAIL="admin@localhost.test"

# Function to wait for Matomo to be ready
wait_for_matomo() {
    local timeout=${1:-180}
    local elapsed=0

    echo "Waiting for Matomo to be ready (this may take a few minutes on first run)..."

    while [ $elapsed -lt $timeout ]; do
        # Check if Matomo returns HTTP 200 or 302 (redirect to installer on first run)
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$MATOMO_URL" 2>/dev/null)
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
            echo "Matomo is ready after ${elapsed}s (HTTP $HTTP_CODE)"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        echo "  Waiting... ${elapsed}s (HTTP $HTTP_CODE)"
    done

    echo "WARNING: Matomo readiness check timed out after ${timeout}s"
    return 1
}

# Function to execute SQL
run_sql() {
    docker exec matomo-db mysql -u matomo -pmatomo123 matomo -e "$1"
}

# Copy docker-compose.yml to working directory
echo "Setting up Docker Compose configuration..."
mkdir -p /home/ga/matomo
cp /workspace/config/docker-compose.yml /home/ga/matomo/
chown -R ga:ga /home/ga/matomo

# Start Matomo containers
echo "Starting Matomo Docker containers..."
cd /home/ga/matomo

# Pull images first (better error handling)
docker-compose pull

# Start containers in detached mode
docker-compose up -d

echo "Containers starting..."
docker-compose ps

# Wait for Matomo to be fully ready
wait_for_matomo 180

# Show container status
echo ""
echo "Container status:"
docker-compose ps

# Check if Matomo needs initial setup (installation wizard)
echo ""
echo "Checking Matomo installation status..."

# Wait for database to be fully ready first
echo "Waiting for database to be ready..."
for i in {1..60}; do
    if docker exec matomo-db mysql -u matomo -pmatomo123 matomo -e "SELECT 1" &>/dev/null; then
        echo "Database is ready after ${i}s"
        break
    fi
    sleep 2
done

# Check if config.ini.php exists and has proper setup
CONFIG_EXISTS=$(docker exec matomo-app test -f /var/www/html/config/config.ini.php && echo "yes" || echo "no")
USER_COUNT=$(docker exec matomo-db mysql -u matomo -pmatomo123 matomo -N -e "SELECT COUNT(*) FROM matomo_user" 2>/dev/null || echo "0")

if [ "$CONFIG_EXISTS" = "no" ] || [ "$USER_COUNT" = "0" ]; then
    echo "Matomo installation needed..."

    # Fix directory permissions first
    docker exec matomo-app bash -c "
        mkdir -p /var/www/html/tmp/cache/tracker /var/www/html/tmp/assets
        mkdir -p /var/www/html/tmp/templates_c /var/www/html/tmp/tcpdf /var/www/html/tmp/sessions
        chown -R www-data:www-data /var/www/html/tmp /var/www/html/config
        chmod -R 775 /var/www/html/tmp /var/www/html/config
    " 2>/dev/null || true

    # IMPORTANT: Do NOT delete config.ini.php - the Docker entrypoint creates it from
    # environment variables. If it doesn't exist, create it.
    if [ "$CONFIG_EXISTS" = "no" ]; then
        echo "Creating config.ini.php..."
        docker exec matomo-app bash -c 'cat > /var/www/html/config/config.ini.php << CFGEOF
; <?php exit; ?> DO NOT REMOVE THIS LINE
; Matomo configuration file

[database]
host = "db"
username = "matomo"
password = "matomo123"
dbname = "matomo"
tables_prefix = "matomo_"
charset = "utf8mb4"

[General]
salt = "'$(head -c 32 /dev/urandom | xxd -p | head -c 32)'"
trusted_hosts[] = "localhost"
trusted_hosts[] = "127.0.0.1"
enable_browser_archiving_triggering = 1
force_ssl = 0
CFGEOF
chown www-data:www-data /var/www/html/config/config.ini.php
chmod 644 /var/www/html/config/config.ini.php'
    fi

    # ---- Approach 1: Use Matomo's console installer ----
    echo "Attempting console installation..."
    # First list available commands to see what's available
    CONSOLE_LIST=$(docker exec -u www-data matomo-app php /var/www/html/console list --raw 2>&1 | head -50) || true
    echo "Available console commands (first 50):"
    echo "$CONSOLE_LIST"

    # Try core:install if it exists
    if echo "$CONSOLE_LIST" | grep -q "core:install"; then
        echo "Running core:install..."
        docker exec -u www-data matomo-app php /var/www/html/console core:install \
            --db-host="db" --db-username="matomo" --db-password="matomo123" \
            --db-name="matomo" --db-prefix="matomo_" \
            --first-site-name="Demo Site" --first-site-url="https://example.com" \
            --superuser-login="admin" --superuser-password="Admin12345" \
            --superuser-email="admin@localhost.test" --force -n 2>&1 || true
    fi

    # Also try database:create-tables if it exists
    if echo "$CONSOLE_LIST" | grep -q "database:create-tables"; then
        echo "Running database:create-tables..."
        docker exec -u www-data matomo-app php /var/www/html/console database:create-tables -n 2>&1 || true
    fi

    sleep 3
    TABLE_COUNT=$(docker exec matomo-db mysql -u matomo -pmatomo123 matomo -N -e "SHOW TABLES LIKE 'matomo_%'" 2>/dev/null | wc -l)
    USER_COUNT=$(docker exec matomo-db mysql -u matomo -pmatomo123 matomo -N -e "SELECT COUNT(*) FROM matomo_user" 2>/dev/null || echo "0")
    echo "After console: $TABLE_COUNT tables, $USER_COUNT users"

    # ---- Approach 2: PHP script with Environment bootstrap (using existing config) ----
    if [ "$TABLE_COUNT" -lt 10 ] || [ "$USER_COUNT" = "0" ]; then
        echo "Console insufficient. Trying PHP Environment bootstrap..."

        cat > /tmp/matomo_install.php << 'PHPEOF'
<?php
error_reporting(E_ALL);
ini_set('display_errors', 1);

define('PIWIK_INCLUDE_PATH', '/var/www/html');
define('PIWIK_USER_PATH', '/var/www/html');
$_SERVER['HTTP_HOST'] = 'localhost';
$_SERVER['REQUEST_URI'] = '/';
$_SERVER['SCRIPT_NAME'] = '/index.php';
$_SERVER['REMOTE_ADDR'] = '127.0.0.1';

require_once PIWIK_INCLUDE_PATH . '/vendor/autoload.php';

echo "Config exists: " . (file_exists('/var/www/html/config/config.ini.php') ? 'YES' : 'NO') . "\n";

$tableCreated = false;

// Try 'cli' environment bootstrap (config.ini.php should already exist)
try {
    $environment = new \Piwik\Application\Environment('cli');
    $environment->init();
    echo "CLI Environment bootstrapped OK\n";

    $schema = \Piwik\Db\Schema::getInstance();
    $schema->createTables();
    echo "Tables created via CLI bootstrap\n";
    $tableCreated = true;
} catch (\Throwable $e) {
    echo "CLI bootstrap error: " . get_class($e) . ": " . $e->getMessage() . "\n";
}

// Try null environment
if (!$tableCreated) {
    try {
        $environment = new \Piwik\Application\Environment(null);
        $environment->init();
        echo "Null Environment bootstrapped OK\n";

        $schema = \Piwik\Db\Schema::getInstance();
        $schema->createTables();
        echo "Tables created via null bootstrap\n";
        $tableCreated = true;
    } catch (\Throwable $e) {
        echo "Null bootstrap error: " . get_class($e) . ": " . $e->getMessage() . "\n";
    }
}

// Try direct Db::createDatabaseObject
if (!$tableCreated) {
    try {
        \Piwik\Db::createDatabaseObject(array(
            'host' => 'db', 'username' => 'matomo', 'password' => 'matomo123',
            'dbname' => 'matomo', 'tables_prefix' => 'matomo_', 'charset' => 'utf8mb4',
            'adapter' => 'PDO\\MYSQL', 'port' => 3306, 'type' => 'InnoDB',
            'schema' => 'Mysql'
        ));
        echo "Direct DB object created OK\n";

        $schema = \Piwik\Db\Schema::getInstance();
        $schema->createTables();
        echo "Tables created via direct Db\n";
        $tableCreated = true;
    } catch (\Throwable $e) {
        echo "Direct Db error: " . get_class($e) . ": " . $e->getMessage() . "\n";
    }
}

// Verify
$pdo = new PDO('mysql:host=db;dbname=matomo;charset=utf8mb4', 'matomo', 'matomo123');
$pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
$tables = $pdo->query("SHOW TABLES LIKE 'matomo_%'")->fetchAll(PDO::FETCH_COLUMN);
echo "Tables found: " . count($tables) . "\n";
if (count($tables) > 0) echo "Tables: " . implode(', ', array_slice($tables, 0, 10)) . "...\n";

if (count($tables) >= 10) {
    // Create superuser
    try {
        $hash = password_hash('Admin12345', PASSWORD_BCRYPT);
        $pdo->exec("INSERT INTO matomo_user (login, password, email, superuser_access, date_registered, ts_password_modified)
            VALUES ('admin', '$hash', 'admin@localhost.test', 1, NOW(), NOW())
            ON DUPLICATE KEY UPDATE password='$hash', superuser_access=1");
        echo "Superuser created\n";
    } catch (\Throwable $e) { echo "Superuser: " . $e->getMessage() . "\n"; }

    try {
        $pdo->exec("INSERT INTO matomo_site (name, main_url, ts_created, ecommerce, sitesearch,
            sitesearch_keyword_parameters, sitesearch_category_parameters, timezone, currency,
            exclude_unknown_urls, excluded_ips, excluded_parameters, excluded_user_agents,
            excluded_referrers, `group`, type, keep_url_fragment, creator_login)
            VALUES ('Demo Site', 'https://example.com', NOW(), 0, 1, '', '', 'UTC', 'USD',
            0, '', '', '', '', '', 'website', 0, 'admin')
            ON DUPLICATE KEY UPDATE name='Demo Site'");
        echo "Site created\n";
    } catch (\Throwable $e) { echo "Site: " . $e->getMessage() . "\n"; }

    try {
        $matomoVersion = '';
        $versionFile = PIWIK_INCLUDE_PATH . '/core/Version.php';
        if (file_exists($versionFile)) {
            $content = file_get_contents($versionFile);
            if (preg_match("/VERSION\s*=\s*'([^']+)'/", $content, $m)) {
                $matomoVersion = $m[1];
            }
        }
        if (empty($matomoVersion)) $matomoVersion = '5.0.0';
        echo "Matomo version: $matomoVersion\n";

        $pdo->exec("INSERT INTO matomo_option (option_name, option_value, autoload) VALUES
            ('install_version', '5', 1),
            ('version_core', '$matomoVersion', 1),
            ('MatomoInstallationFinished', '1', 1),
            ('UpdateCheck_LastTimeChecked', UNIX_TIMESTAMP(), 0)
            ON DUPLICATE KEY UPDATE option_value=VALUES(option_value)");
        echo "Installation marked complete\n";
    } catch (\Throwable $e) { echo "Options: " . $e->getMessage() . "\n"; }
}

echo "DONE\n";
PHPEOF

        docker cp /tmp/matomo_install.php matomo-app:/tmp/matomo_install.php
        docker exec -u www-data matomo-app php /tmp/matomo_install.php 2>&1

        sleep 3
        TABLE_COUNT=$(docker exec matomo-db mysql -u matomo -pmatomo123 matomo -N -e "SHOW TABLES LIKE 'matomo_%'" 2>/dev/null | wc -l)
        USER_COUNT=$(docker exec matomo-db mysql -u matomo -pmatomo123 matomo -N -e "SELECT COUNT(*) FROM matomo_user" 2>/dev/null || echo "0")
        echo "After PHP: $TABLE_COUNT tables, $USER_COUNT users"
    fi

    # ---- Approach 3: Automate the web wizard via curl ----
    if [ "$TABLE_COUNT" -lt 10 ] || [ "$USER_COUNT" = "0" ]; then
        echo "PHP insufficient. Trying curl wizard automation..."

        COOKIE_JAR=/tmp/matomo_cookies
        rm -f "$COOKIE_JAR"

        # Helper: extract nonce from HTML response
        extract_nonce() {
            echo "$1" | grep -oP 'name="nonce"\s+value="\K[^"]+' || \
            echo "$1" | grep -oP "name='nonce'\s+value='\K[^']+" || \
            echo "$1" | grep -oP 'nonce[^"]*value="\K[^"]+' || true
        }

        for STEP_NAME in welcome systemCheck databaseSetup tablesCreation setupSuperUser firstWebsiteSetup trackingCode finished; do
            echo "  Wizard step: $STEP_NAME"
            RESP=$(curl -s -c "$COOKIE_JAR" -b "$COOKIE_JAR" "http://localhost/index.php?module=Installation&action=$STEP_NAME" 2>/dev/null)
            NONCE=$(extract_nonce "$RESP")

            case $STEP_NAME in
                databaseSetup)
                    curl -s -c "$COOKIE_JAR" -b "$COOKIE_JAR" -L \
                        -d "nonce=$NONCE&host=db&username=matomo&password=matomo123&dbname=matomo&tables_prefix=matomo_&adapter=PDO%5CMYSQL" \
                        "http://localhost/index.php?module=Installation&action=$STEP_NAME" > /dev/null 2>&1
                    sleep 3
                    ;;
                tablesCreation)
                    curl -s -c "$COOKIE_JAR" -b "$COOKIE_JAR" -L \
                        -d "nonce=$NONCE" \
                        "http://localhost/index.php?module=Installation&action=$STEP_NAME" > /dev/null 2>&1
                    sleep 5
                    ;;
                setupSuperUser)
                    curl -s -c "$COOKIE_JAR" -b "$COOKIE_JAR" -L \
                        -d "nonce=$NONCE&login=admin&password=Admin12345&password_bis=Admin12345&email=admin%40localhost.test&subscribe_newsletter_piwikorg=0&subscribe_newsletter_professionalservices=0" \
                        "http://localhost/index.php?module=Installation&action=$STEP_NAME" > /dev/null 2>&1
                    ;;
                firstWebsiteSetup)
                    curl -s -c "$COOKIE_JAR" -b "$COOKIE_JAR" -L \
                        -d "nonce=$NONCE&siteName=Demo+Site&url=https%3A%2F%2Fexample.com&timezone=UTC&ecommerce=0" \
                        "http://localhost/index.php?module=Installation&action=$STEP_NAME" > /dev/null 2>&1
                    ;;
                *)
                    curl -s -c "$COOKIE_JAR" -b "$COOKIE_JAR" -L \
                        -d "nonce=$NONCE" \
                        "http://localhost/index.php?module=Installation&action=$STEP_NAME" > /dev/null 2>&1
                    ;;
            esac
            sleep 1
        done

        sleep 3
        TABLE_COUNT=$(docker exec matomo-db mysql -u matomo -pmatomo123 matomo -N -e "SHOW TABLES LIKE 'matomo_%'" 2>/dev/null | wc -l)
        USER_COUNT=$(docker exec matomo-db mysql -u matomo -pmatomo123 matomo -N -e "SELECT COUNT(*) FROM matomo_user" 2>/dev/null || echo "0")
        echo "After curl wizard: $TABLE_COUNT tables, $USER_COUNT users"
    fi

    SITE_COUNT=$(docker exec matomo-db mysql -u matomo -pmatomo123 matomo -N -e "SELECT COUNT(*) FROM matomo_site" 2>/dev/null || echo "0")

    echo ""
    echo "Final state: $TABLE_COUNT tables, $USER_COUNT users, $SITE_COUNT sites"
    echo "  Login URL: http://localhost/"
    echo "  Username: ${ADMIN_USER}"
    echo "  Password: ${ADMIN_PASS}"
else
    echo "Matomo appears to be already configured"
    echo "  Config exists: $CONFIG_EXISTS"
    echo "  User count: $USER_COUNT"
fi

# Set up Firefox profile for user 'ga'
echo "Setting up Firefox profile..."
FIREFOX_PROFILE_DIR="/home/ga/.mozilla/firefox"
sudo -u ga mkdir -p "$FIREFOX_PROFILE_DIR/default-release"

# Create Firefox profiles.ini
cat > "$FIREFOX_PROFILE_DIR/profiles.ini" << 'FFPROFILE'
[Install4F96D1932A9F858E]
Default=default-release
Locked=1

[Profile0]
Name=default-release
IsRelative=1
Path=default-release
Default=1

[General]
StartWithLastProfile=1
Version=2
FFPROFILE
chown ga:ga "$FIREFOX_PROFILE_DIR/profiles.ini"

# Create user.js to configure Firefox (disable first-run dialogs, etc.)
cat > "$FIREFOX_PROFILE_DIR/default-release/user.js" << 'USERJS'
// Disable first-run screens and welcome pages
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.rights.3.shown", true);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.shell.didSkipDefaultBrowserCheckOnFirstRun", true);

// Set homepage to Matomo
user_pref("browser.startup.homepage", "http://localhost/");
user_pref("browser.startup.page", 1);

// Disable update checks
user_pref("app.update.enabled", false);
user_pref("app.update.auto", false);

// Disable password saving prompts
user_pref("signon.rememberSignons", false);
user_pref("signon.autofillForms", false);

// Disable sidebar and other popups
user_pref("sidebar.revamp", false);
user_pref("sidebar.verticalTabs", false);
user_pref("browser.sidebar.dismissed", true);
user_pref("browser.vpn_promo.enabled", false);
user_pref("browser.messaging-system.whatsNewPanel.enabled", false);
user_pref("browser.uitour.enabled", false);
user_pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.addons", false);
user_pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.features", false);
user_pref("extensions.pocket.enabled", false);
user_pref("identity.fxaccounts.enabled", false);
USERJS
chown ga:ga "$FIREFOX_PROFILE_DIR/default-release/user.js"

# Set ownership of Firefox profile
chown -R ga:ga "$FIREFOX_PROFILE_DIR"

# Create desktop shortcut
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/Matomo.desktop << 'DESKTOPEOF'
[Desktop Entry]
Name=Matomo Analytics
Comment=Web Analytics Platform
Exec=firefox http://localhost/
Icon=firefox
StartupNotify=true
Terminal=false
Type=Application
Categories=Office;Development;
DESKTOPEOF
chown ga:ga /home/ga/Desktop/Matomo.desktop
chmod +x /home/ga/Desktop/Matomo.desktop

# Create utility script for database queries
cat > /usr/local/bin/matomo-db-query << 'DBQUERYEOF'
#!/bin/bash
# Execute SQL query against Matomo database (via Docker)
docker exec matomo-db mysql -u matomo -pmatomo123 matomo -e "$1"
DBQUERYEOF
chmod +x /usr/local/bin/matomo-db-query

# Start Firefox for the ga user
echo "Launching Firefox with Matomo..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority firefox '$MATOMO_URL' > /tmp/firefox_matomo.log 2>&1 &"

# Wait for Firefox window
sleep 5
FIREFOX_STARTED=false
for i in {1..30}; do
    if DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|matomo"; then
        FIREFOX_STARTED=true
        echo "Firefox window detected after ${i}s"
        break
    fi
    sleep 1
done

if [ "$FIREFOX_STARTED" = true ]; then
    sleep 2
    # Maximize Firefox window
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
fi

echo ""
echo "=== Final Health Check ==="

# Robust health check - verify Matomo is actually accessible
HEALTH_CHECK_PASSED=false
MAX_HEALTH_RETRIES=30

for i in $(seq 1 $MAX_HEALTH_RETRIES); do
    # Check Docker containers are running
    CONTAINERS_RUNNING=$(docker ps --format "{{.Names}}" 2>/dev/null | grep -c "matomo" || echo "0")
    if [ "$CONTAINERS_RUNNING" -lt 2 ]; then
        echo "  Health check $i/$MAX_HEALTH_RETRIES: Docker containers not running ($CONTAINERS_RUNNING/2), restarting..."
        cd /home/ga/matomo && docker-compose up -d 2>/dev/null
        sleep 10
        continue
    fi

    # Check HTTP response from Matomo
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost/" 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
        # Verify page content contains Matomo (not error page)
        PAGE_CONTENT=$(curl -s "http://localhost/" 2>/dev/null | head -100)
        if echo "$PAGE_CONTENT" | grep -qi "matomo\|piwik\|installation\|sign in\|login"; then
            echo "  Health check $i/$MAX_HEALTH_RETRIES: Matomo accessible (HTTP $HTTP_CODE, content verified)"
            HEALTH_CHECK_PASSED=true
            break
        else
            echo "  Health check $i/$MAX_HEALTH_RETRIES: HTTP $HTTP_CODE but content not recognized"
        fi
    else
        echo "  Health check $i/$MAX_HEALTH_RETRIES: HTTP $HTTP_CODE (waiting...)"
    fi

    sleep 5
done

if [ "$HEALTH_CHECK_PASSED" = true ]; then
    echo ""
    echo "=== Matomo Setup Complete ==="
    echo ""
    echo "Matomo is running at: http://localhost/"
    echo ""
    echo "Login credentials:"
    echo "  Username: ${ADMIN_USER}"
    echo "  Password: ${ADMIN_PASS}"
else
    echo ""
    echo "=== WARNING: Matomo Health Check Failed ==="
    echo ""
    echo "Matomo may not be fully accessible. Common issues:"
    echo "  - Docker Hub rate limiting (wait and retry)"
    echo "  - Container startup delay (containers may still be initializing)"
    echo ""
    echo "Troubleshooting commands:"
    echo "  docker ps                                    # Check running containers"
    echo "  docker-compose -f /home/ga/matomo/docker-compose.yml logs  # View logs"
    echo "  docker-compose -f /home/ga/matomo/docker-compose.yml up -d # Restart"
fi

echo ""
echo "Database access (via Docker):"
echo "  matomo-db-query \"SELECT COUNT(*) FROM matomo_site\""
echo ""
echo "Docker commands:"
echo "  docker-compose -f /home/ga/matomo/docker-compose.yml logs -f"
echo "  docker-compose -f /home/ga/matomo/docker-compose.yml ps"
echo ""
