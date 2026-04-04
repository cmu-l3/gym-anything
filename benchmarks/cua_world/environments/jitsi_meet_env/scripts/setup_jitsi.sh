#!/bin/bash
set -e

echo "=== Setting up Jitsi Meet ==="

# ── Wait for Docker daemon ──────────────────────────────────────────────────
wait_for_docker() {
    local timeout=120
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if docker info >/dev/null 2>&1; then
            echo "Docker daemon is ready"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "ERROR: Docker daemon did not start within ${timeout}s"
    return 1
}

wait_for_docker

# ── Detect docker compose command ───────────────────────────────────────────
if docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
    DOCKER_COMPOSE="docker-compose"
else
    echo "ERROR: No docker compose available"
    exit 1
fi
echo "Using: $DOCKER_COMPOSE"

# ── Create config directories ──────────────────────────────────────────────
mkdir -p /home/ga/.jitsi-meet-cfg/{web,transcripts,prosody/config,prosody/prosody-plugins-custom,jicofo,jvb}
chown -R ga:ga /home/ga/.jitsi-meet-cfg

# ── Create jitsi directory and copy docker-compose ───────────────────────────
mkdir -p /home/ga/jitsi
cp /workspace/config/docker-compose.yml /home/ga/jitsi/docker-compose.yml
chown -R ga:ga /home/ga/jitsi

# ── Generate stable passwords (fixed values for reproducibility) ──────────────
cat > /home/ga/jitsi/.env << 'ENVEOF'
JICOFO_AUTH_PASSWORD=a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4
JVB_AUTH_PASSWORD=b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5
JIBRI_RECORDER_PASSWORD=c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6
JIBRI_XMPP_PASSWORD=d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1
JIGASI_XMPP_PASSWORD=e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2
JIGASI_TRANSCRIBER_PASSWORD=f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3
ENVEOF
chown ga:ga /home/ga/jitsi/.env

# ── Start Jitsi Meet containers ──────────────────────────────────────────────
echo "Starting Jitsi Meet containers..."
cd /home/ga/jitsi
$DOCKER_COMPOSE up -d

# ── Wait for web service to be reachable ─────────────────────────────────────
wait_for_http() {
    local url="$1"
    local timeout="${2:-300}"
    local elapsed=0
    echo "Waiting for $url (timeout=${timeout}s)..."
    while [ $elapsed -lt $timeout ]; do
        if curl -sfk "$url" >/dev/null 2>&1; then
            echo "Service ready: $url"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done
    echo "ERROR: Service not ready after ${timeout}s: $url"
    return 1
}

if ! wait_for_http "http://localhost:8080" 300; then
    echo "--- Container logs ---"
    cd /home/ga/jitsi && $DOCKER_COMPOSE logs --tail=50 || true
    exit 1
fi

echo "Jitsi Meet is running at http://localhost:8080"

# ── Set up Firefox profile ─────────────────────────────────────────────────
# NOTE: Firefox is installed as snap. Snap Firefox uses
# /home/ga/snap/firefox/common/.mozilla/firefox/ as the profile directory.
# We write to /home/ga/.mozilla/firefox/ and the snap syncs it on first launch.
# Do NOT use -profile flag with snap Firefox.
FIREFOX_PROFILE_DIR="/home/ga/.mozilla/firefox/jitsi.profile"
mkdir -p "$FIREFOX_PROFILE_DIR"

cat > "${FIREFOX_PROFILE_DIR}/user.js" << 'EOF'
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutConfig.showWarning", false);
user_pref("browser.tabs.warnOnClose", false);
user_pref("browser.sessionstore.resume_from_crash", false);
user_pref("app.update.enabled", false);
user_pref("extensions.update.enabled", false);
user_pref("browser.startup.page", 0);
user_pref("browser.startup.homepage", "about:blank");
user_pref("startup.homepage_welcome_url", "");
user_pref("startup.homepage_welcome_url.additional", "");
user_pref("browser.cache.disk.enable", false);
user_pref("media.navigator.permission.disabled", true);
user_pref("media.autoplay.default", 0);
user_pref("permissions.default.camera", 1);
user_pref("permissions.default.microphone", 1);
user_pref("geo.enabled", false);
user_pref("browser.download.always_ask_before_handling_new_types", false);
EOF

mkdir -p /home/ga/.mozilla/firefox
cat > /home/ga/.mozilla/firefox/profiles.ini << 'EOF'
[Profile0]
Name=jitsi
IsRelative=1
Path=jitsi.profile
Default=1

[General]
StartWithLastProfile=1
Version=2
EOF

chown -R ga:ga /home/ga/.mozilla

# ── Warm-up Firefox (snap version - use nohup, NOT su -c or -profile flag) ───
# This allows snap Firefox to create its internal profile at
# /home/ga/snap/firefox/common/.mozilla/firefox/jitsi.profile
# and apply our user.js prefs.
echo "Warming up Firefox (snap)..."
DISPLAY=:1 nohup firefox http://localhost:8080 >/tmp/firefox_warmup.log 2>&1 &
sleep 20

# Dismiss any Firefox first-run dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

# Kill Firefox warmup so tasks start clean
pkill -9 -f firefox 2>/dev/null || true
sleep 3

# Clear lock files
rm -f /home/ga/snap/firefox/common/.mozilla/firefox/jitsi.profile/lock \
      /home/ga/snap/firefox/common/.mozilla/firefox/jitsi.profile/.parentlock \
      /home/ga/.mozilla/firefox/jitsi.profile/lock \
      /home/ga/.mozilla/firefox/jitsi.profile/.parentlock 2>/dev/null || true

echo "=== Jitsi Meet setup complete ==="
echo "Access at: http://localhost:8080"
