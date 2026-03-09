#!/bin/bash
# Export script for financial_audit_prep task

echo "=== Exporting financial_audit_prep result ==="

source /workspace/scripts/task_utils.sh

# Kill Thunderbird so it flushes drafts and address book to disk
close_thunderbird
sleep 3
echo "Thunderbird closed to flush configs"

take_screenshot /tmp/financial_audit_prep_end_screenshot.png

TASK_START=$(cat /tmp/financial_audit_prep_start_ts 2>/dev/null || echo "0")
INBOX_BASELINE=$(cat /tmp/financial_audit_prep_inbox_baseline 2>/dev/null || echo "9")

# ============================================================
# Check folder structure: Regulatory.sbd directory
# ============================================================
REGULATORY_SBD_EXISTS="false"
if [ -d "${LOCAL_MAIL_DIR}/Regulatory.sbd" ]; then
    REGULATORY_SBD_EXISTS="true"
fi

# SEC_Examination subfolder (accept common name variants)
SEC_FOLDER=""
SEC_COUNT=0
for name in SEC_Examination SEC-Examination SECExamination SEC_Exam SEC; do
    if [ -f "${LOCAL_MAIL_DIR}/Regulatory.sbd/${name}" ]; then
        SEC_FOLDER="${name}"
        SEC_COUNT=$(grep -c "^From " "${LOCAL_MAIL_DIR}/Regulatory.sbd/${name}" 2>/dev/null || echo "0")
        break
    fi
done

# FINRA_Review subfolder (accept common name variants)
FINRA_FOLDER=""
FINRA_COUNT=0
for name in FINRA_Review FINRA-Review FINRAReview FINRA_Exam FINRA; do
    if [ -f "${LOCAL_MAIL_DIR}/Regulatory.sbd/${name}" ]; then
        FINRA_FOLDER="${name}"
        FINRA_COUNT=$(grep -c "^From " "${LOCAL_MAIL_DIR}/Regulatory.sbd/${name}" 2>/dev/null || echo "0")
        break
    fi
done

# ============================================================
# Check address book for Jennifer Kowalski / jkowalski@sec.gov
# ============================================================
JENNIFER_ADDED="false"
JENNIFER_EMAIL_FOUND="false"
python3 << 'PYEOF'
import sqlite3, os, json

abook_path = os.path.expanduser("~ga/.thunderbird/default-release/abook.sqlite")
result = {"found": False, "email_found": False}

if os.path.exists(abook_path):
    try:
        conn = sqlite3.connect(abook_path)
        cur = conn.cursor()
        cur.execute("SELECT value FROM properties WHERE name='PrimaryEmail' AND LOWER(value) LIKE '%jkowalski%'")
        email_rows = cur.fetchall()
        if email_rows:
            result["email_found"] = True
            result["found"] = True
        cur.execute("SELECT value FROM properties WHERE name='DisplayName' AND LOWER(value) LIKE '%kowalski%'")
        name_rows = cur.fetchall()
        if name_rows:
            result["found"] = True
        conn.close()
    except Exception as e:
        result["error"] = str(e)

with open("/tmp/financial_audit_prep_abook_check.json", "w") as f:
    json.dump(result, f)
print(json.dumps(result))
PYEOF

if [ -f "/tmp/financial_audit_prep_abook_check.json" ]; then
    JENNIFER_ADDED=$(python3 -c "import json; d=json.load(open('/tmp/financial_audit_prep_abook_check.json')); print('true' if d.get('found') else 'false')" 2>/dev/null || echo "false")
    JENNIFER_EMAIL_FOUND=$(python3 -c "import json; d=json.load(open('/tmp/financial_audit_prep_abook_check.json')); print('true' if d.get('email_found') else 'false')" 2>/dev/null || echo "false")
fi

# ============================================================
# Check Drafts folder for a draft reply to Jennifer Kowalski
# Drafts live in Local Folders/Drafts (local account)
# ============================================================
DRAFT_TO_KOWALSKI="false"
DRAFT_HAS_KEYWORDS="false"
python3 << 'PYEOF'
import mailbox, os, json

result = {"draft_found": False, "to_kowalski": False, "has_keywords": False}

drafts_path = os.path.expanduser("~ga/.thunderbird/default-release/Mail/Local Folders/Drafts")

if os.path.exists(drafts_path) and os.path.isfile(drafts_path):
    try:
        mb = mailbox.mbox(drafts_path)
        for msg in mb:
            to_header = (msg.get('To', '') + ' ' + msg.get('to', '')).lower()
            if 'jkowalski' in to_header or 'sec.gov' in to_header:
                result["draft_found"] = True
                result["to_kowalski"] = True
                # Check body for relevant examination-acknowledgment keywords
                body_text = ""
                if msg.is_multipart():
                    for part in msg.walk():
                        if part.get_content_type() == 'text/plain':
                            try:
                                body_text += part.get_payload(decode=True).decode('utf-8', errors='ignore')
                            except Exception:
                                pass
                else:
                    payload = msg.get_payload()
                    if isinstance(payload, bytes):
                        body_text = payload.decode('utf-8', errors='ignore')
                    elif isinstance(payload, str):
                        body_text = payload
                body_lower = body_text.lower()
                kw_hits = sum(1 for kw in ['compliance', 'document', 'examination', 'manual', 'client', 'code', 'review', 'receipt', 'acknowledge'] if kw in body_lower)
                if kw_hits >= 1:
                    result["has_keywords"] = True
        mb.close()
    except Exception as e:
        result["error"] = str(e)

with open("/tmp/financial_audit_prep_draft_check.json", "w") as f:
    json.dump(result, f)
print(json.dumps(result))
PYEOF

if [ -f "/tmp/financial_audit_prep_draft_check.json" ]; then
    DRAFT_TO_KOWALSKI=$(python3 -c "import json; d=json.load(open('/tmp/financial_audit_prep_draft_check.json')); print('true' if d.get('to_kowalski') else 'false')" 2>/dev/null || echo "false")
    DRAFT_HAS_KEYWORDS=$(python3 -c "import json; d=json.load(open('/tmp/financial_audit_prep_draft_check.json')); print('true' if d.get('has_keywords') else 'false')" 2>/dev/null || echo "false")
fi

# ============================================================
# Remaining inbox count
# ============================================================
CURRENT_INBOX_COUNT=$(grep -c "^From " "${LOCAL_MAIL_DIR}/Inbox" 2>/dev/null || echo "0")

# ============================================================
# Escape string values safely for JSON
# ============================================================
esc() { echo "$1" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip())[1:-1])" 2>/dev/null || echo "$1"; }

SEC_FOLDER_ESC=$(esc "$SEC_FOLDER")
FINRA_FOLDER_ESC=$(esc "$FINRA_FOLDER")

# ============================================================
# Write result JSON
# ============================================================
cat > /tmp/financial_audit_prep_result.json << EOF
{
    "task_start": $TASK_START,
    "inbox_baseline": $INBOX_BASELINE,
    "current_inbox_count": $CURRENT_INBOX_COUNT,
    "regulatory_sbd_exists": $REGULATORY_SBD_EXISTS,
    "sec_folder": "$SEC_FOLDER_ESC",
    "sec_email_count": $SEC_COUNT,
    "finra_folder": "$FINRA_FOLDER_ESC",
    "finra_email_count": $FINRA_COUNT,
    "jennifer_kowalski_in_abook": $JENNIFER_ADDED,
    "jennifer_kowalski_email_in_abook": $JENNIFER_EMAIL_FOUND,
    "draft_to_kowalski": $DRAFT_TO_KOWALSKI,
    "draft_has_keywords": $DRAFT_HAS_KEYWORDS
}
EOF

chmod 666 /tmp/financial_audit_prep_result.json
echo "Result saved:"
cat /tmp/financial_audit_prep_result.json

echo ""
echo "=== Export complete ==="
