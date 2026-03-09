#!/bin/bash
set -e

echo "=== Setting up FreeScout ==="

# Wait for desktop to be ready
sleep 5

# ===== Start Docker containers =====
mkdir -p /home/ga/freescout
cp /workspace/config/docker-compose.yml /home/ga/freescout/
chown -R ga:ga /home/ga/freescout

cd /home/ga/freescout
docker-compose pull 2>&1 || echo "WARNING: Pull failed, using cached images"
docker-compose up -d

# ===== Wait for MariaDB =====
wait_for_mysql() {
    local timeout=${1:-120}
    local elapsed=0
    echo "Waiting for MariaDB..."
    while [ $elapsed -lt $timeout ]; do
        if docker exec freescout-db mysqladmin ping -h localhost -u root -prootpass123 2>/dev/null | grep -q "alive"; then
            echo "MariaDB is ready after ${elapsed}s"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done
    echo "MariaDB timeout after ${timeout}s"
    return 1
}
wait_for_mysql 120 || true

# Fallback: ensure database exists
docker exec freescout-db mysql -u root -prootpass123 -e "CREATE DATABASE IF NOT EXISTS freescout CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null || true
docker exec freescout-db mysql -u root -prootpass123 -e "GRANT ALL PRIVILEGES ON freescout.* TO 'freescout'@'%' IDENTIFIED BY 'freescout123'; FLUSH PRIVILEGES;" 2>/dev/null || true

# ===== Wait for FreeScout application =====
wait_for_freescout() {
    local timeout=${1:-600}
    local elapsed=0
    echo "Waiting for FreeScout (first boot takes 2-5 minutes for schema setup)..."
    while [ $elapsed -lt $timeout ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/login" 2>/dev/null || echo "000")
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
            echo "FreeScout is ready after ${elapsed}s (HTTP $HTTP_CODE)"
            return 0
        fi
        sleep 10
        elapsed=$((elapsed + 10))
        if [ $((elapsed % 60)) -eq 0 ]; then
            echo "  Still waiting... (${elapsed}s, HTTP $HTTP_CODE)"
        fi
    done
    echo "FreeScout timeout after ${timeout}s"
    docker logs freescout-app --tail 30 2>&1 || true
    return 1
}

if ! wait_for_freescout 600; then
    echo "ERROR: FreeScout failed to start, attempting restart..."
    docker restart freescout-app 2>/dev/null || true
    sleep 30
    wait_for_freescout 180 || true
fi

# Additional wait for full initialization
sleep 30

# ===== Verify admin login works =====
echo "Verifying admin login..."
LOGIN_RESPONSE=$(curl -s -c /tmp/cookies.txt -b /tmp/cookies.txt http://localhost:8080/login 2>/dev/null)
CSRF_TOKEN=$(echo "$LOGIN_RESPONSE" | grep -oP 'name="_token" value="\K[^"]+' | head -1)
if [ -n "$CSRF_TOKEN" ]; then
    curl -s -L -b /tmp/cookies.txt -c /tmp/cookies.txt \
        -d "_token=${CSRF_TOKEN}&email=admin@helpdesk.local&password=Admin123!" \
        http://localhost:8080/login > /dev/null 2>&1
    echo "Login verification attempted"
fi
rm -f /tmp/cookies.txt

# ===== Configure Firefox =====
# Firefox is a snap, so profile goes to both locations
echo "Configuring Firefox..."

# Standard location
FIREFOX_PROFILE_DIR="/home/ga/.mozilla/firefox"
sudo -u ga mkdir -p "$FIREFOX_PROFILE_DIR/default-release"

USERJS_CONTENT='// Disable first-run screens
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.rights.3.shown", true);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);

// Set FreeScout as homepage
user_pref("browser.startup.homepage", "http://localhost:8080");
user_pref("browser.startup.page", 1);

// Disable updates and popups
user_pref("app.update.enabled", false);
user_pref("browser.newtabpage.enabled", false);
user_pref("browser.tabs.warnOnClose", false);

// Disable password and form saving
user_pref("signon.rememberSignons", false);
user_pref("signon.autofillForms", false);

// Disable sidebar completely
user_pref("sidebar.revamp", false);
user_pref("sidebar.verticalTabs", false);
user_pref("sidebar.main.tools", "");
user_pref("sidebar.visibility", "hide-sidebar");
user_pref("sidebar.revamp.defaultLauncherVisible", false);
user_pref("sidebar.nimbus", "");
user_pref("sidebar.notification.badge.aichat", false);
user_pref("browser.sidebar.dismissed", true);
user_pref("extensions.pocket.enabled", false);'

PROFILESINI_CONTENT='[Install4F96D1932A9F858E]
Default=default-release
Locked=1

[Profile0]
Name=default-release
IsRelative=1
Path=default-release
Default=1

[General]
StartWithLastProfile=1
Version=2'

# Write to standard location
echo "$PROFILESINI_CONTENT" > "$FIREFOX_PROFILE_DIR/profiles.ini"
echo "$USERJS_CONTENT" > "$FIREFOX_PROFILE_DIR/default-release/user.js"
chown -R ga:ga "$FIREFOX_PROFILE_DIR"

# ===== Launch Firefox (first time to create snap profile) =====
echo "Launching Firefox (first time)..."
su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/login' > /tmp/firefox.log 2>&1 &"
sleep 10

# Wait for Firefox window
WAIT_FF=0
while [ $WAIT_FF -lt 30 ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|freescout"; then
        echo "Firefox window detected"
        break
    fi
    sleep 2
    WAIT_FF=$((WAIT_FF + 2))
done

# Kill Firefox to configure snap profile
pkill -f firefox || true
sleep 3

# Write user.js to snap profile location (created by first launch)
SNAP_PROFILE_DIR="/home/ga/snap/firefox/common/.mozilla/firefox"
if [ -d "$SNAP_PROFILE_DIR" ]; then
    echo "Configuring snap Firefox profile..."
    SNAP_RELEASE_DIR="$SNAP_PROFILE_DIR/default-release"
    if [ ! -d "$SNAP_RELEASE_DIR" ]; then
        # Find the actual profile dir
        SNAP_RELEASE_DIR=$(find "$SNAP_PROFILE_DIR" -maxdepth 1 -type d -name "*.default-release" 2>/dev/null | head -1)
        [ -z "$SNAP_RELEASE_DIR" ] && SNAP_RELEASE_DIR="$SNAP_PROFILE_DIR/default-release"
    fi
    sudo -u ga mkdir -p "$SNAP_RELEASE_DIR"
    echo "$PROFILESINI_CONTENT" > "$SNAP_PROFILE_DIR/profiles.ini"
    echo "$USERJS_CONTENT" > "$SNAP_RELEASE_DIR/user.js"

    # Also patch prefs.js if it exists to force sidebar off
    if [ -f "$SNAP_RELEASE_DIR/prefs.js" ]; then
        sed -i 's/"sidebar.revamp", true/"sidebar.revamp", false/' "$SNAP_RELEASE_DIR/prefs.js"
        sed -i 's/"sidebar.main.tools", "[^"]*"/"sidebar.main.tools", ""/' "$SNAP_RELEASE_DIR/prefs.js"
    fi
    chown -R ga:ga "$SNAP_PROFILE_DIR"
fi

# ===== Relaunch Firefox =====
echo "Relaunching Firefox..."
su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/login' > /tmp/firefox.log 2>&1 &"
sleep 8

# Wait for Firefox window again
WAIT_FF=0
while [ $WAIT_FF -lt 30 ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|freescout"; then
        echo "Firefox window detected"
        break
    fi
    sleep 2
    WAIT_FF=$((WAIT_FF + 2))
done

# Maximize Firefox
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

echo "=== FreeScout setup complete ==="
echo "Admin URL: http://localhost:8080"
echo "Admin email: admin@helpdesk.local"
echo "Admin password: Admin123!"
