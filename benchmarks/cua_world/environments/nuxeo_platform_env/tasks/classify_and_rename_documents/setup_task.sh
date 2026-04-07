#!/bin/bash
set -e
echo "=== Setting up task: classify_and_rename_documents@1 ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Ensure Nuxeo is ready
wait_for_nuxeo 180

# 1. Create 'Incoming Scans' workspace if not exists
echo "Creating workspace..."
WS_ID=$(create_doc_if_missing "/default-domain/workspaces" "Workspace" "Incoming-Scans" "Incoming Scans" "Digitized mail requiring classification")

# 2. Content for Document 1 (Invoice)
DOC1_CONTENT="<p><strong>INVOICE #INV-9982</strong></p><p><strong>Vendor:</strong> Global Logistics Inc</p><p><strong>Date:</strong> October 24, 2024</p><p><strong>To:</strong> Nuxeo Corp</p><hr/><p>Services Rendered: Air Freight - SFO to JFK (Ref: #SHIP-22)</p><p><strong>Total Due: $1,250.00</strong></p>"

# 3. Content for Document 2 (NDA)
DOC2_CONTENT="<p><strong>MUTUAL NON-DISCLOSURE AGREEMENT</strong></p><p>This Agreement is entered into by and between Nuxeo Corp and <strong>StartUp Dynamics</strong> (the 'Partner').</p><p>1. <strong>Confidential Information.</strong> The parties agree to maintain the confidentiality of all proprietary data...</p>"

# 4. Create Documents via REST API (Using 'Note' type for easy content rendering)
# We use curl directly to parse the UID reliably for verification
echo "Creating unclassified documents..."

# Create Doc 1
PAYLOAD1=$(cat <<EOFJSON
{
  "entity-type": "document",
  "type": "Note",
  "name": "Scan_2024_001",
  "properties": {
    "dc:title": "Scan_2024_001",
    "dc:description": "Scanned on 2024-10-24 08:30:00",
    "note:note": "$DOC1_CONTENT"
  }
}
EOFJSON
)
DOC1_RESP=$(nuxeo_api POST "/path/default-domain/workspaces/Incoming-Scans" "$PAYLOAD1")
DOC1_UID=$(echo "$DOC1_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uid',''))")
echo "$DOC1_UID" > /tmp/doc1_uid.txt
echo "Created Scan_2024_001 (UID: $DOC1_UID)"

# Create Doc 2
PAYLOAD2=$(cat <<EOFJSON
{
  "entity-type": "document",
  "type": "Note",
  "name": "Scan_2024_002",
  "properties": {
    "dc:title": "Scan_2024_002",
    "dc:description": "Scanned on 2024-10-24 08:31:15",
    "note:note": "$DOC2_CONTENT"
  }
}
EOFJSON
)
DOC2_RESP=$(nuxeo_api POST "/path/default-domain/workspaces/Incoming-Scans" "$PAYLOAD2")
DOC2_UID=$(echo "$DOC2_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uid',''))")
echo "$DOC2_UID" > /tmp/doc2_uid.txt
echo "Created Scan_2024_002 (UID: $DOC2_UID)"

# 5. Launch Firefox and navigate to the workspace
# Open Nuxeo UI to the specific workspace
open_nuxeo_url "$NUXEO_UI/#!/browse/default-domain/workspaces/Incoming-Scans" 10

# Perform login if necessary (handled by open_nuxeo_url/nuxeo_login logic if on login page)
# We check if we are on login page
sleep 5
PAGE_TITLE=$(ga_x "xdotool getactivewindow getwindowname" 2>/dev/null || echo "")
if echo "$PAGE_TITLE" | grep -qi "login"; then
    nuxeo_login
fi

# Ensure window is maximized
ga_x "wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz" 2>/dev/null || true

# Initial screenshot
echo "Capturing initial state..."
ga_x "scrot /tmp/task_initial.png" 2>/dev/null || true

echo "=== Task setup complete ==="