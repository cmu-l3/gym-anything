#!/bin/bash
set -e

echo "=== Setting up LimeSurvey ==="

# Create LimeSurvey directory
mkdir -p /home/ga/limesurvey
cd /home/ga/limesurvey

# Copy docker-compose from mounted config
if [ -f /workspace/config/docker-compose-limesurvey.yml ]; then
    cp /workspace/config/docker-compose-limesurvey.yml docker-compose.yml
else
    # Create docker-compose.yml for LimeSurvey
    cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  limesurvey:
    image: martialblog/limesurvey:6-apache
    container_name: limesurvey-app
    restart: unless-stopped
    ports:
      - "80:8080"
    environment:
      - DB_TYPE=mysql
      - DB_HOST=limesurvey-db
      - DB_PORT=3306
      - DB_NAME=limesurvey
      - DB_USERNAME=limesurvey
      - DB_PASSWORD=limesurvey_pass
      - ADMIN_USER=admin
      - ADMIN_PASSWORD=Admin123!
      - ADMIN_NAME=Administrator
      - ADMIN_EMAIL=admin@example.com
      - PUBLIC_URL=http://localhost
      - BASE_URL=
    volumes:
      - limesurvey-upload:/var/www/html/upload
      - limesurvey-plugins:/var/www/html/plugins
    depends_on:
      limesurvey-db:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/index.php/admin"]
      interval: 30s
      timeout: 10s
      retries: 5

  limesurvey-db:
    image: mysql:8.0
    container_name: limesurvey-db
    restart: unless-stopped
    environment:
      - MYSQL_ROOT_PASSWORD=limesurvey_root_pw
      - MYSQL_DATABASE=limesurvey
      - MYSQL_USER=limesurvey
      - MYSQL_PASSWORD=limesurvey_pass
    volumes:
      - limesurvey-mysql:/var/lib/mysql
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost", "-u", "root", "-plimesurvey_root_pw"]
      interval: 10s
      timeout: 5s
      retries: 10

volumes:
  limesurvey-upload:
  limesurvey-plugins:
  limesurvey-mysql:
EOF
fi

chown -R ga:ga /home/ga/limesurvey

# Start LimeSurvey containers
echo "Starting LimeSurvey Docker containers..."
cd /home/ga/limesurvey
docker-compose up -d

# Wait for MySQL to be healthy
echo "Waiting for MySQL to be ready..."
wait_for_mysql() {
    local timeout=120
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if docker exec limesurvey-db mysqladmin ping -h localhost -u root -plimesurvey_root_pw 2>/dev/null; then
            echo "MySQL is ready after ${elapsed}s"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        echo "  Waiting... ${elapsed}s"
    done
    echo "WARNING: MySQL readiness check timed out after ${timeout}s"
    return 1
}
wait_for_mysql || true

# Wait for LimeSurvey to initialize (it auto-installs on first run)
echo "Waiting for LimeSurvey to initialize..."
wait_for_limesurvey() {
    local timeout=180
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/ 2>/dev/null || echo "000")
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
            echo "LimeSurvey is ready after ${elapsed}s (HTTP $HTTP_CODE)"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        echo "  Waiting... ${elapsed}s (HTTP $HTTP_CODE)"
    done
    echo "WARNING: LimeSurvey readiness check timed out after ${timeout}s"
    return 1
}
wait_for_limesurvey || true

# Enable JSON-RPC API via direct SQL (in case it is disabled by default in LimeSurvey settings)
echo "Enabling LimeSurvey JSON-RPC API via database..."
RPCINTERFACE_ENABLED="false"
for i in $(seq 1 12); do
    if docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -e \
        "INSERT INTO lime_settings_global (stg_name, stg_value) VALUES ('RPCInterface', 'json') ON DUPLICATE KEY UPDATE stg_value='json';" 2>/dev/null; then
        echo "JSON-RPC API enabled in DB"
        RPCINTERFACE_ENABLED="true"
        break
    fi
    echo "  Waiting for DB schema... attempt $i"
    sleep 5
done
echo "JSON-RPC API enabled: $RPCINTERFACE_ENABLED"

# Wait for LimeSurvey's JSON-RPC API to be ready (first-time DB install can take several minutes)
echo "Waiting for LimeSurvey API (JSON-RPC) to be ready..."
wait_for_limesurvey_api() {
    local timeout=600
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        RESULT=$(python3 - << 'PYEOF' 2>/dev/null
import json, urllib.request
BASE = "http://localhost/index.php/admin/remotecontrol"
data = json.dumps({"method": "get_session_key", "params": ["admin", "Admin123!"], "id": 1}).encode()
req = urllib.request.Request(BASE, data=data, headers={"Content-Type": "application/json"})
try:
    r = json.loads(urllib.request.urlopen(req, timeout=10).read())
    s = r.get("result", "")
    if s and isinstance(s, str) and len(s) > 5 and "error" not in str(s).lower():
        rel = json.dumps({"method": "release_session_key", "params": [s], "id": 2}).encode()
        rreq = urllib.request.Request(BASE, data=rel, headers={"Content-Type": "application/json"})
        try: urllib.request.urlopen(rreq, timeout=5)
        except: pass
        print("ready")
except Exception:
    pass
PYEOF
)
        if [ "$RESULT" = "ready" ]; then
            echo "LimeSurvey API is ready after ${elapsed}s"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        echo "  API not ready yet... ${elapsed}s"
    done
    echo "WARNING: LimeSurvey API readiness timed out after ${timeout}s"
    return 1
}
wait_for_limesurvey_api || true

# Show container status
echo ""
echo "Container status:"
docker-compose ps

# Create database query helper
cat > /usr/local/bin/limesurvey-db-query << 'DBEOF'
#!/bin/bash
docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "$1" 2>/dev/null
DBEOF
chmod +x /usr/local/bin/limesurvey-db-query

# Set up Firefox profile to disable first-run dialogs
echo "Setting up Firefox profile..."
mkdir -p /home/ga/.mozilla/firefox/default.profile
cat > /home/ga/.mozilla/firefox/default.profile/user.js << 'USERJS'
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutConfig.showWarning", false);
user_pref("browser.tabs.warnOnClose", false);
user_pref("browser.warnOnQuit", false);
user_pref("browser.sessionstore.resume_from_crash", false);
user_pref("security.enterprise_roots.enabled", true);
user_pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);
user_pref("browser.newtabpage.activity-stream.feeds.topsites", false);
user_pref("browser.newtabpage.activity-stream.feeds.section.topstories", false);
USERJS

cat > /home/ga/.mozilla/firefox/profiles.ini << 'PROFILES'
[Profile0]
Name=default
IsRelative=1
Path=default.profile
Default=1

[General]
StartWithLastProfile=1
Version=2
PROFILES

chown -R ga:ga /home/ga/.mozilla

# NOTE: Firefox is NOT launched here. It will be launched by each task's
# setup_task.sh via restart_firefox() from task_utils.sh. This avoids
# "Firefox is already running" lock file conflicts between setup and task hooks.

echo ""
echo "=== LimeSurvey Setup Complete ==="
echo ""
echo "LimeSurvey is running at: http://localhost/index.php/admin"
echo ""
echo "Login credentials:"
echo "  Username: admin"
echo "  Password: Admin123!"
echo ""
echo "Database access (via Docker):"
echo "  limesurvey-db-query \"SELECT COUNT(*) FROM lime_surveys\""
echo ""
echo "Docker commands:"
echo "  docker-compose -f /home/ga/limesurvey/docker-compose.yml logs -f"
echo "  docker-compose -f /home/ga/limesurvey/docker-compose.yml ps"
