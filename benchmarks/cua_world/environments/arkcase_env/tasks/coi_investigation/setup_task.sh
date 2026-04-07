#!/bin/bash
set -euo pipefail
echo "=== Setting up COI Investigation task ==="

source /workspace/scripts/task_utils.sh
ensure_portforward
wait_for_arkcase

# ── Delete stale outputs ────────────────────────────────────────────────────
rm -f /home/ga/Documents/coi_report.json 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/coi_ground_truth.json 2>/dev/null || true
rm -f /root/validation/coi_ground_truth.json 2>/dev/null || true

# ── Record task start time ──────────────────────────────────────────────────
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# ── Create Meridian-related cases ───────────────────────────────────────────
echo "Creating Meridian Holdings Group cases..."

CASE1_RESP=$(arkcase_api POST "plugin/complaint" '{
  "caseType": "GENERAL",
  "complaintTitle": "FOIA Request - Meridian Holdings Group Federal Contract Records",
  "details": "Freedom of Information Act request for all federal contract records, bid submissions, and award notifications involving Meridian Holdings Group for fiscal years 2023-2025. This case has been assigned to Lead Analyst: Elena Rodriguez (elena.rodriguez@agency.gov) for review and processing. Requester: Government Accountability Project. Filed: January 15, 2026. The request covers approximately 3,400 pages of procurement documentation across 17 federal agencies. Initial review indicates significant volume of potentially responsive records in the Department of Defense and Department of Energy contract archives.",
  "priority": "Medium",
  "status": "ACTIVE"
}')
CASE1_ID=$(echo "$CASE1_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('complaintId', d.get('id','')))" 2>/dev/null || echo "")
CASE1_NUM=$(echo "$CASE1_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('caseNumber', d.get('complaintNumber','')))" 2>/dev/null || echo "")
echo "  Case 1 (Meridian/Rodriguez): ID=$CASE1_ID, Number=$CASE1_NUM"

CASE2_RESP=$(arkcase_api POST "plugin/complaint" '{
  "caseType": "GENERAL",
  "complaintTitle": "Complaint - Meridian Holdings Environmental Violations",
  "details": "Formal complaint alleging environmental regulation violations by Meridian Holdings Group at their Riverside manufacturing facility. Allegations include improper hazardous waste disposal and falsified EPA compliance reports submitted between March 2024 and November 2025. Assigned Analyst: David Chen (david.chen@agency.gov). Referred by: EPA Region 5 Office. Filed: February 3, 2026. Case involves coordination with state environmental agencies and potential referral to the Department of Justice Environmental Crimes Section.",
  "priority": "High",
  "status": "ACTIVE"
}')
CASE2_ID=$(echo "$CASE2_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('complaintId', d.get('id','')))" 2>/dev/null || echo "")
CASE2_NUM=$(echo "$CASE2_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('caseNumber', d.get('complaintNumber','')))" 2>/dev/null || echo "")
echo "  Case 2 (Meridian/Chen): ID=$CASE2_ID, Number=$CASE2_NUM"

CASE3_RESP=$(arkcase_api POST "plugin/complaint" '{
  "caseType": "GENERAL",
  "complaintTitle": "Records Request - Meridian Holdings Group Tax Compliance Review",
  "details": "Request for tax compliance audit records and IRS correspondence related to Meridian Holdings Group subsidiary entities for tax years 2022-2024. Assigned Analyst: Sarah Martinez (sarah.martinez@agency.gov). Requester: Senate Finance Committee Staff. Filed: December 8, 2025. This request originated from a congressional oversight inquiry and has been designated as priority correspondence requiring response within 10 business days per agency policy on legislative branch requests.",
  "priority": "Medium",
  "status": "ACTIVE"
}')
CASE3_ID=$(echo "$CASE3_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('complaintId', d.get('id','')))" 2>/dev/null || echo "")
CASE3_NUM=$(echo "$CASE3_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('caseNumber', d.get('complaintNumber','')))" 2>/dev/null || echo "")
echo "  Case 3 (Meridian/Martinez): ID=$CASE3_ID, Number=$CASE3_NUM"

CASE4_RESP=$(arkcase_api POST "plugin/complaint" '{
  "caseType": "GENERAL",
  "complaintTitle": "FOIA Request - Meridian Holdings Subsidiary Financial Disclosures",
  "details": "Request for SEC filing records, annual financial disclosures, and board meeting minutes for all Meridian Holdings Group subsidiary corporations including Meridian Capital Partners, Meridian Infrastructure LLC, and Meridian Defense Systems Inc. Assigned Analyst: Elena Rodriguez (elena.rodriguez@agency.gov). Cross-reference with Case regarding federal contract records. Filed: March 1, 2026. This request involves multi-agency coordination with SEC, Treasury, and Commerce Department records custodians.",
  "priority": "Medium",
  "status": "ACTIVE"
}')
CASE4_ID=$(echo "$CASE4_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('complaintId', d.get('id','')))" 2>/dev/null || echo "")
CASE4_NUM=$(echo "$CASE4_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('caseNumber', d.get('complaintNumber','')))" 2>/dev/null || echo "")
echo "  Case 4 (Meridian/Rodriguez again): ID=$CASE4_ID, Number=$CASE4_NUM"

# ── Create investigation cases ──────────────────────────────────────────────
echo "Creating internal investigation cases..."

CASE5_RESP=$(arkcase_api POST "plugin/complaint" '{
  "caseType": "GENERAL",
  "complaintTitle": "Internal Investigation - Elena Rodriguez - Unauthorized Document Access",
  "details": "Internal affairs investigation into allegations that Senior Analyst Elena Rodriguez accessed restricted case files outside her authorized portfolio on multiple occasions between September and November 2025. Subject of Investigation: Elena Rodriguez, Senior Analyst, FOIA Processing Division. Investigation initiated following automated access log audit revealing 47 unauthorized file accesses across 12 classified case folders. Investigating Officer: James Wright, Office of Professional Responsibility. Filed: November 20, 2025. Rodriguez has been notified of the investigation per agency policy and union collective bargaining agreement Article 14.",
  "priority": "High",
  "status": "ACTIVE"
}')
CASE5_ID=$(echo "$CASE5_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('complaintId', d.get('id','')))" 2>/dev/null || echo "")
CASE5_NUM=$(echo "$CASE5_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('caseNumber', d.get('complaintNumber','')))" 2>/dev/null || echo "")
echo "  Case 5 (Investigation/Rodriguez): ID=$CASE5_ID, Number=$CASE5_NUM"

CASE6_RESP=$(arkcase_api POST "plugin/complaint" '{
  "caseType": "GENERAL",
  "complaintTitle": "Misconduct Investigation - David Chen - Policy Violation Report",
  "details": "Investigation into reported policy violations by Analyst David Chen regarding premature disclosure of case-sensitive information to external parties. Subject of Investigation: David Chen, Analyst, Environmental Compliance Division. Report filed by Division Chief Maria Santos on January 3, 2026, after discovering that preliminary findings from an ongoing enforcement action were shared with a regulated entity before the formal notice of violation was issued. Filed: January 8, 2026. This matter has been referred to the Office of Inspector General for parallel review.",
  "priority": "High",
  "status": "ACTIVE"
}')
CASE6_ID=$(echo "$CASE6_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('complaintId', d.get('id','')))" 2>/dev/null || echo "")
CASE6_NUM=$(echo "$CASE6_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('caseNumber', d.get('complaintNumber','')))" 2>/dev/null || echo "")
echo "  Case 6 (Investigation/Chen): ID=$CASE6_ID, Number=$CASE6_NUM"

# ── Save ground truth (hidden from agent) ───────────────────────────────────
mkdir -p /root/validation
cat > /root/validation/coi_ground_truth.json <<GTEOF
{
  "organization": "Meridian Holdings Group",
  "directive_number": "COI-2026-03",
  "meridian_cases": {
    "case1": {"id": "${CASE1_ID}", "number": "${CASE1_NUM}", "title": "FOIA Request - Meridian Holdings Group Federal Contract Records", "analyst": "Elena Rodriguez"},
    "case2": {"id": "${CASE2_ID}", "number": "${CASE2_NUM}", "title": "Complaint - Meridian Holdings Environmental Violations", "analyst": "David Chen"},
    "case3": {"id": "${CASE3_ID}", "number": "${CASE3_NUM}", "title": "Records Request - Meridian Holdings Group Tax Compliance Review", "analyst": "Sarah Martinez"},
    "case4": {"id": "${CASE4_ID}", "number": "${CASE4_NUM}", "title": "FOIA Request - Meridian Holdings Subsidiary Financial Disclosures", "analyst": "Elena Rodriguez"}
  },
  "investigation_cases": {
    "case5": {"id": "${CASE5_ID}", "number": "${CASE5_NUM}", "title": "Internal Investigation - Elena Rodriguez - Unauthorized Document Access", "subject": "Elena Rodriguez"},
    "case6": {"id": "${CASE6_ID}", "number": "${CASE6_NUM}", "title": "Misconduct Investigation - David Chen - Policy Violation Report", "subject": "David Chen"}
  },
  "expected_conflicts": [
    {"analyst": "Elena Rodriguez", "meridian_case_numbers": ["${CASE1_NUM}", "${CASE4_NUM}"], "investigation_case_number": "${CASE5_NUM}"},
    {"analyst": "David Chen", "meridian_case_numbers": ["${CASE2_NUM}"], "investigation_case_number": "${CASE6_NUM}"}
  ],
  "clean_analysts": ["Sarah Martinez"],
  "expected_ethics_complaints": 2,
  "task_start_time": "$(cat /tmp/task_start_time.txt)"
}
GTEOF
chmod 600 /root/validation/coi_ground_truth.json
echo "Ground truth saved to /root/validation/coi_ground_truth.json"

# ── Create directive file ───────────────────────────────────────────────────
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/coi_directive.txt <<'DIREOF'
AGENCY DIRECTIVE 2026-03
CONFLICT OF INTEREST REVIEW

Date: March 20, 2026
Authority: 5 C.F.R. Part 2635.502

TO: FOIA Compliance Division
FROM: Office of Inspector General

SUBJECT: Mandatory Conflict of Interest Review - Meridian Holdings Group

Pursuant to 5 C.F.R. Part 2635.502 (Personal and business relationships),
the Office of Inspector General has determined that a conflict-of-interest
review is required for all personnel assigned to cases involving Meridian
Holdings Group.

BACKGROUND:
Recent reporting has raised concerns about potential conflicts of interest
among analysts assigned to review matters involving Meridian Holdings Group
and its subsidiaries. This directive mandates a systematic review to ensure
the integrity of all pending cases.

DIRECTIVE:
You are instructed to identify all active complaint cases in ArkCase whose
titles mention "Meridian Holdings". For each such case, determine the
Assigned Analyst by reading the case description. Then verify whether any
identified analyst is currently the subject of a separate internal
investigation by searching for cases with "Investigation" in the title
that name that analyst.

An analyst who is both assigned to handle Meridian Holdings cases AND is
the subject of an active internal investigation presents a conflict of
interest per 5 C.F.R. Part 2635.502(a).

REQUIRED ACTIONS:
For each confirmed conflict of interest:
  1. File a new Ethics Review complaint in ArkCase with:
     - Title: "Ethics Review: [Analyst Name] - COI Directive 2026-03"
     - Category: Government
     - Priority: High
     - Description: Must cite the assigned case number(s) and the
       investigation case number

  2. Produce a written investigation report at:
     ~/Documents/coi_report.json

Directive Number: COI-2026-03

                                        /s/ Robert J. Hammond
                                        Inspector General
DIREOF
chown ga:ga /home/ga/Documents/coi_directive.txt
echo "Directive file created at /home/ga/Documents/coi_directive.txt"

# Ensure Documents directory is ready for agent output
chown ga:ga /home/ga/Documents

# ── Wait for Solr to index the new cases ────────────────────────────────────
# ArkCase uses Solr for full-text search; newly created cases need time to be indexed.
# 45 seconds is sufficient for 6 cases based on observed indexing latency.
echo "Waiting for Solr indexing..."
sleep 45

# ── Launch Firefox, handle SSL, login, navigate to Complaints ───────────────
echo "Setting up Firefox..."
pkill -f firefox 2>/dev/null || true
sleep 2
rm -f /home/ga/snap/firefox/common/.mozilla/firefox/*/lock 2>/dev/null || true

ensure_firefox_on_arkcase "${ARKCASE_URL}/login"
sleep 5
handle_ssl_warning
sleep 3
auto_login_arkcase "${ARKCASE_URL}/#!/complaints"
sleep 5
focus_firefox
maximize_firefox

take_screenshot /tmp/task_start.png
echo "=== COI Investigation task setup complete ==="
echo "Agent should: read directive -> search Meridian cases -> identify analysts -> check for investigations -> file ethics complaints -> write report"
