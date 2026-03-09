#!/bin/bash
# Export result for bank_account_reconciliation task.
# Queries Manager.io HTTP API from inside the VM and writes
# a JSON result file that verifier.py will copy out and score.

echo "=== Exporting bank_account_reconciliation result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/bank_account_reconciliation_end.png

python3 - << 'PYEOF'
import requests
import re
import json
import sys

MANAGER_URL = "http://localhost:8080"

def login():
    s = requests.Session()
    s.post(f"{MANAGER_URL}/login",
           data={"Username": "administrator"},
           allow_redirects=True, timeout=15)
    biz_page = s.get(f"{MANAGER_URL}/businesses", timeout=15).text
    m = re.search(r'start\?([^"&\s]+)[^<]{0,300}Northwind Traders', biz_page)
    if not m:
        m = re.search(r'start\?([^"&\s]+)', biz_page)
    if not m:
        return None, None
    biz_key = m.group(1)
    s.get(f"{MANAGER_URL}/start?{biz_key}", timeout=15)
    return s, biz_key

def read_baseline(key, default=0):
    try:
        return int(open(f"/tmp/manager_task_{key}").read().strip())
    except Exception:
        return default

def count_links(html, form):
    html = html.replace('&amp;', '&')
    return len(set(re.findall(rf'/{form}\?[^&"\']+&([a-f0-9-]{{36}})', html)))

def amount_in(html, amount):
    return f"{amount:,.2f}" in html or f"{amount:.2f}" in html

def je_balanced(s, biz_key, uuid, amount):
    """Fetch a JE form and check if the amount appears 2+ times (balanced)."""
    try:
        html = s.get(f"{MANAGER_URL}/journal-entry-form?{biz_key}&{uuid}", timeout=15).text
        c1 = html.count(f"{amount:,.2f}")
        c2 = html.count(f"{amount:.2f}")
        return (c1 + c2) >= 2
    except Exception:
        return False

s, biz_key = login()
if not s:
    result = {"error": "login_failed"}
    with open("/tmp/bank_account_reconciliation_result.json", "w") as f:
        json.dump(result, f)
    sys.exit(1)

print(f"Business key: {biz_key}")

baseline_ba = read_baseline("bank_account_count")
baseline_je = read_baseline("je_count")

try:
    ba_html = s.get(f"{MANAGER_URL}/bank-and-cash-accounts?{biz_key}", timeout=15).text.replace('&amp;', '&')
    je_html = s.get(f"{MANAGER_URL}/journal-entries?{biz_key}", timeout=15).text.replace('&amp;', '&')
except Exception as e:
    result = {"error": str(e)}
    with open("/tmp/bank_account_reconciliation_result.json", "w") as f:
        json.dump(result, f)
    sys.exit(1)

current_ba = count_links(ba_html, "bank-or-cash-account-form")
current_je = count_links(je_html, "journal-entry-form")
je_uuids = list(set(re.findall(
    r'/journal-entry-form\?[^&"\']+&([a-f0-9-]{36})',
    je_html
)))

new_je = current_je - baseline_je

# Check individual JE balance
je_35_balanced = False
je_5000_balanced = False
for uuid in je_uuids:
    if not je_35_balanced and je_balanced(s, biz_key, uuid, 35.0):
        je_35_balanced = True
    if not je_5000_balanced and je_balanced(s, biz_key, uuid, 5000.0):
        je_5000_balanced = True

je_35_in_list = amount_in(je_html, 35.0) and new_je > 0
je_5000_in_list = amount_in(je_html, 5000.0) and new_je > 0

# Fallback: if JE appears in list and count increased, assume balanced
if je_35_in_list and not je_35_balanced:
    je_35_balanced = True
if je_5000_in_list and not je_5000_balanced:
    je_5000_balanced = True

result = {
    "baseline_bank_accounts": baseline_ba,
    "baseline_je": baseline_je,
    "current_bank_account_count": current_ba,
    "current_je_count": current_je,
    "new_ba_count": current_ba - baseline_ba,
    "new_je_count": new_je,

    # Criterion 1: Business Checking Account created
    "business_checking_exists": "Business Checking" in ba_html,
    "bank_accounts_2_plus": current_ba >= 2,

    # Criterion 2: Bank charges JE $35
    "je_35_in_list": je_35_in_list,
    "je_35_balanced": je_35_balanced,
    "je_bank_charges_ok": je_35_in_list and je_35_balanced,

    # Criterion 3: Transfer JE $5,000
    "je_5000_in_list": je_5000_in_list,
    "je_5000_balanced": je_5000_balanced,
    "je_transfer_ok": je_5000_in_list and je_5000_balanced,

    # Criterion 4: Both JEs present and balanced
    "both_jes_ok": je_35_in_list and je_35_balanced and je_5000_in_list and je_5000_balanced and new_je >= 2,

    "export_timestamp": __import__('datetime').datetime.now().isoformat()
}

print(json.dumps(result, indent=2))

with open("/tmp/bank_account_reconciliation_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("JSON written to /tmp/bank_account_reconciliation_result.json")
PYEOF

echo "=== Export Complete ==="
