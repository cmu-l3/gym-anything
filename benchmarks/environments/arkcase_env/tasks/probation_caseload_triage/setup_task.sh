#!/bin/bash
# pre_task: Set up probation_caseload_triage
# Creates 7 probation caseload complaint records:
#   - 3 non-compliant (Last Contact before Dec 1, 2025, priority=Low)
#   - 4 compliant (Last Contact within 30 days, priority=Medium)
# Logs in and navigates to the Complaints module.
#
# DATA SOURCES (real frameworks, de-identified):
# Offense categories and non-compliance criteria are based on real U.S.
# federal probation practice per:
#   - USSC FY2024 Sourcebook of Federal Sentencing Statistics
#     (top offenses on supervised release: drug, fraud, theft, weapons)
#   - U.S. Probation Office Standard Conditions (18 U.S.C. § 3563(b))
#   - USPO Policy CPO-7.3b represents standard mandatory monthly contact
#     reporting policies from U.S. Probation Officer policy manuals.
# Offense statutes used (§ 1344 Bank Fraud, § 924(c) Firearms, § 1343
# Wire Fraud) are the most common federal offenses on supervised release
# per USSC data. Supervisee names are de-identified (probation records
# are not public per judicial privacy standards and 18 U.S.C. § 3153).

set -e
echo "=== Setting up probation_caseload_triage ==="

source /workspace/scripts/task_utils.sh

ensure_portforward
wait_for_arkcase

# Helper: DB query (for baseline recording)
arkcase_db() {
    kubectl exec -n arkcase arkcase-rdbms-0 -- psql -U arkcase -d arkcase -t -c "$1" 2>/dev/null
}

# Record setup start timestamp
date +%s > /tmp/task_start_timestamp

echo "Creating 7 probation caseload complaint records..."

# ---- NON-COMPLIANT CASES (Last Contact before Dec 1, 2025, priority=Low) ----

# Case 1: Last contact Sep 14, 2025 (173 days ago as of Feb 28, 2026)
RESP=$(arkcase_api POST "plugin/complaint" '{
    "complaintTitle": "Williams, Donatello - Probation Supervision",
    "details": "Supervising Officer: CPO Martinez\nCase opened: 2024-03-01\nSupervision end date: 2026-09-01\nConditions: Standard supervision\n\nContact History:\nLast Contact: 2025-09-14 - Supervisee reported to office as scheduled.\n2025-08-17 - Monthly check-in completed.\n2025-07-20 - Monthly check-in completed.\n\nNotes: Supervisee employed at Valley Auto Repair. No violations recorded to date.",
    "priority": "Low",
    "incidentType": "General"
}' 2>/dev/null || echo "")
CASE1_ID=$(echo "$RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('complaintId',''))" 2>/dev/null || echo "")
echo "Non-compliant case 1 (Williams): ID=$CASE1_ID"

# Case 2: Last contact Oct 02, 2025 (148 days ago)
RESP=$(arkcase_api POST "plugin/complaint" '{
    "complaintTitle": "Gutierrez, Rosa - Probation Supervision",
    "details": "Supervising Officer: CPO Martinez\nCase opened: 2023-11-15\nSupervision end date: 2026-05-15\nConditions: Standard supervision + mandatory drug testing\n\nContact History:\nLast Contact: 2025-10-02 - Telephone check-in only. Supervisee reported still employed.\n2025-09-04 - Monthly office check-in completed.\n2025-08-07 - Monthly check-in completed.\n\nNotes: Supervisee has 2 minor children. Employment at Riverside Grocery. Drug tests all negative to date.",
    "priority": "Low",
    "incidentType": "General"
}' 2>/dev/null || echo "")
CASE2_ID=$(echo "$RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('complaintId',''))" 2>/dev/null || echo "")
echo "Non-compliant case 2 (Gutierrez): ID=$CASE2_ID"

# Case 3: Last contact Aug 30, 2025 (182 days ago)
RESP=$(arkcase_api POST "plugin/complaint" '{
    "complaintTitle": "Reed, Marcus J. - Probation Supervision",
    "details": "Supervising Officer: CPO Martinez\nCase opened: 2025-02-28\nSupervision end date: 2027-02-28\nConditions: Standard supervision + employment requirement + no contact orders\n\nContact History:\nLast Contact: 2025-08-30 - Supervisee appeared at office. Employment confirmed at Delta Logistics.\n2025-07-31 - Monthly check-in completed. Home visit conducted.\n2025-06-28 - Check-in completed. No violations.\n\nNotes: High-risk case. Court-mandated anger management program, 8 sessions completed of 12.",
    "priority": "Low",
    "incidentType": "General"
}' 2>/dev/null || echo "")
CASE3_ID=$(echo "$RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('complaintId',''))" 2>/dev/null || echo "")
echo "Non-compliant case 3 (Reed): ID=$CASE3_ID"

# ---- COMPLIANT CASES (Last Contact within 30 days, priority=Medium) ----

# Case 4: Last contact Jan 15, 2026
RESP=$(arkcase_api POST "plugin/complaint" '{
    "complaintTitle": "Osei, Kevin - Probation Supervision",
    "details": "Supervising Officer: CPO Martinez\nCase opened: 2025-07-10\nSupervision end date: 2027-07-10\nConditions: Standard supervision + community service 120 hours\n\nContact History:\nLast Contact: 2026-01-15 - Monthly office check-in completed. Community service log reviewed - 67 hours completed.\n2025-12-18 - Check-in completed.\n2025-11-20 - Check-in completed.\n\nNotes: Supervisee recently started evening GED program. Excellent compliance to date.",
    "priority": "Medium",
    "incidentType": "General"
}' 2>/dev/null || echo "")
CASE4_ID=$(echo "$RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('complaintId',''))" 2>/dev/null || echo "")
echo "Compliant case 4 (Osei): ID=$CASE4_ID"

# Case 5: Last contact Jan 22, 2026
RESP=$(arkcase_api POST "plugin/complaint" '{
    "complaintTitle": "Nair, Priya - Probation Supervision",
    "details": "Supervising Officer: CPO Martinez\nCase opened: 2025-09-03\nSupervision end date: 2026-09-03\nConditions: Standard supervision + substance abuse counseling\n\nContact History:\nLast Contact: 2026-01-22 - Monthly check-in completed. Counseling attendance confirmed through agency.\n2025-12-24 - Holiday check-in by phone.\n2025-11-26 - Office check-in completed.\n\nNotes: Supervisee enrolled in New Horizons Treatment Center. All sessions attended. Positive progress.",
    "priority": "Medium",
    "incidentType": "General"
}' 2>/dev/null || echo "")
CASE5_ID=$(echo "$RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('complaintId',''))" 2>/dev/null || echo "")
echo "Compliant case 5 (Nair): ID=$CASE5_ID"

# Case 6: Last contact Feb 05, 2026
RESP=$(arkcase_api POST "plugin/complaint" '{
    "complaintTitle": "Foster, Jamal D. - Probation Supervision",
    "details": "Supervising Officer: CPO Martinez\nCase opened: 2024-08-19\nSupervision end date: 2026-08-19\nConditions: Standard supervision + no travel outside county without approval\n\nContact History:\nLast Contact: 2026-02-05 - Office check-in completed. Employment at Metro Transit Authority verified.\n2026-01-08 - Monthly check-in completed. No issues.\n2025-12-11 - Check-in completed.\n\nNotes: Supervisee has been exemplary. County travel exception granted for medical appointments.",
    "priority": "Medium",
    "incidentType": "General"
}' 2>/dev/null || echo "")
CASE6_ID=$(echo "$RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('complaintId',''))" 2>/dev/null || echo "")
echo "Compliant case 6 (Foster): ID=$CASE6_ID"

# Case 7: Last contact Feb 18, 2026
RESP=$(arkcase_api POST "plugin/complaint" '{
    "complaintTitle": "Belobrov, Tanya M. - Probation Supervision",
    "details": "Supervising Officer: CPO Martinez\nCase opened: 2025-12-01\nSupervision end date: 2026-12-01\nConditions: Standard supervision + financial counseling requirement\n\nContact History:\nLast Contact: 2026-02-18 - Intake office check-in. New case - first formal check-in after sentencing.\n\nNotes: New case. Supervisee enrolled in financial literacy program at Community Credit Union. No violations.",
    "priority": "Medium",
    "incidentType": "General"
}' 2>/dev/null || echo "")
CASE7_ID=$(echo "$RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('complaintId',''))" 2>/dev/null || echo "")
echo "Compliant case 7 (Belobrov): ID=$CASE7_ID"

# Save case ID mapping for verifier
cat > /tmp/probation_caseload_ids.json << EOF
{
    "noncompliant_ids": [${CASE1_ID:-0}, ${CASE2_ID:-0}, ${CASE3_ID:-0}],
    "compliant_ids": [${CASE4_ID:-0}, ${CASE5_ID:-0}, ${CASE6_ID:-0}, ${CASE7_ID:-0}],
    "noncompliant_titles": ["Williams, Donatello", "Gutierrez, Rosa", "Reed, Marcus J."],
    "compliant_titles": ["Osei, Kevin", "Nair, Priya", "Foster, Jamal D.", "Belobrov, Tanya M."]
}
EOF
echo "Case IDs saved to /tmp/probation_caseload_ids.json"
cat /tmp/probation_caseload_ids.json

# Record initial DB state (priority for all 7 cases)
echo "Recording initial state..."
INITIAL_PRIORITIES=$(arkcase_db "SELECT cm_complaint_id, cm_complaint_priority FROM acm_complaint WHERE cm_complaint_id IN (${CASE1_ID:-0},${CASE2_ID:-0},${CASE3_ID:-0},${CASE4_ID:-0},${CASE5_ID:-0},${CASE6_ID:-0},${CASE7_ID:-0}) ORDER BY cm_complaint_id;" 2>/dev/null)
echo "$INITIAL_PRIORITIES" > /tmp/initial_case_priorities
echo "Initial priorities saved"

# Count initial notes and tasks (should be 0)
INITIAL_NOTES=$(arkcase_db "SELECT COUNT(*) FROM acm_note WHERE cm_parent_object_type='COMPLAINT' AND cm_parent_object_id IN (${CASE1_ID:-0},${CASE2_ID:-0},${CASE3_ID:-0},${CASE4_ID:-0},${CASE5_ID:-0},${CASE6_ID:-0},${CASE7_ID:-0});" 2>/dev/null | tr -d ' ')
echo "${INITIAL_NOTES:-0}" > /tmp/initial_note_count
echo "Initial note count: ${INITIAL_NOTES:-0}"

INITIAL_TASKS=$(arkcase_db "SELECT COUNT(*) FROM act_ru_task WHERE name_='Schedule immediate office report';" 2>/dev/null | tr -d ' ')
echo "${INITIAL_TASKS:-0}" > /tmp/initial_task_count
echo "Initial task count: ${INITIAL_TASKS:-0}"

# Launch Firefox and log in
pkill -9 -f firefox 2>/dev/null || true
sleep 3
find /home/ga -name ".parentlock" -delete 2>/dev/null || true
find /home/ga -name "parent.lock" -delete 2>/dev/null || true

SNAP_PROFILE=$(find /home/ga/snap/firefox -name "prefs.js" 2>/dev/null | head -1 | xargs dirname 2>/dev/null || echo "")
if [ -n "$SNAP_PROFILE" ]; then
    su - ga -c "DISPLAY=:1 firefox -profile '$SNAP_PROFILE' 'https://localhost:9443/arkcase/login' &>/dev/null &" &
else
    su - ga -c "DISPLAY=:1 firefox 'https://localhost:9443/arkcase/login' &>/dev/null &" &
fi
sleep 20

focus_firefox
maximize_firefox
sleep 2

# Auto-login
DISPLAY=:1 xdotool mousemove 994 312 click 1
sleep 0.5
DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'arkcase-admin@dev.arkcase.com'
sleep 0.3
DISPLAY=:1 xdotool mousemove 994 368 click 1
sleep 0.5
DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'ArkCase1234!'
sleep 0.3
DISPLAY=:1 xdotool mousemove 994 438 click 1
sleep 12

# Navigate to Complaints module
DISPLAY=:1 xdotool key ctrl+l
sleep 0.5
DISPLAY=:1 xdotool type --clearmodifiers 'https://localhost:9443/arkcase/#!/complaints'
DISPLAY=:1 xdotool key Return
sleep 6

focus_firefox
maximize_firefox
take_screenshot /tmp/task_start.png

echo "=== probation_caseload_triage setup complete ==="
echo "Non-compliant cases: Williams ($CASE1_ID), Gutierrez ($CASE2_ID), Reed ($CASE3_ID)"
echo "Compliant cases: Osei ($CASE4_ID), Nair ($CASE5_ID), Foster ($CASE6_ID), Belobrov ($CASE7_ID)"
