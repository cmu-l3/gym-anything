#!/bin/bash
# pre_task hook for litigation_hold_quarantine task.
# CLEAN → SEED → LAUNCH ordering (Lesson 169).
# No set -e (Lesson 174).

echo "=== Setting up litigation_hold_quarantine task ==="

source /workspace/scripts/task_utils.sh

wait_for_nuxeo 120

# =====================================================================
# CLEAN: Remove state from previous runs
# =====================================================================
echo "Cleaning previous task state..."

# Remove legal-hold tags from all known documents
for DOC_PATH in \
    "/default-domain/workspaces/Projects/Phoenix-Initiative-Proposal" \
    "/default-domain/workspaces/Projects/Phoenix-Budget-Analysis" \
    "/default-domain/workspaces/Projects/Marketing-Campaign-Summary"; do
    curl -s -u "$NUXEO_AUTH" -X DELETE \
        "$NUXEO_URL/api/v1/path${DOC_PATH}/@tagging/legal-hold" > /dev/null 2>&1 || true
done

# Delete litigation hold comments on documents
for DOC_PATH in \
    "/default-domain/workspaces/Projects/Phoenix-Initiative-Proposal" \
    "/default-domain/workspaces/Projects/Phoenix-Budget-Analysis" \
    "/default-domain/workspaces/Projects/Marketing-Campaign-Summary"; do
    DOC_UID=$(curl -s -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/path${DOC_PATH}" 2>/dev/null | \
        python3 -c "import sys,json; print(json.load(sys.stdin).get('uid',''))" 2>/dev/null || echo "")
    if [ -n "$DOC_UID" ]; then
        COMMENTS=$(curl -s -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/id/${DOC_UID}/@comment" 2>/dev/null)
        COMMENT_IDS=$(echo "$COMMENTS" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for e in data.get('entries', []):
        cid = e.get('id', '')
        if cid: print(cid)
except: pass
" 2>/dev/null || true)
        for CID in $COMMENT_IDS; do
            curl -s -u "$NUXEO_AUTH" -X DELETE "$NUXEO_URL/api/v1/id/${CID}" > /dev/null 2>&1 || true
        done
    fi
done

# Delete Litigation Hold collection
COLL_SEARCH=$(curl -s -u "$NUXEO_AUTH" \
    "$NUXEO_URL/api/v1/search/lang/NXQL/execute?query=SELECT+*+FROM+Collection+WHERE+dc:title='Litigation+Hold+-+Meridian+v+Acme'+AND+ecm:isTrashed=0+AND+ecm:isVersion=0" 2>/dev/null)
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

# Delete the Phoenix-related documents and Marketing decoy (will recreate)
for DOC_PATH in \
    "/default-domain/workspaces/Projects/Phoenix-Initiative-Proposal" \
    "/default-domain/workspaces/Projects/Phoenix-Budget-Analysis" \
    "/default-domain/workspaces/Projects/Marketing-Campaign-Summary" \
    "/default-domain/workspaces/Projects/Litigation-Hold-Notice"; do
    if doc_exists "$DOC_PATH"; then
        D_UID=$(curl -s -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/path${DOC_PATH}" | \
            python3 -c "import sys,json; print(json.load(sys.stdin).get('uid',''))" 2>/dev/null || echo "")
        [ -n "$D_UID" ] && curl -s -u "$NUXEO_AUTH" -X DELETE "$NUXEO_URL/api/v1/id/${D_UID}?permanent=true" > /dev/null 2>&1 || true
    fi
done

# Remove outside-counsel ACLs
for WS_PATH in \
    "/default-domain/workspaces/Projects"; do
    curl -s -u "$NUXEO_AUTH" -H "Content-Type: application/json" \
        -X POST "$NUXEO_URL/api/v1/path${WS_PATH}/@op/Document.RemoveACL" \
        -d '{"params":{"acl":"local"}}' > /dev/null 2>&1 || true
done

sleep 2

# =====================================================================
# SEED: Create Phoenix documents, decoy, outside-counsel, and hold notice
# =====================================================================
echo "Seeding litigation documents..."

# Create user outside-counsel if not exists
OC_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/user/outside-counsel")
if [ "$OC_CODE" != "200" ]; then
    nuxeo_api POST "/user/" '{"entity-type":"user","id":"outside-counsel","properties":{"username":"outside-counsel","firstName":"Robert","lastName":"Harrington","email":"rharrington@lawfirm.com","password":"password123","groups":["members"]}}' > /dev/null 2>&1
    echo "Created user outside-counsel."
fi

# Create Phoenix Initiative Proposal (IN SCOPE)
nuxeo_api POST "/path/default-domain/workspaces/Projects/" '{
  "entity-type":"document","type":"Note","name":"Phoenix-Initiative-Proposal",
  "properties":{"dc:title":"Phoenix Initiative Proposal","dc:description":"Original proposal document for Project Phoenix — strategic partnership with Meridian Corp for joint product development","note:note":"<h2>Project Phoenix — Strategic Partnership Proposal</h2><p>This document outlines the proposed partnership between Acme Industries and Meridian Corp for the Phoenix Initiative. The initiative covers joint development of next-generation industrial automation systems. Key deliverables include shared IP licensing, co-development of the Phoenix Control Platform, and joint go-to-market strategy for the EMEA region. Total investment: $12.5M over 3 years.</p>"}
}' > /dev/null 2>&1

# Create Phoenix Budget Analysis (IN SCOPE)
nuxeo_api POST "/path/default-domain/workspaces/Projects/" '{
  "entity-type":"document","type":"Note","name":"Phoenix-Budget-Analysis",
  "properties":{"dc:title":"Phoenix Budget Analysis Q2","dc:description":"Financial analysis of Project Phoenix expenditures and budget variances for Q2 2025","note:note":"<h2>Phoenix Initiative — Q2 Budget Analysis</h2><p>Total Q2 spend: $1.87M against projected $2.1M. Underspend driven by delayed Meridian Corp engineering resource allocation. Key variances: R&D (-$142K), Legal (+$68K due to contract renegotiation), Travel (-$51K). Forecast for Q3: $2.3M with catch-up allocation from Meridian.</p>"}
}' > /dev/null 2>&1

# Create Marketing Campaign Summary (OUT OF SCOPE — decoy, no Phoenix reference)
nuxeo_api POST "/path/default-domain/workspaces/Projects/" '{
  "entity-type":"document","type":"Note","name":"Marketing-Campaign-Summary",
  "properties":{"dc:title":"Marketing Campaign Summary Q3","dc:description":"Summary of Q3 2025 digital marketing campaigns and performance metrics","note:note":"<h2>Q3 Marketing Campaign Summary</h2><p>Email campaigns: 12 launched, 34.2% open rate, 8.7% CTR. Social media: LinkedIn impressions up 45%, Twitter engagement flat. PPC spend: $287K across Google Ads and LinkedIn Ads. Top performing campaign: Enterprise Solutions webinar series (412 registrations, 67% attendance rate). Recommendation: Increase budget allocation for LinkedIn content promotion in Q4.</p>"}
}' > /dev/null 2>&1

# Grant outside-counsel Read access to ALL documents in Projects (to be selectively removed)
curl -s -u "$NUXEO_AUTH" -H "Content-Type: application/json" \
    -X POST "$NUXEO_URL/api/v1/path/default-domain/workspaces/Projects/@op/Document.AddACE" \
    -d '{"params":{"user":"outside-counsel","permission":"Read","grant":true,"acl":"local"}}' > /dev/null 2>&1

echo "Litigation documents and permissions seeded."

# Create the Litigation Hold Notice reference document
echo "Creating Litigation Hold Notice..."
NOTICE_PAYLOAD=$(cat <<'NOTICE_JSON'
{
  "entity-type": "document",
  "type": "Note",
  "name": "Litigation-Hold-Notice",
  "properties": {
    "dc:title": "Litigation Hold Notice",
    "dc:description": "Legal hold notice for Meridian Corp v. Acme Industries, Case No. 2025-CV-04891",
    "note:note": "<h2>LITIGATION HOLD NOTICE</h2><h3>Meridian Corp v. Acme Industries</h3><h3>Case No. 2025-CV-04891</h3><p><strong>Date Issued:</strong> October 15, 2025</p><p><strong>Issued By:</strong> General Counsel's Office</p><hr/><h3>Scope of Hold</h3><p>This litigation hold applies to <strong>all documents that reference Project Phoenix or the Phoenix Initiative</strong>, including but not limited to proposals, budget analyses, correspondence, contracts, and technical specifications related to the Acme-Meridian partnership.</p><h3>Required Actions</h3><ol><li>Identify all documents within scope based on title, description, or content referencing 'Phoenix'</li><li>Apply the tag <strong>legal-hold</strong> to each in-scope document</li><li>Add a preservation comment to each document: 'Document placed under litigation hold per Case No. 2025-CV-04891. Do not modify, delete, or relocate.'</li><li>Remove access for user <strong>outside-counsel</strong> (Robert Harrington) from all held documents — this user's engagement is under review</li><li>Create a collection titled <strong>Litigation Hold - Meridian v Acme</strong> containing all held documents</li></ol><h3>Important</h3><p>Do NOT apply the hold to documents that do not reference Project Phoenix or the Phoenix Initiative. Applying a hold to out-of-scope documents creates unnecessary legal exposure and may constitute spoliation of unrelated proceedings.</p>"
  }
}
NOTICE_JSON
)
nuxeo_api POST "/path/default-domain/workspaces/Projects/" "$NOTICE_PAYLOAD" > /dev/null 2>&1
echo "Litigation Hold Notice created."

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
echo "Agent must read litigation hold notice, identify in-scope docs, quarantine them."
echo "=== litigation_hold_quarantine setup complete ==="
