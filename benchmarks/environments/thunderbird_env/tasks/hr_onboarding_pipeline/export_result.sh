#!/bin/bash
# Export script for hr_onboarding_pipeline task

echo "=== Exporting hr_onboarding_pipeline result ==="

source /workspace/scripts/task_utils.sh

close_thunderbird
sleep 3
echo "Thunderbird closed to flush configs"

take_screenshot /tmp/hr_onboarding_pipeline_end_screenshot.png

TASK_START=$(cat /tmp/hr_onboarding_pipeline_start_ts 2>/dev/null || echo "0")
INBOX_BASELINE=$(cat /tmp/hr_onboarding_pipeline_inbox_baseline 2>/dev/null || echo "9")

# ============================================================
# Check folder structure: Onboarding_Q1.sbd directory
# ============================================================
ONBOARDING_SBD_EXISTS="false"
for parent in Onboarding_Q1 Onboarding-Q1 OnboardingQ1 Onboarding_2025 Onboarding; do
    if [ -d "${LOCAL_MAIL_DIR}/${parent}.sbd" ]; then
        ONBOARDING_SBD_EXISTS="true"
        ONBOARDING_PARENT="${parent}"
        break
    fi
done
ONBOARDING_PARENT="${ONBOARDING_PARENT:-Onboarding_Q1}"

# Documents_Pending subfolder
DOCS_FOLDER=""
DOCS_COUNT=0
for name in Documents_Pending Documents-Pending DocumentsPending Pending_Docs Outstanding_Documents Docs_Pending; do
    if [ -f "${LOCAL_MAIL_DIR}/${ONBOARDING_PARENT}.sbd/${name}" ]; then
        DOCS_FOLDER="${name}"
        DOCS_COUNT=$(grep -c "^From " "${LOCAL_MAIL_DIR}/${ONBOARDING_PARENT}.sbd/${name}" 2>/dev/null || echo "0")
        break
    fi
done

# IT_Requests subfolder
IT_FOLDER=""
IT_COUNT=0
for name in IT_Requests IT-Requests ITRequests IT_Setup IT_Provisioning; do
    if [ -f "${LOCAL_MAIL_DIR}/${ONBOARDING_PARENT}.sbd/${name}" ]; then
        IT_FOLDER="${name}"
        IT_COUNT=$(grep -c "^From " "${LOCAL_MAIL_DIR}/${ONBOARDING_PARENT}.sbd/${name}" 2>/dev/null || echo "0")
        break
    fi
done

# ============================================================
# Check Drafts for a reply to Marcus Thompson
# ============================================================
python3 << 'PYEOF'
import mailbox, os, json

drafts_path = os.path.expanduser("~ga/.thunderbird/default-release/Mail/Local Folders/Drafts")
result = {"to_marcus": False, "draft_has_keywords": False}

if os.path.exists(drafts_path) and os.path.isfile(drafts_path):
    try:
        mb = mailbox.mbox(drafts_path)
        keywords = ["johnson", "kim", "chen", "monday", "start", "march 17", "march17"]
        for msg in mb:
            to_header = (msg.get('To', '') or '').lower()
            cc_header = (msg.get('Cc', '') or '').lower()
            if 'm.thompson' in to_header or 'techventure-it.com' in to_header or \
               'm.thompson' in cc_header or 'techventure-it.com' in cc_header:
                result["to_marcus"] = True
                # Check body for relevant keywords
                body = ''
                if msg.is_multipart():
                    for part in msg.walk():
                        if part.get_content_type() == 'text/plain':
                            try:
                                body += (part.get_payload(decode=True) or b'').decode('utf-8', errors='replace')
                            except Exception:
                                pass
                else:
                    try:
                        body = (msg.get_payload(decode=True) or b'').decode('utf-8', errors='replace')
                    except Exception:
                        body = str(msg.get_payload() or '')
                body_lower = body.lower()
                subject_lower = (msg.get('Subject', '') or '').lower()
                combined = body_lower + ' ' + subject_lower
                if any(kw in combined for kw in keywords):
                    result["draft_has_keywords"] = True
        mb.close()
    except Exception as e:
        result["error"] = str(e)

with open("/tmp/hr_onboarding_pipeline_draft_check.json", "w") as f:
    json.dump(result, f)
print(json.dumps(result))
PYEOF

DRAFT_TO_MARCUS="false"
DRAFT_HAS_KEYWORDS="false"
if [ -f "/tmp/hr_onboarding_pipeline_draft_check.json" ]; then
    DRAFT_TO_MARCUS=$(python3 -c "import json; d=json.load(open('/tmp/hr_onboarding_pipeline_draft_check.json')); print('true' if d.get('to_marcus') else 'false')" 2>/dev/null || echo "false")
    DRAFT_HAS_KEYWORDS=$(python3 -c "import json; d=json.load(open('/tmp/hr_onboarding_pipeline_draft_check.json')); print('true' if d.get('draft_has_keywords') else 'false')" 2>/dev/null || echo "false")
fi

# ============================================================
# Check address book for Marcus Thompson
# ============================================================
MARCUS_ADDED="false"
MARCUS_EMAIL_FOUND="false"
python3 << 'PYEOF'
import sqlite3, os, json

abook_path = os.path.expanduser("~ga/.thunderbird/default-release/abook.sqlite")
result = {"found": False, "email_found": False}

if os.path.exists(abook_path):
    try:
        conn = sqlite3.connect(abook_path)
        cur = conn.cursor()
        cur.execute("SELECT value FROM properties WHERE name='PrimaryEmail' AND LOWER(value) LIKE '%m.thompson%techventure%'")
        email_rows = cur.fetchall()
        if email_rows:
            result["email_found"] = True
            result["found"] = True
        # Also check exact email
        cur.execute("SELECT value FROM properties WHERE name='PrimaryEmail' AND LOWER(value) = 'm.thompson@techventure-it.com'")
        exact_rows = cur.fetchall()
        if exact_rows:
            result["email_found"] = True
            result["found"] = True
        cur.execute("SELECT value FROM properties WHERE name='DisplayName' AND LOWER(value) LIKE '%thompson%'")
        name_rows = cur.fetchall()
        if name_rows:
            result["found"] = True
        conn.close()
    except Exception as e:
        result["error"] = str(e)

with open("/tmp/hr_onboarding_pipeline_abook_check.json", "w") as f:
    json.dump(result, f)
print(json.dumps(result))
PYEOF

if [ -f "/tmp/hr_onboarding_pipeline_abook_check.json" ]; then
    MARCUS_ADDED=$(python3 -c "import json; d=json.load(open('/tmp/hr_onboarding_pipeline_abook_check.json')); print('true' if d.get('found') else 'false')" 2>/dev/null || echo "false")
    MARCUS_EMAIL_FOUND=$(python3 -c "import json; d=json.load(open('/tmp/hr_onboarding_pipeline_abook_check.json')); print('true' if d.get('email_found') else 'false')" 2>/dev/null || echo "false")
fi

# ============================================================
# Remaining inbox count
# ============================================================
CURRENT_INBOX_COUNT=$(grep -c "^From " "${LOCAL_MAIL_DIR}/Inbox" 2>/dev/null || echo "0")

# ============================================================
# Escape values for JSON
# ============================================================
esc() { echo "$1" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip())[1:-1])" 2>/dev/null || echo "$1"; }

DOCS_FOLDER_ESC=$(esc "$DOCS_FOLDER")
IT_FOLDER_ESC=$(esc "$IT_FOLDER")

# ============================================================
# Write result JSON
# ============================================================
cat > /tmp/hr_onboarding_pipeline_result.json << EOF
{
    "task_start": $TASK_START,
    "inbox_baseline": $INBOX_BASELINE,
    "current_inbox_count": $CURRENT_INBOX_COUNT,
    "onboarding_sbd_exists": $ONBOARDING_SBD_EXISTS,
    "docs_folder": "$DOCS_FOLDER_ESC",
    "docs_email_count": $DOCS_COUNT,
    "it_folder": "$IT_FOLDER_ESC",
    "it_email_count": $IT_COUNT,
    "draft_to_marcus": $DRAFT_TO_MARCUS,
    "draft_has_keywords": $DRAFT_HAS_KEYWORDS,
    "marcus_thompson_in_abook": $MARCUS_ADDED,
    "marcus_thompson_email_in_abook": $MARCUS_EMAIL_FOUND
}
EOF

chmod 666 /tmp/hr_onboarding_pipeline_result.json
echo "Result saved:"
cat /tmp/hr_onboarding_pipeline_result.json

echo ""
echo "=== Export complete ==="
