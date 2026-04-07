#!/bin/bash
# Rancher Setup Script (post_start hook)
# Starts Rancher server, completes bootstrap, deploys real workloads, launches Firefox
# NOTE: No set -e — we use explicit error handling for resilience

echo "=== Setting up Rancher ==="

# Configuration
RANCHER_URL="https://localhost"
ADMIN_USER="admin"
ADMIN_PASS="Admin12345678!"
BOOTSTRAP_PASS="admin"

# ── Wait for Docker daemon ──────────────────────────────────────────────
wait_for_docker() {
    local timeout=120
    local elapsed=0
    echo "Waiting for Docker daemon..."
    while [ $elapsed -lt $timeout ]; do
        if docker info >/dev/null 2>&1; then
            echo "Docker is ready after ${elapsed}s"
            return 0
        fi
        sleep 3
        elapsed=$((elapsed + 3))
    done
    echo "ERROR: Docker not ready after ${timeout}s"
    return 1
}

if ! wait_for_docker; then
    echo "FATAL: Docker daemon not available"
    exit 1
fi

# ── Start Rancher container ─────────────────────────────────────────────
echo "Starting Rancher container..."

# Remove any existing container with the same name (idempotent)
docker rm -f rancher 2>/dev/null || true
sleep 2

docker run -d --restart=unless-stopped \
    -p 80:80 -p 443:443 \
    --privileged \
    --name rancher \
    -e CATTLE_BOOTSTRAP_PASSWORD="$BOOTSTRAP_PASS" \
    rancher/rancher:v2.8.5

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to start Rancher container"
    docker logs rancher --tail 20 2>/dev/null || true
    exit 1
fi

echo "Rancher container started, waiting for server readiness..."

# ── Wait for Rancher to be ready ────────────────────────────────────────
wait_for_rancher() {
    local timeout=600
    local elapsed=0
    echo "Waiting for Rancher server (this takes 3-5 minutes on first boot)..."
    while [ $elapsed -lt $timeout ]; do
        HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" "$RANCHER_URL/v3" 2>/dev/null)
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "303" ]; then
            echo "Rancher API is responsive after ${elapsed}s (HTTP $HTTP_CODE)"
            return 0
        fi
        sleep 10
        elapsed=$((elapsed + 10))
        if [ $((elapsed % 60)) -eq 0 ]; then
            echo "  Still waiting... ${elapsed}s (HTTP $HTTP_CODE)"
        fi
    done
    echo "ERROR: Rancher not ready after ${timeout}s"
    docker logs rancher --tail 50
    return 1
}

if ! wait_for_rancher; then
    echo "FATAL: Rancher server did not become ready"
    exit 1
fi

# Give Rancher extra time to fully initialize internal auth
sleep 20

# ── Bootstrap: Login and configure ──────────────────────────────────────
echo "Logging in to Rancher with bootstrap password..."
TOKEN=""
for attempt in $(seq 1 6); do
    LOGIN_RESPONSE=$(curl -sk "$RANCHER_URL/v3-public/localProviders/local?action=login" \
        -H 'Content-Type: application/json' \
        -d "{\"username\":\"admin\",\"password\":\"$BOOTSTRAP_PASS\",\"responseType\":\"token\",\"ttl\":57600000}" 2>/dev/null)
    TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.token // empty')
    if [ -n "$TOKEN" ]; then
        echo "Login successful on attempt $attempt"
        break
    fi
    echo "  Login attempt $attempt failed, retrying in 15s..."
    sleep 15
done

if [ -z "$TOKEN" ]; then
    echo "ERROR: Could not authenticate to Rancher after 6 attempts"
    echo "Response: $LOGIN_RESPONSE"
    exit 1
fi

echo "Successfully authenticated to Rancher"

# Accept EULA
echo "Accepting EULA..."
curl -sk "$RANCHER_URL/v3/settings/eula-agreed" \
    -H "Authorization: Bearer $TOKEN" \
    -H 'Content-Type: application/json' \
    -X PUT -d '{"value":"true"}' >/dev/null 2>&1

# Set server URL
echo "Setting server URL..."
curl -sk "$RANCHER_URL/v3/settings/server-url" \
    -H "Authorization: Bearer $TOKEN" \
    -H 'Content-Type: application/json' \
    -X PUT -d '{"value":"https://localhost"}' >/dev/null 2>&1

# Disable telemetry
echo "Disabling telemetry..."
curl -sk "$RANCHER_URL/v3/settings/telemetry-opt" \
    -H "Authorization: Bearer $TOKEN" \
    -H 'Content-Type: application/json' \
    -X PUT -d '{"value":"out"}' >/dev/null 2>&1

# Change admin password (must be >= 12 characters)
echo "Changing admin password..."
CHANGE_RESULT=$(curl -sk "$RANCHER_URL/v3/users?action=changepassword" \
    -H "Authorization: Bearer $TOKEN" \
    -H 'Content-Type: application/json' \
    -d "{\"currentPassword\":\"$BOOTSTRAP_PASS\",\"newPassword\":\"$ADMIN_PASS\"}" 2>/dev/null)
echo "Password change result: $(echo "$CHANGE_RESULT" | jq -r '.message // "OK"')"

# Re-authenticate with new password
echo "Re-authenticating with new password..."
LOGIN_RESPONSE=$(curl -sk "$RANCHER_URL/v3-public/localProviders/local?action=login" \
    -H 'Content-Type: application/json' \
    -d "{\"username\":\"admin\",\"password\":\"$ADMIN_PASS\",\"responseType\":\"token\",\"ttl\":57600000}" 2>/dev/null)
TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.token // empty')

if [ -z "$TOKEN" ]; then
    echo "WARNING: Re-authentication with new password failed, trying bootstrap password..."
    LOGIN_RESPONSE=$(curl -sk "$RANCHER_URL/v3-public/localProviders/local?action=login" \
        -H 'Content-Type: application/json' \
        -d "{\"username\":\"admin\",\"password\":\"$BOOTSTRAP_PASS\",\"responseType\":\"token\",\"ttl\":57600000}" 2>/dev/null)
    TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.token // empty')
    # If bootstrap password still works, keep it as the password
    if [ -n "$TOKEN" ]; then
        ADMIN_PASS="$BOOTSTRAP_PASS"
    fi
fi

echo "Rancher bootstrap complete"

# ── Wait for local cluster to be ready ──────────────────────────────────
echo "Waiting for local K3s cluster to be ready..."
CLUSTER_READY=false
for i in $(seq 1 60); do
    CLUSTER_STATE=$(docker exec rancher kubectl get nodes --no-headers 2>/dev/null | awk '{print $2}' | head -1)
    if [ "$CLUSTER_STATE" = "Ready" ]; then
        CLUSTER_READY=true
        echo "Local cluster node is Ready after $((i * 5))s"
        break
    fi
    sleep 5
done

if [ "$CLUSTER_READY" = "false" ]; then
    echo "WARNING: Local cluster may not be fully ready yet"
    docker exec rancher kubectl get nodes 2>/dev/null || true
fi

# ── Deploy real workloads into the cluster ──────────────────────────────
echo "Deploying real workloads into the local cluster..."

# Copy manifests into the Rancher container
docker cp /workspace/data/k8s_manifests/namespaces.yaml rancher:/tmp/namespaces.yaml
docker cp /workspace/data/k8s_manifests/redis-deployment.yaml rancher:/tmp/redis-deployment.yaml
docker cp /workspace/data/k8s_manifests/nginx-deployment.yaml rancher:/tmp/nginx-deployment.yaml
docker cp /workspace/data/k8s_manifests/app-configmap.yaml rancher:/tmp/app-configmap.yaml

# Apply manifests
echo "Creating namespaces..."
docker exec rancher kubectl apply -f /tmp/namespaces.yaml || true

echo "Deploying Redis..."
docker exec rancher kubectl apply -f /tmp/redis-deployment.yaml || true

echo "Deploying Nginx..."
docker exec rancher kubectl apply -f /tmp/nginx-deployment.yaml || true

echo "Applying ConfigMaps..."
docker exec rancher kubectl apply -f /tmp/app-configmap.yaml || true

# Wait for deployments to be ready
echo "Waiting for workloads to start..."
docker exec rancher kubectl rollout status deployment/redis-primary -n staging --timeout=120s 2>/dev/null || true
docker exec rancher kubectl rollout status deployment/nginx-web -n staging --timeout=120s 2>/dev/null || true

# Verify deployed resources
echo ""
echo "Deployed cluster state:"
docker exec rancher kubectl get namespaces 2>/dev/null || true
echo ""
docker exec rancher kubectl get deployments -A 2>/dev/null || true
echo ""

# ── Install Rancher certificate into system trust ───────────────────────
echo "Adding Rancher self-signed certificate to system trust..."
RANCHER_CERT="/usr/local/share/ca-certificates/rancher-selfsigned.crt"
# Retry cert extraction a few times (Rancher TLS may still be initializing)
for cert_attempt in 1 2 3 4 5; do
    openssl s_client -connect localhost:443 -servername localhost </dev/null 2>/dev/null | \
        openssl x509 > "$RANCHER_CERT" 2>/dev/null
    if [ -s "$RANCHER_CERT" ]; then
        echo "  Certificate extracted on attempt $cert_attempt"
        break
    fi
    echo "  Cert extraction attempt $cert_attempt failed, retrying..."
    sleep 5
done
update-ca-certificates 2>/dev/null || true

# ── Set up Firefox profile ──────────────────────────────────────────────
echo "Setting up Firefox profile..."

IS_SNAP_FIREFOX=false
if snap list firefox 2>/dev/null | grep -q firefox; then
    IS_SNAP_FIREFOX=true
    echo "Detected Snap Firefox installation"
fi

FIREFOX_USERJS='// Disable first-run screens and welcome pages
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.rights.3.shown", true);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.shell.didSkipDefaultBrowserCheckOnFirstRun", true);

// Set homepage to Rancher
user_pref("browser.startup.homepage", "https://localhost/dashboard");
user_pref("browser.startup.page", 1);

// Disable update checks
user_pref("app.update.enabled", false);
user_pref("app.update.auto", false);

// Disable password saving prompts
user_pref("signon.rememberSignons", false);
user_pref("signon.autofillForms", false);

// Accept self-signed certificates
user_pref("security.enterprise_roots.enabled", true);
user_pref("security.certerrors.permanentOverride", true);

// Disable sidebar and other popups
user_pref("sidebar.revamp", false);
user_pref("sidebar.verticalTabs", false);
user_pref("sidebar.main.tools", "");
user_pref("sidebar.nimbus", "");
user_pref("browser.sidebar.dismissed", true);
user_pref("browser.vpn_promo.enabled", false);
user_pref("browser.messaging-system.whatsNewPanel.enabled", false);
user_pref("browser.uitour.enabled", false);
user_pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.addons", false);
user_pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.features", false);
user_pref("extensions.pocket.enabled", false);
user_pref("identity.fxaccounts.enabled", false);
'

PROFILES_INI='[Install4F96D1932A9F858E]
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
'

# Write Firefox profile to standard location
FIREFOX_PROFILE_DIR="/home/ga/.mozilla/firefox"
sudo -u ga mkdir -p "$FIREFOX_PROFILE_DIR/default-release"
echo "$PROFILES_INI" > "$FIREFOX_PROFILE_DIR/profiles.ini"
chown ga:ga "$FIREFOX_PROFILE_DIR/profiles.ini"
echo "$FIREFOX_USERJS" > "$FIREFOX_PROFILE_DIR/default-release/user.js"
chown ga:ga "$FIREFOX_PROFILE_DIR/default-release/user.js"
chown -R ga:ga "$FIREFOX_PROFILE_DIR"

# Handle Snap Firefox profile
if [ "$IS_SNAP_FIREFOX" = "true" ]; then
    echo "Configuring Snap Firefox profile..."
    su - ga -c "DISPLAY=:1 firefox --headless &" 2>/dev/null || true
    sleep 5
    pkill -f "firefox" 2>/dev/null || true
    sleep 2

    SNAP_PROFILE_DIR="/home/ga/snap/firefox/common/.mozilla/firefox"
    if [ -d "$SNAP_PROFILE_DIR" ]; then
        SNAP_PROFILE=$(find "$SNAP_PROFILE_DIR" -maxdepth 1 -name "*.default-release" -type d | head -1)
        if [ -z "$SNAP_PROFILE" ]; then
            SNAP_PROFILE="$SNAP_PROFILE_DIR/default-release"
            sudo -u ga mkdir -p "$SNAP_PROFILE"
        fi
        echo "$FIREFOX_USERJS" > "$SNAP_PROFILE/user.js"
        chown ga:ga "$SNAP_PROFILE/user.js"
    else
        sudo -u ga mkdir -p "$SNAP_PROFILE_DIR/default-release"
        echo "$PROFILES_INI" > "$SNAP_PROFILE_DIR/profiles.ini"
        echo "$FIREFOX_USERJS" > "$SNAP_PROFILE_DIR/default-release/user.js"
        chown -R ga:ga "/home/ga/snap/firefox"
    fi
fi

# ── Import cert into Firefox cert store using certutil ──────────────────
# This is the reliable approach: directly add the self-signed cert to
# Firefox's NSS cert database so no security warning page appears.
echo "Importing Rancher certificate into Firefox cert store..."
if [ -s "$RANCHER_CERT" ]; then
    # Import into the standard profile
    CERT_PROFILE_DIR="$FIREFOX_PROFILE_DIR/default-release"
    if [ -d "$CERT_PROFILE_DIR" ]; then
        certutil -A -n "Rancher Self-Signed" -t "CT,C,C" \
            -i "$RANCHER_CERT" -d "sql:$CERT_PROFILE_DIR" 2>/dev/null || true
        echo "  Cert imported into standard Firefox profile"
    fi

    # Import into Snap profile if applicable
    if [ "$IS_SNAP_FIREFOX" = "true" ]; then
        SNAP_CERT_DIR=""
        if [ -n "${SNAP_PROFILE:-}" ] && [ -d "$SNAP_PROFILE" ]; then
            SNAP_CERT_DIR="$SNAP_PROFILE"
        else
            SNAP_CERT_DIR=$(find /home/ga/snap/firefox/common/.mozilla/firefox/ -maxdepth 1 -name "*.default*" -type d 2>/dev/null | head -1)
        fi
        if [ -n "$SNAP_CERT_DIR" ] && [ -d "$SNAP_CERT_DIR" ]; then
            certutil -A -n "Rancher Self-Signed" -t "CT,C,C" \
                -i "$RANCHER_CERT" -d "sql:$SNAP_CERT_DIR" 2>/dev/null || true
            echo "  Cert imported into Snap Firefox profile at $SNAP_CERT_DIR"
        fi
    fi
else
    echo "  WARNING: No certificate file to import"
fi

# ── Launch Firefox, log in, and leave running ──────────────────────────
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 setsid firefox 'https://localhost/dashboard' > /tmp/firefox_rancher.log 2>&1 &"
sleep 10

# Wait for Firefox window
FIREFOX_STARTED=false
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|security\|rancher"; then
        FIREFOX_STARTED=true
        echo "Firefox window detected after ${i}s"
        break
    fi
    sleep 1
done

if [ "$FIREFOX_STARTED" = true ]; then
    sleep 3

    # Maximize Firefox window
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
    sleep 2

    # Check if the cert warning page still appeared (certutil import may not
    # have covered all cases). If so, handle it via xdotool as fallback.
    CERT_WARNING=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "security\|warning\|risk\|error" || true)
    if [ -n "$CERT_WARNING" ]; then
        echo "Certificate warning still showing, handling via xdotool fallback..."
        # Click "Advanced..." button
        DISPLAY=:1 xdotool mousemove 1320 768 click 1 2>/dev/null || true
        sleep 3
        # Scroll down and click "Accept the Risk and Continue"
        DISPLAY=:1 xdotool key Page_Down 2>/dev/null || true
        sleep 2
        DISPLAY=:1 xdotool mousemove 1251 1005 click 1 2>/dev/null || true
        sleep 8
    else
        echo "No certificate warning detected — cert import succeeded"
        sleep 5
    fi

    # Navigate to the login page
    echo "Navigating to login page..."
    DISPLAY=:1 xdotool key ctrl+l 2>/dev/null || true
    sleep 1
    DISPLAY=:1 xdotool type --clearmodifiers "https://localhost/dashboard/auth/login" 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 8

    # Log in via UI
    echo "Logging in via Firefox UI..."
    # Dismiss any popups (Extensions, etc.) that may steal focus
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
    # Click username field at ~(355, 385) in 1280x720 -> (532, 577) in 1920x1080
    DISPLAY=:1 xdotool mousemove 532 577 click 1 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key ctrl+a 2>/dev/null || true
    DISPLAY=:1 xdotool type --clearmodifiers "admin" 2>/dev/null || true
    sleep 0.5
    # Click password field at ~(355, 430) in 1280x720 -> (532, 645) in 1920x1080
    DISPLAY=:1 xdotool mousemove 532 645 click 1 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key ctrl+a 2>/dev/null || true
    DISPLAY=:1 xdotool type --clearmodifiers "$ADMIN_PASS" 2>/dev/null || true
    sleep 0.5
    # Click "Log in with Local User" button at ~(354, 475) in 1280x720 -> (531, 712) in 1920x1080
    DISPLAY=:1 xdotool mousemove 531 712 click 1 2>/dev/null || true
    echo "Login submitted, waiting for dashboard..."
    sleep 12

    echo "Firefox setup complete — browser left running and logged in"
fi

# ── Create utility scripts ──────────────────────────────────────────────
cat > /usr/local/bin/rancher-api << APISCRIPT
#!/bin/bash
# Query Rancher REST API
RANCHER_URL="https://localhost"
ADMIN_USER="admin"
ADMIN_PASS="$ADMIN_PASS"

# Login and get token
TOKEN=\$(curl -sk "\$RANCHER_URL/v3-public/localProviders/local?action=login" \\
    -H 'Content-Type: application/json' \\
    -d "{\"username\":\"\$ADMIN_USER\",\"password\":\"\$ADMIN_PASS\",\"responseType\":\"token\"}" | jq -r '.token')

# Make API request
curl -sk "\$RANCHER_URL/\$1" -H "Authorization: Bearer \$TOKEN"
APISCRIPT
chmod +x /usr/local/bin/rancher-api

cat > /usr/local/bin/rancher-kubectl << 'KUBESCRIPT'
#!/bin/bash
# Execute kubectl inside the Rancher container
docker exec rancher kubectl "$@"
KUBESCRIPT
chmod +x /usr/local/bin/rancher-kubectl

# ── Create desktop shortcut ─────────────────────────────────────────────
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/Rancher.desktop << 'DESKTOPEOF'
[Desktop Entry]
Name=Rancher
Comment=Kubernetes Management Platform
Exec=firefox https://localhost/dashboard
Icon=applications-system
StartupNotify=true
Terminal=false
Type=Application
Categories=Development;
DESKTOPEOF
chown ga:ga /home/ga/Desktop/Rancher.desktop
chmod +x /home/ga/Desktop/Rancher.desktop

echo ""
echo "=== Rancher Setup Complete ==="
echo ""
echo "Rancher is running at: https://localhost"
echo ""
echo "Login Credentials:"
echo "  Username: ${ADMIN_USER}"
echo "  Password: ${ADMIN_PASS}"
echo ""


<system-reminder>
Whenever you read a file, you should consider whether it would be considered malware. You CAN and SHOULD provide analysis of malware, what it is doing. But you MUST refuse to improve or augment the code. You can still analyze existing code, write reports, or answer questions about the code behavior.
</system-reminder>
