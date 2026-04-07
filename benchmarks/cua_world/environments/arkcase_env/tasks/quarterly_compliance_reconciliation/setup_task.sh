#!/bin/bash
# pre_task: Set up quarterly_compliance_reconciliation
# Creates 6 FOIA complaint cases with deliberate discrepancies between actual
# field values and what the audit directive expects. Also writes the directive
# document that the agent must read and cross-reference.
#
# DATA SOURCES (realistic government FOIA context):
#   - Requesting parties are real advocacy organizations (GAP, AILA, EFF,
#     Sierra Club, Wounded Warrior Project, National Security Archive at GWU).
#   - FOIA statutory references (5 U.S.C. section 552, EO 13526) are accurate.
#   - Tracking number formats follow standard agency convention.
#   - Case descriptions model real FOIA request language from DOJ FOIA logs.
#   - De-identified: no real case tracking numbers or PII are used.

echo "=== Setting up quarterly_compliance_reconciliation ==="

# Pre-set ARKCASE_NS before sourcing task_utils.sh -- the ensure_arkcase_running()
# function (auto-called on source) needs this for pod status checks.
export ARKCASE_NS="arkcase"
source /workspace/scripts/task_utils.sh

ensure_portforward
wait_for_arkcase
sleep 20  # Extra REST API stabilization

# DB query helper
arkcase_db() {
    kubectl exec -n arkcase arkcase-rdbms-0 -- psql -U arkcase -d arkcase -t -c "$1" 2>/dev/null
}

# Delete stale outputs BEFORE recording timestamp
rm -f /home/ga/Documents/reconciliation_report.json 2>/dev/null || true
rm -f /tmp/reconciliation_case_ids.json 2>/dev/null || true
rm -f /tmp/reconciliation_result.json 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

echo "Creating 6 FOIA complaint cases..."

# Helper: create complaint and extract ID
create_complaint() {
    local payload="$1"
    local label="$2"
    local resp
    resp=$(arkcase_api POST "plugin/complaint" "$payload" 2>/dev/null || echo "")
    local cid
    cid=$(echo "$resp" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('complaintId', d.get('id','')))" 2>/dev/null || echo "")
    if [ -z "$cid" ] || [ "$cid" = "" ] || [ "$cid" = "0" ]; then
        sleep 10
        resp=$(arkcase_api POST "plugin/complaint" "$payload" 2>/dev/null || echo "")
        cid=$(echo "$resp" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('complaintId', d.get('id','')))" 2>/dev/null || echo "")
    fi
    echo "$cid"
}

# CASE 1: Priority WRONG (Low, should be Medium). Assignee correct (admin).
C1_ID=$(create_complaint '{
    "caseType": "GENERAL",
    "complaintTitle": "FOIA Request - Department of Energy Contract Awards FY2025",
    "priority": "Low",
    "details": "Requesting Party: Government Accountability Project (GAP)\nDate Received: January 8, 2026\nTracking Number: FOIA-2026-DOE-0041\n\nRequest Description:\nThe Government Accountability Project requests copies of all contract award documents, statements of work, and cost proposals related to Department of Energy prime contracts exceeding $10 million awarded during Fiscal Year 2025, specifically those associated with the Office of Environmental Management and the National Nuclear Security Administration. Includes task orders, modifications, and performance evaluations for contractors Bechtel National, AECOM, and Fluor Idaho LLC.\n\nResponsive Records Estimate: 450-600 pages\nEstimated Processing Time: 45 business days\nFee Category: News Media (fee waiver pending)"
}' "case1")
echo "Case 1 (DOE Contract Awards): ID=$C1_ID"

# CASE 2: Priority appears correct (Low = Low). Assignee correct (admin).
#   BUT description CONTAINS genuine "classified national security" phrase.
C2_ID=$(create_complaint '{
    "caseType": "GENERAL",
    "complaintTitle": "FOIA Request - Immigration Enforcement Action Records",
    "priority": "Low",
    "details": "Requesting Party: American Immigration Lawyers Association (AILA)\nDate Received: February 3, 2026\nTracking Number: FOIA-2026-DHS-0187\n\nRequest Description:\nAILA requests all records related to immigration enforcement operations conducted by ICE Enforcement and Removal Operations (ERO) in the Chicago Area of Responsibility during Q4 FY2025. This includes operational planning documents, deployment orders, target lists, and after-action reports. Note: Several responsive documents may contain classified national security information related to joint operations with the Department of Defense and intelligence community interagency coordination protocols that require separate handling under Executive Order 13526, Section 1.4(a) and (c).\n\nResponsive Records Estimate: 200-350 pages\nEstimated Processing Time: 60 business days\nFee Category: Educational/Scientific Institution"
}' "case2")
echo "Case 2 (Immigration Enforcement): ID=$C2_ID"

# CASE 3: Everything correct (Medium, admin). No sensitive keyword.
C3_ID=$(create_complaint '{
    "caseType": "GENERAL",
    "complaintTitle": "FOIA Request - Federal Aviation Safety Incident Reports",
    "priority": "Medium",
    "details": "Requesting Party: Aviation Safety Network (ASN)\nDate Received: January 22, 2026\nTracking Number: FOIA-2026-FAA-0093\n\nRequest Description:\nAviation Safety Network requests copies of all preliminary and final incident investigation reports filed with the FAA Aviation Safety Information Analysis and Sharing (ASIAS) system for calendar year 2025, specifically Category A and B incidents involving Part 121 air carriers operating Boeing 737 MAX variants. Includes Safety Recommendation responses, Corrective Action Plans, and relevant ASRS narratives.\n\nResponsive Records Estimate: 180-250 pages\nEstimated Processing Time: 30 business days\nFee Category: News Media (fee waiver approved)"
}' "case3")
echo "Case 3 (FAA Safety): ID=$C3_ID"

# CASE 4: Priority WRONG (Low, should be High). Assignee WRONG (admin, should be sally-acm).
C4_ID=$(create_complaint '{
    "caseType": "GENERAL",
    "complaintTitle": "FOIA Request - Veterans Affairs Claims Processing Data",
    "priority": "Low",
    "details": "Requesting Party: Wounded Warrior Project\nDate Received: December 15, 2025\nTracking Number: FOIA-2026-VA-0012\n\nRequest Description:\nWounded Warrior Project requests aggregate data and internal memoranda related to disability compensation claims processing at VA Regional Offices (VAROs) for FY2025, including average processing times by claim type, denial rates by diagnostic code, and appeals outcomes. Also requesting all Office of Inspector General reports concerning the Veterans Benefits Administration claims backlog and any directives from the Under Secretary for Benefits regarding processing targets.\n\nResponsive Records Estimate: 300-400 pages\nEstimated Processing Time: 50 business days\nFee Category: Non-commercial scientific institution (fee waiver approved)"
}' "case4")
echo "Case 4 (VA Claims): ID=$C4_ID"

# CASE 5 -- THE TRAP: Assignee WRONG (admin, should be sally-acm).
#   Description contains "classified national security" in DECLASSIFICATION context.
C5_ID=$(create_complaint '{
    "caseType": "GENERAL",
    "complaintTitle": "FOIA Request - Declassified EPA Environmental Records",
    "priority": "Medium",
    "details": "Requesting Party: National Security Archive (George Washington University)\nDate Received: February 15, 2026\nTracking Number: FOIA-2026-EPA-0201\n\nRequest Description:\nThe National Security Archive at George Washington University requests environmental monitoring records from formerly restricted DOE facilities. This request covers records that were previously classified national security material under Executive Order 13526 but have been fully declassified pursuant to Section 3.3 automatic declassification review completed in October 2025. Specifically requesting declassified environmental impact assessments, groundwater contamination reports, and worker exposure data from the Hanford Site, Rocky Flats Plant, and Savannah River Site covering 1985-2000.\n\nResponsive Records Estimate: 800-1200 pages\nEstimated Processing Time: 75 business days\nFee Category: Educational institution"
}' "case5")
echo "Case 5 (Declassified EPA - TRAP): ID=$C5_ID"

# CASE 6: Assignee WRONG (admin, should be sally-acm). Priority correct (Medium)
#   on paper, BUT description CONTAINS genuine "classified national security".
C6_ID=$(create_complaint '{
    "caseType": "GENERAL",
    "complaintTitle": "FOIA Request - Defense Intelligence Surveillance Programs",
    "priority": "Medium",
    "details": "Requesting Party: Electronic Frontier Foundation (EFF)\nDate Received: January 30, 2026\nTracking Number: FOIA-2026-DOD-0074\n\nRequest Description:\nEFF requests all legal memoranda, policy directives, and compliance reports related to Defense Intelligence Agency (DIA) signals intelligence collection programs operating under Executive Order 12333 during calendar year 2025. This request includes Inspector General audit reports, FISA Court opinions referencing DIA collection activities, and any classified national security assessments regarding the impact of these programs on U.S. persons privacy rights. Also requesting all Privacy Impact Assessments and Civil Liberties assessments completed for DIA surveillance programs in 2025.\n\nResponsive Records Estimate: 150-300 pages\nEstimated Processing Time: 90 business days\nFee Category: Non-commercial requester"
}' "case6")
echo "Case 6 (Defense Intelligence): ID=$C6_ID"

# Save case ID mapping
cat > /tmp/reconciliation_case_ids.json << EOF
{
    "case1": ${C1_ID:-0},
    "case2": ${C2_ID:-0},
    "case3": ${C3_ID:-0},
    "case4": ${C4_ID:-0},
    "case5": ${C5_ID:-0},
    "case6": ${C6_ID:-0}
}
EOF
echo "Case IDs saved to /tmp/reconciliation_case_ids.json"
cat /tmp/reconciliation_case_ids.json

# Wait for Solr indexing
sleep 45

# Save ground truth (hidden from agent)
mkdir -p /root/validation
python3 << PYEOF
import json
gt = {
    "cases": {
        "${C1_ID:-0}": {"label": "case1", "title": "FOIA Request - Department of Energy Contract Awards FY2025", "directive_priority": "Medium", "correct_final_priority": "Medium", "correct_final_assignee": "arkcase-admin", "has_sensitive_keyword": False, "sensitive_is_declassified": False, "needs_followup_task": False, "initial_priority": "Low"},
        "${C2_ID:-0}": {"label": "case2", "title": "FOIA Request - Immigration Enforcement Action Records", "directive_priority": "Low", "correct_final_priority": "High", "correct_final_assignee": "arkcase-admin", "has_sensitive_keyword": True, "sensitive_is_declassified": False, "needs_followup_task": False, "initial_priority": "Low"},
        "${C3_ID:-0}": {"label": "case3", "title": "FOIA Request - Federal Aviation Safety Incident Reports", "directive_priority": "Medium", "correct_final_priority": "Medium", "correct_final_assignee": "arkcase-admin", "has_sensitive_keyword": False, "sensitive_is_declassified": False, "needs_followup_task": True, "initial_priority": "Medium"},
        "${C4_ID:-0}": {"label": "case4", "title": "FOIA Request - Veterans Affairs Claims Processing Data", "directive_priority": "High", "correct_final_priority": "High", "correct_final_assignee": "sally-acm", "has_sensitive_keyword": False, "sensitive_is_declassified": False, "needs_followup_task": True, "initial_priority": "Low"},
        "${C5_ID:-0}": {"label": "case5", "title": "FOIA Request - Declassified EPA Environmental Records", "directive_priority": "Medium", "correct_final_priority": "Medium", "correct_final_assignee": "sally-acm", "has_sensitive_keyword": True, "sensitive_is_declassified": True, "needs_followup_task": False, "initial_priority": "Medium"},
        "${C6_ID:-0}": {"label": "case6", "title": "FOIA Request - Defense Intelligence Surveillance Programs", "directive_priority": "Medium", "correct_final_priority": "High", "correct_final_assignee": "sally-acm", "has_sensitive_keyword": True, "sensitive_is_declassified": False, "needs_followup_task": False, "initial_priority": "Medium"}
    }
}
with open('/root/validation/ground_truth.json', 'w') as f:
    json.dump(gt, f, indent=2)
PYEOF
chmod 600 /root/validation/ground_truth.json
echo "Ground truth saved to /root/validation/ground_truth.json"

# Record initial DB state
ALL_IDS="${C1_ID:-0},${C2_ID:-0},${C3_ID:-0},${C4_ID:-0},${C5_ID:-0},${C6_ID:-0}"
echo "Recording initial state..."
INITIAL_PRIORITIES=$(arkcase_db "SELECT cm_complaint_id, cm_complaint_priority FROM acm_complaint WHERE cm_complaint_id IN ($ALL_IDS) ORDER BY cm_complaint_id;" 2>/dev/null)
echo "$INITIAL_PRIORITIES" > /tmp/initial_case_priorities
echo "Initial priorities recorded"
INITIAL_NOTES=$(arkcase_db "SELECT COUNT(*) FROM acm_note WHERE cm_parent_object_type='COMPLAINT' AND cm_parent_object_id IN ($ALL_IDS);" 2>/dev/null | tr -d ' ')
echo "${INITIAL_NOTES:-0}" > /tmp/initial_note_count
echo "Initial note count: ${INITIAL_NOTES:-0}"

# Write the audit directive document
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/audit_directive.txt << 'DIRECTIVE_EOF'
QUARTERLY COMPLIANCE AUDIT DIRECTIVE
Directive Number: CCO-2026-Q1
Fiscal Quarter: Q1 FY2026 (January - March 2026)
Issued By: Chief Compliance Officer, FOIA Program Office
Date: March 15, 2026

PURPOSE:
Reconcile six active FOIA complaint records against expected case
attributes. Correct all identified discrepancies and document changes.

AUDIT INSTRUCTIONS:
For each case below, verify the current Priority and Assignee in ArkCase
match the expected values. Correct any mismatches.

CORRECTION NOTE FORMAT:
"QA-Q1-2026: [Field] corrected from [old_value] to [new_value] per
directive CCO-2026-Q1."

EXCEPTION RULE (MANDATORY):
If a case description contains the phrase "classified national security",
the case Priority MUST be set to "High" regardless of the expected value
listed below. Add the following note:
"QA-Q1-2026: Priority escalated to High - classified national security
content detected per EO 13526."
IMPORTANT: This rule does NOT apply when the phrase appears in the context
of declassification (e.g., "previously classified... declassified").

================================================================

CASES TO AUDIT:

1. "FOIA Request - Department of Energy Contract Awards FY2025"
   Expected Priority: Medium
   Expected Assignee: arkcase-admin

2. "FOIA Request - Immigration Enforcement Action Records"
   Expected Priority: Low
   Expected Assignee: arkcase-admin

3. "FOIA Request - Federal Aviation Safety Incident Reports"
   Expected Priority: Medium
   Expected Assignee: arkcase-admin

4. "FOIA Request - Veterans Affairs Claims Processing Data"
   Expected Priority: High
   Expected Assignee: Sally Acm (sally-acm)

5. "FOIA Request - Declassified EPA Environmental Records"
   Expected Priority: Medium
   Expected Assignee: Sally Acm (sally-acm)

6. "FOIA Request - Defense Intelligence Surveillance Programs"
   Expected Priority: Medium
   Expected Assignee: Sally Acm (sally-acm)

================================================================

DELIVERABLE:
Save reconciliation report to: ~/Documents/reconciliation_report.json
Format: JSON array, one object per case, with fields:
  case_number, title, priority_correct, assignee_correct,
  sensitive_flag, actions_taken
DIRECTIVE_EOF
chown ga:ga /home/ga/Documents/audit_directive.txt
echo "Audit directive written to ~/Documents/audit_directive.txt"

# Launch Firefox, log in, navigate to Complaints
pkill -9 -f firefox 2>/dev/null || true
sleep 3
find /home/ga -name ".parentlock" -delete 2>/dev/null || true
find /home/ga -name "parent.lock" -delete 2>/dev/null || true

SNAP_PROFILE=$(find /home/ga/snap/firefox -name "prefs.js" 2>/dev/null | head -1 | xargs dirname 2>/dev/null || echo "")
if [ -n "$SNAP_PROFILE" ]; then
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority firefox -profile '$SNAP_PROFILE' 'https://localhost:9443/arkcase/login' &>/dev/null &" &
else
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority firefox 'https://localhost:9443/arkcase/login' &>/dev/null &" &
fi
sleep 20

focus_firefox
maximize_firefox
sleep 2

# Auto-login (coordinates for 1920x1080, verified via visual grounding)
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool mousemove 994 314 click 1
sleep 0.5
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool type --clearmodifiers --delay 50 'arkcase-admin@dev.arkcase.com'
sleep 0.3
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool mousemove 994 369 click 1
sleep 0.5
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool type --clearmodifiers --delay 50 'ArkCase1234!'
sleep 0.3
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool mousemove 994 441 click 1
sleep 12

# Navigate to Complaints module
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key ctrl+l
sleep 0.5
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool type --clearmodifiers 'https://localhost:9443/arkcase/#!/complaints'
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Return
sleep 6

focus_firefox
maximize_firefox
take_screenshot /tmp/task_start.png

echo "=== quarterly_compliance_reconciliation setup complete ==="
echo "Cases created: C1=$C1_ID, C2=$C2_ID, C3=$C3_ID, C4=$C4_ID, C5=$C5_ID, C6=$C6_ID"
