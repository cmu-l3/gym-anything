#!/bin/bash
# pre_task hook for compliance_metadata_remediation task.
# CLEAN → SEED → LAUNCH ordering (Lesson 169).
# No set -e (Lesson 174).

echo "=== Setting up compliance_metadata_remediation task ==="

source /workspace/scripts/task_utils.sh

wait_for_nuxeo 120

# =====================================================================
# CLEAN: Remove any state from previous runs
# =====================================================================
echo "Cleaning previous task state..."

# Remove compliance-reviewed tags from all known documents
for DOC_PATH in \
    "/default-domain/workspaces/Projects/Annual-Report-2023" \
    "/default-domain/workspaces/Projects/Project-Proposal" \
    "/default-domain/workspaces/Templates/Contract-Template" \
    "/default-domain/workspaces/Projects/Q3-Status-Report"; do
    curl -s -u "$NUXEO_AUTH" -X DELETE \
        "$NUXEO_URL/api/v1/path${DOC_PATH}/@tagging/compliance-reviewed" > /dev/null 2>&1 || true
done

# Delete compliance review comments on documents
for DOC_PATH in \
    "/default-domain/workspaces/Projects/Annual-Report-2023" \
    "/default-domain/workspaces/Projects/Project-Proposal" \
    "/default-domain/workspaces/Templates/Contract-Template" \
    "/default-domain/workspaces/Projects/Q3-Status-Report"; do
    DOC_UID=$(curl -s -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/path${DOC_PATH}" 2>/dev/null | \
        python3 -c "import sys,json; print(json.load(sys.stdin).get('uid',''))" 2>/dev/null || echo "")
    if [ -n "$DOC_UID" ]; then
        COMMENTS=$(curl -s -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/id/${DOC_UID}/@comment" 2>/dev/null)
        COMMENT_IDS=$(echo "$COMMENTS" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    entries = data.get('entries', [])
    for e in entries:
        cid = e.get('id', '')
        if cid:
            print(cid)
except: pass
" 2>/dev/null || true)
        for CID in $COMMENT_IDS; do
            curl -s -u "$NUXEO_AUTH" -X DELETE "$NUXEO_URL/api/v1/id/${CID}" > /dev/null 2>&1 || true
        done
    fi
done

# Delete Q4 2025 Compliance Audit collection
COLL_SEARCH=$(curl -s -u "$NUXEO_AUTH" \
    "$NUXEO_URL/api/v1/search/lang/NXQL/execute?query=SELECT+*+FROM+Collection+WHERE+dc:title='Q4+2025+Compliance+Audit'+AND+ecm:isTrashed=0+AND+ecm:isVersion=0" 2>/dev/null)
COLL_UID=$(echo "$COLL_SEARCH" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    entries = d.get('entries', [])
    if entries:
        print(entries[0].get('uid', ''))
except: pass
" 2>/dev/null || echo "")
if [ -n "$COLL_UID" ]; then
    curl -s -u "$NUXEO_AUTH" -X DELETE "$NUXEO_URL/api/v1/id/${COLL_UID}?permanent=true" > /dev/null 2>&1 || true
    echo "Deleted previous Q4 2025 Compliance Audit collection."
fi

# Delete existing compliance standards note (will recreate)
if doc_exists "/default-domain/workspaces/Projects/Document-Metadata-Compliance-Standards"; then
    STD_UID=$(curl -s -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/path/default-domain/workspaces/Projects/Document-Metadata-Compliance-Standards" | \
        python3 -c "import sys,json; print(json.load(sys.stdin).get('uid',''))" 2>/dev/null || echo "")
    [ -n "$STD_UID" ] && curl -s -u "$NUXEO_AUTH" -X DELETE "$NUXEO_URL/api/v1/id/${STD_UID}?permanent=true" > /dev/null 2>&1 || true
fi

sleep 2

# =====================================================================
# SEED: Set up the non-compliant state + companion reference document
# =====================================================================
echo "Seeding non-compliant document metadata..."

# Set Project Proposal description to clearly non-compliant placeholder
curl -s -u "$NUXEO_AUTH" -H "Content-Type: application/json" \
    -X PUT "$NUXEO_URL/api/v1/path/default-domain/workspaces/Projects/Project-Proposal" \
    -d '{"entity-type":"document","properties":{"dc:description":"placeholder text - needs update","dc:coverage":"","dc:subjects":[]}}' > /dev/null 2>&1

# Clear Annual Report 2023 compliance-critical metadata
curl -s -u "$NUXEO_AUTH" -H "Content-Type: application/json" \
    -X PUT "$NUXEO_URL/api/v1/path/default-domain/workspaces/Projects/Annual-Report-2023" \
    -d '{"entity-type":"document","properties":{"dc:coverage":"","dc:subjects":[]}}' > /dev/null 2>&1

# Set Contract Template dc:expired to past date, ensure lifecycle is "project"
curl -s -u "$NUXEO_AUTH" -H "Content-Type: application/json" \
    -X PUT "$NUXEO_URL/api/v1/path/default-domain/workspaces/Templates/Contract-Template" \
    -d '{"entity-type":"document","properties":{"dc:expired":"2024-06-30T00:00:00.000Z"}}' > /dev/null 2>&1

# Ensure Contract Template lifecycle is "project" (reset if previously transitioned)
CT_UID=$(curl -s -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/path/default-domain/workspaces/Templates/Contract-Template" | \
    python3 -c "import sys,json; print(json.load(sys.stdin).get('uid',''))" 2>/dev/null || echo "")
CT_STATE=$(curl -s -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/path/default-domain/workspaces/Templates/Contract-Template" | \
    python3 -c "import sys,json; print(json.load(sys.stdin).get('state',''))" 2>/dev/null || echo "")
if [ "$CT_STATE" != "project" ] && [ -n "$CT_UID" ]; then
    # Try to transition back to project
    curl -s -u "$NUXEO_AUTH" -H "Content-Type: application/json" \
        -X POST "$NUXEO_URL/api/v1/id/${CT_UID}/@op/Document.FollowLifecycleTransition" \
        -d '{"params":{"value":"backToProject"}}' > /dev/null 2>&1 || true
fi

echo "Non-compliant state seeded."

# Create the companion reference document: Document Metadata Compliance Standards
echo "Creating compliance standards reference document..."
STANDARDS_PAYLOAD=$(cat <<'STANDARDS_JSON'
{
  "entity-type": "document",
  "type": "Note",
  "name": "Document-Metadata-Compliance-Standards",
  "properties": {
    "dc:title": "Document Metadata Compliance Standards",
    "dc:description": "Regulatory compliance requirements for document metadata in the ECM system",
    "note:note": "<h2>Document Metadata Compliance Standards</h2><h3>Effective Date: January 1, 2025</h3><p>All documents stored in the enterprise content management system must meet the following metadata requirements to comply with regulatory standards (SEC Rule 17a-4, SOX Section 802, FINRA Rule 4511).</p><h3>1. Description Requirement</h3><p>Every document of type File or Note must have a <strong>dc:description</strong> field populated with a meaningful description of at least 50 characters. Placeholder text such as 'needs update', 'TBD', or 'placeholder' is not acceptable.</p><h3>2. Coverage Requirement</h3><p>All financial documents (Annual Reports, Budget Reports, Financial Statements) must have the <strong>dc:coverage</strong> field set to indicate the geographic or jurisdictional scope. Example values: 'United States', 'North America', 'Global Operations'.</p><h3>3. Subject Classification</h3><p>All financial documents must have at least one entry in the <strong>dc:subjects</strong> field for proper classification. Acceptable subject categories include: 'Finance', 'Compliance', 'Operations', 'Strategy', 'Legal'.</p><h3>4. Expired Document Lifecycle</h3><p>Any document whose <strong>dc:expired</strong> date has passed (is earlier than today's date) must have its lifecycle state transitioned to <strong>obsolete</strong>. Documents in 'project' state with past expiration dates are in violation of retention policy.</p><h3>5. Remediation Procedure</h3><p>When remediating a non-compliant document:</p><ul><li>Update all missing or incorrect metadata fields</li><li>Apply the tag <strong>compliance-reviewed</strong> to the document</li><li>Add a comment describing what was corrected</li><li>Add the document to the quarterly compliance audit collection</li></ul>"
  }
}
STANDARDS_JSON
)
nuxeo_api POST "/path/default-domain/workspaces/Projects/" "$STANDARDS_PAYLOAD" > /dev/null 2>&1
echo "Compliance standards document created."

sleep 2

# =====================================================================
# LAUNCH: Open Firefox, log in, navigate to Nuxeo home
# =====================================================================
open_nuxeo_url "$NUXEO_URL/login.jsp" 8

sleep 3
PAGE_TITLE=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    xdotool getactivewindow getwindowname 2>/dev/null || echo "")
if ! echo "$PAGE_TITLE" | grep -q " - Nuxeo Platform"; then
    nuxeo_login
fi

sleep 2
navigate_to "$NUXEO_UI/#!/home"
sleep 3

echo "Task start state: Firefox on Nuxeo home page."
echo "Agent must read compliance standards, audit documents, and remediate."
echo "=== compliance_metadata_remediation setup complete ==="
