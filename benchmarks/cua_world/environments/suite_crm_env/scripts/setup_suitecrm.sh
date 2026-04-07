#!/bin/bash
set -e

echo "=== Setting up SuiteCRM ==="

# Wait for desktop to be ready
sleep 5

# ---------------------------------------------------------------
# 1. Prepare SuiteCRM directory and configuration
# ---------------------------------------------------------------
echo "--- Preparing SuiteCRM configuration ---"
mkdir -p /home/ga/suitecrm/docker
cp /workspace/config/docker-compose.yml /home/ga/suitecrm/
cp /workspace/config/Dockerfile /home/ga/suitecrm/docker/
cp /workspace/config/entrypoint.sh /home/ga/suitecrm/docker/
chown -R ga:ga /home/ga/suitecrm

# ---------------------------------------------------------------
# 2. Start Docker containers
# ---------------------------------------------------------------
echo "--- Starting Docker containers ---"
cd /home/ga/suitecrm
docker compose build --no-cache
docker compose up -d

# Wait for MariaDB to be ready
echo "--- Waiting for MariaDB ---"
wait_for_mysql() {
    local timeout=120
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if docker exec suitecrm-db mysqladmin ping -h localhost -u root -proot_pass 2>/dev/null | grep -q "alive"; then
            echo "MariaDB is ready (${elapsed}s)"
            return 0
        fi
        sleep 3
        elapsed=$((elapsed + 3))
    done
    echo "MariaDB timeout after ${timeout}s"
    return 1
}
wait_for_mysql

# ---------------------------------------------------------------
# 3. Wait for SuiteCRM web server to respond
# ---------------------------------------------------------------
echo "--- Waiting for SuiteCRM application ---"
wait_for_suitecrm() {
    local timeout=180
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/install.php 2>/dev/null || echo "000")
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "301" ]; then
            echo "SuiteCRM is ready (HTTP $HTTP_CODE) (${elapsed}s)"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        echo "  Waiting... (${elapsed}s, HTTP $HTTP_CODE)"
    done
    echo "SuiteCRM timeout after ${timeout}s"
    return 1
}
wait_for_suitecrm

# ---------------------------------------------------------------
# 4. Run SuiteCRM silent install
# ---------------------------------------------------------------
echo "--- Running SuiteCRM silent install ---"

# Copy silent install config into the container
docker cp /workspace/config/config_si.php suitecrm-app:/var/www/html/config_si.php
docker exec suitecrm-app chown www-data:www-data /var/www/html/config_si.php

# SuiteCRM 7.x silent install via PHP CLI
# This is the documented approach: set $_SERVER vars and include install.php
echo "  Running PHP CLI silent install..."
docker exec -u www-data suitecrm-app bash -c 'cd /var/www/html && php -r "\$_SERVER[\"HTTP_HOST\"] = \"localhost\"; \$_SERVER[\"REQUEST_URI\"] = \"install.php\"; \$_REQUEST = array(\"goto\" => \"SilentInstall\", \"cli\" => true); require_once \"install.php\";"' 2>&1 | tail -20 || true
sleep 10

# Verify config.php was created
CONFIG_EXISTS=$(docker exec suitecrm-app test -f /var/www/html/config.php && echo "yes" || echo "no")
echo "  config.php exists: $CONFIG_EXISTS"

if [ "$CONFIG_EXISTS" = "no" ]; then
    echo "  PHP CLI install failed, trying curl-based approach..."
    # Fallback: use curl with cookies to simulate browser install
    curl -c /tmp/suitecrm_cookies.txt -b /tmp/suitecrm_cookies.txt \
        -s "http://localhost:8000/install.php?goto=SilentInstall&cli=true" > /dev/null 2>&1 || true
    sleep 30
    CONFIG_EXISTS=$(docker exec suitecrm-app test -f /var/www/html/config.php && echo "yes" || echo "no")
    echo "  config.php exists after curl: $CONFIG_EXISTS"
fi

echo "  Silent install done"

# Fix permissions after install
docker exec suitecrm-app bash -c "
    chmod -R 775 /var/www/html/cache
    chmod -R 775 /var/www/html/custom
    chmod -R 775 /var/www/html/modules
    chmod -R 775 /var/www/html/upload
    chmod 775 /var/www/html/config.php 2>/dev/null
    chmod 775 /var/www/html/config_override.php 2>/dev/null
    chmod 775 /var/www/html/.htaccess 2>/dev/null
    chown -R www-data:www-data /var/www/html
" 2>/dev/null || true

# Restart Apache to pick up new config
docker exec suitecrm-app apache2ctl restart 2>/dev/null || true
sleep 5

# Verify install succeeded by checking for config.php
CONFIG_CHECK=$(docker exec suitecrm-app test -f /var/www/html/config.php && echo "ok" || echo "fail")
if [ "$CONFIG_CHECK" = "ok" ]; then
    echo "  SuiteCRM config.php exists"
else
    echo "  WARNING: config.php not found, install may have failed"
fi

# Verify login page loads (follow redirects)
LOGIN_CHECK=$(curl -sL http://localhost:8000/ 2>/dev/null | grep -ci "log.in\|LBL_LOGIN" || true)
if [ -n "$LOGIN_CHECK" ] && [ "$LOGIN_CHECK" -gt 0 ] 2>/dev/null; then
    echo "  Login page verified OK"
else
    echo "  WARNING: Login page check returned $LOGIN_CHECK"
fi

# ---------------------------------------------------------------
# 4b. Enable the Holidays module
# ---------------------------------------------------------------
# SuiteCRM 7.x has a Holidays module but it may not be visible in the
# navigation by default. Enable it by adding it to the displayed_modules
# list in config_override.php and ensuring the holidays table exists.
echo "--- Enabling Holidays module ---"
docker exec suitecrm-app bash -c '
    # Ensure the holidays DB table exists (it is part of SuiteCRM core but
    # some stripped-down releases omit it).
    cd /var/www/html
    php -r "
    define(\"sugarEntry\", true);
    require_once \"include/entryPoint.php\";

    // Create the holidays table if it does not exist
    \$db = DBManagerFactory::getInstance();
    \$result = \$db->query(\"SHOW TABLES LIKE '\''holidays'\''\");
    if (\$db->getRowCount(\$result) == 0) {
        \$query = \"CREATE TABLE holidays (
            id char(36) NOT NULL,
            name varchar(255) DEFAULT NULL,
            date_entered datetime DEFAULT NULL,
            date_modified datetime DEFAULT NULL,
            modified_user_id char(36) DEFAULT NULL,
            created_by char(36) DEFAULT NULL,
            description text,
            deleted tinyint(1) DEFAULT 0,
            holiday_date date DEFAULT NULL,
            person_id char(36) DEFAULT NULL,
            related_module varchar(50) DEFAULT NULL,
            PRIMARY KEY (id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4\";
        \$db->query(\$query);
        echo \"Created holidays table\n\";
    } else {
        echo \"Holidays table already exists\n\";
    }

    // Ensure Holidays module is in the displayed modules
    // Check modules_info for Holidays
    if (file_exists(\"modules/Holidays\")) {
        echo \"Holidays module directory exists\n\";
    } else {
        echo \"Holidays module directory does not exist, checking moduleList\n\";
    }
    "
' 2>&1 || true

# Ensure the Holidays module directory structure exists. SuiteCRM 7.x ships
# Holidays as a schedulers/admin module. If the directory is missing, create
# the minimal module scaffolding so ?module=Holidays&action=index works.
docker exec suitecrm-app bash -c '
    if [ ! -d /var/www/html/modules/Holidays ]; then
        echo "Creating Holidays module directory..."
        mkdir -p /var/www/html/modules/Holidays
        # Create minimal module metadata so SuiteCRM recognises it
        cat > /var/www/html/modules/Holidays/vardefs.php << '\''VARDEFS'\''
<?php
$dictionary["Holiday"] = array(
    "table" => "holidays",
    "fields" => array(
        "id" => array("name" => "id", "type" => "id", "required" => true),
        "name" => array("name" => "name", "vname" => "LBL_NAME", "type" => "name", "dbType" => "varchar", "len" => 255),
        "date_entered" => array("name" => "date_entered", "type" => "datetime"),
        "date_modified" => array("name" => "date_modified", "type" => "datetime"),
        "modified_user_id" => array("name" => "modified_user_id", "type" => "id"),
        "created_by" => array("name" => "created_by", "type" => "id"),
        "description" => array("name" => "description", "type" => "text"),
        "deleted" => array("name" => "deleted", "type" => "bool", "default" => 0),
        "holiday_date" => array("name" => "holiday_date", "vname" => "LBL_HOLIDAY_DATE", "type" => "date"),
        "person_id" => array("name" => "person_id", "type" => "id"),
        "related_module" => array("name" => "related_module", "type" => "varchar", "len" => 50),
    ),
    "indices" => array(
        array("name" => "holidays_pk", "type" => "primary", "fields" => array("id")),
    ),
);
VARDEFS

        # Module menu item
        cat > /var/www/html/modules/Holidays/Menu.php << '\''MENU'\''
<?php
if (!defined("sugarEntry") || !sugarEntry) die("Not A Valid Entry Point");
global $mod_strings, $app_strings;
$module_menu = array();
$module_menu[] = array("index.php?module=Holidays&action=EditView", $app_strings["LNK_NEW_RECORD"] ?? "Create Holiday", "CreateHolidays", "Holidays");
$module_menu[] = array("index.php?module=Holidays&action=index", $app_strings["LNK_LIST"] ?? "View Holidays", "Holidays", "Holidays");
MENU

        # Language file
        mkdir -p /var/www/html/modules/Holidays/language
        cat > /var/www/html/modules/Holidays/language/en_us.lang.php << '\''LANG'\''
<?php
$mod_strings = array(
    "LBL_MODULE_NAME" => "Holidays",
    "LBL_MODULE_TITLE" => "Holidays",
    "LBL_HOLIDAY_DATE" => "Holiday Date",
    "LBL_DESCRIPTION" => "Description",
    "LBL_NAME" => "Holiday Name",
    "LBL_LIST_FORM_TITLE" => "Holiday List",
    "LBL_PERSON" => "User",
    "LNK_NEW_RECORD" => "Create Holiday",
    "LNK_LIST" => "View Holidays",
);
LANG

        chown -R www-data:www-data /var/www/html/modules/Holidays
        echo "Holidays module scaffolding created"
    else
        echo "Holidays module directory already exists"
    fi
' 2>&1 || true

# Register Holidays module in SuiteCRM module registry so it is accessible
docker exec suitecrm-app bash -c '
    cd /var/www/html

    # Create a minimal Bean class if missing
    if [ ! -f modules/Holidays/Holiday.php ]; then
        cat > modules/Holidays/Holiday.php << '\''BEANPHP'\''
<?php
if (!defined("sugarEntry")) define("sugarEntry", true);
require_once "data/SugarBean.php";
class Holiday extends SugarBean {
    var $module_dir = "Holidays";
    var $object_name = "Holiday";
    var $table_name = "holidays";
    var $new_schema = true;
    var $importable = true;
    function __construct() { parent::__construct(); }
    function bean_implements($interface) { return false; }
}
BEANPHP
        chown www-data:www-data modules/Holidays/Holiday.php
        echo "Created Holiday bean class"
    fi

    # Write extension source file
    mkdir -p custom/Extension/application/Ext/Include
    cat > custom/Extension/application/Ext/Include/Holidays.php << '\''EXTPHP'\''
<?php
$beanList["Holidays"] = "Holiday";
$beanFiles["Holiday"] = "modules/Holidays/Holiday.php";
$moduleList[] = "Holidays";
EXTPHP

    # CRITICAL: Also write the compiled extension file directly
    # (rebuildExtensions() may fail silently in non-interactive context)
    mkdir -p custom/application/Ext/Include
    COMPILED="custom/application/Ext/Include/modules.ext.php"
    if [ ! -f "$COMPILED" ]; then
        echo "<?php" > "$COMPILED"
    fi
    if ! grep -q "Holidays" "$COMPILED" 2>/dev/null; then
        cat >> "$COMPILED" << '\''CEXTPHP'\''

// Holidays module registration
$beanList["Holidays"] = "Holiday";
$beanFiles["Holiday"] = "modules/Holidays/Holiday.php";
$moduleList[] = "Holidays";
CEXTPHP
        echo "Added Holidays to compiled extension include"
    fi

    # Belt-and-suspenders: also append to core include/modules.php
    if ! grep -q "Holidays" include/modules.php 2>/dev/null; then
        cat >> include/modules.php << '\''COREPHP'\''

// Holidays module
$beanList["Holidays"] = "Holiday";
$beanFiles["Holiday"] = "modules/Holidays/Holiday.php";
$moduleList[] = "Holidays";
COREPHP
        echo "Added Holidays to core modules.php"
    fi

    # Set ownership
    chown -R www-data:www-data custom/Extension/application/Ext/Include/ \
        custom/application/Ext/Include/ modules/Holidays/ include/modules.php 2>/dev/null || true

    # Targeted cache clear for Holidays module (preserves language packs etc.)
    rm -rf cache/modules/Holidays/ 2>/dev/null || true
    rm -f cache/class_map.php 2>/dev/null || true
    rm -f cache/modules/unified_search_modules.php 2>/dev/null || true
    echo "Holidays caches cleared"

    # Try running repair (may fail, thats OK - direct edits above are the real fix)
    php -r "
    define(\"sugarEntry\", true);
    \$_SESSION = array();
    require_once \"include/entryPoint.php\";
    require_once \"modules/Administration/QuickRepairAndRebuild.php\";
    \$repair = new RepairAndClear();
    \$repair->rebuildExtensions();
    echo \"Extensions rebuilt\\n\";
    " 2>&1 || echo "rebuildExtensions failed (OK - direct file edits used as fallback)"
' 2>&1 || true

# Ensure holidays DB table exists via SQL fallback (in case PHP approach failed)
docker exec suitecrm-db mysql -u suitecrm -psuitecrm_pass suitecrm -e "
    CREATE TABLE IF NOT EXISTS holidays (
        id char(36) NOT NULL,
        name varchar(255) DEFAULT NULL,
        date_entered datetime DEFAULT NULL,
        date_modified datetime DEFAULT NULL,
        modified_user_id char(36) DEFAULT NULL,
        created_by char(36) DEFAULT NULL,
        description text,
        deleted tinyint(1) DEFAULT 0,
        holiday_date date DEFAULT NULL,
        person_id char(36) DEFAULT NULL,
        related_module varchar(50) DEFAULT NULL,
        PRIMARY KEY (id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
" 2>/dev/null || true
echo "Holidays module setup complete"

# Grant admin full access to the Holidays module via ACL entries (SQL approach)
echo "--- Creating ACL entries for Holidays module ---"
ACL_EXISTS=$(docker exec suitecrm-db mysql -u suitecrm -psuitecrm_pass suitecrm -N -e "SELECT COUNT(*) FROM acl_actions WHERE category='Holidays'" 2>/dev/null || echo "0")
if [ "${ACL_EXISTS:-0}" = "0" ] || [ "${ACL_EXISTS:-0}" -lt 2 ] 2>/dev/null; then
    docker exec suitecrm-db mysql -u suitecrm -psuitecrm_pass suitecrm -e "
        DELETE FROM acl_actions WHERE category='Holidays';
        INSERT INTO acl_actions (id, date_entered, date_modified, modified_user_id, name, category, acltype, aclaccess, deleted)
        VALUES
        (UUID(), NOW(), NOW(), '1', 'access', 'Holidays', 'module', 99, 0),
        (UUID(), NOW(), NOW(), '1', 'view', 'Holidays', 'module', 99, 0),
        (UUID(), NOW(), NOW(), '1', 'list', 'Holidays', 'module', 99, 0),
        (UUID(), NOW(), NOW(), '1', 'edit', 'Holidays', 'module', 99, 0),
        (UUID(), NOW(), NOW(), '1', 'delete', 'Holidays', 'module', 99, 0),
        (UUID(), NOW(), NOW(), '1', 'import', 'Holidays', 'module', 99, 0),
        (UUID(), NOW(), NOW(), '1', 'export', 'Holidays', 'module', 99, 0),
        (UUID(), NOW(), NOW(), '1', 'massupdate', 'Holidays', 'module', 99, 0);
    " 2>/dev/null && echo "ACL entries created for Holidays" || echo "WARNING: ACL insert failed"
else
    echo "ACL entries already exist for Holidays (count: $ACL_EXISTS)"
fi

# Add Holidays module to displayed tabs via config_override.php
docker exec suitecrm-app bash -c '
    cd /var/www/html
    if ! grep -q "Holidays" config_override.php 2>/dev/null; then
        # Create a small PHP script to safely add Holidays to display_modules
        cat > /tmp/add_holidays_tab.php << "ADDTAB"
<?php
define("sugarEntry", true);
require_once "include/entryPoint.php";
// Add Holidays to the tab controller display list
require_once "modules/MySettings/TabController.php";
$tc = new TabController();
$tabs = $tc->get_system_tabs();
$tabs["Holidays"] = "Holidays";
$tc->set_system_tabs($tabs);
echo "Holidays tab added to display\n";
ADDTAB
        php /tmp/add_holidays_tab.php 2>&1 || echo "Tab add via TabController failed, using fallback"
        rm -f /tmp/add_holidays_tab.php
    fi
    chown www-data:www-data config_override.php 2>/dev/null || true
' 2>&1 || true

# Ensure admin user definitely has is_admin=1
docker exec suitecrm-db mysql -u suitecrm -psuitecrm_pass suitecrm -e \
    "UPDATE users SET is_admin=1 WHERE user_name='admin'" 2>/dev/null || true

# Create minimal list view metadata so the Holidays list page works
docker exec suitecrm-app bash -c '
    mkdir -p /var/www/html/modules/Holidays/metadata
    if [ ! -f /var/www/html/modules/Holidays/metadata/listviewdefs.php ]; then
        cat > /var/www/html/modules/Holidays/metadata/listviewdefs.php << '\''LVDEFS'\''
<?php
$listViewDefs["Holidays"] = array(
    "NAME" => array("width" => "30%", "label" => "LBL_NAME", "link" => true, "default" => true),
    "HOLIDAY_DATE" => array("width" => "20%", "label" => "LBL_HOLIDAY_DATE", "default" => true),
    "DESCRIPTION" => array("width" => "30%", "label" => "LBL_DESCRIPTION", "default" => true),
    "DATE_ENTERED" => array("width" => "20%", "label" => "LBL_DATE_ENTERED", "default" => true),
);
LVDEFS
        chown www-data:www-data /var/www/html/modules/Holidays/metadata/listviewdefs.php
    fi
    if [ ! -f /var/www/html/modules/Holidays/metadata/searchdefs.php ]; then
        cat > /var/www/html/modules/Holidays/metadata/searchdefs.php << '\''SDEFS'\''
<?php
$searchdefs["Holidays"] = array(
    "layout" => array(
        "basic_search" => array("name" => array("name" => "name", "default" => true)),
        "advanced_search" => array("name" => array("name" => "name", "default" => true)),
    ),
);
SDEFS
        chown www-data:www-data /var/www/html/modules/Holidays/metadata/searchdefs.php
    fi
    if [ ! -f /var/www/html/modules/Holidays/metadata/editviewdefs.php ]; then
        cat > /var/www/html/modules/Holidays/metadata/editviewdefs.php << '\''EVDEFS'\''
<?php
$viewdefs["Holidays"]["EditView"] = array(
    "templateMeta" => array("maxColumns" => "2", "widths" => array(array("label" => "10", "field" => "30"))),
    "panels" => array(
        "default" => array(
            array(array("name" => "name", "label" => "LBL_NAME")),
            array(array("name" => "holiday_date", "label" => "LBL_HOLIDAY_DATE")),
            array(array("name" => "description", "label" => "LBL_DESCRIPTION")),
        ),
    ),
);
EVDEFS
        chown www-data:www-data /var/www/html/modules/Holidays/metadata/editviewdefs.php
    fi

    # Targeted cache clear for Holidays module only (do NOT nuke all caches)
    rm -rf /var/www/html/cache/modules/Holidays/ 2>/dev/null || true
    rm -f /var/www/html/cache/class_map.php 2>/dev/null || true
    rm -f /var/www/html/cache/modules/unified_search_modules.php 2>/dev/null || true
' 2>&1 || true

# Restart Apache so PHP picks up new module files
docker exec suitecrm-app apache2ctl restart 2>/dev/null || true
sleep 3

# ---------------------------------------------------------------
# 5. Seed realistic CRM data
# ---------------------------------------------------------------
echo "--- Seeding CRM data ---"
cp /workspace/utils/seed_data.php /tmp/seed_data.php
docker cp /tmp/seed_data.php suitecrm-app:/tmp/seed_data.php
docker exec suitecrm-app php /tmp/seed_data.php 2>&1 | tail -10 || true
echo "  Data seeding complete"

# ---------------------------------------------------------------
# 6. Verify data was loaded
# ---------------------------------------------------------------
echo "--- Verifying seeded data ---"
ACCOUNT_COUNT=$(docker exec suitecrm-db mysql -u suitecrm -psuitecrm_pass suitecrm -N -e "SELECT COUNT(*) FROM accounts WHERE deleted=0" 2>/dev/null || echo "0")
CONTACT_COUNT=$(docker exec suitecrm-db mysql -u suitecrm -psuitecrm_pass suitecrm -N -e "SELECT COUNT(*) FROM contacts WHERE deleted=0" 2>/dev/null || echo "0")
OPP_COUNT=$(docker exec suitecrm-db mysql -u suitecrm -psuitecrm_pass suitecrm -N -e "SELECT COUNT(*) FROM opportunities WHERE deleted=0" 2>/dev/null || echo "0")
CASE_COUNT=$(docker exec suitecrm-db mysql -u suitecrm -psuitecrm_pass suitecrm -N -e "SELECT COUNT(*) FROM cases WHERE deleted=0" 2>/dev/null || echo "0")
echo "  Accounts: $ACCOUNT_COUNT"
echo "  Contacts: $CONTACT_COUNT"
echo "  Opportunities: $OPP_COUNT"
echo "  Cases: $CASE_COUNT"

# ---------------------------------------------------------------
# 7. Create database query helper
# ---------------------------------------------------------------
echo "--- Creating database query helper ---"
cat > /usr/local/bin/suitecrm-db-query << 'DBEOF'
#!/bin/bash
# Execute SQL query against SuiteCRM database
docker exec suitecrm-db mysql -u suitecrm -psuitecrm_pass suitecrm -N -e "$1" 2>/dev/null
DBEOF
chmod +x /usr/local/bin/suitecrm-db-query

# ---------------------------------------------------------------
# 8. Setup Firefox
# ---------------------------------------------------------------
echo "--- Setting up Firefox ---"

# Warm-up launch to create default profile
su - ga -c "DISPLAY=:1 firefox --headless &"
sleep 8
pkill -f firefox || true
sleep 2

# Find default profile directory (snap Firefox)
SNAP_PROFILE_DIR=$(find /home/ga/snap/firefox/common/.mozilla/firefox/ -maxdepth 1 -name '*.default*' -type d 2>/dev/null | head -1)
if [ -z "$SNAP_PROFILE_DIR" ]; then
    SNAP_PROFILE_DIR=$(find /home/ga/.mozilla/firefox/ -maxdepth 1 -name '*.default*' -type d 2>/dev/null | head -1)
fi

if [ -n "$SNAP_PROFILE_DIR" ]; then
    echo "  Found Firefox profile at: $SNAP_PROFILE_DIR"
    cat > "$SNAP_PROFILE_DIR/user.js" << 'FFEOF'
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutConfig.showWarning", false);
user_pref("browser.startup.homepage", "http://localhost:8000");
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
FFEOF
    chown ga:ga "$SNAP_PROFILE_DIR/user.js"
else
    echo "  WARNING: Could not find Firefox default profile directory"
fi

# Create desktop shortcut
cat > /home/ga/Desktop/SuiteCRM.desktop << 'DSKEOF'
[Desktop Entry]
Name=SuiteCRM
Comment=Customer Relationship Management
Exec=firefox http://localhost:8000
Icon=firefox
Terminal=false
Type=Application
Categories=Network;WebBrowser;
DSKEOF
chmod +x /home/ga/Desktop/SuiteCRM.desktop
chown ga:ga /home/ga/Desktop/SuiteCRM.desktop

# ---------------------------------------------------------------
# 9. Launch Firefox and perform initial login
# ---------------------------------------------------------------
echo "--- Launching Firefox ---"
su - ga -c "DISPLAY=:1 firefox http://localhost:8000/ &"

# Wait for Firefox window to appear
echo "--- Waiting for Firefox window ---"
FIREFOX_TIMEOUT=60
FIREFOX_ELAPSED=0
while [ $FIREFOX_ELAPSED -lt $FIREFOX_TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iq "firefox\|suitecrm\|mozilla"; then
        echo "Firefox window detected (${FIREFOX_ELAPSED}s)"
        break
    fi
    sleep 3
    FIREFOX_ELAPSED=$((FIREFOX_ELAPSED + 3))
done

# Maximize Firefox window
sleep 2
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 3

# ---------------------------------------------------------------
# 10. Auto-login to SuiteCRM (coordinates at 1920x1080)
# ---------------------------------------------------------------
echo "--- Logging into SuiteCRM ---"

# Wait for Firefox to fully render the login page
sleep 12

# SuiteCRM 7.x login page - coordinates calibrated via visual_grounding
# At 1920x1080: Username=(995,480), Password=(995,539), LOG IN=(995,597)
# Note: If "session expired" banner present, fields shift ~30px down
DISPLAY=:1 xdotool mousemove 995 480
sleep 0.3
DISPLAY=:1 xdotool click 1
sleep 0.5
DISPLAY=:1 xdotool click --repeat 3 1
sleep 0.2
DISPLAY=:1 xdotool type --delay 30 "admin"
sleep 0.3

# Tab to password field
DISPLAY=:1 xdotool key Tab
sleep 0.5
DISPLAY=:1 xdotool type --delay 30 "Admin1234!"
sleep 0.3

# Click LOG IN button
DISPLAY=:1 xdotool mousemove 995 597
sleep 0.3
DISPLAY=:1 xdotool click 1
sleep 8

# SuiteCRM may show a first-login setup wizard or redirect to dashboard
# Navigate to home/dashboard to ensure we're on the main page
DISPLAY=:1 xdotool key ctrl+l
sleep 0.5
DISPLAY=:1 xdotool key ctrl+a
sleep 0.2
DISPLAY=:1 xdotool type --delay 20 "http://localhost:8000/index.php?module=Home&action=index"
DISPLAY=:1 xdotool key Return
sleep 5

echo "=== SuiteCRM setup complete ==="
echo "  URL: http://localhost:8000"
echo "  Admin: admin / Admin1234!"
