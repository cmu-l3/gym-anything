#!/bin/bash
set -e
echo "=== Setting up classify_by_version_status task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

wait_for_nuxeo 120

# ---------------------------------------------------------------------------
# 1. Clean up and Create Workspace Structure
# ---------------------------------------------------------------------------
# Delete Holding-Area if exists to ensure clean slate
if doc_exists "/default-domain/workspaces/Holding-Area"; then
    echo "Cleaning up existing Holding-Area..."
    curl -s -u "$NUXEO_AUTH" -X DELETE "$NUXEO_URL/api/v1/path/default-domain/workspaces/Holding-Area" > /dev/null
    sleep 2
fi

# Create Holding-Area
echo "Creating Holding Area..."
create_doc_if_missing "/default-domain/workspaces" "Workspace" "Holding-Area" "Holding Area" "Incoming documents for audit"
HOLDING_UID=$(nuxeo_api GET "/path/default-domain/workspaces/Holding-Area" | python3 -c "import sys,json; print(json.load(sys.stdin)['uid'])")

# Create Subfolders
create_doc_if_missing "/default-domain/workspaces/Holding-Area" "Folder" "Released" "Released" "Approved documents (v1.0+)"
create_doc_if_missing "/default-domain/workspaces/Holding-Area" "Folder" "Drafts" "Drafts" "Work in progress (v0.x)"

# ---------------------------------------------------------------------------
# 2. Helper function to create documents with specific versions
# ---------------------------------------------------------------------------
create_versioned_doc() {
    local name="$1"
    local title="$2"
    local version_strategy="$3" # "minor" or "major"
    local iterations="$4"       # number of times to increment
    
    echo "Creating $name ($title)..."
    
    # Create the base document (File)
    local payload='{"entity-type":"document","type":"File","name":"'"$name"'","properties":{"dc:title":"'"$title"'","dc:description":"Document pending classification"}}'
    local uid
    uid=$(nuxeo_api POST "/path/default-domain/workspaces/Holding-Area/" "$payload" | python3 -c "import sys,json; print(json.load(sys.stdin)['uid'])")
    
    if [ -z "$uid" ] || [ "$uid" == "null" ]; then
        echo "Error creating document $name"
        return 1
    fi

    # Increment version
    for ((i=1; i<=iterations; i++)); do
        # CheckIn increments the version
        # Nuxeo API: POST /id/{id}/@op/Document.CheckIn
        # Params: version: "minor" or "major"
        local ver_param="minor"
        if [ "$version_strategy" == "major" ]; then ver_param="major"; fi
        
        curl -s -u "$NUXEO_AUTH" -H "Content-Type: application/json" \
            -X POST "$NUXEO_URL/api/v1/id/$uid/@op/Document.CheckIn" \
            -d '{"params":{"version":"'"$ver_param"'"}}' > /dev/null
            
        # Immediately CheckOut to keep it "Live" (so it appears in workspace normally, not as a frozen version)
        # But we want the Live doc to reflect the version we just set.
        # When you checkout, the version number on the live doc usually remains what it was at checkin 
        # until modified, or increments. 
        # Let's verify behavior: CheckIn (0.1) -> Live doc is 0.1+.
        
        curl -s -u "$NUXEO_AUTH" -H "Content-Type: application/json" \
            -X POST "$NUXEO_URL/api/v1/id/$uid/@op/Document.CheckOut" > /dev/null
    done
}

# ---------------------------------------------------------------------------
# 3. Create Documents
# ---------------------------------------------------------------------------

# Product-Specs: Target ~0.2 (Draft)
# Create (0.0) -> CheckIn Minor (0.1) -> CheckOut -> CheckIn Minor (0.2) -> CheckOut
create_versioned_doc "Product-Specs" "Product Specifications" "minor" 2

# User-Guide: Target ~1.0 (Released)
# Create (0.0) -> CheckIn Major (1.0) -> CheckOut
create_versioned_doc "User-Guide" "User Guide" "major" 1

# Marketing-Flyer: Target ~2.0 (Released)
# Create -> Major (1.0) -> Major (2.0)
create_versioned_doc "Marketing-Flyer" "Marketing Flyer 2024" "major" 2

# Internal-Memo: Target ~0.5 (Draft)
create_versioned_doc "Internal-Memo" "Internal Team Memo" "minor" 5

sleep 2

# ---------------------------------------------------------------------------
# 4. Browser Setup
# ---------------------------------------------------------------------------
# Open Firefox, log in, navigate to Holding Area
open_nuxeo_url "$NUXEO_URL/login.jsp" 8

sleep 3
PAGE_TITLE=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    xdotool getactivewindow getwindowname 2>/dev/null || echo "")
if ! echo "$PAGE_TITLE" | grep -q " - Nuxeo Platform"; then
    nuxeo_login
fi

sleep 2
navigate_to "$NUXEO_UI/#!/browse/default-domain/workspaces/Holding-Area"
sleep 4

# Maximize (ensure)
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="