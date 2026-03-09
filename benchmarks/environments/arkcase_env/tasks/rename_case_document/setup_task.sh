#!/bin/bash
set -e
echo "=== Setting up rename_case_document task ==="

source /workspace/scripts/task_utils.sh

# Ensure ArkCase is accessible
ensure_portforward
wait_for_arkcase

# Create a python script to handle API interactions (Case creation + Doc Upload)
cat > /tmp/setup_data.py << 'PYEOF'
import requests
import json
import sys
import os
import time

BASE_URL = "https://localhost:9443/arkcase/api/v1"
AUTH = ("arkcase-admin@dev.arkcase.com", "ArkCase1234!")
VERIFY_SSL = False

def create_case():
    url = f"{BASE_URL}/plugin/complaint"
    payload = {
        "caseType": "GENERAL",
        "complaintTitle": "Complaint - Incorrect Document Metadata Test",
        "details": "This case contains a document with incorrect metadata that needs to be fixed by the agent.",
        "priority": "Medium",
        "status": "ACTIVE"
    }
    headers = {"Content-Type": "application/json", "Accept": "application/json"}
    
    print(f"Creating case at {url}...")
    try:
        resp = requests.post(url, json=payload, auth=AUTH, verify=VERIFY_SSL, timeout=20)
        resp.raise_for_status()
        data = resp.json()
        # Handle various ID fields ArkCase might return
        case_id = data.get("complaintId") or data.get("id") or data.get("caseId")
        print(f"Case created: {case_id}")
        return case_id
    except Exception as e:
        print(f"Failed to create case: {e}")
        if 'resp' in locals(): print(resp.text)
        return None

def upload_document(case_id):
    # Prepare a dummy PDF
    with open("/tmp/scan_20240315.pdf", "wb") as f:
        f.write(b"%PDF-1.4\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n3 0 obj\n<< /Type /Page /Parent 2 0 R /Resources << /Font << /F1 4 0 R >> >> /MediaBox [0 0 612 792] /Contents 5 0 R >>\nendobj\n4 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\n5 0 obj\n<< /Length 44 >>\nstream\nBT /F1 24 Tf 100 700 Td (Real Government Document Content) Tj ET\nendstream\nendobj\nxref\n0 6\n0000000000 65535 f \n0000000010 00000 n \n0000000060 00000 n \n0000000157 00000 n \n0000000305 00000 n \n0000000392 00000 n \ntrailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n487\n%%EOF")

    # Upload endpoint - often plugin specific or core DMS
    # Trying generic add document to container endpoint
    url = f"{BASE_URL}/dms/container/{case_id}/document"
    
    # Metadata for the upload
    metadata = {
        "documentName": "scan_20240315",
        "title": "scan_20240315",
        "documentType": "Other",
        "description": "Initial scan upload"
    }
    
    files = {
        'file': ('scan_20240315.pdf', open('/tmp/scan_20240315.pdf', 'rb'), 'application/pdf'),
        'metadata': (None, json.dumps(metadata), 'application/json')
    }
    
    print(f"Uploading document to {case_id}...")
    try:
        # Note: ArkCase API upload signatures vary. Trying common multipart pattern.
        # If /dms/container/... fails, we might try /plugin/complaint/{id}/document
        resp = requests.post(url, files=files, auth=AUTH, verify=VERIFY_SSL)
        
        if resp.status_code == 404:
            # Fallback endpoint
            url = f"{BASE_URL}/plugin/complaint/{case_id}/document"
            print(f"Retrying at {url}...")
            files['file'][1].seek(0)
            resp = requests.post(url, files=files, auth=AUTH, verify=VERIFY_SSL)
            
        resp.raise_for_status()
        doc_data = resp.json()
        doc_id = doc_data.get("documentId") or doc_data.get("id") or doc_data.get("objectId")
        print(f"Document uploaded: {doc_id}")
        return doc_id
    except Exception as e:
        print(f"Failed to upload document: {e}")
        if 'resp' in locals(): print(resp.text)
        return None

case_id = create_case()
if case_id:
    doc_id = upload_document(case_id)
    if doc_id:
        with open("/tmp/task_context.json", "w") as f:
            json.dump({"caseId": case_id, "documentId": doc_id}, f)
        print("Setup successful")
    else:
        print("Document upload failed")
        sys.exit(1)
else:
    print("Case creation failed")
    sys.exit(1)
PYEOF

# Execute the python setup script
echo "Executing data setup..."
python3 /tmp/setup_data.py
if [ $? -ne 0 ]; then
    echo "ERROR: Data setup failed. Falling back to browser-only start (Agent might struggle)."
fi

# Get Case ID for URL
CASE_ID=$(jq -r '.caseId' /tmp/task_context.json 2>/dev/null || echo "")

# Prepare Browser
# Kill any existing Firefox and clean lock files
pkill -9 -f firefox 2>/dev/null || true
sleep 2
find /home/ga -name ".parentlock" -delete 2>/dev/null || true
find /home/ga -name "parent.lock" -delete 2>/dev/null || true

# Launch Firefox
# If we have a case ID, go there. Otherwise login page.
TARGET_URL="https://localhost:9443/arkcase/login"
if [ -n "$CASE_ID" ]; then
    TARGET_URL="https://localhost:9443/arkcase/#!/complaint/${CASE_ID}"
fi

echo "Launching Firefox to $TARGET_URL"
SNAP_PROFILE=$(find /home/ga/snap/firefox -name "prefs.js" 2>/dev/null | head -1 | xargs dirname 2>/dev/null || echo "")
if [ -n "$SNAP_PROFILE" ]; then
    su - ga -c "DISPLAY=:1 firefox -profile '$SNAP_PROFILE' '$TARGET_URL' &>/dev/null &" &
else
    su - ga -c "DISPLAY=:1 firefox '$TARGET_URL' &>/dev/null &" &
fi
sleep 20

# Handle Login if redirected (Auto-login)
focus_firefox
maximize_firefox
sleep 2

# Check if we are on login page (by checking if URL contains 'login' or looking for login fields)
# We perform the login sequence blindly just in case, or check for the login button
echo "Performing auto-login sequence..."
# Username
DISPLAY=:1 xdotool mousemove 994 312 click 1
sleep 0.5
DISPLAY=:1 xdotool type --clearmodifiers --delay 20 'arkcase-admin@dev.arkcase.com'
# Password
DISPLAY=:1 xdotool mousemove 994 368 click 1
sleep 0.5
DISPLAY=:1 xdotool type --clearmodifiers --delay 20 'ArkCase1234!'
# Login Button
DISPLAY=:1 xdotool mousemove 994 438 click 1
sleep 15

# Ensure we are at the target case if we logged in
if [ -n "$CASE_ID" ]; then
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type --clearmodifiers "$TARGET_URL"
    DISPLAY=:1 xdotool key Return
    sleep 8
fi

# Initial Screenshot
take_screenshot /tmp/task_initial.png

# Record start time
date +%s > /tmp/task_start_time.txt

echo "=== Setup complete ==="
echo "Case created: $CASE_ID"
echo "Instructions: Rename document 'scan_20240315' to 'Response_Letter_March2025' and change type to 'Correspondence'."