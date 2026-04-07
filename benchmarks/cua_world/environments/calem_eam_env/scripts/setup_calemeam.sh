#!/bin/bash
# CalemEAM Setup Script (post_start hook)
# Starts MySQL, configures CalemEAM, loads data, launches Firefox
#
# Default credentials: admin / admin_password

echo "=== Setting up CalemEAM ==="

CALEMEAM_URL="http://localhost/CalemEAM/"
CALEMEAM_DIR="/var/www/html/CalemEAM"
ADMIN_USER="admin"
ADMIN_PASS="admin_password"
DB_HOST="127.0.0.1"
DB_NAME="calemeam"
DB_USER="calemeam"
DB_PASS="calemeam"

# ---- Start MySQL Docker Container ----
echo "Setting up Docker Compose configuration..."
mkdir -p /home/ga/calemeam
cp /workspace/config/docker-compose.yml /home/ga/calemeam/
chown -R ga:ga /home/ga/calemeam

echo "Starting MySQL Docker container..."
cd /home/ga/calemeam
docker-compose pull
docker-compose up -d

# ---- Wait for MySQL ----
wait_for_mysql() {
    local timeout=${1:-120}
    local elapsed=0
    echo "Waiting for MySQL to be ready..."
    while [ $elapsed -lt $timeout ]; do
        if docker exec calemeam-mysql mysqladmin ping -h localhost -uroot -proot 2>/dev/null | grep -q "alive"; then
            echo "MySQL is ready after ${elapsed}s"
            return 0
        fi
        sleep 3
        elapsed=$((elapsed + 3))
        echo "  Waiting... ${elapsed}s"
    done
    echo "WARNING: MySQL readiness check timed out after ${timeout}s"
    return 1
}

wait_for_mysql 120

# Grant permissions
echo "Configuring MySQL database..."
docker exec calemeam-mysql mysql -uroot -proot -e "
    GRANT ALL PRIVILEGES ON calemeam.* TO 'calemeam'@'%' IDENTIFIED BY 'calemeam';
    GRANT ALL PRIVILEGES ON calemeam.* TO 'root'@'%' IDENTIFIED BY 'root';
    FLUSH PRIVILEGES;
" 2>/dev/null

# Ensure Apache is running
systemctl restart apache2
sleep 2

# ---- Configure CalemEAM ----
echo "Configuring CalemEAM application..."
cat > "$CALEMEAM_DIR/server/conf/calem.custom.php" << 'CUSTOMPHP'
<?php
$_CALEM_dist['calem_db_name'] = 'calemeam';
$_CALEM_dist['calem_db_host'] = '127.0.0.1';
$_CALEM_dist['calem_db_user'] = 'calemeam';
$_CALEM_dist['calem_db_password'] = 'calemeam';
$_CALEM_dist['calem_application_host'] = 'localhost';
$_CALEM_dist['db_admin_user'] = 'root';
$_CALEM_dist['db_admin_password'] = 'root';
$_CALEM_dist['calem_root_uri']='/CalemEAM';
$_CALEM_dist['calem_request_uri']='/CalemEAM/index.php';
$_CALEM_dist['calem_soap_uri']='/CalemEAM/CalemSoapService.php';
?>
CUSTOMPHP
chown www-data:www-data "$CALEMEAM_DIR/server/conf/calem.custom.php"

# ---- Create Database Schema ----
echo "Creating database schema..."
cd "$CALEMEAM_DIR/server/setup"
php CreateSchemaCmd.php 2>/dev/null
echo "Schema created"

# ---- Load Data via Direct PHP Loader ----
echo "Loading data into CalemEAM..."
cat > "$CALEMEAM_DIR/server/setup/DirectLoad.php" << 'LOADPHP'
<?php
if (!defined("_CALEM_DIR_")) {
    chdir("../..");
    define("_CALEM_DIR_", getcwd() . "/");
}
require_once _CALEM_DIR_ . "server/conf/calem.php";
$conf = $GLOBALS["_CALEM_conf"];
$dsn = "mysql:host=" . $conf["calem_db_host"] . ";dbname=" . $conf["calem_db_name"];
$pdo = new PDO($dsn, $conf["calem_db_user"], $conf["calem_db_password"]);
$pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);

function loadDataFile($pdo, $table, $file) {
    $data = null;
    include $file;
    if (!$data || !is_array($data)) return;
    $inserted = 0;
    foreach ($data as $row) {
        $cols = array_keys($row);
        $placeholders = array_map(function($c) { return ":$c"; }, $cols);
        $sql = "INSERT IGNORE INTO $table (" . implode(",", $cols) . ") VALUES (" . implode(",", $placeholders) . ")";
        try {
            $stmt = $pdo->prepare($sql);
            $stmt->execute($row);
            $inserted++;
        } catch (Exception $e) { }
    }
    echo "  $table: $inserted/" . count($data) . "\n";
}

echo "Loading init data...\n";
$initDir = _CALEM_DIR_ . "server/setup/init/";
$initFiles = array(
    "acl_group" => "acl_group.php", "users" => "users.php",
    "asset_seq" => "asset_seq.php", "in_seq" => "in_seq.php",
    "po_seq" => "po_seq.php", "req_seq" => "req_seq.php",
    "wo_seq" => "wo_seq.php", "po_address" => "po_address.php",
    "scheduler_task" => "scheduler_task.php", "wo_semaphore" => "wo_semaphore.php",
);
foreach ($initFiles as $table => $file) {
    loadDataFile($pdo, $table, $initDir . $file);
}

echo "Loading sample data...\n";
$sampleDir = _CALEM_DIR_ . "server/setup/sampledata/";
$ordered = array(
    "acl_group", "dept", "costcode", "craft", "uom", "manufacturer", "vendor",
    "contact", "doc_type", "document", "asset_type", "in_type",
    "in_location", "users", "budget_title", "budget", "asset", "asset_comment",
    "asset_depreciation", "asset_downtime", "asset_meter", "asset_part",
    "meter_type", "meter_transaction", "inventory", "in_tran", "in_tran_worksheet",
    "pm", "workorder", "po"
);
foreach ($ordered as $table) {
    $file = $sampleDir . $table . ".php";
    if (file_exists($file)) loadDataFile($pdo, $table, $file);
}

$pdo->exec("INSERT IGNORE INTO version (id, vid, note) VALUES ('calem_version', 'r2.1e', 'CalemEAM R2.1e')");
echo "Done!\n";
?>
LOADPHP

php "$CALEMEAM_DIR/server/setup/DirectLoad.php" 2>/dev/null
echo "Data loaded"

# Verify data
ASSET_COUNT=$(docker exec calemeam-mysql mysql -uroot -proot calemeam -N -e "SELECT COUNT(*) FROM asset" 2>/dev/null)
WO_COUNT=$(docker exec calemeam-mysql mysql -uroot -proot calemeam -N -e "SELECT COUNT(*) FROM workorder" 2>/dev/null)
USER_COUNT=$(docker exec calemeam-mysql mysql -uroot -proot calemeam -N -e "SELECT COUNT(*) FROM users" 2>/dev/null)
echo "Loaded: ${ASSET_COUNT} assets, ${WO_COUNT} work orders, ${USER_COUNT} users"

# ---- Build ACL Group Cache ----
echo "Building ACL group cache..."
cp /workspace/scripts/build_cache.php "$CALEMEAM_DIR/server/setup/BuildCache.php"
cd "$CALEMEAM_DIR/server/setup"
php BuildCache.php 2>/dev/null
echo "Cache built"

# Remove installation directory (CalemEAM warns if it exists)
rm -rf "$CALEMEAM_DIR/installation"
rm -f "$CALEMEAM_DIR/server/setup/DirectLoad.php"
rm -f "$CALEMEAM_DIR/server/setup/BuildCache.php"
rm -f "$CALEMEAM_DIR/test_log.php" "$CALEMEAM_DIR/boot_log.txt"

# ---- Create DB Query Utilities ----
cat > /usr/local/bin/calemeam-db-query << 'DBQUERYEOF'
#!/bin/bash
docker exec calemeam-mysql mysql -uroot -proot calemeam -e "$1"
DBQUERYEOF
chmod +x /usr/local/bin/calemeam-db-query

cat > /usr/local/bin/calemeam-db-query-silent << 'DBQUERYEOF'
#!/bin/bash
docker exec calemeam-mysql mysql -uroot -proot calemeam -N -e "$1" 2>/dev/null
DBQUERYEOF
chmod +x /usr/local/bin/calemeam-db-query-silent

# ---- Set up Firefox Profile ----
echo "Setting up Firefox profile..."
FIREFOX_PROFILE_DIR="/home/ga/.mozilla/firefox"
sudo -u ga mkdir -p "$FIREFOX_PROFILE_DIR/default-release"

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

cat > "$FIREFOX_PROFILE_DIR/default-release/user.js" << 'USERJS'
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.rights.3.shown", true);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.shell.didSkipDefaultBrowserCheckOnFirstRun", true);
user_pref("browser.startup.homepage", "http://localhost/CalemEAM/");
user_pref("browser.startup.page", 1);
user_pref("app.update.enabled", false);
user_pref("app.update.auto", false);
user_pref("signon.rememberSignons", false);
user_pref("signon.autofillForms", false);
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
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("browser.startup.firstrunSkipsHomepage", true);
user_pref("startup.homepage_welcome_url", "");
user_pref("startup.homepage_welcome_url.additional", "");
user_pref("browser.startup.homepage_override.buildID", "20260101000000");
USERJS
chown -R ga:ga "$FIREFOX_PROFILE_DIR"

# ---- Launch Firefox ----
echo "Launching Firefox with CalemEAM..."
su - ga -c "DISPLAY=:1 firefox-esr '$CALEMEAM_URL' > /tmp/firefox_calemeam.log 2>&1 &"

sleep 5
FIREFOX_STARTED=false
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|calem"; then
        FIREFOX_STARTED=true
        echo "Firefox window detected after ${i}s"
        break
    fi
    sleep 1
done

if [ "$FIREFOX_STARTED" = true ]; then
    sleep 2
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
fi

echo ""
echo "=== CalemEAM Setup Complete ==="
echo "CalemEAM: $CALEMEAM_URL"
echo "Login: ${ADMIN_USER} / ${ADMIN_PASS}"
echo "Assets: ${ASSET_COUNT}, Work Orders: ${WO_COUNT}, Users: ${USER_COUNT}"
