#!/bin/bash
set -e

echo "=== Setting up SciNote ELN ==="

# Wait for desktop to be ready
sleep 5

# Ensure Docker is running
systemctl start docker
sleep 3

# ============================================================
# Build and start SciNote via Docker Compose
# ============================================================

# Copy docker-compose.yml to the scinote-web directory
cp /workspace/config/docker-compose.yml /home/ga/scinote-web/docker-compose.production.yml

cd /home/ga/scinote-web

# Build the production Docker image with BuildKit enabled
echo "=== Building SciNote Docker image (this may take several minutes) ==="
export DOCKER_BUILDKIT=1
docker compose -f docker-compose.production.yml build web 2>&1 || {
    echo "Docker build failed, retrying with explicit buildkit..."
    sleep 5
    DOCKER_BUILDKIT=1 docker compose -f docker-compose.production.yml build web 2>&1
}

# Start the containers
echo "=== Starting SciNote containers ==="
docker compose -f docker-compose.production.yml up -d

# ============================================================
# Wait for PostgreSQL to be ready
# ============================================================

wait_for_postgres() {
    local timeout=120
    local elapsed=0
    echo "Waiting for PostgreSQL..."
    while [ $elapsed -lt $timeout ]; do
        if docker exec scinote_db pg_isready -U postgres > /dev/null 2>&1; then
            echo "PostgreSQL is ready (${elapsed}s)"
            return 0
        fi
        sleep 3
        elapsed=$((elapsed + 3))
    done
    echo "PostgreSQL timeout after ${timeout}s"
    return 1
}

wait_for_postgres

# ============================================================
# Initialize database
# ============================================================

echo "=== Initializing SciNote database ==="
docker exec scinote_web bash -c "bundle exec rake db:create 2>/dev/null || true"
docker exec scinote_web bash -c "bundle exec rake db:migrate"
docker exec scinote_web bash -c "bundle exec rake db:seed"

echo "=== Database initialized ==="

# ============================================================
# Wait for SciNote web interface to be ready
# ============================================================

SCINOTE_URL="http://localhost:3000"

wait_for_scinote() {
    local timeout=180
    local elapsed=0
    echo "Waiting for SciNote web interface at ${SCINOTE_URL}..."
    while [ $elapsed -lt $timeout ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${SCINOTE_URL}" 2>/dev/null)
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "301" ]; then
            echo "SciNote is ready (HTTP ${HTTP_CODE}, ${elapsed}s)"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done
    echo "SciNote timeout after ${timeout}s (last HTTP code: ${HTTP_CODE})"
    return 1
}

wait_for_scinote

# ============================================================
# Configure Firefox for SciNote
# ============================================================

echo "=== Configuring Firefox ==="

FIREFOX_PROFILE_DIR="/home/ga/.mozilla/firefox"
sudo -u ga mkdir -p "$FIREFOX_PROFILE_DIR/default-release"

# Create profiles.ini
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

# Create user.js to disable first-run dialogs and set homepage
cat > "$FIREFOX_PROFILE_DIR/default-release/user.js" << USERJS
// Disable first-run screens and welcome pages
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.rights.3.shown", true);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.shell.didSkipDefaultBrowserCheckOnFirstRun", true);
user_pref("startup.homepage_welcome_url", "");
user_pref("startup.homepage_welcome_url.additional", "");
user_pref("startup.homepage_override_url", "");
user_pref("browser.startup.firstrunSkipsHomepage", true);
user_pref("browser.tabs.warnOnClose", false);

// Suppress Privacy Notice / data reporting policy dialogs
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("datareporting.policy.dataSubmissionPolicyAcceptedVersion", 2);
user_pref("datareporting.policy.firstRunURL", "");
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);

// Set homepage to SciNote
user_pref("browser.startup.homepage", "${SCINOTE_URL}/users/sign_in");
user_pref("browser.startup.page", 1);
user_pref("browser.newtabpage.enabled", false);

// Disable updates
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

// Disable What's New and post-update pages
user_pref("browser.startup.upgradeDialog.enabled", false);
user_pref("browser.messaging-system.whatsNewPanel.enabled", false);

// Disable default browser notification
user_pref("browser.defaultbrowser.notificationbar", false);

// Disable import wizard
user_pref("browser.migration.version", 9999);

// Disable telemetry
user_pref("toolkit.telemetry.enabled", false);
user_pref("toolkit.telemetry.unified", false);
user_pref("toolkit.telemetry.archive.enabled", false);
user_pref("browser.ping-centre.telemetry", false);
user_pref("toolkit.telemetry.server", "");
user_pref("toolkit.telemetry.newProfilePing.enabled", false);
user_pref("toolkit.telemetry.shutdownPingSender.enabled", false);
user_pref("toolkit.telemetry.updatePing.enabled", false);
user_pref("toolkit.telemetry.bhrPing.enabled", false);
user_pref("toolkit.telemetry.firstShutdownPing.enabled", false);

// Performance
user_pref("browser.cache.disk.enable", true);
user_pref("browser.cache.memory.enable", true);
USERJS
chown ga:ga "$FIREFOX_PROFILE_DIR/default-release/user.js"

chown -R ga:ga "$FIREFOX_PROFILE_DIR"

# Create desktop shortcut
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/scinote.desktop << DESKTOPEOF
[Desktop Entry]
Version=1.0
Type=Application
Name=SciNote ELN
Exec=firefox ${SCINOTE_URL}/users/sign_in
Icon=firefox
Terminal=false
Categories=Science;Education;
DESKTOPEOF
chmod +x /home/ga/Desktop/scinote.desktop
chown ga:ga /home/ga/Desktop/scinote.desktop

# ============================================================
# Launch Firefox with SciNote
# ============================================================

echo "=== Launching Firefox with SciNote ==="
su - ga -c "DISPLAY=:1 firefox '${SCINOTE_URL}/users/sign_in' > /tmp/firefox_scinote.log 2>&1 &"

# Wait for Firefox window
echo "Waiting for Firefox window..."
FIREFOX_TIMEOUT=30
FIREFOX_ELAPSED=0
while [ $FIREFOX_ELAPSED -lt $FIREFOX_TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|scinote"; then
        echo "Firefox window detected (${FIREFOX_ELAPSED}s)"
        break
    fi
    sleep 2
    FIREFOX_ELAPSED=$((FIREFOX_ELAPSED + 2))
done

# Maximize Firefox
sleep 2
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

echo "=== SciNote setup complete ==="
echo "SciNote is running at ${SCINOTE_URL}"
echo "Default credentials: admin@scinote.net / inHisHouseAtRlyehDeadCthulhuWaitsDreaming"
