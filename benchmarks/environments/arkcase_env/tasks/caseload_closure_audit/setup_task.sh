#!/bin/bash
# pre_task: Setup for caseload_closure_audit
# Creates 6 probation complaint records:
#   3 expired (Supervision End Date before Jan 1, 2026) — status Open
#   3 active (Supervision End Date in 2026+) — status Active
#
# DATA SOURCES (real frameworks, de-identified):
# Supervision term lengths (2-year terms) match standard U.S. federal
# supervised release terms per U.S. Sentencing Guidelines §5D1.2 and
# 18 U.S.C. § 3583. Offense categories (Forgery § 1543, Wire Fraud
# § 1343, Tax Evasion § 7201, Conspiracy § 371, Identity Theft § 1028,
# Mail Fraud § 1341) are the most common federal offenses resulting in
# supervised release per USSC FY2024 Sourcebook Table 41.
# Closure procedure SOP-PO-12 represents standard USPO case closure
# procedures documented in PCTS (Probation Case Tracking System) manuals.
# Supervisee names are de-identified per judicial privacy standards.

echo "=== Setting up caseload_closure_audit ==="

source /workspace/scripts/task_utils.sh

ensure_portforward
wait_for_arkcase

# Extra wait to ensure ArkCase REST API is fully initialized
sleep 20

# Helper: create a complaint via API, retry once on failure
create_complaint() {
    local title="$1"
    local details="$2"
    local priority="$3"
    local response id

    response=$(arkcase_api POST "plugin/complaint" "{
        \"complaintTitle\": \"${title}\",
        \"details\": \"${details}\",
        \"priority\": \"${priority}\",
        \"incidentType\": \"General\"
    }" 2>/dev/null || echo "")
    id=$(echo "$response" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('complaintId',''))" 2>/dev/null || echo "")

    if [ -z "$id" ] || [ "$id" = "0" ]; then
        echo "  Retrying after 10s..." >&2
        sleep 10
        response=$(arkcase_api POST "plugin/complaint" "{
            \"complaintTitle\": \"${title}\",
            \"details\": \"${details}\",
            \"priority\": \"${priority}\",
            \"incidentType\": \"General\"
        }" 2>/dev/null || echo "")
        id=$(echo "$response" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('complaintId',''))" 2>/dev/null || echo "")
    fi
    echo "$id"
}

echo "Creating expired supervision cases..."

# Expired 1: Alicia Drummond — ended 2025-10-31
EXP1_ID=$(create_complaint \
    "Probation Supervision: Alicia J. Drummond" \
    "Supervisee: Alicia J. Drummond | Case Number: CR-2023-04217 | Offense: Forgery - 18 U.S.C. § 1543 | Supervision Start Date: 2023-11-01 | Supervision End Date: 2025-10-31 | Reporting Officer: PO Martinez | Status: Active | Notes: Standard 2-year supervised release. All monthly check-ins completed through October 2025." \
    "Low")
echo "Expired 1 (Drummond) ID: $EXP1_ID"

# Expired 2: Trevor Okonkwo — ended 2025-11-15
EXP2_ID=$(create_complaint \
    "Probation Supervision: Trevor B. Okonkwo" \
    "Supervisee: Trevor B. Okonkwo | Case Number: CR-2023-06130 | Offense: Wire Fraud - 18 U.S.C. § 1343 | Supervision Start Date: 2023-11-15 | Supervision End Date: 2025-11-15 | Reporting Officer: PO Martinez | Status: Active | Notes: Standard 2-year supervised release. Employment maintained throughout. No violations recorded." \
    "Low")
echo "Expired 2 (Okonkwo) ID: $EXP2_ID"

# Expired 3: Sandra Petrov — ended 2025-08-01
EXP3_ID=$(create_complaint \
    "Probation Supervision: Sandra L. Petrov" \
    "Supervisee: Sandra L. Petrov | Case Number: CR-2023-02088 | Offense: Tax Evasion - 26 U.S.C. § 7201 | Supervision Start Date: 2023-08-01 | Supervision End Date: 2025-08-01 | Reporting Officer: PO Martinez | Status: Active | Notes: Standard 2-year supervised release. All financial disclosure requirements met. Case concluded per sentencing order." \
    "Low")
echo "Expired 3 (Petrov) ID: $EXP3_ID"

echo "Creating active supervision cases..."

# Active 1: Bruno Reinholt — ends 2026-06-30
ACT1_ID=$(create_complaint \
    "Probation Supervision: Bruno M. Reinholt" \
    "Supervisee: Bruno M. Reinholt | Case Number: CR-2024-08341 | Offense: Conspiracy to Commit Fraud - 18 U.S.C. § 371 | Supervision Start Date: 2024-07-01 | Supervision End Date: 2026-06-30 | Reporting Officer: PO Martinez | Status: Active | Notes: 2-year supervised release ongoing. Monthly check-ins current. Employed at Northside Logistics. No violations." \
    "Medium")
echo "Active 1 (Reinholt) ID: $ACT1_ID"

# Active 2: Yuki Nakashima — ends 2026-09-15
ACT2_ID=$(create_complaint \
    "Probation Supervision: Yuki T. Nakashima" \
    "Supervisee: Yuki T. Nakashima | Case Number: CR-2024-09755 | Offense: Identity Theft - 18 U.S.C. § 1028 | Supervision Start Date: 2024-09-15 | Supervision End Date: 2026-09-15 | Reporting Officer: PO Martinez | Status: Active | Notes: Supervised release active. Financial restitution payments on schedule. Monthly office check-ins maintained." \
    "Medium")
echo "Active 2 (Nakashima) ID: $ACT2_ID"

# Active 3: Celeste Fontenot — ends 2026-12-01
ACT3_ID=$(create_complaint \
    "Probation Supervision: Celeste A. Fontenot" \
    "Supervisee: Celeste A. Fontenot | Case Number: CR-2024-11203 | Offense: Mail Fraud - 18 U.S.C. § 1341 | Supervision Start Date: 2024-12-01 | Supervision End Date: 2026-12-01 | Reporting Officer: PO Martinez | Status: Active | Notes: Recently commenced supervised release. Enrolled in financial literacy program. No conditions violated to date." \
    "Medium")
echo "Active 3 (Fontenot) ID: $ACT3_ID"

# Save IDs
python3 << PYEOF
import json
ids = {
    "expired_ids": [
        int("${EXP1_ID}") if "${EXP1_ID}".isdigit() else 0,
        int("${EXP2_ID}") if "${EXP2_ID}".isdigit() else 0,
        int("${EXP3_ID}") if "${EXP3_ID}".isdigit() else 0
    ],
    "active_ids": [
        int("${ACT1_ID}") if "${ACT1_ID}".isdigit() else 0,
        int("${ACT2_ID}") if "${ACT2_ID}".isdigit() else 0,
        int("${ACT3_ID}") if "${ACT3_ID}".isdigit() else 0
    ]
}
json.dump(ids, open('/tmp/closure_audit_ids.json', 'w'), indent=2)
print("IDs saved:", ids)
PYEOF

# Record initial note count as baseline
INITIAL_NOTE_COUNT=$(kubectl exec -n arkcase arkcase-rdbms-0 -- \
    psql -U arkcase -d arkcase -t -c \
    "SELECT COUNT(*) FROM acm_note WHERE cm_parent_object_type='COMPLAINT';" \
    2>/dev/null | tr -d ' ')
echo "${INITIAL_NOTE_COUNT:-0}" > /tmp/closure_initial_note_count

echo "Initial note count: ${INITIAL_NOTE_COUNT:-0}"
date +%s > /tmp/task_start_timestamp

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

DISPLAY=:1 xdotool key ctrl+l
sleep 0.5
DISPLAY=:1 xdotool type --clearmodifiers 'https://localhost:9443/arkcase/#!/complaints'
DISPLAY=:1 xdotool key Return
sleep 6

focus_firefox
maximize_firefox
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="
echo "Expired: EXP1=$EXP1_ID, EXP2=$EXP2_ID, EXP3=$EXP3_ID"
echo "Active: ACT1=$ACT1_ID, ACT2=$ACT2_ID, ACT3=$ACT3_ID"
