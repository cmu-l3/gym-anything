#!/bin/bash
# pre_task hook for access_control_audit task.
# CLEAN → SEED → LAUNCH ordering (Lesson 169).
# No set -e (Lesson 174).

echo "=== Setting up access_control_audit task ===" | tee /tmp/access_setup.log
exec >> /tmp/access_setup.log 2>&1

source /workspace/scripts/task_utils.sh

wait_for_nuxeo 120

# =====================================================================
# CLEAN: Remove state from previous runs
# =====================================================================
echo "Cleaning previous task state..."

# Delete iam-auditors group if exists
curl -s -o /dev/null -w "%{http_code}" -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/group/iam-auditors" 2>/dev/null | grep -q "200" && \
    curl -s -u "$NUXEO_AUTH" -X DELETE "$NUXEO_URL/api/v1/group/iam-auditors" > /dev/null 2>&1 || true

# Remove all local ACLs from Projects and Templates (clears dpatel, lnovak, iam-auditors from prior runs)
for WS_PATH in \
    "/default-domain/workspaces/Projects" \
    "/default-domain/workspaces/Templates"; do
    curl -s -u "$NUXEO_AUTH" -H "Content-Type: application/json" \
        -X POST "$NUXEO_URL/api/v1/path${WS_PATH}/@op/Document.RemoveACL" \
        -d '{"params":{"acl":"local"}}' > /dev/null 2>&1 || true
done

# Delete access review policy note if exists
if doc_exists "/default-domain/workspaces/Templates/Access-Review-Policy"; then
    ARP_UID=$(curl -s -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/path/default-domain/workspaces/Templates/Access-Review-Policy" | \
        python3 -c "import sys,json; print(json.load(sys.stdin).get('uid',''))" 2>/dev/null || echo "")
    [ -n "$ARP_UID" ] && curl -s -u "$NUXEO_AUTH" -X DELETE "$NUXEO_URL/api/v1/id/${ARP_UID}?permanent=true" > /dev/null 2>&1 || true
fi

# Delete uploaded access review report from Templates workspace (any CSV file)
REPORT_SEARCH=$(curl -s -u "$NUXEO_AUTH" \
    "$NUXEO_URL/api/v1/search/lang/NXQL/execute?query=SELECT+*+FROM+Document+WHERE+ecm:parentId+IN+(SELECT+ecm:uuid+FROM+Workspace+WHERE+dc:title%3D'Templates')+AND+dc:title+LIKE+'%25access%25review%25'+AND+ecm:isTrashed%3D0+AND+ecm:isVersion%3D0" 2>/dev/null)
REPORT_UID=$(echo "$REPORT_SEARCH" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    entries = d.get('entries', [])
    if entries: print(entries[0].get('uid', ''))
except: pass
" 2>/dev/null || echo "")
if [ -n "$REPORT_UID" ]; then
    curl -s -u "$NUXEO_AUTH" -X DELETE "$NUXEO_URL/api/v1/id/${REPORT_UID}?permanent=true" > /dev/null 2>&1 || true
fi

# Delete audit trail comments from workspace documents
for WS_PATH in \
    "/default-domain/workspaces/Projects" \
    "/default-domain/workspaces/Templates"; do
    WS_UID=$(curl -s -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/path${WS_PATH}" 2>/dev/null | \
        python3 -c "import sys,json; print(json.load(sys.stdin).get('uid',''))" 2>/dev/null || echo "")
    if [ -n "$WS_UID" ]; then
        COMMENTS=$(curl -s -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/id/${WS_UID}/@comment" 2>/dev/null)
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

sleep 2

# =====================================================================
# SEED: Create users, grant overly broad permissions, and create reference doc
# =====================================================================
echo "Seeding access control violations..."

# Create user dpatel (departed employee) if not exists
DPATEL_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/user/dpatel")
if [ "$DPATEL_CODE" != "200" ]; then
    nuxeo_api POST "/user/" '{"entity-type":"user","id":"dpatel","properties":{"username":"dpatel","firstName":"Deepak","lastName":"Patel","email":"dpatel@acme.com","password":"password123","groups":["members"]}}' > /dev/null 2>&1
    echo "Created user dpatel."
fi

# Create user lnovak (has overly broad permissions — will need downgrade to ReadWrite)
LNOVAK_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/user/lnovak")
if [ "$LNOVAK_CODE" != "200" ]; then
    nuxeo_api POST "/user/" '{"entity-type":"user","id":"lnovak","properties":{"username":"lnovak","firstName":"Laura","lastName":"Novak","email":"lnovak@acme.com","password":"password123","groups":["members"]}}' > /dev/null 2>&1
    echo "Created user lnovak."
fi

echo "Granting overly broad permissions..."
# Note: Document.AddACE via @op REPLACES the local ACL on each call.
# To seed one user per workspace, we use ONE @op call per workspace (the last call wins).

# Projects workspace: lnovak (contractor) with Everything — violates contractor policy
# (This is the ONLY call to Projects — lnovak will be the sole local ACE)
curl -s -u "$NUXEO_AUTH" -H "Content-Type: application/json" \
    -X POST "$NUXEO_URL/api/v1/path/default-domain/workspaces/Projects/@op/Document.AddACE" \
    -d '{"params":{"user":"lnovak","permission":"Everything","grant":true,"acl":"local"}}' > /dev/null 2>&1
echo "lnovak@Projects: Everything"

# Templates workspace: dpatel (departed employee) with ReadWrite — must be revoked
# (This is the ONLY call to Templates — dpatel will be the sole local ACE)
curl -s -u "$NUXEO_AUTH" -H "Content-Type: application/json" \
    -X POST "$NUXEO_URL/api/v1/path/default-domain/workspaces/Templates/@op/Document.AddACE" \
    -d '{"params":{"user":"dpatel","permission":"ReadWrite","grant":true,"acl":"local"}}' > /dev/null 2>&1
echo "dpatel@Templates: ReadWrite"

# Verify ACLs were set
echo "Projects ACL:"
curl -s -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/path/default-domain/workspaces/Projects/@acl" | \
    python3 -c "import sys,json; d=json.load(sys.stdin); [print('  ',a.get('username','?'),'=',a.get('permission','?')) for acl in d.get('acl',[]) if acl.get('name')=='local' for a in acl.get('ace',[]) if a.get('granted',True)]" 2>/dev/null || true
echo "Templates ACL:"
curl -s -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/path/default-domain/workspaces/Templates/@acl" | \
    python3 -c "import sys,json; d=json.load(sys.stdin); [print('  ',a.get('username','?'),'=',a.get('permission','?')) for acl in d.get('acl',[]) if acl.get('name')=='local' for a in acl.get('ace',[]) if a.get('granted',True)]" 2>/dev/null || true

echo "Overly broad permissions seeded."

# Create the Access Review Policy reference document in Templates
echo "Creating Access Review Policy reference document..."
POLICY_PAYLOAD=$(cat <<'POLICY_JSON'
{
  "entity-type": "document",
  "type": "Note",
  "name": "Access-Review-Policy",
  "properties": {
    "dc:title": "Access Review Policy",
    "dc:description": "Quarterly access review policy for Nuxeo document management system",
    "note:note": "<h2>Quarterly Access Review Policy</h2><h3>Policy ID: IAM-QAR-2025-Q4</h3><p><strong>Effective Date:</strong> October 1, 2025 | <strong>Next Review:</strong> January 1, 2026</p><hr/><h3>Purpose</h3><p>This policy defines the quarterly access review process to enforce the principle of least privilege across all workspaces in the enterprise content management system.</p><h3>Departed User Revocation</h3><p>User <strong>dpatel</strong> (Deepak Patel, Engineering, departed September 30, 2025) must have all access permissions revoked immediately. A review of the system has identified that dpatel currently has <strong>ReadWrite</strong> access on the <strong>Templates</strong> workspace. This access must be removed immediately. Departed users must retain zero access to company systems.</p><h3>Permission Standards by Role</h3><table border='1'><tr><th>Role</th><th>Maximum Permission</th><th>Workspace Scope</th></tr><tr><td>Full-time Employees</td><td>ReadWrite</td><td>Assigned workspace only</td></tr><tr><td>Contractors</td><td>ReadWrite</td><td>Projects workspace only</td></tr><tr><td>External Collaborators</td><td>Read</td><td>Assigned workspace only</td></tr><tr><td>Departed Employees</td><td>None</td><td>All workspaces</td></tr></table><h3>Overly Broad Permissions to Remediate</h3><p>The following users currently have permissions that exceed the policy maximum and must be corrected:</p><ul><li><strong>lnovak</strong> (Laura Novak, Contractor): Currently has <strong>'Everything'</strong> permission on the Projects workspace. Per policy, contractors may only have 'ReadWrite' maximum. Must be downgraded to 'ReadWrite'.</li></ul><h3>Audit Trail Requirements</h3><p>For every workspace where permissions are modified, add a comment documenting: (1) user(s) affected, (2) permission changes made, (3) policy reference (IAM-QAR-2025-Q4), and (4) your name/role.</p><h3>Security Audit Group</h3><p>Create a new user group called <strong>iam-auditors</strong> for the Information Security audit team. Grant this group <strong>Read</strong> access to all workspaces (Projects and Templates) to enable ongoing compliance monitoring without modification rights.</p><h3>Audit Documentation</h3><p>Upon completion, upload the access review report file from the Desktop (<strong>/home/ga/Desktop/access_review_report.csv</strong>) to the <strong>Templates</strong> workspace as a permanent record of this audit cycle.</p>"
  }
}
POLICY_JSON
)
nuxeo_api POST "/path/default-domain/workspaces/Templates/" "$POLICY_PAYLOAD" > /dev/null 2>&1
echo "Access Review Policy reference document created."

# Create access_review_report.csv on Desktop
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/access_review_report.csv << 'CSV_EOF'
Audit Cycle,Q4 2025
Policy Reference,IAM-QAR-2025-Q4
Auditor,
Audit Date,
Workspace,User,Previous Permission,New Permission,Action Taken,Notes
Templates,dpatel,ReadWrite,None,Revoked,Departed employee - Sep 30 2025
Projects,lnovak,Everything,ReadWrite,Downgraded,Contractor - exceeds maximum allowed
CSV_EOF
chown ga:ga /home/ga/Desktop/access_review_report.csv 2>/dev/null || true
echo "access_review_report.csv created on Desktop."

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
echo "Agent must read Access Review Policy, revoke dpatel, downgrade lnovak,"
echo "create iam-auditors group, grant Read to workspaces, add audit comments, upload CSV."
echo "=== access_control_audit setup complete ==="
