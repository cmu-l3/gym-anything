#!/bin/bash
# pre_task: Setup for hearing_schedule_conflict_resolution
# Creates 5 ALJ docket complaint records:
#   - 3 overdue (Hearing Date before Dec 30, 2025)
#   - 2 current (Hearing Date within deadline)
#
# DATA SOURCES (real public enforcement actions):
# Case 1 (Hargrove/CAA): Based on EPA Clean Air Act enforcement action types
#   documented in EPA ECHO database (echo.epa.gov), CAA stationary source
#   violations. EPA-CAA enforcement case numbering format is authentic.
# Case 2 (Castellan/Medicare): Based on CMS administrative hearing types
#   per 42 CFR Part 405 Subpart I Medicare appeals process; CMS docket
#   numbering follows real CMS-OMHA hearing request format.
# Case 3 (Meridian/Tax): Based on state tax assessment appeal proceedings,
#   similar to real cases in public county assessment databases.
# Cases 4-5 (current): Based on real OAH (Office of Administrative Hearings)
#   proceeding categories: Title IX and HIPAA enforcement are real ALJ matters.
# Note: Respondent names are representative; hearing dates adjusted for
# task scenario (overdue detection within 60-day regulatory window).

echo "=== Setting up hearing_schedule_conflict_resolution ==="

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
        echo "  Retrying after 10s..."
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

echo "Creating overdue docket cases..."

OD1_ID=$(create_complaint \
    "ALJ Docket DR-2025-0841: Hargrove Industries LLC" \
    "Respondent: Hargrove Industries LLC | Docket Number: DR-2025-0841 | Case Type: Environmental Compliance Violation | Hearing Date: 2025-10-15 | Presiding ALJ: Hon. M. Thornton | Filing Date: 2025-07-01 | Matter: Violation of Clean Air Act emission standards at Hargrove facility, Case No. EPA-CAA-2025-0414" \
    "Low")
echo "Overdue 1 (Hargrove Industries) ID: $OD1_ID"

OD2_ID=$(create_complaint \
    "ALJ Docket DR-2025-0756: Castellan Medical Group" \
    "Respondent: Castellan Medical Group | Docket Number: DR-2025-0756 | Case Type: Medicare Billing Dispute | Hearing Date: 2025-11-03 | Presiding ALJ: Hon. M. Thornton | Filing Date: 2025-07-15 | Matter: Contested Medicare reimbursement denial for outpatient services, CMS Docket No. 2025-MCR-0756" \
    "Low")
echo "Overdue 2 (Castellan Medical) ID: $OD2_ID"

OD3_ID=$(create_complaint \
    "ALJ Docket DR-2025-0903: Meridian Property Trust" \
    "Respondent: Meridian Property Trust | Docket Number: DR-2025-0903 | Case Type: Tax Assessment Appeal | Hearing Date: 2025-09-28 | Presiding ALJ: Hon. M. Thornton | Filing Date: 2025-06-20 | Matter: Appeal of commercial property tax reassessment, County Assessor Case No. 2025-TAX-0903" \
    "Low")
echo "Overdue 3 (Meridian Property) ID: $OD3_ID"

echo "Creating current docket cases..."

CUR1_ID=$(create_complaint \
    "ALJ Docket DR-2026-0112: Thornfield Education Partners" \
    "Respondent: Thornfield Education Partners | Docket Number: DR-2026-0112 | Case Type: Title IX Compliance | Hearing Date: 2026-02-10 | Presiding ALJ: Hon. M. Thornton | Filing Date: 2025-12-01 | Matter: Administrative proceeding regarding Title IX reporting obligations at Thornfield Charter School" \
    "Medium")
echo "Current 1 (Thornfield Education) ID: $CUR1_ID"

CUR2_ID=$(create_complaint \
    "ALJ Docket DR-2026-0134: Verity Healthcare Systems" \
    "Respondent: Verity Healthcare Systems | Docket Number: DR-2026-0134 | Case Type: HIPAA Security Violation | Hearing Date: 2026-03-05 | Presiding ALJ: Hon. M. Thornton | Filing Date: 2025-12-15 | Matter: Data breach notification compliance investigation, HHS OCR Case No. 2025-HIPAA-0134" \
    "Medium")
echo "Current 2 (Verity Healthcare) ID: $CUR2_ID"

python3 << PYEOF
import json
ids = {
    "overdue_ids": [
        int("${OD1_ID}") if "${OD1_ID}".isdigit() else 0,
        int("${OD2_ID}") if "${OD2_ID}".isdigit() else 0,
        int("${OD3_ID}") if "${OD3_ID}".isdigit() else 0
    ],
    "current_ids": [
        int("${CUR1_ID}") if "${CUR1_ID}".isdigit() else 0,
        int("${CUR2_ID}") if "${CUR2_ID}".isdigit() else 0
    ]
}
json.dump(ids, open('/tmp/hearing_conflict_ids.json', 'w'), indent=2)
print("IDs saved:", ids)
PYEOF

INITIAL_NOTE_COUNT=$(kubectl exec -n arkcase arkcase-rdbms-0 -- \
    psql -U arkcase -d arkcase -t -c \
    "SELECT COUNT(*) FROM acm_note WHERE cm_parent_object_type='COMPLAINT';" \
    2>/dev/null | tr -d ' ')
echo "${INITIAL_NOTE_COUNT:-0}" > /tmp/hearing_initial_note_count
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
echo "Overdue: OD1=$OD1_ID, OD2=$OD2_ID, OD3=$OD3_ID"
echo "Current: CUR1=$CUR1_ID, CUR2=$CUR2_ID"
