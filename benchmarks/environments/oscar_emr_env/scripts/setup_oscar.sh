#!/bin/bash
# OSCAR EMR Setup Script (post_start hook)
# Starts OSCAR EMR via Docker (open-osp stack) and launches Firefox
#
# Default login: oscardoc / oscar / PIN: 1117

OSCAR_URL="http://localhost:8080/oscar/login.do"
WORK_DIR="/home/ga/oscar_emr"

# Function to run docker compose (supports both v1 and v2)
docker_compose() {
    if docker compose version >/dev/null 2>&1; then
        docker compose -f "$WORK_DIR/docker-compose.yml" "$@"
    else
        docker-compose -f "$WORK_DIR/docker-compose.yml" "$@"
    fi
}

# Function to wait for OSCAR HTTP endpoint
wait_for_oscar() {
    local timeout=${1:-420}
    local elapsed=0
    echo "Waiting for OSCAR EMR to be ready (takes 3-5 minutes on first start)..."
    while [ $elapsed -lt $timeout ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$OSCAR_URL" 2>/dev/null || echo "000")
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
            echo "OSCAR EMR is ready after ${elapsed}s (HTTP $HTTP_CODE)"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        if [ $((elapsed % 30)) -eq 0 ]; then
            echo "  Still waiting... ${elapsed}s elapsed (HTTP $HTTP_CODE)"
        fi
    done
    echo "WARNING: OSCAR EMR readiness check timed out after ${timeout}s"
    docker logs oscar-app --tail 20 2>/dev/null || true
    return 1
}

echo "=== Setting up OSCAR EMR via Docker ==="

# ============================================================
# 1. Set up working directory
# ============================================================
echo "Setting up working directory..."
mkdir -p "$WORK_DIR"
cp /workspace/config/docker-compose.yml "$WORK_DIR/docker-compose.yml"
cp /workspace/config/oscar.properties "$WORK_DIR/oscar.properties"
chown -R ga:ga "$WORK_DIR"

# ============================================================
# 2. Generate SSL certificates (required by openosp/open-osp image)
# ============================================================
echo "Generating self-signed SSL certificates..."
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
    -keyout "$WORK_DIR/ssl.key" \
    -out "$WORK_DIR/ssl.crt" \
    -subj "/C=CA/ST=Ontario/L=Toronto/O=OSCAR Demo/CN=localhost" \
    2>/dev/null
chown ga:ga "$WORK_DIR/ssl.key" "$WORK_DIR/ssl.crt"
echo "SSL certificates generated."

# ============================================================
# 3. Pull Docker images (with retry)
# ============================================================
echo "Pulling Docker images..."
for i in 1 2 3; do
    if docker pull mariadb:10.5 2>/dev/null && docker pull openosp/open-osp:release 2>/dev/null; then
        echo "Docker images pulled successfully"
        break
    fi
    echo "Pull attempt $i failed, retrying in 10s..."
    sleep 10
done

# ============================================================
# 4. Start containers
# ============================================================
echo "Starting OSCAR EMR Docker containers..."
docker_compose up -d || true
echo "Containers starting..."

# ============================================================
# 5. Wait for MariaDB to be healthy
# ============================================================
echo "Waiting for MariaDB to be ready..."
for i in $(seq 1 40); do
    if docker exec oscar-db mysqladmin ping -h localhost -uroot -poscarroot 2>/dev/null; then
        echo "MariaDB ready after ${i}x3s"
        break
    fi
    sleep 3
done

# ============================================================
# 6. Initialize OSCAR database schema from /oscar-mysql-scripts/
#    These scripts are bundled inside the oscar-app container.
#    We copy the entire directory to oscar-db and run them in order.
# ============================================================
echo "Checking OSCAR database schema..."
TABLE_COUNT=$(docker exec oscar-db mysql -uroot -poscarroot -N -e \
    "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='oscar'" 2>/dev/null || echo "0")

if [ "${TABLE_COUNT:-0}" -lt 10 ] 2>/dev/null; then
    echo "Oscar DB needs initialization (found $TABLE_COUNT tables)..."

    # Wait for oscar-app container to be running
    for i in $(seq 1 30); do
        if docker ps | grep -q oscar-app; then
            break
        fi
        sleep 2
    done

    # Create the oscar database and set up privileges
    docker exec oscar-db mysql -uroot -poscarroot -e \
        "CREATE DATABASE IF NOT EXISTS oscar CHARACTER SET utf8 COLLATE utf8_general_ci;" 2>/dev/null || true
    docker exec oscar-db mysql -uroot -poscarroot -e \
        "GRANT ALL PRIVILEGES ON oscar.* TO 'oscar'@'%'; FLUSH PRIVILEGES;" 2>/dev/null || true

    # Copy the init scripts directory from oscar-app container to VM then to oscar-db
    docker cp oscar-app:/oscar-mysql-scripts /tmp/oscar-mysql-scripts 2>/dev/null || true

    if [ -d /tmp/oscar-mysql-scripts ]; then
        echo "Found /oscar-mysql-scripts — running init scripts..."
        docker cp /tmp/oscar-mysql-scripts oscar-db:/tmp/oscar-mysql-scripts 2>/dev/null || true

        # Run scripts in required order
        for SCRIPT in \
            "oscarinit.sql" \
            "oscarinit_on.sql" \
            "oscardata.sql" \
            "oscardata_additional.sql" \
            "oscardata_on.sql" \
            "expire_oscardoc.sql" \
            "caisi/initcaisi.sql"; do
            if docker exec oscar-db test -f "/tmp/oscar-mysql-scripts/$SCRIPT" 2>/dev/null; then
                echo "Running: $SCRIPT..."
                docker exec oscar-db bash -c \
                    "mysql -uroot -poscarroot --force oscar < /tmp/oscar-mysql-scripts/$SCRIPT 2>&1 | grep -v '^$' | grep -v '^mysql' | tail -3" 2>/dev/null || true
            else
                echo "  (Not found: $SCRIPT, skipping)"
            fi
        done

        # Run caisi data file if it exists
        for CAISI_SCRIPT in "caisi/initcaisidata.sql" "caisi/initcaisi.sql"; do
            if docker exec oscar-db test -f "/tmp/oscar-mysql-scripts/$CAISI_SCRIPT" 2>/dev/null; then
                echo "Running: $CAISI_SCRIPT..."
                docker exec oscar-db bash -c \
                    "mysql -uroot -poscarroot --force oscar < /tmp/oscar-mysql-scripts/$CAISI_SCRIPT 2>&1 | grep -v '^$' | tail -3" 2>/dev/null || true
            fi
        done

        echo "DB initialization complete."
        TABLE_COUNT_AFTER=$(docker exec oscar-db mysql -uroot -poscarroot -N -e \
            "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='oscar'" 2>/dev/null || echo "0")
        echo "Tables after init: $TABLE_COUNT_AFTER"
    else
        echo "WARNING: Could not find /oscar-mysql-scripts in oscar-app container"
    fi
else
    echo "Oscar DB already has $TABLE_COUNT tables — skipping initialization"
fi

# ============================================================
# 7. Patch spring_managers.xml to add FaxSchedulerJob bean
#    MUST happen BEFORE wait_for_oscar to avoid the FaxScheduler
#    boot failure. We wait for oscar-app to extract the WAR first
#    (spring_managers.xml appears after WAR extraction begins).
#    The patch must happen early — before Tomcat finishes loading
#    the context (typically within the first 30s of WAR deployment).
# ============================================================
echo "Waiting for oscar-app to extract WAR (spring_managers.xml)..."
SPRING_FILE="/usr/local/tomcat/webapps/oscar/WEB-INF/classes/spring_managers.xml"
FAX_BEAN='    <bean id="faxSchedulerJob" class="org.oscarehr.fax.core.FaxSchedulerJob" />'

for i in $(seq 1 60); do
    if docker exec oscar-app test -f "$SPRING_FILE" 2>/dev/null; then
        echo "WAR extracted after ${i}x3s"
        break
    fi
    sleep 3
done

echo "Patching spring_managers.xml to add FaxSchedulerJob bean..."
if docker exec oscar-app grep -q "faxSchedulerJob" "$SPRING_FILE" 2>/dev/null; then
    echo "spring_managers.xml already patched, skipping restart"
else
    echo "Adding faxSchedulerJob bean to spring_managers.xml..."
    docker exec oscar-app sed -i "s|</beans>|$FAX_BEAN\n</beans>|" "$SPRING_FILE" 2>/dev/null || true
    echo "spring_managers.xml patched — restarting oscar-app to apply..."
    docker restart oscar-app 2>/dev/null || true
    sleep 5
fi

# ============================================================
# 8. Wait for OSCAR EMR webapp to be ready
# ============================================================
wait_for_oscar 420

# ============================================================
# 9. Fix oscardoc account password and expiry
#    OSCAR's checkPassword() uses SHA-1 (EncryptionUtils.getSha1)
#    and concatenates the bytes as signed integers (no separator).
#    Password 'oscar' SHA-1 = 45-179-551441115-117798-30877213-3052-6889-30-60
# ============================================================
echo "Setting oscardoc password and fixing account..."
OSCAR_PW_HASH="45-179-551441115-117798-30877213-3052-6889-30-60"

for i in 1 2 3; do
    if docker exec oscar-db mysql -u oscar -poscar oscar -e \
        "UPDATE security SET password='${OSCAR_PW_HASH}', forcePasswordReset=0,
         date_ExpireDate=DATE_ADD(CURDATE(), INTERVAL 3600 DAY), b_ExpireSet=0
         WHERE user_name='oscardoc';" 2>/dev/null; then
        echo "oscardoc account configured (password: oscar, PIN: 1117)"
        break
    fi
    echo "Account update attempt $i failed, waiting 15s..."
    sleep 15
done

# ============================================================
# 10. Ensure provider record for oscardoc exists
#     Use provider_no=999998 for oscardoc (scheduler user).
#     seed_patients.sql adds provider_no=999999 for Dr. Chen.
# ============================================================
echo "Ensuring provider record for oscardoc (999998)..."
docker exec oscar-db mysql -u oscar -poscar oscar -e \
    "INSERT IGNORE INTO provider (provider_no, last_name, first_name, provider_type, sex, specialty,
     work_phone, status, ohip_no)
     VALUES ('999998', 'Chen', 'Sarah', 'doctor', 'F', 'General Practice',
     '(416) 555-0100', '1', '123456789');" 2>/dev/null || true

# Link oscardoc security user to provider 999998
docker exec oscar-db mysql -u oscar -poscar oscar -e \
    "UPDATE security SET provider_no='999998' WHERE user_name='oscardoc';" 2>/dev/null || true

# ============================================================
# 11. Seed realistic patient data
# ============================================================
PATIENT_DATA="/workspace/data/seed_patients.sql"
if [ -f "$PATIENT_DATA" ]; then
    echo "Loading patient data..."

    # Check if patients already seeded
    EXISTING=$(docker exec oscar-db mysql -u oscar -poscar oscar -N -e \
        "SELECT COUNT(*) FROM demographic" 2>/dev/null || echo "0")

    if [ "${EXISTING:-0}" -lt 5 ]; then
        docker cp "$PATIENT_DATA" oscar-db:/tmp/seed_patients.sql 2>/dev/null || true
        docker exec oscar-db bash -c \
            "mysql -u oscar -poscar oscar < /tmp/seed_patients.sql 2>&1 | grep -E '(ERROR|error)' | grep -v 'Duplicate entry' | tail -5" 2>/dev/null || true
        docker exec oscar-db rm -f /tmp/seed_patients.sql 2>/dev/null || true
        PATIENT_COUNT=$(docker exec oscar-db mysql -u oscar -poscar oscar -N -e \
            "SELECT COUNT(*) FROM demographic" 2>/dev/null || echo "0")
        echo "Patient count after seed: $PATIENT_COUNT"
    else
        echo "Patients already seeded ($EXISTING records), skipping"
    fi
fi

# ============================================================
# 12. Set up Firefox profile (suppress first-run dialogs)
# ============================================================
echo "Setting up Firefox profile..."
FIREFOX_PROFILE_DIR="/home/ga/.mozilla/firefox"
mkdir -p "$FIREFOX_PROFILE_DIR/default-release"

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

cat > "$FIREFOX_PROFILE_DIR/default-release/user.js" << 'USERJS'
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.rights.3.shown", true);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.shell.didSkipDefaultBrowserCheckOnFirstRun", true);
user_pref("browser.startup.homepage", "http://localhost:8080/oscar/login.jsp");
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
user_pref("dom.security.https_only_mode", false);
user_pref("dom.security.https_only_mode_ever_enabled", false);
USERJS

chown -R ga:ga "$FIREFOX_PROFILE_DIR"

# ============================================================
# 13. Create desktop shortcut and helper script
# ============================================================
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/OSCAR_EMR.desktop << 'DESKTOPEOF'
[Desktop Entry]
Name=OSCAR EMR
Comment=Open Source Clinical Application and Resource EMR
Exec=firefox http://localhost:8080/oscar/login.jsp
Icon=firefox
StartupNotify=true
Terminal=false
Type=Application
Categories=Office;Medical;
DESKTOPEOF
chown ga:ga /home/ga/Desktop/OSCAR_EMR.desktop
chmod +x /home/ga/Desktop/OSCAR_EMR.desktop

# Helper for DB queries
cat > /usr/local/bin/oscar-query << 'DBQUERYEOF'
#!/bin/bash
docker exec oscar-db mysql -u oscar -poscar oscar -e "$1"
DBQUERYEOF
chmod +x /usr/local/bin/oscar-query

# ============================================================
# 14. Launch Firefox (warm-up to suppress first-run dialogs)
#     Use sudo -u ga to avoid TTY requirement of su -
# ============================================================
echo "Launching Firefox for warm-up..."
sudo -u ga DISPLAY=:1 nohup firefox "http://localhost:8080/oscar/login.jsp" > /tmp/firefox_oscar.log 2>&1 &

sleep 5
for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|OSCAR"; then
        echo "Firefox window detected after ${i}s"
        sleep 2
        WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
        if [ -n "$WID" ]; then
            DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
            DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        fi
        break
    fi
    sleep 1
done

# ============================================================
# Print status summary
# ============================================================
echo ""
echo "=== OSCAR EMR Setup Complete ==="
echo ""
echo "OSCAR EMR is running at: http://localhost:8080/oscar/"
echo ""
echo "Login Credentials:"
echo "  Username: oscardoc"
echo "  Password: oscar"
echo "  PIN:      1117"
echo ""
FINAL_COUNT=$(docker exec oscar-db mysql -u oscar -poscar oscar -N -e \
    "SELECT COUNT(*) FROM demographic" 2>/dev/null || echo "?")
echo "Patients in DB: $FINAL_COUNT"
echo ""
docker ps --format "table {{.Names}}\t{{.Status}}" 2>/dev/null || true
