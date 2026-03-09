#!/bin/bash
# pre_task hook for merger_workspace_consolidation task.
# CLEAN → SEED → LAUNCH ordering (Lesson 169).
# No set -e (Lesson 174).

echo "=== Setting up merger_workspace_consolidation task ==="

source /workspace/scripts/task_utils.sh

wait_for_nuxeo 120

# =====================================================================
# CLEAN: Remove state from previous runs
# =====================================================================
echo "Cleaning previous task state..."

# Delete Integrated Operations workspace if exists
if doc_exists "/default-domain/workspaces/Integrated-Operations"; then
    IO_UID=$(curl -s -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/path/default-domain/workspaces/Integrated-Operations" | \
        python3 -c "import sys,json; print(json.load(sys.stdin).get('uid',''))" 2>/dev/null || echo "")
    [ -n "$IO_UID" ] && curl -s -u "$NUXEO_AUTH" -X DELETE "$NUXEO_URL/api/v1/id/${IO_UID}?permanent=true" > /dev/null 2>&1 || true
    echo "Deleted existing Integrated Operations workspace."
fi

# Delete integrated-team group if exists
curl -s -o /dev/null -w "%{http_code}" -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/group/integrated-team" 2>/dev/null | grep -q "200" && \
    curl -s -u "$NUXEO_AUTH" -X DELETE "$NUXEO_URL/api/v1/group/integrated-team" > /dev/null 2>&1 || true

# Delete Alpha and Beta Division workspaces (will recreate)
for WS in "Alpha-Division" "Beta-Division"; do
    if doc_exists "/default-domain/workspaces/$WS"; then
        WS_UID=$(curl -s -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/path/default-domain/workspaces/$WS" | \
            python3 -c "import sys,json; print(json.load(sys.stdin).get('uid',''))" 2>/dev/null || echo "")
        [ -n "$WS_UID" ] && curl -s -u "$NUXEO_AUTH" -X DELETE "$NUXEO_URL/api/v1/id/${WS_UID}?permanent=true" > /dev/null 2>&1 || true
    fi
done

# Delete Merger Integration Plan note if exists
if doc_exists "/default-domain/workspaces/Merger-Integration-Plan"; then
    MIP_UID=$(curl -s -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/path/default-domain/workspaces/Merger-Integration-Plan" | \
        python3 -c "import sys,json; print(json.load(sys.stdin).get('uid',''))" 2>/dev/null || echo "")
    [ -n "$MIP_UID" ] && curl -s -u "$NUXEO_AUTH" -X DELETE "$NUXEO_URL/api/v1/id/${MIP_UID}?permanent=true" > /dev/null 2>&1 || true
fi

# Delete alpha-team and beta-team groups (will recreate)
for GRP in "alpha-team" "beta-team"; do
    curl -s -o /dev/null -w "%{http_code}" -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/group/$GRP" 2>/dev/null | grep -q "200" && \
        curl -s -u "$NUXEO_AUTH" -X DELETE "$NUXEO_URL/api/v1/group/$GRP" > /dev/null 2>&1 || true
done

sleep 2

# =====================================================================
# SEED: Create division workspaces, users, groups, and reference doc
# =====================================================================
echo "Seeding division workspaces and documents..."

# Create users if they don't exist
create_user_if_missing() {
    local username="$1" first="$2" last="$3" email="$4"
    local code=$(curl -s -o /dev/null -w "%{http_code}" -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/user/$username")
    if [ "$code" != "200" ]; then
        nuxeo_api POST "/user/" "{\"entity-type\":\"user\",\"id\":\"$username\",\"properties\":{\"username\":\"$username\",\"firstName\":\"$first\",\"lastName\":\"$last\",\"email\":\"$email\",\"password\":\"password123\",\"groups\":[\"members\"]}}" > /dev/null 2>&1
        echo "Created user $username ($first $last)."
    fi
}

create_user_if_missing "acohen" "Alice" "Cohen" "acohen@acme.com"
create_user_if_missing "mgarcia" "Maria" "Garcia" "mgarcia@acme.com"
create_user_if_missing "tchen" "Tom" "Chen" "tchen@acme.com"

# Create alpha-team and beta-team groups
nuxeo_api POST "/group/" '{"entity-type":"group","groupname":"alpha-team","grouplabel":"Alpha Division Team","memberUsers":["acohen","jsmith"]}' > /dev/null 2>&1
nuxeo_api POST "/group/" '{"entity-type":"group","groupname":"beta-team","grouplabel":"Beta Division Team","memberUsers":["mgarcia","tchen"]}' > /dev/null 2>&1
echo "Created alpha-team and beta-team groups."

# Create Alpha Division workspace with documents
create_doc_if_missing "/default-domain/workspaces" "Workspace" "Alpha-Division" "Alpha Division" "Legacy workspace for the Alpha Division prior to merger"

nuxeo_api POST "/path/default-domain/workspaces/Alpha-Division/" '{
  "entity-type":"document","type":"Note","name":"Alpha-Project-Plan",
  "properties":{"dc:title":"Alpha Strategic Project Plan","dc:description":"Strategic project roadmap for Alpha Division Q1-Q4 2025","note:note":"<h2>Alpha Division Strategic Project Plan</h2><p>Phase 1: Market expansion into APAC region. Phase 2: Product line consolidation. Phase 3: Technology platform migration. Budget: $2.4M allocated across 3 workstreams.</p>"}
}' > /dev/null 2>&1

nuxeo_api POST "/path/default-domain/workspaces/Alpha-Division/" '{
  "entity-type":"document","type":"Note","name":"Alpha-Budget-Report",
  "properties":{"dc:title":"Alpha Division Budget Report FY2025","dc:description":"Annual budget allocation and expenditure tracking for Alpha Division","note:note":"<h2>Alpha Division Budget Report</h2><p>Total Budget: $5.8M. Personnel: $3.2M. Infrastructure: $1.4M. Operations: $1.2M. Current burn rate: 94% of projected. Variance: -$48K.</p>"}
}' > /dev/null 2>&1

# Create Beta Division workspace with documents
create_doc_if_missing "/default-domain/workspaces" "Workspace" "Beta-Division" "Beta Division" "Legacy workspace for the Beta Division prior to merger"

nuxeo_api POST "/path/default-domain/workspaces/Beta-Division/" '{
  "entity-type":"document","type":"Note","name":"Beta-Product-Roadmap",
  "properties":{"dc:title":"Beta Product Roadmap 2025","dc:description":"Product development roadmap and feature pipeline for Beta Division","note:note":"<h2>Beta Product Roadmap 2025</h2><p>Q1: Authentication overhaul (OAuth 2.1). Q2: Real-time collaboration features. Q3: Mobile SDK v3.0 release. Q4: Enterprise API gateway. Dependencies: Cloud infrastructure migration must complete by Q2.</p>"}
}' > /dev/null 2>&1

nuxeo_api POST "/path/default-domain/workspaces/Beta-Division/" '{
  "entity-type":"document","type":"Note","name":"Beta-Quarterly-Metrics",
  "properties":{"dc:title":"Beta Division Quarterly Metrics Q3 2025","dc:description":"","note:note":"<h2>Beta Division Q3 Metrics</h2><p>Revenue: $4.1M (+12% YoY). Active users: 28,400. Churn rate: 2.1%. NPS: 72. Support tickets: 1,847 (avg resolution: 4.2 hours).</p>"}
}' > /dev/null 2>&1

echo "Division workspaces and documents created."

# Create the Merger Integration Plan reference document
echo "Creating Merger Integration Plan reference document..."
PLAN_PAYLOAD=$(cat <<'PLAN_JSON'
{
  "entity-type": "document",
  "type": "Note",
  "name": "Merger-Integration-Plan",
  "properties": {
    "dc:title": "Merger Integration Plan",
    "dc:description": "Organizational restructuring plan for Alpha-Beta division merger",
    "note:note": "<h2>Merger Integration Plan — Alpha &amp; Beta Division Consolidation</h2><h3>Approved: November 2025</h3><p>Following the board's decision to merge the Alpha and Beta divisions, the following workspace restructuring must be implemented in the document management system.</p><h3>Target Structure</h3><p>Create a new top-level workspace called <strong>Integrated Operations</strong> under Workspaces with two sub-workspaces:</p><ul><li><strong>Product Development</strong> — for all product-related documents (roadmaps, project plans, technical specifications)</li><li><strong>Corporate Services</strong> — for all administrative, financial, and metrics documents (budgets, quarterly metrics, financial reports)</li></ul><h3>Document Migration Rules</h3><ul><li>Project plans and product roadmaps → Product Development</li><li>Budget reports and quarterly metrics → Corporate Services</li><li>All migrated documents must have their descriptions updated to reflect the new organizational context (minimum 20 characters)</li></ul><h3>Access Control</h3><ul><li>Create a new group called <strong>integrated-team</strong></li><li>Add all members from both <strong>alpha-team</strong> and <strong>beta-team</strong> to the integrated-team group</li><li>Grant <strong>ReadWrite</strong> access to the integrated-team group on the Integrated Operations workspace</li></ul><h3>Timeline</h3><p>Complete by end of Q4 2025. Legacy division workspaces may remain as archives but are not to receive new documents.</p>"
  }
}
PLAN_JSON
)
nuxeo_api POST "/path/default-domain/workspaces/" "$PLAN_PAYLOAD" > /dev/null 2>&1
echo "Merger Integration Plan created."

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
echo "Agent must read Merger Integration Plan, create unified structure, migrate docs."
echo "=== merger_workspace_consolidation setup complete ==="
