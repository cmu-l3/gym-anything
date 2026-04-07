#!/bin/bash
set -e
echo "=== Exporting create_bank_account result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Get Database State
CLIENT_ID=$(get_gardenworld_client_id)
INITIAL_BANK_COUNT=$(cat /tmp/initial_bank_count.txt 2>/dev/null || echo "0")
INITIAL_ACCT_COUNT=$(cat /tmp/initial_acct_count.txt 2>/dev/null || echo "0")

# Current counts
CURRENT_BANK_COUNT=$(idempiere_query "SELECT COUNT(*) FROM C_Bank WHERE AD_Client_ID=${CLIENT_ID:-11} AND IsActive='Y'" 2>/dev/null || echo "0")
CURRENT_ACCT_COUNT=$(idempiere_query "SELECT COUNT(*) FROM C_BankAccount WHERE AD_Client_ID=${CLIENT_ID:-11} AND IsActive='Y'" 2>/dev/null || echo "0")

# 3. Query the specific Bank Record (Chase Bank NA)
# We select relevant columns to verify
BANK_JSON=$(idempiere_query "
    SELECT row_to_json(t) FROM (
        SELECT 
            b.C_Bank_ID, 
            b.Name, 
            b.RoutingNo, 
            b.SwiftCode, 
            b.IsActive,
            EXTRACT(EPOCH FROM b.Created) as created_epoch
        FROM C_Bank b
        WHERE b.Name = 'Chase Bank NA' 
          AND b.AD_Client_ID = ${CLIENT_ID:-11}
        ORDER BY b.Created DESC LIMIT 1
    ) t
" 2>/dev/null || echo "{}")

if [ -z "$BANK_JSON" ]; then BANK_JSON="null"; fi

# 4. Query the specific Bank Account Record (Chase Payroll Operating / 8877665544)
# We need to join with C_Currency to check ISO code if possible, or just check ID.
# iDempiere stores Currency ID. Let's get the ISO code via subquery or join.
ACCT_JSON=$(idempiere_query "
    SELECT row_to_json(t) FROM (
        SELECT 
            ba.C_BankAccount_ID,
            ba.AccountNo,
            ba.Name,
            ba.BankAccountType,
            c.ISO_Code as currency_iso,
            ba.CurrentBalance,
            ba.IsActive,
            EXTRACT(EPOCH FROM ba.Created) as created_epoch,
            b.Name as bank_name
        FROM C_BankAccount ba
        JOIN C_Currency c ON ba.C_Currency_ID = c.C_Currency_ID
        JOIN C_Bank b ON ba.C_Bank_ID = b.C_Bank_ID
        WHERE ba.AccountNo = '8877665544' 
          AND ba.AD_Client_ID = ${CLIENT_ID:-11}
        ORDER BY ba.Created DESC LIMIT 1
    ) t
" 2>/dev/null || echo "{}")

if [ -z "$ACCT_JSON" ]; then ACCT_JSON="null"; fi

# 5. Check location/address if linked (optional, but good for verification)
# We check if 'New York' appears in the location linked to the bank
CITY_CHECK=$(idempiere_query "
    SELECT l.City 
    FROM C_Bank b
    JOIN C_Location l ON b.C_Location_ID = l.C_Location_ID
    WHERE b.Name = 'Chase Bank NA' 
      AND b.AD_Client_ID = ${CLIENT_ID:-11}
    ORDER BY b.Created DESC LIMIT 1
" 2>/dev/null || echo "")

# 6. Construct Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_bank_count": $INITIAL_BANK_COUNT,
    "current_bank_count": $CURRENT_BANK_COUNT,
    "initial_acct_count": $INITIAL_ACCT_COUNT,
    "current_acct_count": $CURRENT_ACCT_COUNT,
    "bank_record": $BANK_JSON,
    "account_record": $ACCT_JSON,
    "address_city": "$CITY_CHECK",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="