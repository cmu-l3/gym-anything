#!/bin/bash
# Casebox Setup Script (post_start hook)
# Starts MySQL (Docker), configures Casebox, starts services, seeds data, configures Firefox.

set -euo pipefail

echo "=== Setting up Casebox ==="

CASEBOX_BASE_URL="http://localhost/c/default"
CASEBOX_DIR="/var/www/casebox"

# ============================================================
# Helper: wait for HTTP readiness
# ============================================================
wait_for_http() {
  local url="$1"
  local timeout_sec="${2:-300}"
  local elapsed=0

  echo "Waiting for HTTP readiness: $url"

  while [ "$elapsed" -lt "$timeout_sec" ]; do
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || true)
    [ -z "$code" ] && code="000"

    if [ "$code" = "200" ] || [ "$code" = "302" ] || [ "$code" = "303" ] || [ "$code" = "500" ]; then
      echo "HTTP ready after ${elapsed}s (HTTP $code)"
      return 0
    fi

    sleep 5
    elapsed=$((elapsed + 5))
    echo "  waiting... ${elapsed}s (HTTP $code)"
  done

  echo "ERROR: Timeout waiting for service at $url"
  return 1
}

# ============================================================
# 1. Start MySQL via Docker
# ============================================================
echo "Starting MySQL container..."

# Remove any existing container
docker rm -f casebox-db 2>/dev/null || true

docker run -d \
    --name casebox-db \
    --restart unless-stopped \
    -p 3306:3306 \
    -e MYSQL_DATABASE=casebox \
    -e MYSQL_USER=casebox \
    -e MYSQL_PASSWORD=CaseboxPass123 \
    -e MYSQL_ROOT_PASSWORD=RootPass123 \
    mysql:5.7 \
    --character-set-server=utf8mb4 \
    --collation-server=utf8mb4_unicode_ci \
    --max_allowed_packet=64M

# Wait for MySQL to be ready
echo "Waiting for MySQL..."
for i in $(seq 1 90); do
    if docker exec casebox-db mysqladmin ping -h localhost -u root -pRootPass123 2>/dev/null; then
        echo "MySQL is ready after $((i * 2))s"
        break
    fi
    if [ "$i" -eq 90 ]; then
        echo "ERROR: MySQL timeout"
        exit 1
    fi
    sleep 2
done

# Extra wait for MySQL to be fully initialized
sleep 5

# ============================================================
# 2. Import Casebox database
# ============================================================
echo "Importing Casebox default database..."

# Check if tables already exist
TABLES=$(docker exec casebox-db mysql -u casebox -pCaseboxPass123 casebox -N -e "SHOW TABLES" 2>/dev/null | wc -l || echo "0")

if [ "$TABLES" -lt 5 ]; then
    if [ -f "$CASEBOX_DIR/var/backup/cb_default.sql" ]; then
        docker exec -i casebox-db mysql -u casebox -pCaseboxPass123 casebox < "$CASEBOX_DIR/var/backup/cb_default.sql" 2>&1 || {
            echo "Trying as root..."
            docker exec -i casebox-db mysql -u root -pRootPass123 casebox < "$CASEBOX_DIR/var/backup/cb_default.sql" 2>&1 || true
        }
    else
        echo "WARNING: cb_default.sql not found at $CASEBOX_DIR/var/backup/"
    fi

    # Verify import
    TABLES=$(docker exec casebox-db mysql -u casebox -pCaseboxPass123 casebox -N -e "SHOW TABLES" 2>/dev/null | wc -l || echo "0")
    echo "Database tables after import: $TABLES"

    # Import seed data
    if [ -f /workspace/data/seed_cases.sql ]; then
        echo "Importing seed case data..."
        docker exec -i casebox-db mysql -u casebox -pCaseboxPass123 casebox < /workspace/data/seed_cases.sql 2>&1 || \
            echo "WARNING: Seed data import had issues"
    fi

    # Update admin password (Casebox uses md5('aero' + password) for legacy passwords)
    echo "Setting admin password..."
    ADMIN_HASH=$(php7.4 -r 'echo md5("aero" . "Admin1234!");')
    docker exec casebox-db mysql -u casebox -pCaseboxPass123 casebox -e \
        "UPDATE users_groups SET password='${ADMIN_HASH}' WHERE id=1;" 2>/dev/null || true
fi

# ============================================================
# 3. Update Casebox parameters for local MySQL
# ============================================================
echo "Configuring Casebox parameters..."
cat > "$CASEBOX_DIR/app/config/default/parameters.yml" << 'PARAMS'
parameters:
    db_host: 127.0.0.1
    db_port: 3306
    db_name: casebox
    db_user: casebox
    db_pass: CaseboxPass123

    solr_scheme: http
    solr_host: 127.0.0.1
    solr_port: 8983
    solr_core_name: casebox
    solr_core_log_name: casebox_log
    solr_username: ~
    solr_password: ~

    mailer_transport: smtp
    mailer_host: 127.0.0.1
    mailer_user: ~
    mailer_password: ~

    admin_email: admin@casebox.local
    sender_email: noreply@casebox.local

    secret: casebox_env_secret_key_do_not_use_in_production

    session_lifetime: 4320

    converter: unoconv
    converter_url: ~
    unoconv: "/usr/bin/python3 /usr/bin/unoconv"

    redis_host: 127.0.0.1
    redis_port: 6379
PARAMS

# ============================================================
# 4. Start Redis
# ============================================================
echo "Starting Redis..."
systemctl start redis-server 2>/dev/null || redis-server --daemonize yes 2>/dev/null || true

# ============================================================
# 5. Symlink static assets to web directory
# ============================================================
echo "Linking static assets..."
CASEBOX_PUBLIC="/var/www/casebox/vendor/caseboxdev/core-bundle/src/Resources/public"
if [ -d "$CASEBOX_PUBLIC" ]; then
    ln -sf "$CASEBOX_PUBLIC/css" /var/www/casebox/web/css
    ln -sf "$CASEBOX_PUBLIC/js" /var/www/casebox/web/js
    ln -sf "$CASEBOX_PUBLIC/min" /var/www/casebox/web/min
    ln -sf "$CASEBOX_PUBLIC/libx" /var/www/casebox/web/libx 2>/dev/null || true
    echo "Assets linked"
else
    echo "WARNING: Casebox public assets not found"
fi

# ============================================================
# Start Solr and configure indexes
# ============================================================
if [ -d /opt/solr ]; then
    echo "Starting Solr..."
    # Set up configsets if not done
    mkdir -p /var/solr/data/configsets/
    if [ -d "$CASEBOX_DIR/var/solr/default" ]; then
        ln -sf "$CASEBOX_DIR/var/solr/default" /var/solr/data/configsets/casebox 2>/dev/null || true
    fi
    if [ -d "$CASEBOX_DIR/var/solr/log" ]; then
        ln -sf "$CASEBOX_DIR/var/solr/log" /var/solr/data/configsets/casebox_log 2>/dev/null || true
    fi
    chown -R solr:solr /var/solr/data/configsets/ 2>/dev/null || true

    # Start Solr service
    systemctl start solr 2>/dev/null || /opt/solr/bin/solr start -force 2>/dev/null || true
    sleep 5

    # Initialize Solr indexes
    cd "$CASEBOX_DIR"
    php bin/console casebox:solr:create --env=default 2>/dev/null || true
    php bin/console casebox:solr:update --all=true --env=default 2>/dev/null || true
    php bin/console ca:cl --env=default 2>/dev/null || true
    echo "Solr configured"
else
    echo "WARNING: Solr not installed, search may not work"
fi

# ============================================================
# 6. Clear Casebox cache and set permissions
# ============================================================
echo "Clearing cache and setting permissions..."
cd "$CASEBOX_DIR"
php bin/console ca:cl --env=default 2>/dev/null || true
chmod -R 777 var/cache var/logs var/files var/sessions 2>/dev/null || true
chown -R www-data:www-data /var/www/casebox 2>/dev/null || true

# ============================================================
# 7. Start Apache
# ============================================================
echo "Starting Apache..."
systemctl start apache2 2>/dev/null || apachectl start 2>/dev/null || true
sleep 3

# Verify Apache is running
if ! systemctl is-active --quiet apache2 2>/dev/null; then
    echo "WARNING: Apache may not have started, checking..."
    apachectl start 2>/dev/null || true
fi

# Wait for Casebox to respond
wait_for_http "$CASEBOX_BASE_URL" 120

# ============================================================
# 8. Verify database state
# ============================================================
echo "Verifying database state..."
TREE_COUNT=$(docker exec casebox-db mysql -u casebox -pCaseboxPass123 casebox -N -e "SELECT COUNT(*) FROM tree WHERE dstatus=0" 2>/dev/null || echo "0")
echo "Total active tree nodes: $TREE_COUNT"

USER_COUNT=$(docker exec casebox-db mysql -u casebox -pCaseboxPass123 casebox -N -e "SELECT COUNT(*) FROM users_groups WHERE type=1" 2>/dev/null || echo "0")
echo "Total users: $USER_COUNT"

# Save seed result
cat > /tmp/casebox_seed_result.json << SEED_EOF
{
  "casebox_url": "${CASEBOX_BASE_URL}",
  "admin_user": "root",
  "admin_password": "Admin1234!",
  "tree_nodes": ${TREE_COUNT},
  "users": ${USER_COUNT}
}
SEED_EOF

chmod 666 /tmp/casebox_seed_result.json 2>/dev/null || true
cp /tmp/casebox_seed_result.json /home/ga/casebox_seed_result.json 2>/dev/null || true
chown ga:ga /home/ga/casebox_seed_result.json 2>/dev/null || true

# ============================================================
# 9. Configure Firefox profile
# ============================================================
setup_firefox_profile() {
  echo "Setting up Firefox profile..."

  local profile_root="/home/ga/.mozilla/firefox"
  local profile_dir="$profile_root/default.profile"

  sudo -u ga mkdir -p "$profile_dir"

  cat > "$profile_root/profiles.ini" << 'FFPROFILE'
[Profile0]
Name=default
IsRelative=1
Path=default.profile
Default=1

[General]
StartWithLastProfile=1
Version=2
FFPROFILE

  cat > "$profile_dir/user.js" << 'USERJS'
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

  chown -R ga:ga "$profile_root"
}

setup_firefox_profile

# ============================================================
# 10. Warm-up Firefox
# ============================================================
echo "Re-verifying Casebox before Firefox launch..."
for i in $(seq 1 30); do
    code=$(curl -s -o /dev/null -w "%{http_code}" "$CASEBOX_BASE_URL" 2>/dev/null || echo "000")
    if echo "$code" | grep -qE "200|302|303|500"; then
        echo "Casebox web service ready (HTTP $code)"
        break
    fi
    sleep 2
done

echo "Launching Firefox warm-up..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus setsid firefox '${CASEBOX_BASE_URL}/login' > /tmp/firefox_warmup.log 2>&1 &"

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
  sleep 1
  DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
  echo "Firefox warm-up complete"
else
  echo "WARNING: Firefox warm-up did not detect window within 30s"
fi

echo ""
echo "=== Casebox setup complete ==="
echo "Casebox URL: $CASEBOX_BASE_URL"
echo "Admin: root / Admin1234!"
echo "DB check: $TREE_COUNT tree nodes, $USER_COUNT users"
