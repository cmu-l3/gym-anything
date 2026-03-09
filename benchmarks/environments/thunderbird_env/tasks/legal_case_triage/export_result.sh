#!/bin/bash
# Export script for legal_case_triage task

echo "=== Exporting legal_case_triage result ==="

source /workspace/scripts/task_utils.sh

# Kill Thunderbird gracefully so it flushes filter rules and address book to disk
# (Lesson 28: apps buffer config changes in memory, only write on exit)
close_thunderbird
sleep 3
echo "Thunderbird closed to flush configs"

# Take final screenshot before we close
take_screenshot /tmp/legal_case_triage_end_screenshot.png

TASK_START=$(cat /tmp/legal_case_triage_start_ts 2>/dev/null || echo "0")
INBOX_BASELINE=$(cat /tmp/legal_case_triage_inbox_baseline 2>/dev/null || echo "12")

# ============================================================
# Check folder structure: Cases.sbd directory
# ============================================================
CASES_SBD_EXISTS="false"
if [ -d "${LOCAL_MAIL_DIR}/Cases.sbd" ]; then
    CASES_SBD_EXISTS="true"
fi

# Harrison_Mercer subfolder (accept common name variants)
HARRISON_FOLDER=""
HARRISON_COUNT=0
for name in Harrison_Mercer Harrison-Mercer HarrisonMercer Harrison_v_Mercer Harrison; do
    if [ -f "${LOCAL_MAIL_DIR}/Cases.sbd/${name}" ]; then
        HARRISON_FOLDER="${name}"
        HARRISON_COUNT=$(grep -c "^From " "${LOCAL_MAIL_DIR}/Cases.sbd/${name}" 2>/dev/null || echo "0")
        break
    fi
done

# DataVault_IP subfolder (accept common name variants)
DATAVAULT_FOLDER=""
DATAVAULT_COUNT=0
for name in DataVault_IP DataVault-IP DataVaultIP DataVault_Patent DataVault; do
    if [ -f "${LOCAL_MAIL_DIR}/Cases.sbd/${name}" ]; then
        DATAVAULT_FOLDER="${name}"
        DATAVAULT_COUNT=$(grep -c "^From " "${LOCAL_MAIL_DIR}/Cases.sbd/${name}" 2>/dev/null || echo "0")
        break
    fi
done

# Chen_Estate subfolder (accept common name variants)
CHEN_FOLDER=""
CHEN_COUNT=0
for name in Chen_Estate Chen-Estate ChenEstate Chen_Family_Estate Chen; do
    if [ -f "${LOCAL_MAIL_DIR}/Cases.sbd/${name}" ]; then
        CHEN_FOLDER="${name}"
        CHEN_COUNT=$(grep -c "^From " "${LOCAL_MAIL_DIR}/Cases.sbd/${name}" 2>/dev/null || echo "0")
        break
    fi
done

# ============================================================
# Check Court_Notices folder (or similar)
# ============================================================
COURT_NOTICES_EXISTS="false"
for name in Court_Notices Court-Notices CourtNotices Court_Clerk Court_Filings; do
    if [ -f "${LOCAL_MAIL_DIR}/${name}" ] || [ -f "${LOCAL_MAIL_DIR}/Cases.sbd/${name}" ]; then
        COURT_NOTICES_EXISTS="true"
        break
    fi
done

# ============================================================
# Check message filters for court clerk routing
# ============================================================
FILTER_FILE="${THUNDERBIRD_PROFILE}/Mail/Local Folders/msgFilterRules.dat"
COURT_FILTER_EXISTS="false"
COURT_FILTER_NAME=""
if [ -f "$FILTER_FILE" ]; then
    if grep -qi "courtclerk@district.court\|court.*clerk\|district.court" "$FILTER_FILE" 2>/dev/null; then
        COURT_FILTER_EXISTS="true"
        COURT_FILTER_NAME=$(grep "^name=" "$FILTER_FILE" | tail -1 | sed 's/^name="//' | sed 's/"$//' | tr -d '\r')
    fi
fi

# ============================================================
# Check address book for Marcus Webb / mwebb@hartleypatent.com
# ============================================================
MARCUS_WEBB_ADDED="false"
MARCUS_WEBB_EMAIL_FOUND="false"
python3 << 'PYEOF'
import sqlite3, os, json

abook_path = os.path.expanduser("~ga/.thunderbird/default-release/abook.sqlite")
result = {"found": False, "email_found": False}

if os.path.exists(abook_path):
    try:
        conn = sqlite3.connect(abook_path)
        cur = conn.cursor()
        # Check by email
        cur.execute("SELECT value FROM properties WHERE name='PrimaryEmail' AND LOWER(value) LIKE '%mwebb%'")
        email_rows = cur.fetchall()
        if email_rows:
            result["email_found"] = True
            result["found"] = True
        # Also check by name
        cur.execute("SELECT value FROM properties WHERE name='DisplayName' AND LOWER(value) LIKE '%webb%'")
        name_rows = cur.fetchall()
        if name_rows:
            result["found"] = True
        conn.close()
    except Exception as e:
        result["error"] = str(e)

with open("/tmp/legal_case_triage_abook_check.json", "w") as f:
    json.dump(result, f)
print(json.dumps(result))
PYEOF

if [ -f "/tmp/legal_case_triage_abook_check.json" ]; then
    MARCUS_WEBB_ADDED=$(python3 -c "import json; d=json.load(open('/tmp/legal_case_triage_abook_check.json')); print('true' if d.get('found') else 'false')" 2>/dev/null || echo "false")
    MARCUS_WEBB_EMAIL_FOUND=$(python3 -c "import json; d=json.load(open('/tmp/legal_case_triage_abook_check.json')); print('true' if d.get('email_found') else 'false')" 2>/dev/null || echo "false")
fi

# ============================================================
# Remaining inbox count
# ============================================================
CURRENT_INBOX_COUNT=$(grep -c "^From " "${LOCAL_MAIL_DIR}/Inbox" 2>/dev/null || echo "0")

# ============================================================
# Escape string values safely for JSON
# ============================================================
esc() { echo "$1" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip())[1:-1])" 2>/dev/null || echo "$1"; }

HARRISON_FOLDER_ESC=$(esc "$HARRISON_FOLDER")
DATAVAULT_FOLDER_ESC=$(esc "$DATAVAULT_FOLDER")
CHEN_FOLDER_ESC=$(esc "$CHEN_FOLDER")
COURT_FILTER_NAME_ESC=$(esc "$COURT_FILTER_NAME")

# ============================================================
# Write result JSON
# ============================================================
cat > /tmp/legal_case_triage_result.json << EOF
{
    "task_start": $TASK_START,
    "inbox_baseline": $INBOX_BASELINE,
    "current_inbox_count": $CURRENT_INBOX_COUNT,
    "cases_sbd_exists": $CASES_SBD_EXISTS,
    "harrison_folder": "$HARRISON_FOLDER_ESC",
    "harrison_email_count": $HARRISON_COUNT,
    "datavault_folder": "$DATAVAULT_FOLDER_ESC",
    "datavault_email_count": $DATAVAULT_COUNT,
    "chen_folder": "$CHEN_FOLDER_ESC",
    "chen_email_count": $CHEN_COUNT,
    "court_notices_exists": $COURT_NOTICES_EXISTS,
    "court_filter_exists": $COURT_FILTER_EXISTS,
    "court_filter_name": "$COURT_FILTER_NAME_ESC",
    "marcus_webb_in_abook": $MARCUS_WEBB_ADDED,
    "marcus_webb_email_in_abook": $MARCUS_WEBB_EMAIL_FOUND
}
EOF

chmod 666 /tmp/legal_case_triage_result.json
echo "Result saved:"
cat /tmp/legal_case_triage_result.json

echo ""
echo "=== Export complete ==="
