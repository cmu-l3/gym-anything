#!/bin/bash
# pre_task hook for regulatory_compliance_remediation task.
# CLEAN → SEED → LAUNCH ordering.
# No set -e (resilient to transient API failures).

echo "=== Setting up regulatory_compliance_remediation task ==="

source /workspace/scripts/task_utils.sh

wait_for_nuxeo 120

# =====================================================================
# CLEAN: Remove state from previous runs
# =====================================================================
echo "--- CLEAN phase ---"

# Remove tags from documents
for DOC_PATH in \
    "/default-domain/workspaces/Projects/Security-Policy-2024" \
    "/default-domain/workspaces/Projects/Data-Processing-Agreement"; do
    curl -s -u "$NUXEO_AUTH" -X DELETE \
        "$NUXEO_URL/api/v1/path${DOC_PATH}/@tagging/gdpr-compliant" > /dev/null 2>&1 || true
done

# Delete task documents (will recreate)
for DOC_PATH in \
    "/default-domain/workspaces/Projects/Security-Policy-2024" \
    "/default-domain/workspaces/Projects/Data-Processing-Agreement" \
    "/default-domain/workspaces/Projects/Compliance-Audit-Findings" \
    "/default-domain/workspaces/Projects/Remediation-Summary"; do
    if doc_exists "$DOC_PATH"; then
        D_UID=$(curl -s -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/path${DOC_PATH}" | \
            python3 -c "import sys,json; print(json.load(sys.stdin).get('uid',''))" 2>/dev/null || echo "")
        [ -n "$D_UID" ] && curl -s -u "$NUXEO_AUTH" -X DELETE "$NUXEO_URL/api/v1/id/${D_UID}?permanent=true" > /dev/null 2>&1 || true
    fi
done

# Delete sections (cascades to children/proxies)
for SECTION_NAME in General-Publications Compliance Legal; do
    SEC_PATH="/default-domain/sections/$SECTION_NAME"
    if doc_exists "$SEC_PATH"; then
        SEC_UID=$(curl -s -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/path${SEC_PATH}" | \
            python3 -c "import sys,json; print(json.load(sys.stdin).get('uid',''))" 2>/dev/null || echo "")
        [ -n "$SEC_UID" ] && curl -s -u "$NUXEO_AUTH" -X DELETE "$NUXEO_URL/api/v1/id/${SEC_UID}?permanent=true" > /dev/null 2>&1 || true
    fi
done

# Delete Q1-2025-Compliance-Bundle collection
COLL_SEARCH=$(curl -s -u "$NUXEO_AUTH" \
    "$NUXEO_URL/api/v1/search/lang/NXQL/execute?query=SELECT+*+FROM+Collection+WHERE+dc:title='Q1-2025-Compliance-Bundle'+AND+ecm:isTrashed=0+AND+ecm:isVersion=0" 2>/dev/null)
COLL_UID=$(echo "$COLL_SEARCH" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    entries = d.get('entries', [])
    if entries: print(entries[0].get('uid', ''))
except: pass
" 2>/dev/null || echo "")
if [ -n "$COLL_UID" ]; then
    curl -s -u "$NUXEO_AUTH" -X DELETE "$NUXEO_URL/api/v1/id/${COLL_UID}?permanent=true" > /dev/null 2>&1 || true
fi

# Delete user external-reviewer
curl -s -u "$NUXEO_AUTH" -X DELETE "$NUXEO_URL/api/v1/user/external-reviewer" 2>/dev/null || true

# Remove local ACLs that may have been set on Data-Processing-Agreement
curl -s -u "$NUXEO_AUTH" -H "Content-Type: application/json" \
    -X POST "$NUXEO_URL/api/v1/path/default-domain/workspaces/Projects/@op/Document.RemoveACL" \
    -d '{"params":{"acl":"local"}}' > /dev/null 2>&1 || true

# Clean staged files and stale outputs
rm -f /home/ga/nuxeo/data/DPA_v3_signed.pdf 2>/dev/null || true
rm -f /tmp/task_result.json /tmp/task_final.png /tmp/setup_state.json 2>/dev/null || true

sleep 2

echo "--- CLEAN complete ---"

# =====================================================================
# SEED: Create the pre-task state
# =====================================================================
echo "--- SEED phase ---"

# --- 1. Create section hierarchy ---
# /default-domain/sections/General-Publications         (wrong location for doc 1)
# /default-domain/sections/Compliance/Regulatory-Filings (correct target for doc 1)
# /default-domain/sections/Legal/Legal-Archive           (target for doc 2)

create_doc_if_missing "/default-domain/sections" "Section" "General-Publications" "General Publications" "General purpose publications section"
create_doc_if_missing "/default-domain/sections" "Section" "Compliance" "Compliance" "Compliance and regulatory filings"
create_doc_if_missing "/default-domain/sections/Compliance" "Section" "Regulatory-Filings" "Regulatory Filings" "Regulatory filings and audit submissions"
create_doc_if_missing "/default-domain/sections" "Section" "Legal" "Legal" "Legal department publications"
create_doc_if_missing "/default-domain/sections/Legal" "Section" "Legal-Archive" "Legal Archive" "Archived legal documents and agreements"
echo "  Sections created."

# --- 2. Create user external-reviewer ---
OC_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/user/external-reviewer")
if [ "$OC_CODE" != "200" ]; then
    nuxeo_api POST "/user/" '{"entity-type":"user","id":"external-reviewer","properties":{"username":"external-reviewer","firstName":"External","lastName":"Reviewer","email":"reviewer@external-vendor.com","password":"password123","groups":["members"]}}' > /dev/null 2>&1
fi
echo "  User external-reviewer created."

# --- 3. Create Security-Policy-2024 (File with PDF) ---
# Use the same upload_pdf_to_nuxeo pattern as setup_nuxeo.sh:
# MUST use Content-Type: application/octet-stream and X-File-Size header,
# otherwise Nuxeo 10.10 stores 0-byte blobs.
SEC_PDF="/tmp/security_policy_2024.pdf"
python3 -c "
pdf = b'%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n3 0 obj<</Type/Page/MediaBox[0 0 612 792]/Parent 2 0 R/Resources<<>>>>endobj\nxref\n0 4\n0000000000 65535 f \n0000000009 00000 n \n0000000058 00000 n \n0000000115 00000 n \ntrailer<</Size 4/Root 1 0 R>>\nstartxref\n210\n%%EOF'
with open('$SEC_PDF', 'wb') as f:
    f.write(pdf)
"

BATCH_ID=$(curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/" | \
    python3 -c "import sys,json; print(json.load(sys.stdin).get('batchId',''))" 2>/dev/null)
SEC_SIZE=$(stat -c%s "$SEC_PDF")
curl -s -u "$NUXEO_AUTH" \
    -X POST "$NUXEO_URL/api/v1/upload/$BATCH_ID/0" \
    -H "Content-Type: application/octet-stream" \
    -H "X-File-Name: Security-Policy-2024.pdf" \
    -H "X-File-Type: application/pdf" \
    -H "X-File-Size: $SEC_SIZE" \
    --data-binary @"$SEC_PDF" > /dev/null

SEC_PAYLOAD=$(cat <<SECEOF
{
  "entity-type": "document",
  "type": "File",
  "name": "Security-Policy-2024",
  "properties": {
    "dc:title": "Security Policy 2024",
    "dc:description": "Enterprise information security policy for fiscal year 2024",
    "file:content": {
      "upload-batch": "$BATCH_ID",
      "upload-fileId": "0"
    }
  }
}
SECEOF
)
nuxeo_api POST "/path/default-domain/workspaces/Projects/" "$SEC_PAYLOAD" > /dev/null 2>&1
echo "  Security-Policy-2024 created."

# --- 4. Create Data-Processing-Agreement (File with PDF) ---
DPA_PDF="/tmp/data_processing_agreement.pdf"
python3 -c "
pdf = b'%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n3 0 obj<</Type/Page/MediaBox[0 0 595 842]/Parent 2 0 R/Resources<<>>>>endobj\nxref\n0 4\n0000000000 65535 f \n0000000009 00000 n \n0000000058 00000 n \n0000000115 00000 n \ntrailer<</Size 4/Root 1 0 R>>\nstartxref\n210\n%%EOF'
with open('$DPA_PDF', 'wb') as f:
    f.write(pdf)
"

BATCH_ID2=$(curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/" | \
    python3 -c "import sys,json; print(json.load(sys.stdin).get('batchId',''))" 2>/dev/null)
DPA_SIZE=$(stat -c%s "$DPA_PDF")
curl -s -u "$NUXEO_AUTH" \
    -X POST "$NUXEO_URL/api/v1/upload/$BATCH_ID2/0" \
    -H "Content-Type: application/octet-stream" \
    -H "X-File-Name: Data-Processing-Agreement.pdf" \
    -H "X-File-Type: application/pdf" \
    -H "X-File-Size: $DPA_SIZE" \
    --data-binary @"$DPA_PDF" > /dev/null

DPA_PAYLOAD=$(cat <<DPAEOF
{
  "entity-type": "document",
  "type": "File",
  "name": "Data-Processing-Agreement",
  "properties": {
    "dc:title": "Data Processing Agreement",
    "dc:description": "Data processing agreement with third-party vendor for GDPR compliance",
    "file:content": {
      "upload-batch": "$BATCH_ID2",
      "upload-fileId": "0"
    }
  }
}
DPAEOF
)
nuxeo_api POST "/path/default-domain/workspaces/Projects/" "$DPA_PAYLOAD" > /dev/null 2>&1
echo "  Data-Processing-Agreement created."

# --- 5. Publish Security-Policy-2024 to General-Publications (the WRONG section) ---
# This is the core setup: the agent must discover this and unpublish it.
curl -s -u "$NUXEO_AUTH" -X POST \
    "$NUXEO_URL/api/v1/path/default-domain/workspaces/Projects/Security-Policy-2024/@op/Document.Publish" \
    -H "Content-Type: application/json" \
    -d '{"params":{"target":"/default-domain/sections/General-Publications","override":"true"}}' > /dev/null 2>&1

# Verify the publish worked
PUB_CHECK=$(curl -s -u "$NUXEO_AUTH" \
    "$NUXEO_URL/api/v1/search/lang/NXQL/execute?query=SELECT+*+FROM+Document+WHERE+ecm:path+STARTSWITH+'/default-domain/sections/General-Publications'+AND+ecm:primaryType+!=+'Section'" 2>/dev/null)
PUB_COUNT=$(echo "$PUB_CHECK" | python3 -c "import sys,json; print(json.load(sys.stdin).get('resultsCount',0))" 2>/dev/null || echo "0")
echo "  Security-Policy-2024 published to General-Publications (proxy count: $PUB_COUNT)."

# --- 6. Grant external-reviewer Read access on Data-Processing-Agreement ---
curl -s -u "$NUXEO_AUTH" -H "Content-Type: application/json" \
    -X POST "$NUXEO_URL/api/v1/path/default-domain/workspaces/Projects/Data-Processing-Agreement/@op/Document.AddACE" \
    -d '{"params":{"user":"external-reviewer","permission":"Read","grant":true,"acl":"local"}}' > /dev/null 2>&1
echo "  external-reviewer granted Read on Data-Processing-Agreement."

# --- 7. Stage replacement PDF (must have different content/digest from original) ---
mkdir -p /home/ga/nuxeo/data
DPA_V3="/home/ga/nuxeo/data/DPA_v3_signed.pdf"
python3 -c "
# Generate a PDF with different content so the file digest changes
pdf = b'%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n3 0 obj<</Type/Page/MediaBox[0 0 612 792]/Parent 2 0 R/Contents 4 0 R/Resources<<>>>>endobj\n4 0 obj<</Length 80>>stream\nBT /F1 12 Tf 72 700 Td (Data Processing Agreement v3.0 - Signed 2025-01-15) Tj ET\nendstream\nendobj\nxref\n0 5\n0000000000 65535 f \n0000000009 00000 n \n0000000058 00000 n \n0000000115 00000 n \n0000000206 00000 n \ntrailer<</Size 5/Root 1 0 R>>\nstartxref\n336\n%%EOF'
with open('$DPA_V3', 'wb') as f:
    f.write(pdf)
"
chown ga:ga "$DPA_V3"
chmod 644 "$DPA_V3"
echo "  Replacement PDF staged at $DPA_V3."

# --- 8. Record original DPA file digest for verification ---
DPA_DIGEST=$(curl -s -u "$NUXEO_AUTH" \
    "$NUXEO_URL/api/v1/path/default-domain/workspaces/Projects/Data-Processing-Agreement" \
    -H "X-NXproperties: *" | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('properties',{}).get('file:content',{}).get('digest',''))" 2>/dev/null || echo "")
TEMP_STATE=$(mktemp /tmp/state.XXXXXX.json)
echo "{\"original_dpa_digest\":\"$DPA_DIGEST\"}" > "$TEMP_STATE"
rm -f /tmp/setup_state.json 2>/dev/null || true
cp "$TEMP_STATE" /tmp/setup_state.json
chmod 666 /tmp/setup_state.json
rm -f "$TEMP_STATE"
echo "  Original DPA digest recorded: $DPA_DIGEST"

# --- 9. Create Compliance-Audit-Findings reference note ---
echo "Creating Compliance-Audit-Findings note..."
FINDINGS_PAYLOAD=$(cat <<'FINDINGS_JSON'
{
  "entity-type": "document",
  "type": "Note",
  "name": "Compliance-Audit-Findings",
  "properties": {
    "dc:title": "Compliance Audit Findings",
    "dc:description": "Regulatory compliance audit findings requiring immediate remediation — Q1 2025",
    "note:note": "<h2>Compliance Audit Findings &mdash; Q1 2025</h2><p><strong>Audit Date:</strong> 2025-01-10 &nbsp;|&nbsp; <strong>Auditor:</strong> Regulatory Compliance Division &nbsp;|&nbsp; <strong>Reference:</strong> CA-2025-0142</p><p>The following documents in the <em>Projects</em> workspace require immediate remediation:</p><hr/><h3>Finding 1: Incorrect Publication Location</h3><p><strong>Document:</strong> Security-Policy-2024</p><p><strong>Severity:</strong> High</p><p><strong>Issue:</strong> This document is currently published to the <strong>General Publications</strong> section. Per SOX compliance requirements, all security policy documents must reside in the <strong>Regulatory Filings</strong> section under <strong>Compliance</strong>.</p><p><strong>Required Remediation:</strong></p><ol><li>Unpublish the document from <code>General Publications</code></li><li>Update the <strong>Description</strong> field to <code>SOX-2025-Q1 — Enterprise information security policy for fiscal year 2024</code></li><li>Set the <strong>Coverage</strong> metadata to <code>north-america</code></li><li>Create a <strong>major version</strong> of the document</li><li>Publish the document to <code>Compliance &gt; Regulatory Filings</code></li></ol><hr/><h3>Finding 2: Outdated Data Processing Agreement</h3><p><strong>Document:</strong> Data-Processing-Agreement</p><p><strong>Severity:</strong> High</p><p><strong>Issue:</strong> The attached file is outdated (pre-GDPR Article 28 amendment). Additionally, the external vendor contract has been terminated and their reviewer access must be revoked.</p><p><strong>Required Remediation:</strong></p><ol><li>Replace the main attached file with the updated version at <code>/home/ga/nuxeo/data/DPA_v3_signed.pdf</code></li><li>Add the tag <code>gdpr-compliant</code> to the document</li><li>Create a <strong>major version</strong> of the document</li><li>Remove the <strong>external-reviewer</strong> user's Read permission from this document</li><li>Publish the document to <code>Legal &gt; Legal Archive</code></li></ol><hr/><h3>Post-Remediation Requirements</h3><p>After completing all document remediations:</p><ol><li>Create a Note titled <strong>Remediation-Summary</strong> in the Projects workspace listing each remediated document's title, new version number, and the section it was published to.</li><li>Create a collection named <strong>Q1-2025-Compliance-Bundle</strong> and add both remediated documents plus the Remediation-Summary note to it.</li></ol>"
  }
}
FINDINGS_JSON
)
nuxeo_api POST "/path/default-domain/workspaces/Projects/" "$FINDINGS_PAYLOAD" > /dev/null 2>&1
echo "  Compliance-Audit-Findings note created."

sleep 2

echo "--- SEED complete ---"

# =====================================================================
# LAUNCH: Open Firefox, log in, navigate to Projects workspace
# =====================================================================
echo "--- LAUNCH phase ---"

# Delete stale outputs before recording timestamp
rm -f /tmp/task_result.json /tmp/task_final.png 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

open_nuxeo_url "$NUXEO_URL/login.jsp" 8

sleep 3
PAGE_TITLE=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    xdotool getactivewindow getwindowname 2>/dev/null || echo "")
if ! echo "$PAGE_TITLE" | grep -q " - Nuxeo Platform"; then
    nuxeo_login
fi

sleep 2
navigate_to "$NUXEO_UI/#!/browse/default-domain/workspaces/Projects"
sleep 3

echo "--- LAUNCH complete ---"
echo "Task start state: Firefox on Projects workspace."
echo "Agent must read Compliance-Audit-Findings note and execute all remediation steps."
echo "=== regulatory_compliance_remediation setup complete ==="
