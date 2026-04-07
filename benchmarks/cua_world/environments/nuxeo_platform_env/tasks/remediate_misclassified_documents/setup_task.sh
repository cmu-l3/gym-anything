#!/bin/bash
# Pre-task setup for remediate_misclassified_documents

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up Remediate Misclassified Documents task ==="

# 1. Wait for Nuxeo to be ready
wait_for_nuxeo 180

# 2. Define Workspace Path
WS_PATH="/default-domain/workspaces/Incoming-Scans"

# 3. Clean up existing workspace if it exists
if doc_exists "$WS_PATH"; then
    echo "Cleaning up existing workspace..."
    curl -s -u "$NUXEO_AUTH" -X DELETE "$NUXEO_URL/api/v1/path$WS_PATH" >/dev/null
    sleep 2
fi

# 4. Create the 'Incoming Scans' workspace
echo "Creating Incoming Scans workspace..."
create_doc_if_missing "/default-domain/workspaces" "Workspace" "Incoming-Scans" "Incoming Scans" "Inbox for scanned mail processing"

# 5. Create Documents with Specific Metadata

# Document 1: Vendor Contract Alpha (INCORRECT: Invoice)
# We set dc:nature to 'invoice'
echo "Creating Vendor Contract Alpha (Misclassified)..."
PAYLOAD_1='{
  "entity-type": "document",
  "type": "File",
  "name": "Vendor-Contract-Alpha",
  "properties": {
    "dc:title": "Vendor Contract Alpha",
    "dc:description": "Scanned incoming document",
    "dc:nature": "invoice"
  }
}'
nuxeo_api POST "/path$WS_PATH/" "$PAYLOAD_1" >/dev/null

# Document 2: Service Level Agreement 2023 (INCORRECT: Invoice)
echo "Creating Service Level Agreement 2023 (Misclassified)..."
PAYLOAD_2='{
  "entity-type": "document",
  "type": "File",
  "name": "Service-Level-Agreement-2023",
  "properties": {
    "dc:title": "Service Level Agreement 2023",
    "dc:description": "SLA for IT support",
    "dc:nature": "invoice"
  }
}'
nuxeo_api POST "/path$WS_PATH/" "$PAYLOAD_2" >/dev/null

# Document 3: Office Supplies Invoice #9921 (CORRECT: Invoice - Control)
echo "Creating Office Supplies Invoice (Correct)..."
PAYLOAD_3='{
  "entity-type": "document",
  "type": "File",
  "name": "Office-Supplies-Invoice-9921",
  "properties": {
    "dc:title": "Office Supplies Invoice #9921",
    "dc:description": "Monthly stationary bill",
    "dc:nature": "invoice"
  }
}'
nuxeo_api POST "/path$WS_PATH/" "$PAYLOAD_3" >/dev/null

# Document 4: Consulting Agreement (CORRECT: Contract - Context)
echo "Creating Consulting Agreement (Correct)..."
PAYLOAD_4='{
  "entity-type": "document",
  "type": "File",
  "name": "Consulting-Agreement",
  "properties": {
    "dc:title": "Consulting Agreement",
    "dc:description": "Signed consulting terms",
    "dc:nature": "contract"
  }
}'
nuxeo_api POST "/path$WS_PATH/" "$PAYLOAD_4" >/dev/null

# 6. Record timestamps
date +%s > /tmp/task_start_time.txt
# Record initial modification time of the control document for anti-gaming check
CONTROL_MOD_TIME=$(nuxeo_api GET "/path$WS_PATH/Office-Supplies-Invoice-9921" | python3 -c "import sys, json; print(json.load(sys.stdin).get('properties', {}).get('dc:modified', ''))")
echo "$CONTROL_MOD_TIME" > /tmp/control_doc_initial_mod.txt

# 7. Prepare Browser
# Open Nuxeo, login, and navigate to the workspace
echo "Launching Firefox..."
open_nuxeo_url "$NUXEO_URL/login.jsp" 10

# Check if login is needed
PAGE_TITLE=$(ga_x "xdotool getactivewindow getwindowname" 2>/dev/null || echo "")
if ! echo "$PAGE_TITLE" | grep -q "Nuxeo"; then
    nuxeo_login
fi

# Navigate to the target workspace
navigate_to "$NUXEO_UI/#!/browse$WS_PATH"

# 8. Capture Initial State
echo "Capturing initial screenshot..."
sleep 2
ga_x "scrot /tmp/task_initial.png" 2>/dev/null || true

echo "=== Setup Complete ==="