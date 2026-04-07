#!/bin/bash
# Export script for litigation_email_triage task
# Collects all evidence into a JSON file for the verifier

echo "=== Exporting litigation_email_triage result ==="

source /workspace/scripts/task_utils.sh

# Kill Thunderbird so it flushes filter rules, drafts, and address book to disk
close_thunderbird
sleep 3
echo "Thunderbird closed to flush configs"

take_screenshot /tmp/litigation_email_triage_end_screenshot.png

TASK_START=$(cat /tmp/litigation_email_triage_start_ts 2>/dev/null || echo "0")
INBOX_BASELINE=$(cat /tmp/litigation_email_triage_inbox_baseline 2>/dev/null || echo "15")

# ============================================================
# Check folder structure: Meridian_v_Apex.sbd directory
# ============================================================
PARENT_SBD_EXISTS="false"
PARENT_NAME=""
for parent in Meridian_v_Apex Meridian-v-Apex MeridianApex Meridian_Apex Meridian; do
    if [ -d "${LOCAL_MAIL_DIR}/${parent}.sbd" ]; then
        PARENT_SBD_EXISTS="true"
        PARENT_NAME="${parent}"
        break
    fi
done
PARENT_NAME="${PARENT_NAME:-Meridian_v_Apex}"

# Pleadings subfolder (accept common name variants)
PLEADINGS_FOLDER=""
PLEADINGS_COUNT=0
for name in Pleadings Pleading Court_Filings CourtFilings Motions; do
    if [ -f "${LOCAL_MAIL_DIR}/${PARENT_NAME}.sbd/${name}" ]; then
        PLEADINGS_FOLDER="${name}"
        PLEADINGS_COUNT=$(grep -c "^From " "${LOCAL_MAIL_DIR}/${PARENT_NAME}.sbd/${name}" 2>/dev/null || echo "0")
        break
    fi
done

# Discovery subfolder (accept common name variants)
DISCOVERY_FOLDER=""
DISCOVERY_COUNT=0
for name in Discovery Discoveries Document_Requests Depositions; do
    if [ -f "${LOCAL_MAIL_DIR}/${PARENT_NAME}.sbd/${name}" ]; then
        DISCOVERY_FOLDER="${name}"
        DISCOVERY_COUNT=$(grep -c "^From " "${LOCAL_MAIL_DIR}/${PARENT_NAME}.sbd/${name}" 2>/dev/null || echo "0")
        break
    fi
done

# Billing subfolder (accept common name variants)
BILLING_FOLDER=""
BILLING_COUNT=0
for name in Billing Invoices Costs Billing_Invoices Finance; do
    if [ -f "${LOCAL_MAIL_DIR}/${PARENT_NAME}.sbd/${name}" ]; then
        BILLING_FOLDER="${name}"
        BILLING_COUNT=$(grep -c "^From " "${LOCAL_MAIL_DIR}/${PARENT_NAME}.sbd/${name}" 2>/dev/null || echo "0")
        break
    fi
done

# ============================================================
# Check message filters — base64 encode full content
# ============================================================
FILTER_FILE="${THUNDERBIRD_PROFILE}/Mail/Local Folders/msgFilterRules.dat"
FILTER_EXISTS="false"
FILTER_CONTENT_B64=""
DISCOVERY_FILTER_EXISTS="false"
BILLING_FILTER_EXISTS="false"

if [ -f "$FILTER_FILE" ]; then
    FILTER_EXISTS="true"
    FILTER_CONTENT_B64=$(base64 -w 0 "$FILTER_FILE" 2>/dev/null || echo "")

    # Check for Discovery Alerts filter (OR conditions with Interrogatory/Deposition/Document Request)
    if grep -qi "Interrogatory\|Deposition\|Document.Request" "$FILTER_FILE" 2>/dev/null; then
        DISCOVERY_FILTER_EXISTS="true"
    fi

    # Check for Billing Auto-File filter (legalcosts + URGENT)
    if grep -qi "legalcosts" "$FILTER_FILE" 2>/dev/null; then
        if grep -qi "URGENT" "$FILTER_FILE" 2>/dev/null; then
            BILLING_FILTER_EXISTS="true"
        fi
    fi
fi

# ============================================================
# Check address book for Rebecca Torres
# ============================================================
TORRES_ADDED="false"
TORRES_EMAIL_FOUND="false"
TORRES_PHONE_FOUND="false"
TORRES_FIRM_FOUND="false"
python3 << 'PYEOF'
import sqlite3, os, json

abook_path = os.path.expanduser("~ga/.thunderbird/default-release/abook.sqlite")
result = {"found": False, "email_found": False, "phone_found": False, "firm_found": False}

if os.path.exists(abook_path):
    try:
        conn = sqlite3.connect(abook_path)
        cur = conn.cursor()
        # Check by email
        cur.execute("SELECT card FROM properties WHERE name='PrimaryEmail' AND LOWER(value) LIKE '%torres%kline%'")
        email_cards = [r[0] for r in cur.fetchall()]
        cur.execute("SELECT card FROM properties WHERE name='PrimaryEmail' AND LOWER(value) = 'r.torres@kline-harris.com'")
        email_cards += [r[0] for r in cur.fetchall()]
        email_cards = list(set(email_cards))

        if email_cards:
            result["email_found"] = True
            result["found"] = True
            # Check for phone number on any matching card
            for card_id in email_cards:
                cur.execute("SELECT name, value FROM properties WHERE card=?", (card_id,))
                props = {r[0]: r[1] for r in cur.fetchall()}
                # Check phone fields
                for phone_field in ['WorkPhone', 'HomePhone', 'CellularNumber', 'FaxNumber']:
                    if props.get(phone_field, ''):
                        if '555' in props[phone_field] or '234' in props[phone_field]:
                            result["phone_found"] = True
                # Check company/org
                for org_field in ['Company', 'Organization']:
                    if props.get(org_field, ''):
                        if 'kline' in props[org_field].lower() or 'harris' in props[org_field].lower():
                            result["firm_found"] = True
        else:
            # Check by name as fallback
            cur.execute("SELECT value FROM properties WHERE name='DisplayName' AND LOWER(value) LIKE '%torres%'")
            name_rows = cur.fetchall()
            if name_rows:
                result["found"] = True

        conn.close()
    except Exception as e:
        result["error"] = str(e)

with open("/tmp/litigation_email_triage_abook_check.json", "w") as f:
    json.dump(result, f)
print(json.dumps(result))
PYEOF

if [ -f "/tmp/litigation_email_triage_abook_check.json" ]; then
    TORRES_ADDED=$(python3 -c "import json; d=json.load(open('/tmp/litigation_email_triage_abook_check.json')); print('true' if d.get('found') else 'false')" 2>/dev/null || echo "false")
    TORRES_EMAIL_FOUND=$(python3 -c "import json; d=json.load(open('/tmp/litigation_email_triage_abook_check.json')); print('true' if d.get('email_found') else 'false')" 2>/dev/null || echo "false")
    TORRES_PHONE_FOUND=$(python3 -c "import json; d=json.load(open('/tmp/litigation_email_triage_abook_check.json')); print('true' if d.get('phone_found') else 'false')" 2>/dev/null || echo "false")
    TORRES_FIRM_FOUND=$(python3 -c "import json; d=json.load(open('/tmp/litigation_email_triage_abook_check.json')); print('true' if d.get('firm_found') else 'false')" 2>/dev/null || echo "false")
fi

# ============================================================
# Check Drafts folder for a reply to Rebecca Torres
# ============================================================
DRAFT_TO_TORRES="false"
DRAFT_HAS_KEYWORDS="false"
python3 << 'PYEOF'
import mailbox, os, json

result = {"draft_found": False, "to_torres": False, "has_keywords": False}

drafts_path = os.path.expanduser("~ga/.thunderbird/default-release/Mail/Local Folders/Drafts")

if os.path.exists(drafts_path) and os.path.isfile(drafts_path):
    try:
        mb = mailbox.mbox(drafts_path)
        for msg in mb:
            to_header = (msg.get('To', '') + ' ' + msg.get('to', '')).lower()
            if 'torres' in to_header or 'kline-harris' in to_header or 'r.torres' in to_header:
                result["draft_found"] = True
                result["to_torres"] = True
                # Check body for relevant keywords
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
                kw_hits = sum(1 for kw in [
                    'acknowledg', 'receipt', 'document', 'produc', 'march',
                    'deadline', 'board', 'minutes', 'respond', 'request',
                    'supplemental', 'confirm'
                ] if kw in body_lower)
                if kw_hits >= 1:
                    result["has_keywords"] = True
        mb.close()
    except Exception as e:
        result["error"] = str(e)

with open("/tmp/litigation_email_triage_draft_check.json", "w") as f:
    json.dump(result, f)
print(json.dumps(result))
PYEOF

if [ -f "/tmp/litigation_email_triage_draft_check.json" ]; then
    DRAFT_TO_TORRES=$(python3 -c "import json; d=json.load(open('/tmp/litigation_email_triage_draft_check.json')); print('true' if d.get('to_torres') else 'false')" 2>/dev/null || echo "false")
    DRAFT_HAS_KEYWORDS=$(python3 -c "import json; d=json.load(open('/tmp/litigation_email_triage_draft_check.json')); print('true' if d.get('has_keywords') else 'false')" 2>/dev/null || echo "false")
fi

# ============================================================
# Remaining inbox count
# ============================================================
CURRENT_INBOX_COUNT=$(grep -c "^From " "${LOCAL_MAIL_DIR}/Inbox" 2>/dev/null || echo "0")

# ============================================================
# Escape string values safely for JSON
# ============================================================
esc() { echo "$1" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip())[1:-1])" 2>/dev/null || echo "$1"; }

PLEADINGS_FOLDER_ESC=$(esc "$PLEADINGS_FOLDER")
DISCOVERY_FOLDER_ESC=$(esc "$DISCOVERY_FOLDER")
BILLING_FOLDER_ESC=$(esc "$BILLING_FOLDER")

# ============================================================
# Write result JSON
# ============================================================
cat > /tmp/litigation_email_triage_result.json << EOF
{
    "task_start": $TASK_START,
    "inbox_baseline": $INBOX_BASELINE,
    "current_inbox_count": $CURRENT_INBOX_COUNT,
    "parent_sbd_exists": $PARENT_SBD_EXISTS,
    "pleadings_folder": "$PLEADINGS_FOLDER_ESC",
    "pleadings_email_count": $PLEADINGS_COUNT,
    "discovery_folder": "$DISCOVERY_FOLDER_ESC",
    "discovery_email_count": $DISCOVERY_COUNT,
    "billing_folder": "$BILLING_FOLDER_ESC",
    "billing_email_count": $BILLING_COUNT,
    "filter_exists": $FILTER_EXISTS,
    "filter_content_b64": "$FILTER_CONTENT_B64",
    "discovery_filter_exists": $DISCOVERY_FILTER_EXISTS,
    "billing_filter_exists": $BILLING_FILTER_EXISTS,
    "torres_in_abook": $TORRES_ADDED,
    "torres_email_in_abook": $TORRES_EMAIL_FOUND,
    "torres_phone_in_abook": $TORRES_PHONE_FOUND,
    "torres_firm_in_abook": $TORRES_FIRM_FOUND,
    "draft_to_torres": $DRAFT_TO_TORRES,
    "draft_has_keywords": $DRAFT_HAS_KEYWORDS
}
EOF

chmod 666 /tmp/litigation_email_triage_result.json
echo "Result saved:"
cat /tmp/litigation_email_triage_result.json

echo ""
echo "=== Export complete ==="
