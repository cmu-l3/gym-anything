#!/bin/bash
# Nuxeo Platform Setup Script (post_start hook)
# Starts Nuxeo via Docker Compose, waits for it to be ready,
# creates initial data via the REST API, configures Firefox, and launches the browser.
# NOTE: No 'set -e' — failures in optional steps should not abort the setup.

echo "=== Setting up Nuxeo Platform ==="

NUXEO_URL="http://localhost:8080/nuxeo"
NUXEO_AUTH="Administrator:Administrator"
NUXEO_WORK_DIR="/home/ga/nuxeo"

# ---------------------------------------------------------------------------
# Functions
# ---------------------------------------------------------------------------

wait_for_nuxeo() {
    local timeout=${1:-300}
    local elapsed=0
    echo "Waiting for Nuxeo to be ready (may take 3–5 minutes on first boot)..."
    while [ $elapsed -lt $timeout ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$NUXEO_URL/login.jsp" 2>/dev/null)
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "303" ]; then
            echo "Nuxeo is ready (HTTP $HTTP_CODE) after ${elapsed}s"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        [ $((elapsed % 60)) -eq 0 ] && echo "  Still waiting... ${elapsed}s (HTTP $HTTP_CODE)"
    done
    echo "WARNING: Nuxeo did not become ready within ${timeout}s — check docker logs"
    docker logs nuxeo-app 2>/dev/null | tail -30 || true
    return 1
}

nuxeo_api() {
    local method="$1"
    local path="$2"
    local data="${3:-}"
    if [ -n "$data" ]; then
        curl -s -u "$NUXEO_AUTH" \
            -H "Content-Type: application/json" \
            -H "X-NXproperties: *" \
            -X "$method" \
            "$NUXEO_URL/api/v1$path" \
            -d "$data"
    else
        curl -s -u "$NUXEO_AUTH" \
            -H "Content-Type: application/json" \
            -H "X-NXproperties: *" \
            -X "$method" \
            "$NUXEO_URL/api/v1$path"
    fi
}

doc_exists() {
    local path="$1"
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" -u "$NUXEO_AUTH" \
        "$NUXEO_URL/api/v1/path$path")
    [ "$code" = "200" ]
}

create_doc() {
    local parent="$1"
    local type="$2"
    local name="$3"
    local title="$4"
    local desc="${5:-}"
    local payload
    payload=$(printf '{"entity-type":"document","type":"%s","name":"%s","properties":{"dc:title":"%s","dc:description":"%s"}}' \
        "$type" "$name" "$title" "$desc")
    nuxeo_api POST "/path$parent/" "$payload"
}

# ---------------------------------------------------------------------------
# Step 1: Copy docker-compose.yml to working directory and authenticate
# ---------------------------------------------------------------------------
echo "Setting up Docker Compose workspace..."
mkdir -p "$NUXEO_WORK_DIR"
cp /workspace/config/docker-compose.yml "$NUXEO_WORK_DIR/"
chown -R ga:ga "$NUXEO_WORK_DIR"

# ---------------------------------------------------------------------------
# Step 2: Docker Hub authentication (avoid rate limits)
# ---------------------------------------------------------------------------
if [ -f /workspace/config/.dockerhub_credentials ]; then
    # shellcheck source=/dev/null
    source /workspace/config/.dockerhub_credentials
    echo "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USERNAME" --password-stdin 2>/dev/null || true
    echo "Docker Hub authentication attempted."
fi

# ---------------------------------------------------------------------------
# Step 3: Start containers
# ---------------------------------------------------------------------------
echo "Pulling Docker images..."
cd "$NUXEO_WORK_DIR"
docker-compose pull 2>&1 | tail -5 || true

echo "Starting Nuxeo Docker containers..."
docker-compose up -d || true

echo "Container status:"
docker-compose ps || true

# ---------------------------------------------------------------------------
# Step 4: Wait for Nuxeo to be ready (first boot installs nuxeo-web-ui)
# ---------------------------------------------------------------------------
wait_for_nuxeo 480 || true

# Extra wait to allow Nuxeo to fully initialise its database schema
sleep 20
echo "Nuxeo is running."

# ---------------------------------------------------------------------------
# Step 5: Set up data files from workspace mount
# ---------------------------------------------------------------------------
echo "Preparing document files..."
DATA_DIR="/home/ga/nuxeo/data"
mkdir -p "$DATA_DIR"

# Copy corporate document PDFs from workspace data mount
# Mounted from examples/nuxeo_platform_env/data/
if [ -f "/workspace/data/annual_report_2023.pdf" ]; then
    cp /workspace/data/annual_report_2023.pdf "$DATA_DIR/Annual_Report_2023.pdf"
    echo "  Copied real annual_report_2023.pdf ($(du -sh "$DATA_DIR/Annual_Report_2023.pdf" | cut -f1))"
fi
if [ -f "/workspace/data/project_proposal.pdf" ]; then
    cp /workspace/data/project_proposal.pdf "$DATA_DIR/Project_Proposal.pdf"
    echo "  Copied real project_proposal.pdf ($(du -sh "$DATA_DIR/Project_Proposal.pdf" | cut -f1))"
fi
if [ -f "/workspace/data/quarterly_report.pdf" ]; then
    cp /workspace/data/quarterly_report.pdf "$DATA_DIR/Contract_Template.pdf"
    echo "  Copied real quarterly_report.pdf as Contract_Template.pdf ($(du -sh "$DATA_DIR/Contract_Template.pdf" | cut -f1))"
fi
if [ -f "/workspace/data/q3_status_report.pdf" ]; then
    cp /workspace/data/q3_status_report.pdf "$DATA_DIR/Q3_Status_Report.pdf"
    echo "  Copied real q3_status_report.pdf ($(du -sh "$DATA_DIR/Q3_Status_Report.pdf" | cut -f1))"
fi

chown -R ga:ga "$DATA_DIR"
echo "Documents ready in $DATA_DIR: $(ls "$DATA_DIR" | tr '\n' ' ')"

# ---------------------------------------------------------------------------
# Step 6: Create initial workspace structure via REST API
# ---------------------------------------------------------------------------
echo "Creating initial workspace structure via Nuxeo REST API..."

if ! doc_exists "/default-domain/workspaces/Projects"; then
    result=$(create_doc "/default-domain/workspaces" "Workspace" "Projects" \
        "Projects" "Active project documents and deliverables")
    echo "Created Projects workspace: $(echo "$result" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('uid','?'))" 2>/dev/null)"
else
    echo "Projects workspace already exists."
fi

if ! doc_exists "/default-domain/workspaces/Templates"; then
    create_doc "/default-domain/workspaces" "Workspace" "Templates" \
        "Templates" "Document templates and standard forms" > /dev/null
    echo "Created Templates workspace."
fi

sleep 5

# ---------------------------------------------------------------------------
# Step 7: Upload PDF documents to Projects workspace
# ---------------------------------------------------------------------------
echo "Uploading documents to Projects workspace..."

upload_pdf_to_nuxeo() {
    local local_path="$1"
    local doc_name="$2"
    local doc_title="$3"
    local parent_path="$4"

    local filename
    filename=$(basename "$local_path")
    BATCH_RESPONSE=$(curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/")
    BATCH_ID=$(echo "$BATCH_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('batchId',''))" 2>/dev/null)
    [ -z "$BATCH_ID" ] && { echo "  WARNING: No batch ID for $doc_name"; return 1; }

    local filesize
    filesize=$(stat -c%s "$local_path")
    # MUST use Content-Type: application/octet-stream — curl's default
    # application/x-www-form-urlencoded causes Nuxeo to store 0-byte blobs.
    curl -s -u "$NUXEO_AUTH" \
        -X POST "$NUXEO_URL/api/v1/upload/$BATCH_ID/0" \
        -H "Content-Type: application/octet-stream" \
        -H "X-File-Name: $filename" \
        -H "X-File-Type: application/pdf" \
        -H "X-File-Size: $filesize" \
        --data-binary @"$local_path" > /dev/null

    local payload
    payload=$(cat <<EOFJSON
{
  "entity-type": "document",
  "type": "File",
  "name": "$doc_name",
  "properties": {
    "dc:title": "$doc_title",
    "dc:description": "Uploaded document",
    "file:content": {
      "upload-batch": "$BATCH_ID",
      "upload-fileId": "0"
    }
  }
}
EOFJSON
)
    local uid
    uid=$(nuxeo_api POST "/path$parent_path/" "$payload" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uid','?'))" 2>/dev/null)
    echo "  Uploaded '$doc_title' (uid=$uid)"
}

doc_exists "/default-domain/workspaces/Projects/Annual-Report-2023" || \
    upload_pdf_to_nuxeo "$DATA_DIR/Annual_Report_2023.pdf" \
        "Annual-Report-2023" "Annual Report 2023" \
        "/default-domain/workspaces/Projects"

doc_exists "/default-domain/workspaces/Projects/Project-Proposal" || \
    upload_pdf_to_nuxeo "$DATA_DIR/Project_Proposal.pdf" \
        "Project-Proposal" "Project Proposal" \
        "/default-domain/workspaces/Projects"

doc_exists "/default-domain/workspaces/Templates/Contract-Template" || \
    upload_pdf_to_nuxeo "$DATA_DIR/Contract_Template.pdf" \
        "Contract-Template" "Contract Template" \
        "/default-domain/workspaces/Templates"

# ---------------------------------------------------------------------------
# Step 8: Create a sample Note document in Projects
# ---------------------------------------------------------------------------
echo "Creating sample Note document..."
if ! doc_exists "/default-domain/workspaces/Projects/Q3-Status-Report"; then
    NOTE_PAYLOAD='{"entity-type":"document","type":"Note","name":"Q3-Status-Report","properties":{"dc:title":"Q3 Status Report","dc:description":"Quarterly status report for Q3 2023","note:note":"<p>This is the Q3 2023 status report. Key highlights: Phase 1 complete, budget on track.</p>"}}'
    nuxeo_api POST "/path/default-domain/workspaces/Projects/" "$NOTE_PAYLOAD" > /dev/null
    echo "Created Q3 Status Report note."
fi

# ---------------------------------------------------------------------------
# Step 9: Create test user 'jsmith'
# ---------------------------------------------------------------------------
echo "Creating test user jsmith..."
USER_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/user/jsmith")
if [ "$USER_CODE" != "200" ]; then
    USER_PAYLOAD='{"entity-type":"user","id":"jsmith","properties":{"username":"jsmith","firstName":"John","lastName":"Smith","email":"jsmith@acme.com","password":"password123","groups":["members"]}}'
    nuxeo_api POST "/user/" "$USER_PAYLOAD" > /dev/null
    echo "Created user jsmith."
fi

# ---------------------------------------------------------------------------
# Step 10: Desktop shortcut
# ---------------------------------------------------------------------------
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/Nuxeo.desktop << DESKTOPEOF
[Desktop Entry]
Name=Nuxeo Platform
Comment=Enterprise Content Management
Exec=firefox http://localhost:8080/nuxeo/ui/
Icon=firefox
StartupNotify=true
Terminal=false
Type=Application
Categories=Office;Business;
DESKTOPEOF
chown ga:ga /home/ga/Desktop/Nuxeo.desktop
chmod +x /home/ga/Desktop/Nuxeo.desktop

# ---------------------------------------------------------------------------
# Step 11: Create utility script for REST API queries
# ---------------------------------------------------------------------------
cat > /usr/local/bin/nuxeo-api << 'APIEOF'
#!/bin/bash
# Query Nuxeo REST API
# Usage: nuxeo-api GET /path/to/doc
#        nuxeo-api POST /path -d '{"json":"data"}'
METHOD="${1:-GET}"
PATH_="${2:-/}"
DATA="${3:-}"
AUTH="Administrator:Administrator"
URL="http://localhost:8080/nuxeo/api/v1"
if [ -n "$DATA" ]; then
    curl -s -u "$AUTH" -H "Content-Type: application/json" -H "X-NXproperties: *" \
        -X "$METHOD" "$URL$PATH_" -d "$DATA"
else
    curl -s -u "$AUTH" -H "Content-Type: application/json" -H "X-NXproperties: *" \
        -X "$METHOD" "$URL$PATH_"
fi
APIEOF
chmod +x /usr/local/bin/nuxeo-api

# ---------------------------------------------------------------------------
# Step 12: Launch Firefox with Nuxeo Web UI and log in
# ---------------------------------------------------------------------------
echo "Launching Firefox with Nuxeo Web UI..."

pkill -9 -f firefox 2>/dev/null || true
sleep 2

# Snap Firefox requires DBUS_SESSION_BUS_ADDRESS to launch from root via sudo
sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    DBUS_SESSION_BUS_ADDRESS='unix:path=/run/user/1000/bus' \
    firefox 'http://localhost:8080/nuxeo/login.jsp' > /tmp/firefox_nuxeo.log 2>&1 &"

# Wait for Firefox window
FIREFOX_READY=false
for i in $(seq 1 30); do
    if DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | grep -qi "nuxeo\|firefox\|mozilla"; then
        FIREFOX_READY=true
        echo "Firefox window detected after ${i}s"
        break
    fi
    sleep 1
done

if [ "$FIREFOX_READY" = true ]; then
    sleep 3
    # Maximize Firefox
    WID=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | \
        grep -i "firefox\|mozilla\|nuxeo" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r :ACTIVE: \
            -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi

    # Wait for login page to load
    sleep 5

    # Dismiss any dialog
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Escape 2>/dev/null || true
    sleep 0.5

    # Click dark background area to focus page (not address bar)
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool mousemove --sync 960 200 click 1 2>/dev/null || true
    sleep 0.5

    # Tab to username field (Nuxeo login form: first focusable element is language select,
    # second is username input)
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Tab Tab 2>/dev/null || true
    sleep 0.3
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool type --clearmodifiers \
        --delay 50 "Administrator" 2>/dev/null || true
    sleep 0.3
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Tab 2>/dev/null || true
    sleep 0.3
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool type --clearmodifiers \
        --delay 50 "Administrator" 2>/dev/null || true
    sleep 0.3
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Return 2>/dev/null || true
    sleep 5
    echo "Login attempted."
fi

echo ""
echo "=== Nuxeo Platform Setup Complete ==="
echo ""
echo "Nuxeo URL:      http://localhost:8080/nuxeo/ui/"
echo "Admin login:    Administrator / Administrator"
echo "User 'jsmith':  password123"
echo ""
echo "Container status:"
docker-compose -f "$NUXEO_WORK_DIR/docker-compose.yml" ps 2>/dev/null || true
echo ""
echo "Data loaded:"
echo "  Projects/Annual-Report-2023 (PDF)"
echo "  Projects/Project-Proposal (PDF)"
echo "  Projects/Q3-Status-Report (Note)"
echo "  Templates/Contract-Template (PDF)"
echo ""
