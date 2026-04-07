#!/bin/bash
# NextGen Connect Setup Script (post_start hook)
# Starts the NextGen Connect container, launches the desktop Administrator via Java WebStart
# NOTE: Do NOT use set -e - wait functions may return non-zero

echo "=== Setting up NextGen Connect Integration Engine ==="

# Wait for desktop to be ready
sleep 5

# Function to wait for PostgreSQL to be ready
wait_for_postgres() {
    local timeout=60
    local elapsed=0
    echo "Waiting for PostgreSQL to be ready..."
    while [ $elapsed -lt $timeout ]; do
        if docker exec nextgen-postgres pg_isready -U postgres 2>/dev/null | grep -q "accepting connections"; then
            echo "PostgreSQL is ready"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "PostgreSQL timeout"
    return 1
}

# Function to wait for NextGen Connect to be ready
wait_for_nextgen_connect() {
    local timeout=180
    local elapsed=0
    echo "Waiting for NextGen Connect to be ready..."
    while [ $elapsed -lt $timeout ]; do
        # Check the API endpoint - more reliable than the web page
        # CRITICAL: X-Requested-With header required by NextGen Connect 4.x
        HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" -H "X-Requested-With: OpenAPI" -H "Accept: text/plain" https://localhost:8443/api/server/version 2>/dev/null)
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "401" ]; then
            echo "NextGen Connect API is ready (HTTP $HTTP_CODE)"
            return 0
        fi
        # Also try HTTP landing page
        HTTP_CODE2=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080 2>/dev/null)
        if [ "$HTTP_CODE2" = "200" ]; then
            echo "NextGen Connect HTTP is ready"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done
    echo "NextGen Connect timeout after ${timeout}s"
    return 1
}

# Create Docker network for container communication
docker network create nextgen-network 2>/dev/null || true

# Start PostgreSQL container for message storage
echo "Starting PostgreSQL container..."
docker run -d \
    --name nextgen-postgres \
    --restart unless-stopped \
    --network nextgen-network \
    -e POSTGRES_USER=postgres \
    -e POSTGRES_PASSWORD=postgres \
    -e POSTGRES_DB=mirthdb \
    -p 5432:5432 \
    postgres:15

# Wait for PostgreSQL
wait_for_postgres || true

# Ensure the mirthdb database exists (POSTGRES_DB should create it, but fallback)
docker exec nextgen-postgres psql -U postgres -tc "SELECT 1 FROM pg_database WHERE datname = 'mirthdb'" | grep -q 1 || \
    docker exec nextgen-postgres createdb -U postgres mirthdb || true

# Start NextGen Connect container
echo "Starting NextGen Connect container..."
docker run -d \
    --name nextgen-connect \
    --restart unless-stopped \
    --network nextgen-network \
    -p 8080:8080 \
    -p 8443:8443 \
    -p 6661:6661 \
    -p 6662:6662 \
    -p 6663:6663 \
    -p 6664:6664 \
    -p 6665:6665 \
    -p 6666:6666 \
    -p 6667:6667 \
    -p 6668:6668 \
    -e DATABASE=postgres \
    -e DATABASE_URL=jdbc:postgresql://nextgen-postgres:5432/mirthdb \
    -e DATABASE_USERNAME=postgres \
    -e DATABASE_PASSWORD=postgres \
    -e KEYSTORE_STOREPASS=docker_storepass \
    -e KEYSTORE_KEYPASS=docker_keypass \
    nextgenhealthcare/connect:4.5.0

# Wait for NextGen Connect to start
wait_for_nextgen_connect || true

# Give it extra time for full initialization
sleep 10

# Configure Firefox profile
echo "Configuring Firefox profile..."

# Detect Firefox profile location (snap vs native)
if command -v snap 2>/dev/null && snap list firefox 2>/dev/null; then
    echo "Snap Firefox detected - launching to create profile..."
    su - ga -c "DISPLAY=:1 firefox --headless &"
    sleep 5
    pkill -f firefox || true
    sleep 2

    FIREFOX_DIR="/home/ga/snap/firefox/common/.mozilla/firefox"
    PROFILE_DIR=$(find "$FIREFOX_DIR" -maxdepth 1 -name "*.default-release" -type d 2>/dev/null | head -1)
    if [ -z "$PROFILE_DIR" ]; then
        PROFILE_DIR=$(find "$FIREFOX_DIR" -maxdepth 1 -name "*.default*" -type d 2>/dev/null | head -1)
    fi
    if [ -z "$PROFILE_DIR" ]; then
        PROFILE_DIR="$FIREFOX_DIR/default-release"
        mkdir -p "$PROFILE_DIR"
    fi
else
    FIREFOX_DIR="/home/ga/.mozilla/firefox"
    PROFILE_DIR="$FIREFOX_DIR/default-release"
    mkdir -p "$PROFILE_DIR"
fi

echo "Firefox profile directory: $PROFILE_DIR"

# Create Firefox user.js to disable first-run and configure
cat > "$PROFILE_DIR/user.js" << 'EOF'
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutConfig.showWarning", false);
user_pref("security.enterprise_roots.enabled", true);
user_pref("browser.tabs.warnOnClose", false);
user_pref("browser.tabs.warnOnCloseOtherTabs", false);
user_pref("browser.sessionstore.resume_from_crash", false);
user_pref("browser.startup.homepage", "http://localhost:8080");
user_pref("browser.startup.page", 1);
user_pref("signon.rememberSignons", false);
user_pref("signon.autofillForms", false);
user_pref("sidebar.revamp", false);
user_pref("sidebar.verticalTabs", false);
user_pref("sidebar.main.tools", "");
user_pref("sidebar.nimbus", "");
user_pref("network.stricttransportsecurity.preloadlist", false);
user_pref("security.mixed_content.block_active_content", false);
user_pref("security.cert_pinning.enforcement_level", 0);
user_pref("security.ssl.treat_unsafe_negotiation_as_broken", false);
user_pref("browser.ssl_override_behavior", 1);
EOF

# Also patch prefs.js if it exists (Snap Firefox Nimbus sidebar fix)
if [ -f "$PROFILE_DIR/prefs.js" ]; then
    grep -q 'sidebar.revamp' "$PROFILE_DIR/prefs.js" || \
        echo 'user_pref("sidebar.revamp", false);' >> "$PROFILE_DIR/prefs.js"
    grep -q 'sidebar.verticalTabs' "$PROFILE_DIR/prefs.js" || \
        echo 'user_pref("sidebar.verticalTabs", false);' >> "$PROFILE_DIR/prefs.js"
fi

# Create profiles.ini
cat > "$FIREFOX_DIR/profiles.ini" << EOF
[Profile0]
Name=default-release
IsRelative=1
Path=$(basename "$PROFILE_DIR")
Default=1

[General]
StartWithLastProfile=1
Version=2
EOF

# Set ownership
chown -R ga:ga /home/ga/.mozilla 2>/dev/null || true
chown -R ga:ga /home/ga/snap 2>/dev/null || true

# Re-verify NextGen Connect is responsive before launching Firefox
echo "Re-verifying NextGen Connect is responsive before launching Firefox..."
for i in $(seq 1 60); do
    HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" -H "X-Requested-With: OpenAPI" -H "Accept: text/plain" https://localhost:8443/api/server/version 2>/dev/null || echo "000")
    HTTP_CODE2=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE2" = "200" ]; then
        echo "NextGen Connect web service ready"
        break
    fi
    sleep 2
done

# Launch Firefox pointing to the HTTP landing page
# The landing page shows the "Launch Mirth Connect Administrator" button
echo "Launching Firefox with NextGen Connect landing page..."
su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080' &"

# Wait for Firefox to load
sleep 8

# Display running containers
echo ""
echo "=== Running Containers ==="
docker ps

echo ""
echo "=== NextGen Connect Setup Complete ==="
echo "HTTP Landing: http://localhost:8080"
echo "Web Dashboard: https://localhost:8443 (monitoring - login with admin/admin)"
echo "REST API: https://localhost:8443/api (CRITICAL: requires X-Requested-With: OpenAPI header)"
echo "Default credentials: admin / admin"
echo "HL7 Listener Ports: 6661-6668 (configurable per channel)"
echo ""
echo "Channel management: Use REST API via curl (POST /api/channels with XML)"
echo "Channel monitoring: Web dashboard at https://localhost:8443"
echo "Message sending: MLLP via netcat (printf '\\x0b<msg>\\x1c\\x0d' | nc localhost <port>)"
