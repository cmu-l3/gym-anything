#!/bin/bash
# NOSH ChartingSystem Setup Script (post_start hook)
# Starts NOSH via Docker Compose and initializes practice + patient data
#
# Default credentials: admin / Admin1234!

echo "=== Setting up NOSH ChartingSystem ==="

NOSH_URL="http://localhost/login"
ADMIN_USER="admin"
ADMIN_PASS="Admin1234!"

# ============================================================
# Helper: wait for web app
# ============================================================
wait_for_nosh() {
    local timeout=${1:-300}
    local elapsed=0
    echo "Waiting for NOSH to be ready (this may take a few minutes)..."
    while [ $elapsed -lt $timeout ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$NOSH_URL" 2>/dev/null)
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "301" ]; then
            echo "NOSH is ready after ${elapsed}s (HTTP $HTTP_CODE)"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        echo "  Waiting... ${elapsed}s (HTTP $HTTP_CODE)"
    done
    echo "WARNING: NOSH readiness check timed out after ${timeout}s"
    return 1
}

# ============================================================
# Helper: wait for MariaDB inside container
# ============================================================
wait_for_db() {
    local timeout=120
    local elapsed=0
    echo "Waiting for NOSH database..."
    while [ $elapsed -lt $timeout ]; do
        if docker exec nosh-db mysqladmin ping -h localhost -uroot -prootpassword --silent 2>/dev/null; then
            echo "Database ready after ${elapsed}s"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "WARNING: Database readiness check timed out"
    return 1
}

# ============================================================
# Authenticate with Docker Hub (avoid rate limits)
# ============================================================
if [ -f /workspace/config/.dockerhub_credentials ]; then
    source /workspace/config/.dockerhub_credentials
    echo "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USERNAME" --password-stdin 2>/dev/null || true
fi

# ============================================================
# Set up working directory and copy config files
# ============================================================
echo "Setting up NOSH Docker configuration..."
mkdir -p /home/ga/nosh
cp /workspace/config/docker-compose.yml /home/ga/nosh/
cp /workspace/config/nginx.conf /home/ga/nosh/
chown -R ga:ga /home/ga/nosh

# ============================================================
# Pull and start NOSH containers
# ============================================================
echo "Pulling NOSH Docker images (this may take a while)..."
cd /home/ga/nosh
docker compose pull

echo "Starting NOSH Docker containers..."
docker compose up -d

echo "Containers starting..."
docker compose ps

# Wait for database to be ready
wait_for_db

# Wait for nosh-app to finish running migrations (entrypoint does this automatically)
echo "Waiting for nosh-app to complete startup and migrations..."
sleep 30
for i in $(seq 1 20); do
    APP_STATE=$(docker inspect --format='{{.State.Status}}' nosh-app 2>/dev/null)
    if [ "$APP_STATE" = "running" ]; then
        echo "nosh-app is running"
        break
    fi
    echo "  nosh-app state: $APP_STATE (attempt $i/20)"
    sleep 5
done

# ============================================================
# Create .env file inside nosh-app container
# (NOSH's CheckInstall middleware requires .env file to exist)
# ============================================================
echo "Creating .env file in nosh-app container..."
docker exec nosh-app sh -c 'cat > /var/www/nosh/.env << ENVEOF
APP_ENV=local
APP_DEBUG=false
APP_KEY=base64:jmwtyRJvY4/JhUKDi79WJ9o3MOojEvj5tgh/8H6/XqU=
APP_URL=http://localhost

DB_CONNECTION=mysql
DB_HOST=nosh-db
DB_PORT=3306
DB_DATABASE=nosh
DB_USERNAME=asuser
DB_PASSWORD=noshpassword

CACHE_DRIVER=file
SESSION_DRIVER=file
QUEUE_DRIVER=sync

MAIL_DRIVER=log
MAIL_HOST=localhost
MAIL_PORT=25
MAIL_USERNAME=
MAIL_PASSWORD=
MAIL_ENCRYPTION=

DOCKER=1
ENVEOF
chown www-data:www-data /var/www/nosh/.env
chmod 644 /var/www/nosh/.env'

# Clear Laravel config cache after .env creation
docker exec nosh-app php artisan config:clear 2>/dev/null || true

# Create required storage directories (scans/{practice_id} needed by get_scans())
docker exec nosh-app mkdir -p /var/www/nosh/storage/app/scans/1 2>/dev/null || true
docker exec nosh-app chown -R www-data:www-data /var/www/nosh/storage/app 2>/dev/null || true

# ============================================================
# Initialize NOSH practice and admin user via direct DB
# Use pipe pattern for docker exec (more reliable than heredoc)
# ============================================================
echo "Initializing NOSH practice and admin user..."
sleep 5

# Generate bcrypt hash for Admin1234!
ADMIN_HASH=$(docker exec nosh-app php -r "echo password_hash('Admin1234!', PASSWORD_BCRYPT, ['cost' => 10]);" 2>/dev/null)
if [ -z "$ADMIN_HASH" ]; then
    ADMIN_HASH='$2y$10$6tBChBBTMVa1E3iqLI9.u.vT2Uyunn6F.jrEqN.9YLq/f.TMzI3.'
fi

# Insert groups
echo "INSERT IGNORE INTO \`groups\` (\`id\`, \`title\`, \`description\`) VALUES (1, 'admin', 'Administrator'), (2, 'provider', 'Provider'), (3, 'assistant', 'Assistant'), (4, 'billing', 'Billing'), (100, 'patient', 'Patient');" | \
    docker exec -i nosh-db mysql -uroot -prootpassword nosh 2>/dev/null || true

# Insert practice info (version must be '2.0.0' for CheckInstall to pass)
echo "INSERT IGNORE INTO \`practiceinfo\` (\`practice_id\`, \`practice_name\`, \`practicehandle\`, \`street_address1\`, \`city\`, \`state\`, \`zip\`, \`phone\`, \`fax\`, \`email\`, \`weight_unit\`, \`height_unit\`, \`temp_unit\`, \`active\`, \`version\`) VALUES (1, 'Hillside Family Medicine', 'hillside', '100 Main St', 'Springfield', 'MA', '01101', '413-555-1234', '413-555-5678', 'admin@hillsidefm.local', 'lbs', 'inches', 'F', '1', '2.0.0');" | \
    docker exec -i nosh-db mysql -uroot -prootpassword nosh 2>/dev/null || true

# Insert practiceinfo_plus (required by CheckInstall; JWK fields must be NULL not empty)
echo "INSERT IGNORE INTO \`practiceinfo_plus\` (\`practice_id\`, \`private_jwk\`, \`public_jwk\`) VALUES (1, NULL, NULL);" | \
    docker exec -i nosh-db mysql -uroot -prootpassword nosh 2>/dev/null || true

# Insert admin user
echo "INSERT IGNORE INTO \`users\` (\`id\`, \`username\`, \`email\`, \`displayname\`, \`firstname\`, \`lastname\`, \`password\`, \`group_id\`, \`active\`, \`practice_id\`) VALUES (1, 'admin', 'admin@hillsidefm.local', 'Dr. Sarah Admin', 'Sarah', 'Admin', '${ADMIN_HASH}', 1, 1, 1);" | \
    docker exec -i nosh-db mysql -uroot -prootpassword nosh 2>/dev/null || true

# Generate hash and insert provider user
PROV_HASH=$(docker exec nosh-app php -r "echo password_hash('Provider1234!', PASSWORD_BCRYPT, ['cost' => 10]);" 2>/dev/null)
if [ -z "$PROV_HASH" ]; then
    PROV_HASH='$2y$10$6tBChBBTMVa1E3iqLI9.u.vT2Uyunn6F.jrEqN.9YLq/f.TMzI3.'
fi

echo "INSERT IGNORE INTO \`users\` (\`id\`, \`username\`, \`email\`, \`displayname\`, \`firstname\`, \`lastname\`, \`password\`, \`group_id\`, \`active\`, \`practice_id\`) VALUES (2, 'demo_provider', 'provider@hillsidefm.local', 'Dr. James Carter', 'James', 'Carter', '${PROV_HASH}', 2, 1, 1);" | \
    docker exec -i nosh-db mysql -uroot -prootpassword nosh 2>/dev/null || true

# Insert provider profile (required for /users/2/1 physicians list — joins users with providers table)
echo "INSERT IGNORE INTO providers (id, npi, specialty, timeslotsperhour, schedule_increment, practice_id) VALUES (2, '1234567890', 'Family Medicine', 2, '20', 1);" | \
    docker exec -i nosh-db mysql -uroot -prootpassword nosh 2>/dev/null || true

# Set practiceinfo calendar fields (required for FullCalendar schedule page to render correctly)
# Without these, the calendar shows "Closed" blocks for all time slots
echo "UPDATE \`practiceinfo\` SET \`weekends\`='0', \`minTime\`='08:00', \`maxTime\`='18:00', \`timezone\`='America/New_York', \`mon_o\`='08:00', \`mon_c\`='17:00', \`tue_o\`='08:00', \`tue_c\`='17:00', \`wed_o\`='08:00', \`wed_c\`='17:00', \`thu_o\`='08:00', \`thu_c\`='17:00', \`fri_o\`='08:00', \`fri_c\`='17:00' WHERE \`practice_id\`=1;" | \
    docker exec -i nosh-db mysql -uroot -prootpassword nosh 2>/dev/null || true

# Insert calendar visit type (required for appointment booking — empty calendar table = no visit types available)
echo "INSERT IGNORE INTO \`calendar\` (\`visit_type\`, \`duration\`, \`active\`, \`practice_id\`, \`provider_id\`) VALUES ('Office Visit', 30, 'y', 1, 0);" | \
    docker exec -i nosh-db mysql -uroot -prootpassword nosh 2>/dev/null || true

echo "Practice and admin user initialized."

# ============================================================
# Load Synthea patient data
# ============================================================
PATIENT_DATA="/workspace/data/patients.sql"
if [ -f "$PATIENT_DATA" ]; then
    echo "Loading Synthea patient data..."
    docker cp "$PATIENT_DATA" nosh-db:/tmp/patients.sql
    docker exec nosh-db mysql -uroot -prootpassword nosh -e "source /tmp/patients.sql" 2>&1 | grep -v "Duplicate entry" | head -30
    docker exec nosh-db rm -f /tmp/patients.sql
    PATIENT_COUNT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "SELECT COUNT(*) FROM demographics" 2>/dev/null)
    echo "Loaded patients: $PATIENT_COUNT"
else
    echo "Note: patients.sql not found at $PATIENT_DATA"
fi

# ============================================================
# Set up demographics_relate for existing patients
# Note: nosh2 demographics_relate has no 'relation' column
# ============================================================
echo "Setting up patient-practice relationships..."
echo "INSERT IGNORE INTO \`demographics_relate\` (\`pid\`, \`id\`, \`practice_id\`) SELECT pid, 2, 1 FROM demographics WHERE active = 1;" | \
    docker exec -i nosh-db mysql -uroot -prootpassword nosh 2>/dev/null || true

# ============================================================
# Wait for NOSH web app to become ready
# ============================================================
wait_for_nosh 300

# ============================================================
# Set up Firefox profile
# ============================================================
echo "Setting up Firefox profile..."
FIREFOX_SNAP_DIR="/home/ga/snap/firefox/common/.mozilla/firefox"
FIREFOX_NATIVE_DIR="/home/ga/.mozilla/firefox"

if snap list firefox &>/dev/null 2>&1; then
    FF_TYPE="snap"
    FF_PROFILE_DIR="$FIREFOX_SNAP_DIR"
    FF_PROFILE_NAME="nosh.profile"
else
    FF_TYPE="native"
    FF_PROFILE_DIR="$FIREFOX_NATIVE_DIR"
    FF_PROFILE_NAME="default-release"
fi

mkdir -p "$FF_PROFILE_DIR/$FF_PROFILE_NAME"

if [ "$FF_TYPE" = "snap" ]; then
    cat > "$FIREFOX_SNAP_DIR/profiles.ini" << FFPROFILE2
[Install4F96D1932A9F858E]
Default=${FF_PROFILE_NAME}
Locked=1

[Profile0]
Name=${FF_PROFILE_NAME}
IsRelative=1
Path=${FF_PROFILE_NAME}
Default=1

[General]
StartWithLastProfile=1
Version=2
FFPROFILE2
else
    cat > "$FF_PROFILE_DIR/profiles.ini" << 'FFPROFILE'
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
fi

cat > "$FF_PROFILE_DIR/$FF_PROFILE_NAME/user.js" << 'USERJS'
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.rights.3.shown", true);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.shell.didSkipDefaultBrowserCheckOnFirstRun", true);
user_pref("browser.startup.homepage", "http://localhost/login");
user_pref("browser.startup.page", 1);
user_pref("app.update.enabled", false);
user_pref("app.update.auto", false);
user_pref("signon.rememberSignons", false);
user_pref("signon.autofillForms", false);
user_pref("browser.formfill.enable", false);
user_pref("signon.generation.enabled", false);
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

chown -R ga:ga /home/ga/snap 2>/dev/null || true
chown -R ga:ga /home/ga/.mozilla 2>/dev/null || true

# ============================================================
# Launch Firefox with NOSH login page
# ============================================================
echo "Launching Firefox with NOSH login page..."
rm -f "$FF_PROFILE_DIR/$FF_PROFILE_NAME/.parentlock" 2>/dev/null || true
rm -f "$FF_PROFILE_DIR/$FF_PROFILE_NAME/lock" 2>/dev/null || true

if [ "$FF_TYPE" = "snap" ]; then
    su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid /snap/bin/firefox --new-instance -profile '$FIREFOX_SNAP_DIR/$FF_PROFILE_NAME' 'http://localhost/login' > /tmp/firefox_nosh.log 2>&1 &"
else
    su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid firefox -profile '$FIREFOX_NATIVE_DIR/$FF_PROFILE_NAME' 'http://localhost/login' > /tmp/firefox_nosh.log 2>&1 &"
fi

sleep 5
FIREFOX_STARTED=false
for i in $(seq 1 30); do
    if DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|nosh"; then
        FIREFOX_STARTED=true
        echo "Firefox window detected after ${i}s"
        break
    fi
    sleep 1
done

if [ "$FIREFOX_STARTED" = true ]; then
    sleep 2
    WID=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
fi

# ============================================================
# Create utility script for DB queries
# ============================================================
cat > /usr/local/bin/nosh-db-query << 'DBQUERYEOF'
#!/bin/bash
docker exec nosh-db mysql -uroot -prootpassword nosh -e "$1"
DBQUERYEOF
chmod +x /usr/local/bin/nosh-db-query

echo ""
echo "=== NOSH ChartingSystem Setup Complete ==="
echo "NOSH is running at: http://localhost/login"
echo "Admin: admin / Admin1234!"
echo "Provider: demo_provider / Provider1234!"
echo "Practice: Hillside Family Medicine (practice_id=1)"
echo ""
