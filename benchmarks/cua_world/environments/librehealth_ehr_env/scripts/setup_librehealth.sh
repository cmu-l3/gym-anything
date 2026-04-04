#!/bin/bash
# LibreHealth EHR Setup Script (post_start hook)
# Starts LibreHealth EHR via Docker with NHANES real patient data
#
# Default credentials: admin / password (with NHANES demo data)
# Data: 9,375 real NHANES patients (from official LibreHealthIO/lh-ehr repository)

echo "=== Setting up LibreHealth EHR via Docker ==="

LIBREHEALTH_URL="http://localhost:8000/interface/login/login.php?site=default"
ADMIN_USER="admin"
ADMIN_PASS="password"
DB_USER="libreehr"
DB_PASS="s3cret"
DB_NAME="libreehr"
DB_ROOT_PASS="m4ster_s3cret"
APP_CONTAINER="librehealth-app"
DB_CONTAINER="librehealth-db"

# Wait for Docker daemon to be ready
echo "Waiting for Docker daemon..."
for i in $(seq 1 30); do
    if docker info > /dev/null 2>&1; then
        echo "Docker daemon ready after ${i}s"
        break
    fi
    sleep 2
done

# Set up LibreHealth EHR working directory
echo "Setting up LibreHealth EHR directory..."
mkdir -p /home/ga/librehealth
cp /workspace/config/docker-compose.yml /home/ga/librehealth/
chown -R ga:ga /home/ga/librehealth

# Start DB and adminer containers first
echo "Starting MariaDB and Adminer containers..."
docker compose -f /home/ga/librehealth/docker-compose.yml up -d db adminer

# Wait for MariaDB to be healthy
echo "Waiting for MariaDB to be ready..."
for i in $(seq 1 60); do
    if docker exec "${DB_CONTAINER}" mysqladmin ping -h localhost -uroot -p"${DB_ROOT_PASS}" --silent 2>/dev/null; then
        echo "MariaDB is ready after ${i}s"
        break
    fi
    sleep 2
    if [ $((i % 10)) -eq 0 ]; then
        echo "  Waiting for MariaDB... ${i}s"
    fi
done

# Download and import NHANES demo database BEFORE starting app container
# NOTE: The NHANES SQL is a complete dump with DROP TABLE + CREATE TABLE statements.
# It creates all tables and populates them -- no separate schema init needed.
# Source: real National Health and Nutrition Examination Survey data from LibreHealthIO/lh-ehr
echo ""
echo "Downloading NHANES real patient data (~39MB, 9,375 patients)..."
NHANES_URL="https://github.com/LibreHealthIO/lh-ehr/raw/master/sql/nhanes/libreehr_nhanes.sql.gz"
NHANES_ALT="https://gitlab.com/librehealth/ehr/lh-ehr/-/raw/master/sql/nhanes/libreehr_nhanes.sql.gz"
NHANES_FILE="/tmp/libreehr_nhanes.sql.gz"

wget -q --timeout=300 -O "$NHANES_FILE" "$NHANES_URL" 2>/dev/null || \
wget -q --timeout=300 -O "$NHANES_FILE" "$NHANES_ALT" 2>/dev/null || true

if [ -f "$NHANES_FILE" ] && [ -s "$NHANES_FILE" ]; then
    echo "Importing NHANES data into MariaDB..."
    zcat "$NHANES_FILE" | docker exec -i "${DB_CONTAINER}" mysql -uroot -p"${DB_ROOT_PASS}" "${DB_NAME}" 2>&1 | tail -5
    rm -f "$NHANES_FILE"
    PATIENT_COUNT=$(docker exec "${DB_CONTAINER}" mysql -u"${DB_USER}" -p"${DB_PASS}" "${DB_NAME}" -N -e \
        "SELECT COUNT(*) FROM patient_data" 2>/dev/null || echo "0")
    echo "NHANES import complete. Patients loaded: ${PATIENT_COUNT}"
else
    echo "WARNING: NHANES data unavailable -- database will be empty"
fi

# Start the LibreHealth EHR app container
echo ""
echo "Starting LibreHealth EHR app container..."
docker compose -f /home/ga/librehealth/docker-compose.yml up -d lh-ehr

# Wait for container to be running
for i in $(seq 1 30); do
    if docker ps --format '{{.Names}}' | grep -q "^${APP_CONTAINER}$"; then
        echo "App container running after ${i}s"
        break
    fi
    sleep 2
done

# Write sqlconf.php via temp file + docker cp (avoids bash quoting issues with heredoc)
# $config=1 bypasses the setup wizard
echo "Writing sqlconf.php to bypass setup wizard..."
cat > /tmp/librehealth_sqlconf.php << 'PHPEOF'
<?php
//  LibreEHR
//  MySQL Config

$host   = 'db';
$port   = '3306';
$login  = 'libreehr';
$pass   = 's3cret';
$dbase  = 'libreehr';

global $disable_utf8_flag;
$disable_utf8_flag = false;

$sqlconf = array();
global $sqlconf;
$sqlconf["host"]= $host;
$sqlconf["port"] = $port;
$sqlconf["login"] = $login;
$sqlconf["pass"] = $pass;
$sqlconf["dbase"] = $dbase;
/////////WARNING!/////////
//Setting $config to = 0//
// will break this site //
//and cause SETUP to run//
$config = 1; /////////////
//////////////////////////
?>
PHPEOF

docker exec "${APP_CONTAINER}" mkdir -p /var/www/html/sites/default 2>/dev/null || true
docker cp /tmp/librehealth_sqlconf.php "${APP_CONTAINER}:/var/www/html/sites/default/sqlconf.php"
docker exec "${APP_CONTAINER}" chown www-data:www-data /var/www/html/sites/default/sqlconf.php 2>/dev/null || true
docker exec "${APP_CONTAINER}" chmod 644 /var/www/html/sites/default/sqlconf.php 2>/dev/null || true
rm -f /tmp/librehealth_sqlconf.php
echo "sqlconf.php configured"

# Wait for LibreHealth EHR to be accessible
echo "Waiting for LibreHealth EHR to be ready..."
for i in $(seq 1 60); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$LIBREHEALTH_URL" 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "303" ]; then
        echo "LibreHealth EHR is ready after ${i}s (HTTP $HTTP_CODE)"
        break
    fi
    sleep 5
    if [ $((i % 6)) -eq 0 ]; then
        echo "  Still waiting... $((i*5))s (HTTP $HTTP_CODE)"
    fi
done

# Reset admin password to 'password' using PHP inside the container
# The NHANES data has its own password hash that does not match 'password'
echo "Resetting admin password to 'password'..."
docker exec "${APP_CONTAINER}" php -r '
$password = "password";
$new_hash = password_hash($password, PASSWORD_BCRYPT, array("cost" => 10));
$new_salt = substr($new_hash, 0, 29);
$mysqli = new mysqli("librehealth-db", "libreehr", "s3cret", "libreehr");
if ($mysqli->connect_error) { die("Connection failed: " . $mysqli->connect_error . "\n"); }
$stmt = $mysqli->prepare("UPDATE users_secure SET password=?, salt=? WHERE username=\"admin\"");
$stmt->bind_param("ss", $new_hash, $new_salt);
$stmt->execute();
$rows = $stmt->affected_rows;
$stmt->close();
if ($rows == 0) {
    $id_row = $mysqli->query("SELECT id FROM users WHERE username=\"admin\"")->fetch_assoc();
    if ($id_row) {
        $stmt = $mysqli->prepare("INSERT INTO users_secure (id, username, password, salt) VALUES (?, \"admin\", ?, ?)");
        $stmt->bind_param("iss", $id_row["id"], $new_hash, $new_salt);
        $stmt->execute();
        $stmt->close();
        echo "Inserted admin password\n";
    }
} else {
    echo "Updated admin password: $rows rows\n";
}
$row = $mysqli->query("SELECT password FROM users_secure WHERE username=\"admin\"")->fetch_assoc();
echo "Verify: " . (password_verify($password, $row["password"]) ? "YES - login ready" : "NO - check failed") . "\n";
$mysqli->close();
' 2>&1
echo "Admin password reset complete"

# Create a utility script for DB queries (used by task scripts)
cat > /usr/local/bin/librehealth-query << 'DBSCRIPT'
#!/bin/bash
docker exec librehealth-db mysql -u libreehr -ps3cret libreehr -N -e "$1" 2>/dev/null
DBSCRIPT
chmod +x /usr/local/bin/librehealth-query

# Set up Firefox profile for user 'ga' (snap Firefox uses a different profile path)
echo "Setting up Firefox profile..."
SNAP_PROFILE_DIR="/home/ga/snap/firefox/common/.mozilla/firefox/default-release"
mkdir -p "$SNAP_PROFILE_DIR"
cat > "$SNAP_PROFILE_DIR/user.js" << 'USERJS'
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.rights.3.shown", true);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.shell.didSkipDefaultBrowserCheckOnFirstRun", true);
user_pref("browser.startup.homepage", "http://localhost:8000/interface/login/login.php?site=default");
user_pref("browser.startup.page", 1);
user_pref("app.update.enabled", false);
user_pref("app.update.auto", false);
user_pref("signon.rememberSignons", false);
user_pref("signon.autofillForms", false);
user_pref("sidebar.revamp", false);
user_pref("browser.sidebar.dismissed", true);
user_pref("browser.vpn_promo.enabled", false);
user_pref("browser.messaging-system.whatsNewPanel.enabled", false);
user_pref("browser.uitour.enabled", false);
user_pref("extensions.pocket.enabled", false);
user_pref("identity.fxaccounts.enabled", false);
USERJS
chown -R ga:ga "$SNAP_PROFILE_DIR"

# Create desktop shortcut
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/LibreHealth.desktop << 'DESKTOPEOF'
[Desktop Entry]
Name=LibreHealth EHR
Comment=Electronic Health Records - NHANES Data
Exec=firefox http://localhost:8000/interface/login/login.php?site=default
Icon=firefox
StartupNotify=true
Terminal=false
Type=Application
Categories=Office;Medical;
DESKTOPEOF
chown ga:ga /home/ga/Desktop/LibreHealth.desktop
chmod +x /home/ga/Desktop/LibreHealth.desktop

# Launch Firefox at LibreHealth EHR login page (snap Firefox needs correct XAUTHORITY)
echo "Launching Firefox with LibreHealth EHR..."
XAUTHORITY=/run/user/1000/gdm/Xauthority su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority firefox '$LIBREHEALTH_URL' > /tmp/firefox_librehealth.log 2>&1 &"

# Wait for Firefox window
sleep 6
for i in $(seq 1 30); do
    if DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|librehealth"; then
        echo "Firefox window detected after ${i}s"
        break
    fi
    sleep 1
done

# Maximize Firefox window
WID=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

echo ""
echo "=== LibreHealth EHR Setup Complete ==="
echo ""
echo "LibreHealth EHR: http://localhost:8000/"
echo "  Username: ${ADMIN_USER} | Password: ${ADMIN_PASS}"
echo ""
echo "NHANES Patient Data (9,375 real patients):"
echo "  librehealth-query \"SELECT COUNT(*) FROM patient_data\""
echo ""
echo "Adminer: http://localhost:8001/ | Server: db | User: ${DB_USER} | Pass: ${DB_PASS}"
