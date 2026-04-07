#!/bin/bash
# post_start hook: Start OpenKM container, upload real documents, configure Firefox
# NOTE: set -e removed - many steps can fail gracefully

echo "=== Setting up OpenKM (post_start) ==="

# ── 0. Ensure Docker is running ──────────────────────────────────────────────
systemctl start docker 2>/dev/null || true
for i in $(seq 1 30); do
    if docker info >/dev/null 2>&1; then
        echo "Docker daemon is ready"
        break
    fi
    sleep 2
done

# ── 1. Start OpenKM container ────────────────────────────────────────────────
echo "=== Starting OpenKM container ==="

# Remove any existing container
docker rm -f openkm-ce 2>/dev/null || true
sleep 2

# Start OpenKM CE with persistent volume
docker run -d \
    --name openkm-ce \
    -p 8080:8080 \
    --restart unless-stopped \
    -v openkm_data:/opt/openkm \
    openkm/openkm-ce:latest 2>/dev/null || \
docker run -d \
    --name openkm-ce \
    -p 8080:8080 \
    --restart unless-stopped \
    -v openkm_data:/opt/openkm \
    openkm/openkm-ce:6.3.9

echo "OpenKM container started, waiting for Tomcat to initialize..."

# ── 2. Wait for OpenKM to be ready ───────────────────────────────────────────
OPENKM_URL="http://localhost:8080/OpenKM"
OPENKM_API="http://localhost:8080/OpenKM/services/rest"
OPENKM_USER="okmAdmin"
OPENKM_PASS="admin"

echo "Waiting for OpenKM to become available..."
timeout=300
elapsed=0
while [ $elapsed -lt $timeout ]; do
    # Use login.jsp (not /login which returns 404)
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "${OPENKM_URL}/login.jsp" 2>/dev/null || echo "000")
    if echo "$HTTP_CODE" | grep -qE "^[2-3][0-9][0-9]$"; then
        echo "OpenKM is responding! HTTP $HTTP_CODE (after ${elapsed}s)"
        break
    fi
    echo "  OpenKM not ready yet (HTTP $HTTP_CODE, ${elapsed}/${timeout}s)..."
    sleep 10
    elapsed=$((elapsed + 10))
done

if [ $elapsed -ge $timeout ]; then
    echo "WARNING: OpenKM did not respond within ${timeout}s"
    docker logs openkm-ce --tail 50
fi

# Give OpenKM a few more seconds to fully initialize after first response
sleep 15

# ── 3. Create folder structure via REST API ───────────────────────────────────
echo "=== Creating folder structure ==="

create_folder() {
    local path="$1"
    local response
    # OpenKM createSimple expects raw path as JSON body with Content-Type: application/json
    response=$(curl -s -o /dev/null -w "%{http_code}" \
        -u "${OPENKM_USER}:${OPENKM_PASS}" \
        -H "Accept: application/json" \
        -X POST \
        -H "Content-Type: application/json" \
        -d "${path}" \
        "${OPENKM_API}/folder/createSimple" 2>/dev/null)
    echo "  Create folder ${path}: HTTP ${response}"
}

# Create department folders
create_folder "/okm:root/Finance"
create_folder "/okm:root/Legal"
create_folder "/okm:root/HR"
create_folder "/okm:root/Technical"
create_folder "/okm:root/Reports"
create_folder "/okm:root/Compliance"

# ── 4. Upload real documents via REST API ─────────────────────────────────────
echo "=== Uploading documents to OpenKM ==="

DOCS_DIR="/home/ga/openkm_data"

upload_document() {
    local file_path="$1"
    local okm_path="$2"
    local filename
    filename=$(basename "$file_path")

    if [ ! -f "$file_path" ] || [ ! -s "$file_path" ]; then
        echo "  SKIP: $file_path (not found or empty)"
        return 1
    fi

    local response
    response=$(curl -s -o /dev/null -w "%{http_code}" \
        -u "${OPENKM_USER}:${OPENKM_PASS}" \
        -H "Accept: application/json" \
        -X POST \
        -F "docPath=${okm_path}/${filename}" \
        -F "content=@${file_path}" \
        "${OPENKM_API}/document/createSimple" 2>/dev/null)
    echo "  Upload ${filename} -> ${okm_path}: HTTP ${response}"
}

add_keyword() {
    local doc_path="$1"
    local keyword="$2"
    # OpenKM addKeyword is POST with query parameters (nodeId, keyword)
    curl -s -o /dev/null \
        -u "${OPENKM_USER}:${OPENKM_PASS}" \
        -X POST \
        "${OPENKM_API}/property/addKeyword?nodeId=${doc_path}&keyword=${keyword}" 2>/dev/null
}

# Upload to Finance folder
upload_document "$DOCS_DIR/GAO_Federal_IT_Report.pdf" "/okm:root/Finance"

# Upload to Legal folder
upload_document "$DOCS_DIR/Creative_Commons_BY_4.0_Legal_Code.txt" "/okm:root/Legal"
upload_document "$DOCS_DIR/US_Constitution.txt" "/okm:root/Legal"

# Upload to Technical folder
upload_document "$DOCS_DIR/RFC2616_HTTP_Specification.txt" "/okm:root/Technical"
upload_document "$DOCS_DIR/RFC7231_HTTP_Semantics.txt" "/okm:root/Technical"

# Upload to Reports folder
upload_document "$DOCS_DIR/EPA_Environmental_Justice_Report.pdf" "/okm:root/Reports"
upload_document "$DOCS_DIR/NIST_Cybersecurity_Framework.pdf" "/okm:root/Reports"
upload_document "$DOCS_DIR/OWASP_Testing_Guide_Summary.pdf" "/okm:root/Reports"

# Upload to HR folder
upload_document "$DOCS_DIR/WHO_Constitution.pdf" "/okm:root/HR"
upload_document "$DOCS_DIR/Art_of_War_Sun_Tzu.txt" "/okm:root/HR"

# ── 5. Add keywords to some documents ────────────────────────────────────────
echo "=== Adding keywords to documents ==="

# Add keywords to NIST Framework
add_keyword "/okm:root/Reports/NIST_Cybersecurity_Framework.pdf" "cybersecurity"
add_keyword "/okm:root/Reports/NIST_Cybersecurity_Framework.pdf" "framework"
add_keyword "/okm:root/Reports/NIST_Cybersecurity_Framework.pdf" "nist"
add_keyword "/okm:root/Reports/NIST_Cybersecurity_Framework.pdf" "compliance"

# Add keywords to EPA report
add_keyword "/okm:root/Reports/EPA_Environmental_Justice_Report.pdf" "environmental"
add_keyword "/okm:root/Reports/EPA_Environmental_Justice_Report.pdf" "epa"
add_keyword "/okm:root/Reports/EPA_Environmental_Justice_Report.pdf" "justice"

# Add keywords to RFC docs
add_keyword "/okm:root/Technical/RFC2616_HTTP_Specification.txt" "http"
add_keyword "/okm:root/Technical/RFC2616_HTTP_Specification.txt" "protocol"
add_keyword "/okm:root/Technical/RFC2616_HTTP_Specification.txt" "rfc"

# ── 5b. Fix X11 authentication for mouse events ──────────────────────────────
# GDM stores Xauthority at /run/user/1000/gdm/Xauthority, not ~/.Xauthority
# Without this fix, xdotool/pyautogui mouse events won't reach Firefox
GDM_AUTH="/run/user/1000/gdm/Xauthority"
if [ -f "$GDM_AUTH" ] && [ -s "$GDM_AUTH" ]; then
    cp "$GDM_AUTH" /home/ga/.Xauthority
    chown ga:ga /home/ga/.Xauthority
    echo "Fixed Xauthority from GDM session"
fi

# ── 6. Configure Firefox profile ─────────────────────────────────────────────
echo "=== Configuring Firefox ==="

# Try snap profile first (Ubuntu 22.04+), then classic profile
FIREFOX_PROFILE=""
SNAP_PROFILE=$(find /home/ga/snap/firefox -name "prefs.js" 2>/dev/null | head -1 | xargs dirname 2>/dev/null || echo "")

if [ -n "$SNAP_PROFILE" ]; then
    FIREFOX_PROFILE="$SNAP_PROFILE"
else
    # Create classic profile
    FIREFOX_PROFILE="/home/ga/.mozilla/firefox/default.profile"
    mkdir -p "$FIREFOX_PROFILE"

    # Create profiles.ini
    mkdir -p /home/ga/.mozilla/firefox
    cat > /home/ga/.mozilla/firefox/profiles.ini << 'EOF'
[Profile0]
Name=default
IsRelative=1
Path=default.profile
Default=1

[General]
StartWithLastProfile=1
EOF
fi

# Configure user preferences to suppress first-run dialogs and save-password prompts
cat > "$FIREFOX_PROFILE/user.js" << 'EOF'
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutConfig.showWarning", false);
user_pref("browser.tabs.warnOnClose", false);
user_pref("browser.startup.page", 1);
user_pref("browser.startup.homepage", "http://localhost:8080/OpenKM/login.jsp");
user_pref("browser.download.dir", "/home/ga/Downloads");
user_pref("browser.download.folderList", 2);
user_pref("browser.download.useDownloadDir", true);
user_pref("browser.helperApps.neverAsk.saveToDisk", "application/pdf,application/octet-stream,text/plain,application/zip");
user_pref("pdfjs.disabled", true);
user_pref("signon.rememberSignons", false);
user_pref("signon.autofillForms", false);
user_pref("signon.generation.enabled", false);
user_pref("signon.firefoxRelay.feature", "disabled");
user_pref("signon.management.page.breach-alerts.enabled", false);
user_pref("extensions.formautofill.creditCards.enabled", false);
user_pref("browser.formfill.enable", false);
EOF

chown -R ga:ga /home/ga/.mozilla 2>/dev/null || true
chown -R ga:ga "$FIREFOX_PROFILE" 2>/dev/null || true

# Also inject into snap profile if it exists (warm-up may have created it)
if [ -n "$SNAP_PROFILE" ] && [ "$SNAP_PROFILE" != "$FIREFOX_PROFILE" ]; then
    cp "$FIREFOX_PROFILE/user.js" "$SNAP_PROFILE/user.js" 2>/dev/null || true
    chown -R ga:ga "$SNAP_PROFILE" 2>/dev/null || true
fi

# ── 7. Ensure Downloads directory exists ──────────────────────────────────────
mkdir -p /home/ga/Downloads /home/ga/Documents
chown ga:ga /home/ga/Downloads /home/ga/Documents

# ── 8. Do NOT launch Firefox here — task setup handles it ─────────────────────
echo "=== OpenKM setup complete ==="
echo "URL: ${OPENKM_URL}/login.jsp"
echo "Admin credentials: ${OPENKM_USER} / ${OPENKM_PASS}"
docker ps | grep openkm || echo "WARNING: OpenKM container not running"
