#!/bin/bash
# Export script for procurement_vendor_setup task

echo "=== Exporting procurement_vendor_setup result ==="

source /workspace/scripts/task_utils.sh

close_thunderbird
sleep 3
echo "Thunderbird closed to flush configs"

take_screenshot /tmp/procurement_vendor_setup_end_screenshot.png

TASK_START=$(cat /tmp/procurement_vendor_setup_start_ts 2>/dev/null || echo "0")
INBOX_BASELINE=$(cat /tmp/procurement_vendor_setup_inbox_baseline 2>/dev/null || echo "9")

# ============================================================
# Check folder structure: Vendors.sbd directory
# ============================================================
VENDORS_SBD_EXISTS="false"
for parent in Vendors Vendor_Emails Vendor; do
    if [ -d "${LOCAL_MAIL_DIR}/${parent}.sbd" ]; then
        VENDORS_SBD_EXISTS="true"
        VENDORS_PARENT="${parent}"
        break
    fi
done
VENDORS_PARENT="${VENDORS_PARENT:-Vendors}"

# Active_RFQs subfolder
RFQ_FOLDER=""
RFQ_COUNT=0
for name in Active_RFQs Active-RFQs ActiveRFQs RFQs Active_Quotes Open_RFQs; do
    if [ -f "${LOCAL_MAIL_DIR}/${VENDORS_PARENT}.sbd/${name}" ]; then
        RFQ_FOLDER="${name}"
        RFQ_COUNT=$(grep -c "^From " "${LOCAL_MAIL_DIR}/${VENDORS_PARENT}.sbd/${name}" 2>/dev/null || echo "0")
        break
    fi
done

# Contract_Review subfolder
CONTRACT_FOLDER=""
CONTRACT_COUNT=0
for name in Contract_Review Contract-Review ContractReview Contracts_Pending Legal_Review; do
    if [ -f "${LOCAL_MAIL_DIR}/${VENDORS_PARENT}.sbd/${name}" ]; then
        CONTRACT_FOLDER="${name}"
        CONTRACT_COUNT=$(grep -c "^From " "${LOCAL_MAIL_DIR}/${VENDORS_PARENT}.sbd/${name}" 2>/dev/null || echo "0")
        break
    fi
done

# ============================================================
# Check message filter for @globalsupplyco.com routing
# ============================================================
FILTER_FILE="${THUNDERBIRD_PROFILE}/Mail/Local Folders/msgFilterRules.dat"
GSC_FILTER_EXISTS="false"

if [ -f "$FILTER_FILE" ]; then
    if grep -qi "globalsupplyco\.com\|globalsupply\|@globalsupply" "$FILTER_FILE" 2>/dev/null; then
        GSC_FILTER_EXISTS="true"
    fi
fi

# ============================================================
# Check address book for Sandra Chen / s.chen@globalsupplyco.com
# ============================================================
SANDRA_ADDED="false"
SANDRA_EMAIL_FOUND="false"
python3 << 'PYEOF'
import sqlite3, os, json

abook_path = os.path.expanduser("~ga/.thunderbird/default-release/abook.sqlite")
result = {"found": False, "email_found": False}

if os.path.exists(abook_path):
    try:
        conn = sqlite3.connect(abook_path)
        cur = conn.cursor()
        cur.execute("SELECT value FROM properties WHERE name='PrimaryEmail' AND LOWER(value) LIKE '%chen%globalsupply%'")
        email_rows = cur.fetchall()
        if email_rows:
            result["email_found"] = True
            result["found"] = True
        cur.execute("SELECT value FROM properties WHERE name='PrimaryEmail' AND LOWER(value) = 's.chen@globalsupplyco.com'")
        exact_rows = cur.fetchall()
        if exact_rows:
            result["email_found"] = True
            result["found"] = True
        cur.execute("SELECT value FROM properties WHERE name='DisplayName' AND LOWER(value) LIKE '%sandra%chen%'")
        name_rows = cur.fetchall()
        if name_rows:
            result["found"] = True
        conn.close()
    except Exception as e:
        result["error"] = str(e)

with open("/tmp/procurement_vendor_setup_abook_check.json", "w") as f:
    json.dump(result, f)
print(json.dumps(result))
PYEOF

if [ -f "/tmp/procurement_vendor_setup_abook_check.json" ]; then
    SANDRA_ADDED=$(python3 -c "import json; d=json.load(open('/tmp/procurement_vendor_setup_abook_check.json')); print('true' if d.get('found') else 'false')" 2>/dev/null || echo "false")
    SANDRA_EMAIL_FOUND=$(python3 -c "import json; d=json.load(open('/tmp/procurement_vendor_setup_abook_check.json')); print('true' if d.get('email_found') else 'false')" 2>/dev/null || echo "false")
fi

# ============================================================
# Remaining inbox count
# ============================================================
CURRENT_INBOX_COUNT=$(grep -c "^From " "${LOCAL_MAIL_DIR}/Inbox" 2>/dev/null || echo "0")

# ============================================================
# Escape values for JSON
# ============================================================
esc() { echo "$1" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip())[1:-1])" 2>/dev/null || echo "$1"; }

RFQ_FOLDER_ESC=$(esc "$RFQ_FOLDER")
CONTRACT_FOLDER_ESC=$(esc "$CONTRACT_FOLDER")

# ============================================================
# Write result JSON
# ============================================================
cat > /tmp/procurement_vendor_setup_result.json << EOF
{
    "task_start": $TASK_START,
    "inbox_baseline": $INBOX_BASELINE,
    "current_inbox_count": $CURRENT_INBOX_COUNT,
    "vendors_sbd_exists": $VENDORS_SBD_EXISTS,
    "rfq_folder": "$RFQ_FOLDER_ESC",
    "rfq_email_count": $RFQ_COUNT,
    "contract_folder": "$CONTRACT_FOLDER_ESC",
    "contract_email_count": $CONTRACT_COUNT,
    "gsc_filter_exists": $GSC_FILTER_EXISTS,
    "sandra_chen_in_abook": $SANDRA_ADDED,
    "sandra_chen_email_in_abook": $SANDRA_EMAIL_FOUND
}
EOF

chmod 666 /tmp/procurement_vendor_setup_result.json
echo "Result saved:"
cat /tmp/procurement_vendor_setup_result.json

echo ""
echo "=== Export complete ==="
