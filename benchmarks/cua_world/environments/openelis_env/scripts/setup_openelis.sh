#!/bin/bash
# OpenELIS Global Setup Script (post_start hook)
# Starts Docker Compose services, waits for readiness, configures Firefox,
# seeds realistic patient data, and launches the browser.

set -euo pipefail

echo "=== Setting up OpenELIS Global ==="

OPENELIS_DIR="/home/ga/openelis"
OPENELIS_BASE_URL="https://localhost"
OPENELIS_ADMIN_USER="admin"
OPENELIS_ADMIN_PASS="adminADMIN!"

# Wait for desktop to stabilize
sleep 5

# ─── Detect compose command ───
choose_compose_cmd() {
    if docker compose version >/dev/null 2>&1; then
        echo "docker compose"
    else
        echo "docker-compose"
    fi
}

# ─── Wait for Docker daemon ───
wait_for_docker() {
    local timeout_sec=120
    local elapsed=0
    echo "Waiting for Docker daemon..."
    while [ "$elapsed" -lt "$timeout_sec" ]; do
        if docker info >/dev/null 2>&1; then
            echo "Docker is ready"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "ERROR: Docker daemon did not become ready within ${timeout_sec}s"
    return 1
}

# ─── Wait for PostgreSQL ───
wait_for_database() {
    local timeout=180
    local elapsed=0
    echo "Waiting for PostgreSQL database..."
    while [ $elapsed -lt $timeout ]; do
        if docker exec openelisglobal-database pg_isready -q -d clinlims -U clinlims 2>/dev/null; then
            echo "PostgreSQL is ready (${elapsed}s)"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        if [ $((elapsed % 30)) -eq 0 ]; then
            echo "  waiting for PostgreSQL... ${elapsed}s"
        fi
    done
    echo "WARNING: PostgreSQL timeout after ${timeout}s"
    return 1
}

# ─── Wait for OpenELIS webapp ───
wait_for_webapp() {
    local timeout=600
    local elapsed=0
    echo "Waiting for OpenELIS webapp (Liquibase migrations may take 3-8 minutes)..."
    while [ $elapsed -lt $timeout ]; do
        local status
        status=$(curl -sk -o /dev/null -w "%{http_code}" \
            "https://localhost:8443/api/OpenELIS-Global/LoginPage" 2>/dev/null || echo "000")
        if [ "$status" = "200" ] || [ "$status" = "302" ]; then
            echo "OpenELIS webapp is ready (${elapsed}s) - HTTP $status"
            return 0
        fi
        if [ $((elapsed % 30)) -eq 0 ]; then
            echo "  Still waiting... (${elapsed}s, HTTP=$status)"
        fi
        sleep 10
        elapsed=$((elapsed + 10))
    done
    echo "WARNING: OpenELIS webapp timeout after ${timeout}s"
    docker logs openelisglobal-webapp --tail 50 2>/dev/null || true
    return 1
}

# ─── Wait for frontend proxy ───
wait_for_frontend() {
    local timeout=120
    local elapsed=0
    echo "Waiting for frontend proxy (nginx)..."
    while [ $elapsed -lt $timeout ]; do
        local status
        status=$(curl -sk -o /dev/null -w "%{http_code}" "https://localhost/" 2>/dev/null || echo "000")
        if [ "$status" = "200" ] || [ "$status" = "302" ] || [ "$status" = "301" ]; then
            echo "Frontend proxy is ready (${elapsed}s) - HTTP $status"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done
    echo "WARNING: Frontend proxy timeout after ${timeout}s"
    return 1
}

# ─── Create directory structure for Docker Compose ───
mkdir -p "$OPENELIS_DIR/volume/database"
mkdir -p "$OPENELIS_DIR/volume/properties"
mkdir -p "$OPENELIS_DIR/volume/plugins"
mkdir -p "$OPENELIS_DIR/volume/lucene"
mkdir -p "$OPENELIS_DIR/volume/nginx"
mkdir -p "$OPENELIS_DIR/volume/analyzer"
mkdir -p "$OPENELIS_DIR/volume/odoo"
mkdir -p "$OPENELIS_DIR/volume/configuration"

# Copy config files from mounted workspace
cp /workspace/config/docker-compose.yml "$OPENELIS_DIR/"
cp /workspace/config/database.env "$OPENELIS_DIR/volume/database/"
cp /workspace/config/common.properties "$OPENELIS_DIR/volume/properties/"
cp /workspace/config/nginx.conf "$OPENELIS_DIR/volume/nginx/"
cp /workspace/config/SystemConfiguration.properties "$OPENELIS_DIR/volume/properties/"
cp /workspace/config/analyzer-test-map.csv "$OPENELIS_DIR/volume/analyzer/"
cp /workspace/config/odoo-test-product-mapping.csv "$OPENELIS_DIR/volume/odoo/"

chmod -R 644 "$OPENELIS_DIR/volume/properties/"* 2>/dev/null || true
chmod -R 644 "$OPENELIS_DIR/volume/analyzer/"* 2>/dev/null || true
chmod -R 644 "$OPENELIS_DIR/volume/odoo/"* 2>/dev/null || true
chown -R ga:ga "$OPENELIS_DIR"

# ─── Start Docker ───
wait_for_docker

# Fix Docker config permissions (docker login in pre_start runs as root)
chown -R ga:ga /home/ga/.docker 2>/dev/null || true

# Authenticate with Docker Hub
echo "dckr_pat_YISK01jQAaGVVmzkVoZnkOH3Q3g" | docker login -u "hackear2041" --password-stdin 2>/dev/null || true

# ─── Start Docker Compose ───
cd "$OPENELIS_DIR"
DC=$(choose_compose_cmd)
echo "Using compose command: $DC"

# Ensure clean startup
$DC down --remove-orphans --volumes >/dev/null 2>&1 || true

echo "Starting OpenELIS Docker Compose stack..."
$DC up -d

# ─── Wait for all services ───
wait_for_database
wait_for_webapp
wait_for_frontend

# ─── Verify login works ───
echo "Verifying admin login via API..."
LOGIN_STATUS=$(curl -sk -o /dev/null -w "%{http_code}" \
    -d "loginName=${OPENELIS_ADMIN_USER}&password=${OPENELIS_ADMIN_PASS}" \
    "https://localhost:8443/api/OpenELIS-Global/ValidateLogin" 2>/dev/null || echo "000")
echo "Admin login response: HTTP $LOGIN_STATUS"

# ─── Extract SSL certificate ───
echo "Extracting and installing SSL certificate..."
OPENELIS_CERT="/usr/local/share/ca-certificates/openelis-selfsigned.crt"
for cert_attempt in 1 2 3 4 5; do
    openssl s_client -connect localhost:443 -servername localhost </dev/null 2>/dev/null | \
        openssl x509 > "$OPENELIS_CERT" 2>/dev/null
    if [ -s "$OPENELIS_CERT" ]; then
        echo "  Certificate extracted on attempt $cert_attempt"
        break
    fi
    echo "  Cert extraction attempt $cert_attempt failed, retrying..."
    sleep 5
done
update-ca-certificates 2>/dev/null || true

# ─── Setup Firefox profile (snap-aware, bahmni-proven pattern) ───
setup_firefox_profile() {
    echo "Setting up Firefox profile..."

    IS_SNAP_FIREFOX=false
    if snap list firefox 2>/dev/null | grep -q firefox; then
        IS_SNAP_FIREFOX=true
        echo "  Detected Snap Firefox installation"
    fi

    FIREFOX_USERJS='// Disable first-run screens and welcome pages
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.rights.3.shown", true);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.shell.didSkipDefaultBrowserCheckOnFirstRun", true);

// Set homepage to OpenELIS
user_pref("browser.startup.homepage", "https://localhost/login");
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
user_pref("security.cert_pinning.enforcement_level", 0);
user_pref("network.stricttransportsecurity.preloadlist", false);
user_pref("security.tls.insecure_fallback_hosts", "localhost");

// Disable sidebar and popups
user_pref("sidebar.revamp", false);
user_pref("sidebar.verticalTabs", false);
user_pref("sidebar.main.tools", "");
user_pref("browser.vpn_promo.enabled", false);
user_pref("browser.messaging-system.whatsNewPanel.enabled", false);
user_pref("browser.uitour.enabled", false);
user_pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.addons", false);
user_pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.features", false);
user_pref("extensions.pocket.enabled", false);
user_pref("identity.fxaccounts.enabled", false);

// Privacy settings for testing
user_pref("privacy.trackingprotection.enabled", false);
user_pref("browser.contentblocking.category", "custom");
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

    # Run Firefox headless briefly to initialize profile databases (cert9.db, etc.)
    echo "  Initializing Firefox profile with headless launch..."
    su - ga -c "DISPLAY=:1 firefox --headless &" 2>/dev/null || true
    sleep 8
    pkill -f "firefox" 2>/dev/null || true
    sleep 2

    # Handle Snap Firefox profile
    if [ "$IS_SNAP_FIREFOX" = "true" ]; then
        echo "  Configuring Snap Firefox profile..."
        SNAP_PROFILE_DIR="/home/ga/snap/firefox/common/.mozilla/firefox"
        if [ -d "$SNAP_PROFILE_DIR" ]; then
            SNAP_PROFILE=$(find "$SNAP_PROFILE_DIR" -maxdepth 1 -name "*.default*" -type d | head -1)
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

    # Also find the actual profile dir Firefox created (may differ from our manual one)
    ACTUAL_PROFILE=$(find "$FIREFOX_PROFILE_DIR" -maxdepth 1 -name "*.default*" -type d 2>/dev/null | head -1)
    if [ -n "$ACTUAL_PROFILE" ] && [ "$ACTUAL_PROFILE" != "$FIREFOX_PROFILE_DIR/default-release" ]; then
        echo "  Found Firefox auto-created profile: $ACTUAL_PROFILE"
        echo "$FIREFOX_USERJS" > "$ACTUAL_PROFILE/user.js"
        chown ga:ga "$ACTUAL_PROFILE/user.js"
    fi

    echo "  Firefox profile setup complete"
}

# ─── Import cert into Firefox ───
import_cert_into_firefox() {
    local cert_file="$1"

    echo "Importing OpenELIS certificate into Firefox cert store..."
    if [ ! -s "$cert_file" ]; then
        echo "  WARNING: No certificate file to import"
        return 1
    fi

    FIREFOX_PROFILE_DIR="/home/ga/.mozilla/firefox"

    # Import into ALL Firefox profile directories
    local profile_dirs
    profile_dirs=$(find "$FIREFOX_PROFILE_DIR" -maxdepth 1 -type d -name "*.default*" 2>/dev/null)
    profile_dirs="$FIREFOX_PROFILE_DIR/default-release
$profile_dirs"

    while IFS= read -r pdir; do
        [ -z "$pdir" ] && continue
        [ ! -d "$pdir" ] && continue
        certutil -d "sql:$pdir" -N --empty-password 2>/dev/null || true
        certutil -A -n "OpenELIS-SelfSigned" -t "CT,C,C" \
            -i "$cert_file" -d "sql:$pdir" 2>/dev/null || true
        echo "  Cert imported into Firefox profile: $pdir"
    done <<< "$profile_dirs"

    # Import into Snap profile directories
    if [ -d "/home/ga/snap/firefox/common/.mozilla/firefox/" ]; then
        local snap_dirs
        snap_dirs=$(find /home/ga/snap/firefox/common/.mozilla/firefox/ -maxdepth 1 -type d -name "*.default*" 2>/dev/null || true)
        while IFS= read -r sdir; do
            [ -z "$sdir" ] && continue
            [ ! -d "$sdir" ] && continue
            certutil -d "sql:$sdir" -N --empty-password 2>/dev/null || true
            certutil -A -n "OpenELIS-SelfSigned" -t "CT,C,C" \
                -i "$cert_file" -d "sql:$sdir" 2>/dev/null || true
            echo "  Cert imported into Snap profile: $sdir"
        done <<< "$snap_dirs"
    fi

    # Import into NSS shared database
    mkdir -p /home/ga/.pki/nssdb
    certutil -d sql:/home/ga/.pki/nssdb -N --empty-password 2>/dev/null || true
    certutil -A -n "OpenELIS-SelfSigned" -t "CT,C,C" \
        -i "$cert_file" -d "sql:/home/ga/.pki/nssdb" 2>/dev/null || true
    chown -R ga:ga /home/ga/.pki
    echo "  Cert imported into NSS shared database"

    # Set up Firefox Enterprise Policies
    local POLICIES_JSON
    POLICIES_JSON=$(cat <<POLICIESEOF
{
  "policies": {
    "Certificates": {
      "ImportEnterpriseRoots": true,
      "Install": [
        "$cert_file"
      ]
    }
  }
}
POLICIESEOF
)

    if [ -d "/usr/lib/firefox" ]; then
        mkdir -p /usr/lib/firefox/distribution
        echo "$POLICIES_JSON" > /usr/lib/firefox/distribution/policies.json
        echo "  Policies written to /usr/lib/firefox/distribution/"
    fi
    if snap list firefox 2>/dev/null | grep -q firefox; then
        mkdir -p /etc/firefox/policies
        echo "$POLICIES_JSON" > /etc/firefox/policies/policies.json
        echo "  Policies written to /etc/firefox/policies/"
    fi

    chown -R ga:ga "$FIREFOX_PROFILE_DIR" 2>/dev/null || true
}

# ─── Create cert_override.txt for SSL bypass ───
create_cert_override() {
    local cert_file="$1"

    echo "Creating Firefox cert_override.txt entries..."
    if [ ! -s "$cert_file" ]; then
        echo "  WARNING: No certificate file for cert override"
        return 1
    fi

    local fingerprint
    fingerprint=$(openssl x509 -in "$cert_file" -outform DER 2>/dev/null | \
        openssl dgst -sha256 -binary 2>/dev/null | \
        xxd -p -c 256 2>/dev/null | \
        sed 's/\(..\)/\U\1:/g; s/:$//' 2>/dev/null)

    if [ -z "$fingerprint" ]; then
        echo "  WARNING: Could not compute cert fingerprint"
        return 1
    fi
    echo "  Cert SHA-256 fingerprint: ${fingerprint:0:20}..."

    local override_line
    override_line="localhost:443	OID.2.16.840.1.101.3.4.2.1	${fingerprint}	MU"

    local all_profile_dirs=""
    all_profile_dirs=$(find /home/ga/.mozilla/firefox/ -maxdepth 1 -type d 2>/dev/null | tail -n +2)
    if [ -d "/home/ga/snap/firefox/common/.mozilla/firefox/" ]; then
        all_profile_dirs="${all_profile_dirs}
$(find /home/ga/snap/firefox/common/.mozilla/firefox/ -maxdepth 1 -type d 2>/dev/null | tail -n +2)"
    fi

    while IFS= read -r pdir; do
        [ -z "$pdir" ] && continue
        [ ! -d "$pdir" ] && continue
        local override_file="$pdir/cert_override.txt"
        if [ -f "$override_file" ] && grep -q "localhost:443" "$override_file" 2>/dev/null; then
            echo "  cert_override.txt already has localhost entry in: $pdir"
            continue
        fi
        echo "# PSM Certificate Override Settings file" > "$override_file"
        echo "# This is a generated file! Do not edit." >> "$override_file"
        echo "$override_line" >> "$override_file"
        chown ga:ga "$override_file" 2>/dev/null || true
        echo "  cert_override.txt written to: $pdir"
    done <<< "$all_profile_dirs"
}

# ─── Firefox warmup ───
warmup_browser() {
    echo "Warming up Firefox browser..."

    pkill -KILL -f firefox 2>/dev/null || true
    sleep 2

    find /home/ga/.mozilla/firefox/ -name ".parentlock" -delete 2>/dev/null || true
    find /home/ga/.mozilla/firefox/ -name "lock" -delete 2>/dev/null || true
    find /home/ga/snap/firefox/ -name ".parentlock" -delete 2>/dev/null || true
    find /home/ga/snap/firefox/ -name "lock" -delete 2>/dev/null || true

    su - ga -c "DISPLAY=:1 setsid firefox '${OPENELIS_BASE_URL}/login' > /tmp/firefox_warmup.log 2>&1 &"

    echo "  Waiting for browser window..."
    local elapsed=0
    while [ "$elapsed" -lt 60 ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -v '@!0,0' | grep -qi '.'; then
            break
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    sleep 2
    local wid
    wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -v '@!0,0' | awk '{print $1; exit}')
    if [ -n "$wid" ]; then
        DISPLAY=:1 wmctrl -ia "$wid" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
    sleep 2

    # Check if SSL warning appeared
    local win_title
    win_title=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -v '@!0,0' \
        | awk '{for(i=4;i<=NF;i++) printf $i " "; print ""}' | head -1 | xargs)
    echo "  Current window title: $win_title"

    if echo "$win_title" | grep -qi "security\|warning\|risk\|error"; then
        echo "  Certificate warning detected, dismissing with mouse clicks..."
        # Click "Advanced..." button: VG (879, 470) → actual (1319, 705)
        DISPLAY=:1 xdotool mousemove 1319 705 click 1 2>/dev/null || true
        sleep 4
        # Click "Accept the Risk and Continue"
        DISPLAY=:1 xdotool mousemove 1319 800 click 1 2>/dev/null || true
        sleep 3

        win_title=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -v '@!0,0' \
            | awk '{for(i=4;i<=NF;i++) printf $i " "; print ""}' | head -1 | xargs)
        if echo "$win_title" | grep -qi "security\|warning\|risk\|error"; then
            echo "  First click didn't work, trying alternate positions..."
            DISPLAY=:1 xdotool mousemove 1200 790 click 1 2>/dev/null || true
            sleep 2
            DISPLAY=:1 xdotool mousemove 1100 810 click 1 2>/dev/null || true
            sleep 2
        fi

        win_title=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -v '@!0,0' \
            | awk '{for(i=4;i<=NF;i++) printf $i " "; print ""}' | head -1 | xargs)
        if ! echo "$win_title" | grep -qi "security\|warning\|risk\|error"; then
            echo "  Certificate warning dismissed"
        else
            echo "  WARNING: Certificate warning may still be present"
        fi
    else
        echo "  No certificate warning — cert import succeeded"
    fi

    # Wait for OpenELIS page
    echo "  Waiting for OpenELIS page..."
    elapsed=0
    while [ "$elapsed" -lt 30 ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "openelis\|login\|home\|localhost"; then
            echo "  OpenELIS page loaded"
            break
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    win_title=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -v '@!0,0' | awk '{for(i=4;i<=NF;i++) printf $i " "; print ""}' | head -1 | xargs)
    echo "  Browser window title: ${win_title}"

    echo "Browser warm-up complete"
}

# ─── Execute all setup steps ───
setup_firefox_profile
import_cert_into_firefox "$OPENELIS_CERT"
create_cert_override "$OPENELIS_CERT"

# ─── Seed realistic patient data ───
echo "Seeding realistic patient data..."
if [ -f /workspace/data/seed_openelis.py ]; then
    python3 /workspace/data/seed_openelis.py 2>&1 | tail -30 || echo "WARNING: Data seeding had issues (non-fatal)"
fi

warmup_browser

echo ""
echo "=== OpenELIS Setup Complete ==="
echo "Access URL: ${OPENELIS_BASE_URL}/"
echo "Login: ${OPENELIS_ADMIN_USER} / ${OPENELIS_ADMIN_PASS}"
echo ""
echo "Docker containers:"
docker ps --format "  {{.Names}}: {{.Status}}" 2>/dev/null || true
