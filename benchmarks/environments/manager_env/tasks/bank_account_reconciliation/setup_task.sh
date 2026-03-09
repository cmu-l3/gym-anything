#!/bin/bash
# Setup script for bank_account_reconciliation task in Manager.io
# Records baseline bank-account count and journal-entry count.
# Opens Firefox at the Bank Accounts module.

echo "=== Setting up bank_account_reconciliation task ==="

source /workspace/scripts/task_utils.sh

wait_for_manager 60

echo "$(date +%s)" > /tmp/manager_task_start_time

# ---------------------------------------------------------------------------
# Python: record baseline counts
# ---------------------------------------------------------------------------
python3 - << 'PYEOF'
import requests
import re
import sys

MANAGER_URL = "http://localhost:8080"

s = requests.Session()
s.post(f"{MANAGER_URL}/login",
       data={"Username": "administrator"},
       allow_redirects=True)
biz_page = s.get(f"{MANAGER_URL}/businesses").text
m = re.search(r'start\?([^"&\s]+)[^<]{0,300}Northwind Traders', biz_page)
if not m:
    m = re.search(r'start\?([^"&\s]+)', biz_page)
if not m:
    print("ERROR: Could not get business key", file=sys.stderr)
    sys.exit(1)
biz_key = m.group(1)
s.get(f"{MANAGER_URL}/start?{biz_key}", allow_redirects=True)
print(f"Business key: {biz_key}")

# Bank accounts
ba_page = s.get(f"{MANAGER_URL}/bank-and-cash-accounts?{biz_key}").text.replace('&amp;', '&')
ba_count = len(set(re.findall(
    r'/bank-or-cash-account-form\?[^&"\']+&([a-f0-9-]{36})',
    ba_page
)))
with open("/tmp/manager_task_bank_account_count", "w") as f:
    f.write(str(ba_count))
print(f"Baseline bank account count: {ba_count}")

# Journal entries
je_page = s.get(f"{MANAGER_URL}/journal-entries?{biz_key}").text.replace('&amp;', '&')
je_count = len(set(re.findall(
    r'/journal-entry-form\?[^&"\']+&([a-f0-9-]{36})',
    je_page
)))
with open("/tmp/manager_task_je_count", "w") as f:
    f.write(str(je_count))
print(f"Baseline journal entry count: {je_count}")

print("Baselines recorded.")
PYEOF

take_screenshot /tmp/bank_account_reconciliation_start.png

echo "Opening Manager.io Bank Accounts module..."
open_manager_at "bank_accounts"

echo ""
echo "=== bank_account_reconciliation task setup complete ==="
echo ""
echo "TASK: Bank account setup and reconciliation for Northwind Traders"
echo ""
echo "Step 1 — Create new bank account: 'Business Checking Account'"
echo ""
echo "Step 2 — Record bank service charges (journal entry):"
echo "  Dr Bank Charges    \$35.00"
echo "  Cr Cash on Hand    \$35.00"
echo "  Narration: Bank service charges — monthly"
echo ""
echo "Step 3 — Transfer funds (journal entry):"
echo "  Dr Business Checking Account  \$5,000.00"
echo "  Cr Cash on Hand               \$5,000.00"
echo "  Narration: Inter-account transfer to business checking"
echo ""
echo "After completing, open the Bank Accounts list to verify both accounts."
echo "Login: administrator / (empty password)"
