#!/bin/bash
# Setup for add_documents_to_favorites task
# Ensures target documents exist and are NOT currently in Favorites.

echo "=== Setting up add_documents_to_favorites task ==="

source /workspace/scripts/task_utils.sh

# Wait for Nuxeo to be responsive
wait_for_nuxeo 180

echo "Ensuring target documents exist..."

# 1. Ensure Annual Report exists
if ! doc_exists "/default-domain/workspaces/Projects/Annual-Report-2023"; then
    echo "Creating missing Annual Report..."
    # Ensure parent exists
    create_doc_if_missing "/default-domain/workspaces" "Workspace" "Projects" "Projects"
    
    # Upload file
    PDF_SOURCE="/workspace/data/annual_report_2023.pdf"
    [ ! -f "$PDF_SOURCE" ] && PDF_SOURCE="/home/ga/nuxeo/data/Annual_Report_2023.pdf"
    
    # If no real file, create dummy
    if [ ! -f "$PDF_SOURCE" ]; then
        echo "Creating dummy PDF..."
        echo "Dummy Content" > /tmp/dummy.pdf
        PDF_SOURCE="/tmp/dummy.pdf"
    fi
    
    # Upload logic (simplified for setup script using curl)
    BATCH_ID=$(curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/" | python3 -c "import sys,json; print(json.load(sys.stdin).get('batchId',''))")
    curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/$BATCH_ID/0" -H "X-File-Name: report.pdf" --data-binary @"$PDF_SOURCE" >/dev/null
    
    PAYLOAD="{\"entity-type\":\"document\",\"type\":\"File\",\"name\":\"Annual-Report-2023\",\"properties\":{\"dc:title\":\"Annual Report 2023\",\"file:content\":{\"upload-batch\":\"$BATCH_ID\",\"upload-fileId\":\"0\"}}}"
    nuxeo_api POST "/path/default-domain/workspaces/Projects/" "$PAYLOAD" >/dev/null
fi

# 2. Ensure Contract Template exists
if ! doc_exists "/default-domain/workspaces/Templates/Contract-Template"; then
    echo "Creating missing Contract Template..."
    create_doc_if_missing "/default-domain/workspaces" "Workspace" "Templates" "Templates"
    
    # Upload logic
    BATCH_ID=$(curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/" | python3 -c "import sys,json; print(json.load(sys.stdin).get('batchId',''))")
    # Reuse dummy or existing
    PDF_SOURCE="/workspace/data/quarterly_report.pdf" # Fallback
    [ ! -f "$PDF_SOURCE" ] && echo "Dummy" > /tmp/dummy.pdf && PDF_SOURCE="/tmp/dummy.pdf"
    
    curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/$BATCH_ID/0" -H "X-File-Name: contract.pdf" --data-binary @"$PDF_SOURCE" >/dev/null
    
    PAYLOAD="{\"entity-type\":\"document\",\"type\":\"File\",\"name\":\"Contract-Template\",\"properties\":{\"dc:title\":\"Contract Template\",\"file:content\":{\"upload-batch\":\"$BATCH_ID\",\"upload-fileId\":\"0\"}}}"
    nuxeo_api POST "/path/default-domain/workspaces/Templates/" "$PAYLOAD" >/dev/null
fi

echo "Clearing 'Favorites' status for target documents..."
# We remove the documents from ALL collections to be safe, or specifically Favorites if we could identify it easily.
# Easiest way: Update document to set collectionMember:collectionIds to empty list [].
# Note: This removes them from ALL collections.

nuxeo_api PUT "/path/default-domain/workspaces/Projects/Annual-Report-2023" \
    '{"entity-type":"document","properties":{"collectionMember:collectionIds":[]}}' >/dev/null

nuxeo_api PUT "/path/default-domain/workspaces/Templates/Contract-Template" \
    '{"entity-type":"document","properties":{"collectionMember:collectionIds":[]}}' >/dev/null

# Record start time
date +%s > /tmp/task_start_time.txt

# Launch Browser
echo "Launching Firefox..."
open_nuxeo_url "$NUXEO_URL/login.jsp" 10

# Login
nuxeo_login

# Navigate to Dashboard to start
navigate_to "$NUXEO_UI/#!/home"

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="