#!/bin/bash
# JFrog Artifactory Setup Script (post_start hook)
# Starts Artifactory via Docker, waits for readiness, and configures
# Firefox for the UI. Repository/user creation is done via the UI in tasks.
#
# Default credentials: admin / password
# UI: http://localhost:8082
#
# NOTE: Artifactory OSS 7.x restricts REST API for repo/user/group creation
# to Pro tier only. We only use GET-based REST APIs here.

echo "=== Setting up JFrog Artifactory ==="

ARTIFACTORY_URL="http://localhost:8082"
ADMIN_USER="admin"
ADMIN_PASS="password"
ARTIFACTS_DIR="/home/ga/artifacts"

# ============================================================
# HELPER: Wait for Artifactory to be ready
# ============================================================
wait_for_artifactory() {
    local timeout=${1:-600}
    local elapsed=0
    echo "Waiting for Artifactory to be ready (may take 5-8 minutes on first start)..."
    while [ $elapsed -lt $timeout ]; do
        STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
            -u "${ADMIN_USER}:${ADMIN_PASS}" \
            "${ARTIFACTORY_URL}/artifactory/api/system/ping" 2>/dev/null)
        if [ "$STATUS" = "200" ]; then
            echo "Artifactory is ready after ${elapsed}s"
            return 0
        fi
        sleep 10
        elapsed=$((elapsed + 10))
        echo "  Waiting... ${elapsed}s (HTTP $STATUS)"
    done
    echo "WARNING: Artifactory readiness check timed out after ${timeout}s"
    return 1
}

# ============================================================
# 1. Copy docker-compose.yml and start containers
# ============================================================
echo "Setting up Docker Compose configuration..."
mkdir -p /home/ga/artifactory
cp /workspace/config/docker-compose.yml /home/ga/artifactory/
chown -R ga:ga /home/ga/artifactory

cd /home/ga/artifactory

# Docker Hub login (for postgres image)
if [ -f /workspace/config/.dockerhub_credentials ]; then
    source /workspace/config/.dockerhub_credentials
    echo "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USERNAME" --password-stdin 2>/dev/null || true
    echo "Docker Hub login complete"
fi

echo "Starting JFrog Artifactory containers..."
docker compose up -d
echo "Containers started. Waiting for initialization..."

# Wait for PostgreSQL to be healthy first
echo "Waiting for PostgreSQL..."
for i in $(seq 1 30); do
    if docker exec artifactory-postgresql pg_isready -U artifactory -d artifactory 2>/dev/null; then
        echo "PostgreSQL is ready"
        break
    fi
    sleep 5
done

# ============================================================
# 2. Wait for Artifactory web service
# ============================================================
wait_for_artifactory 600

# ============================================================
# 3. Complete first-time setup — mark admin password as initialized
# (This bypasses the first-run "change password" wizard in the UI)
# ============================================================
echo "Completing Artifactory first-time setup..."

CHANGE_RESULT=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "${ADMIN_USER}:${ADMIN_PASS}" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "{\"userName\":\"${ADMIN_USER}\",\"oldPassword\":\"${ADMIN_PASS}\",\"newPassword\":\"${ADMIN_PASS}\"}" \
    "${ARTIFACTORY_URL}/artifactory/api/security/users/authorization/changePassword" 2>/dev/null)
echo "Password initialization result: HTTP $CHANGE_RESULT"

sleep 5

# ============================================================
# 3b. Verify example-repo-local exists (auto-created by Artifactory OSS)
# Three tasks depend on this repository: upload_artifact, create_virtual_repo,
# set_permission_target. Fail loudly if it's missing.
# ============================================================
echo "Verifying default repositories..."
REPOS_JSON=$(curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" \
    "${ARTIFACTORY_URL}/artifactory/api/repositories" 2>/dev/null)
echo "Repositories available: $REPOS_JSON"

if echo "$REPOS_JSON" | python3 -c "
import sys, json
try:
    repos = json.load(sys.stdin)
    keys = [r.get('key','') for r in repos]
    print('  Repo keys:', keys)
    if 'example-repo-local' in keys:
        print('  example-repo-local: EXISTS (OK)')
        sys.exit(0)
    else:
        print('  example-repo-local: MISSING — 3 tasks will fail!')
        sys.exit(1)
except Exception as e:
    print('  ERROR parsing repo list:', e)
    sys.exit(1)
" 2>/dev/null; then
    echo "example-repo-local confirmed present."
else
    echo "WARNING: example-repo-local not found in repository list."
    echo "Artifactory OSS 7.77.3 should auto-create this on first startup."
    echo "Tasks depending on example-repo-local: upload_artifact, create_virtual_repo, set_permission_target"
fi

# ============================================================
# 4. Download real artifact files for use in tasks
# ============================================================
echo "Downloading real Maven artifacts..."
mkdir -p "$ARTIFACTS_DIR/commons-lang3"

COMMONS_LANG_VERSION="3.14.0"
COMMONS_LANG_BASE="https://repo1.maven.org/maven2/org/apache/commons/commons-lang3/${COMMONS_LANG_VERSION}"

for EXT in jar pom; do
    if wget -q --timeout=60 \
        "${COMMONS_LANG_BASE}/commons-lang3-${COMMONS_LANG_VERSION}.${EXT}" \
        -O "${ARTIFACTS_DIR}/commons-lang3/commons-lang3-${COMMONS_LANG_VERSION}.${EXT}" 2>/dev/null; then
        echo "Downloaded commons-lang3-${COMMONS_LANG_VERSION}.${EXT}"
    else
        echo "WARNING: Failed to download commons-lang3-${COMMONS_LANG_VERSION}.${EXT}"
    fi
done

COMMONS_IO_VERSION="2.15.1"
COMMONS_IO_BASE="https://repo1.maven.org/maven2/org/apache/commons/commons-io/${COMMONS_IO_VERSION}"
mkdir -p "$ARTIFACTS_DIR/commons-io"

for EXT in jar pom; do
    TARGET="${ARTIFACTS_DIR}/commons-io/commons-io-${COMMONS_IO_VERSION}.${EXT}"
    DOWNLOADED=false
    for ATTEMPT in 1 2 3; do
        if wget -q --timeout=90 \
            "${COMMONS_IO_BASE}/commons-io-${COMMONS_IO_VERSION}.${EXT}" \
            -O "$TARGET" 2>/dev/null && [ -s "$TARGET" ]; then
            echo "Downloaded commons-io-${COMMONS_IO_VERSION}.${EXT}"
            DOWNLOADED=true
            break
        fi
        echo "  Attempt $ATTEMPT failed, retrying in 5s..."
        sleep 5
    done
    if [ "$DOWNLOADED" = false ]; then
        echo "WARNING: Failed to download commons-io-${COMMONS_IO_VERSION}.${EXT}"
        # For the JAR, create a minimal valid placeholder so the upload_artifact task isn't broken
        if [ "$EXT" = "jar" ]; then
            python3 -c "
import zipfile, io
buf = io.BytesIO()
with zipfile.ZipFile(buf, 'w') as z:
    z.writestr('META-INF/MANIFEST.MF',
               'Manifest-Version: 1.0\nImplementation-Title: Apache Commons IO\n'
               'Implementation-Version: 2.15.1\n')
buf.seek(0)
with open('$TARGET', 'wb') as f:
    f.write(buf.read())
print('Created placeholder commons-io-${COMMONS_IO_VERSION}.jar (upload_artifact task will still work)')
" 2>/dev/null || true
        fi
    fi
done

chown -R ga:ga "$ARTIFACTS_DIR"

# Copy artifacts to Desktop for easy access
mkdir -p /home/ga/Desktop
cp "${ARTIFACTS_DIR}/commons-io/commons-io-${COMMONS_IO_VERSION}.jar" \
   "/home/ga/Desktop/commons-io-${COMMONS_IO_VERSION}.jar" 2>/dev/null || true
cp "${ARTIFACTS_DIR}/commons-lang3/commons-lang3-${COMMONS_LANG_VERSION}.jar" \
   "/home/ga/Desktop/commons-lang3-${COMMONS_LANG_VERSION}.jar" 2>/dev/null || true

chown -R ga:ga /home/ga/Desktop/ 2>/dev/null || true

# ============================================================
# 5. Set up Firefox profile for Artifactory
# On Ubuntu 22.04+, apt installs Firefox via snap. Snap Firefox stores its
# profile in /home/ga/snap/firefox/common/.mozilla/firefox/ (NOT ~/.mozilla/firefox/).
# We pre-create a named profile in the snap path and use -profile when launching.
# ============================================================
echo "Setting up Firefox profile..."

# Detect snap vs deb Firefox: snap is present if the snap directory exists OR if
# /usr/bin/firefox is a snap wrapper (snap Firefox is installed before its snap dir exists)
# Safe approach: create profiles in BOTH locations; Firefox will use the one it can read.
SNAP_PROFILE_BASE="/home/ga/snap/firefox/common/.mozilla/firefox"
DEB_PROFILE_BASE="/home/ga/.mozilla/firefox"
PROFILE_NAME="artifactory.profile"

# Create snap profile directory (required for snap Firefox)
mkdir -p "${SNAP_PROFILE_BASE}/${PROFILE_NAME}"
# Snap Firefox needs to create /home/ga/snap/firefox/<revision>/ at runtime.
# chown the entire /home/ga/snap/ tree so the ga user can write there.
chown -R ga:ga /home/ga/snap 2>/dev/null || true

# Create deb profile directory (required for deb Firefox)
mkdir -p "${DEB_PROFILE_BASE}/${PROFILE_NAME}"
chown -R ga:ga "${DEB_PROFILE_BASE}" 2>/dev/null || true

# Write profiles.ini to both locations
for PROFILE_BASE in "$SNAP_PROFILE_BASE" "$DEB_PROFILE_BASE"; do
cat > "${PROFILE_BASE}/profiles.ini" << FFPROFILE
[Install4F96D1932A9F858E]
Default=${PROFILE_NAME}
Locked=1

[Profile0]
Name=${PROFILE_NAME}
IsRelative=1
Path=${PROFILE_NAME}
Default=1

[General]
StartWithLastProfile=1
Version=2
FFPROFILE
done
chown ga:ga "${SNAP_PROFILE_BASE}/profiles.ini" 2>/dev/null || true
chown ga:ga "${DEB_PROFILE_BASE}/profiles.ini" 2>/dev/null || true

# Write user.js to both profile directories
write_user_js() {
local PROFILE_DIR="$1"
cat > "${PROFILE_DIR}/user.js" << 'USERJS'
// Disable first-run screens
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.rights.3.shown", true);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.shell.didSkipDefaultBrowserCheckOnFirstRun", true);

// Set homepage to Artifactory
user_pref("browser.startup.homepage", "http://localhost:8082");
user_pref("browser.startup.page", 1);

// Disable update checks
user_pref("app.update.enabled", false);
user_pref("app.update.auto", false);

// Disable ALL password-related dialogs and autofill
user_pref("signon.rememberSignons", false);
user_pref("signon.autofillForms", false);
user_pref("signon.autofillForms.http", false);
user_pref("signon.firefoxRelay.feature", "disabled");
user_pref("signon.generation.enabled", false);
user_pref("signon.management.page.breach-alerts.enabled", false);
user_pref("browser.password-manager.enabled", false);
user_pref("extensions.formautofill.creditCards.enabled", false);
user_pref("extensions.formautofill.addresses.enabled", false);

// Disable notification bars and popups completely
user_pref("browser.contentblocking.report.hide_vpn_banner", true);
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

// Disable all notification permissions
user_pref("permissions.default.desktop-notification", 2);
USERJS
chown ga:ga "${PROFILE_DIR}/user.js"
}

# Write user.js to both snap and deb profile paths
write_user_js "${SNAP_PROFILE_BASE}/${PROFILE_NAME}"
write_user_js "${DEB_PROFILE_BASE}/${PROFILE_NAME}"
chown -R ga:ga "${SNAP_PROFILE_BASE}" 2>/dev/null || true
chown -R ga:ga "${DEB_PROFILE_BASE}" 2>/dev/null || true

# Determine which profile path to use (snap takes priority if snap dir is present)
if [ -d "/snap/firefox" ] || [ -d "/var/lib/snapd/snap/firefox" ]; then
    FIREFOX_PROFILE="${SNAP_PROFILE_BASE}/${PROFILE_NAME}"
    echo "Snap Firefox detected, using snap profile: $FIREFOX_PROFILE"
else
    FIREFOX_PROFILE="${DEB_PROFILE_BASE}/${PROFILE_NAME}"
    echo "Deb Firefox detected, using deb profile: $FIREFOX_PROFILE"
fi
echo "FIREFOX_PROFILE=${FIREFOX_PROFILE}" > /tmp/firefox_profile_path
echo "Firefox profile ready: $FIREFOX_PROFILE"

# Create desktop shortcut
cat > /home/ga/Desktop/Artifactory.desktop << 'DESKTOPEOF'
[Desktop Entry]
Name=JFrog Artifactory
Comment=Artifact Repository Manager
Exec=firefox http://localhost:8082
Icon=firefox
StartupNotify=true
Terminal=false
Type=Application
Categories=Development;
DESKTOPEOF
chown ga:ga /home/ga/Desktop/Artifactory.desktop
chmod +x /home/ga/Desktop/Artifactory.desktop
# Mark desktop file as trusted (GNOME requirement)
su - ga -c "dbus-launch gio set /home/ga/Desktop/Artifactory.desktop metadata::trusted true" 2>/dev/null || true

# ============================================================
# 6. Create REST API utility script
# ============================================================
cat > /usr/local/bin/art-api << 'ARTAPI'
#!/bin/bash
# Query Artifactory REST API
# Usage: art-api GET /api/repositories
#        art-api PUT /api/repositories/my-repo '{"rclass":"local",...}'
METHOD="${1:-GET}"
PATH_ARG="${2:-/api/system/ping}"
DATA="${3:-}"
ADMIN_USER="admin"
ADMIN_PASS="password"
URL="http://localhost:8082/artifactory${PATH_ARG}"
if [ -n "$DATA" ]; then
    curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" -X "$METHOD" \
        -H "Content-Type: application/json" \
        -d "$DATA" "$URL"
else
    curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" -X "$METHOD" "$URL"
fi
ARTAPI
chmod +x /usr/local/bin/art-api

# ============================================================
# 7. Launch Firefox with Artifactory
# ============================================================
echo "Launching Firefox with JFrog Artifactory..."
# Kill any stale Firefox processes and clean lock files
pkill -9 -f firefox 2>/dev/null || true
killall -9 firefox 2>/dev/null || true
sleep 3
# Clean lock files from all possible locations
find /home/ga/.mozilla/firefox/ -name ".parentlock" -delete 2>/dev/null || true
find /home/ga/.mozilla/firefox/ -name "lock" -delete 2>/dev/null || true
find /home/ga/snap/firefox/ -name ".parentlock" -delete 2>/dev/null || true
find /home/ga/snap/firefox/ -name "lock" -delete 2>/dev/null || true
# Use simple launch command (matching proven rancher_env pattern)
su - ga -c "DISPLAY=:1 setsid firefox 'http://localhost:8082' > /tmp/firefox_artifactory.log 2>&1 &"

# Wait for Firefox window (snap Firefox takes longer to initialize)
sleep 15
FIREFOX_STARTED=false
for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|artifactory"; then
        FIREFOX_STARTED=true
        echo "Firefox window detected after ${i}s"
        break
    fi
    sleep 1
done

if [ "$FIREFOX_STARTED" = true ]; then
    sleep 2
    WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
fi

echo ""
echo "=== JFrog Artifactory Setup Complete ==="
echo ""
echo "Artifactory is running at: ${ARTIFACTORY_URL}"
echo ""
echo "Login Credentials:"
echo "  Username: ${ADMIN_USER}"
echo "  Password: ${ADMIN_PASS}"
echo ""
echo "Default repository available: example-repo-local (Generic)"
echo "Artifact files available in: ${ARTIFACTS_DIR}/"
echo "  - commons-io-2.15.1.jar"
echo "  - commons-lang3-3.14.0.jar"
echo ""
echo "NOTE: Artifactory OSS 7.x - repositories/users/groups are created via UI."
echo ""
echo "Docker status:"
docker compose -f /home/ga/artifactory/docker-compose.yml ps 2>/dev/null || \
    docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "artif|post" || true
