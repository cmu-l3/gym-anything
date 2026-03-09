#!/bin/bash
# Export script for medical_referral_triage task

echo "=== Exporting medical_referral_triage result ==="

source /workspace/scripts/task_utils.sh

close_thunderbird
sleep 3
echo "Thunderbird closed to flush configs"

take_screenshot /tmp/medical_referral_triage_end_screenshot.png

TASK_START=$(cat /tmp/medical_referral_triage_start_ts 2>/dev/null || echo "0")
INBOX_BASELINE=$(cat /tmp/medical_referral_triage_inbox_baseline 2>/dev/null || echo "9")

# ============================================================
# Check folder structure: Referrals.sbd directory
# ============================================================
REFERRALS_SBD_EXISTS="false"
if [ -d "${LOCAL_MAIL_DIR}/Referrals.sbd" ]; then
    REFERRALS_SBD_EXISTS="true"
fi

# Urgent_Referrals subfolder (accept common name variants)
URGENT_FOLDER=""
URGENT_COUNT=0
for name in Urgent_Referrals Urgent-Referrals UrgentReferrals Urgent_Cases Urgent; do
    if [ -f "${LOCAL_MAIL_DIR}/Referrals.sbd/${name}" ]; then
        URGENT_FOLDER="${name}"
        URGENT_COUNT=$(grep -c "^From " "${LOCAL_MAIL_DIR}/Referrals.sbd/${name}" 2>/dev/null || echo "0")
        break
    fi
done

# Routine_Referrals subfolder (accept common name variants)
ROUTINE_FOLDER=""
ROUTINE_COUNT=0
for name in Routine_Referrals Routine-Referrals RoutineReferrals Standard_Referrals Routine; do
    if [ -f "${LOCAL_MAIL_DIR}/Referrals.sbd/${name}" ]; then
        ROUTINE_FOLDER="${name}"
        ROUTINE_COUNT=$(grep -c "^From " "${LOCAL_MAIL_DIR}/Referrals.sbd/${name}" 2>/dev/null || echo "0")
        break
    fi
done

# ============================================================
# Check for tagged emails in the Urgent_Referrals folder
# After closing Thunderbird, X-Mozilla-Keys is written to mbox
# Thunderbird tags: $label1=Important, $label2=Work, $label3=Personal, $label4=TODO, $label5=Later
# Also checks for custom tags or any non-empty X-Mozilla-Keys
# ============================================================
TAGGED_URGENT_COUNT=0
python3 << PYEOF
import mailbox, os, json

tagged_count = 0
total_in_folder = 0

# Try all common name variants
for name in ["Urgent_Referrals", "Urgent-Referrals", "UrgentReferrals", "Urgent_Cases", "Urgent"]:
    path = os.path.expanduser(f"~ga/.thunderbird/default-release/Mail/Local Folders/Referrals.sbd/{name}")
    if os.path.exists(path) and os.path.isfile(path):
        try:
            mb = mailbox.mbox(path)
            for msg in mb:
                total_in_folder += 1
                # Check X-Mozilla-Keys for any tag keyword
                keywords = (msg.get('X-Mozilla-Keys', '') or
                           msg.get('X-Keywords', '') or
                           msg.get('Keywords', '') or '')
                if keywords.strip():
                    tagged_count += 1
            mb.close()
        except Exception as e:
            pass
        break

result = {"tagged_count": tagged_count, "total_in_folder": total_in_folder}
with open("/tmp/medical_referral_triage_tag_check.json", "w") as f:
    json.dump(result, f)
print(f"tagged={tagged_count}/{total_in_folder}")
PYEOF

if [ -f "/tmp/medical_referral_triage_tag_check.json" ]; then
    TAGGED_URGENT_COUNT=$(python3 -c "import json; d=json.load(open('/tmp/medical_referral_triage_tag_check.json')); print(d.get('tagged_count', 0))" 2>/dev/null || echo "0")
fi

# ============================================================
# Check address book for Dr. Patricia Nguyen
# ============================================================
NGUYEN_ADDED="false"
NGUYEN_EMAIL_FOUND="false"
python3 << 'PYEOF'
import sqlite3, os, json

abook_path = os.path.expanduser("~ga/.thunderbird/default-release/abook.sqlite")
result = {"found": False, "email_found": False}

if os.path.exists(abook_path):
    try:
        conn = sqlite3.connect(abook_path)
        cur = conn.cursor()
        cur.execute("SELECT value FROM properties WHERE name='PrimaryEmail' AND LOWER(value) LIKE '%nguyen%bayview%'")
        email_rows = cur.fetchall()
        if email_rows:
            result["email_found"] = True
            result["found"] = True
        cur.execute("SELECT value FROM properties WHERE name='PrimaryEmail' AND LOWER(value) = 'p.nguyen@bayviewcardiology.com'")
        exact_rows = cur.fetchall()
        if exact_rows:
            result["email_found"] = True
            result["found"] = True
        cur.execute("SELECT value FROM properties WHERE name='DisplayName' AND LOWER(value) LIKE '%nguyen%'")
        name_rows = cur.fetchall()
        if name_rows:
            result["found"] = True
        conn.close()
    except Exception as e:
        result["error"] = str(e)

with open("/tmp/medical_referral_triage_abook_check.json", "w") as f:
    json.dump(result, f)
print(json.dumps(result))
PYEOF

if [ -f "/tmp/medical_referral_triage_abook_check.json" ]; then
    NGUYEN_ADDED=$(python3 -c "import json; d=json.load(open('/tmp/medical_referral_triage_abook_check.json')); print('true' if d.get('found') else 'false')" 2>/dev/null || echo "false")
    NGUYEN_EMAIL_FOUND=$(python3 -c "import json; d=json.load(open('/tmp/medical_referral_triage_abook_check.json')); print('true' if d.get('email_found') else 'false')" 2>/dev/null || echo "false")
fi

# ============================================================
# Remaining inbox count
# ============================================================
CURRENT_INBOX_COUNT=$(grep -c "^From " "${LOCAL_MAIL_DIR}/Inbox" 2>/dev/null || echo "0")

esc() { echo "$1" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip())[1:-1])" 2>/dev/null || echo "$1"; }

URGENT_FOLDER_ESC=$(esc "$URGENT_FOLDER")
ROUTINE_FOLDER_ESC=$(esc "$ROUTINE_FOLDER")

cat > /tmp/medical_referral_triage_result.json << EOF
{
    "task_start": $TASK_START,
    "inbox_baseline": $INBOX_BASELINE,
    "current_inbox_count": $CURRENT_INBOX_COUNT,
    "referrals_sbd_exists": $REFERRALS_SBD_EXISTS,
    "urgent_folder": "$URGENT_FOLDER_ESC",
    "urgent_email_count": $URGENT_COUNT,
    "routine_folder": "$ROUTINE_FOLDER_ESC",
    "routine_email_count": $ROUTINE_COUNT,
    "tagged_urgent_count": $TAGGED_URGENT_COUNT,
    "nguyen_in_abook": $NGUYEN_ADDED,
    "nguyen_email_in_abook": $NGUYEN_EMAIL_FOUND
}
EOF

chmod 666 /tmp/medical_referral_triage_result.json
echo "Result saved:"
cat /tmp/medical_referral_triage_result.json

echo ""
echo "=== Export complete ==="
