#!/bin/bash
# Setup script for bank_reconciliation task
# Creates a Bank, Bank Account, GL Account, 5 Payment Entries, and 5 Bank Transactions.

set -e
echo "=== Setting up bank_reconciliation task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

echo "Waiting for ERPNext..."
wait_for_erpnext 300

python3 << 'PYEOF'
import requests, json, sys, time
from datetime import date

ERPNEXT_URL = "http://localhost:8080"
session = requests.Session()

r = session.post(f"{ERPNEXT_URL}/api/method/login",
                 json={"usr": "Administrator", "pwd": "admin"})
if r.status_code != 200:
    print(f"ERROR: Login failed {r.status_code}", file=sys.stderr)
    sys.exit(1)
print("Logged in successfully")

def api_get(doctype, filters=None, fields=None, limit=10):
    params = {"limit_page_length": limit}
    if filters:
        params["filters"] = json.dumps(filters)
    if fields:
        params["fields"] = json.dumps(fields)
    return session.get(f"{ERPNEXT_URL}/api/resource/{doctype}", params=params).json().get("data", [])

def get_or_create(doctype, filters, values):
    existing = api_get(doctype, filters)
    if existing:
        return existing[0]["name"]
    r = session.post(f"{ERPNEXT_URL}/api/resource/{doctype}", json=values)
    if r.status_code in (200, 201):
        return r.json().get("data", {}).get("name")
    print(f"ERROR creating {doctype}: {r.text}", file=sys.stderr)
    return None

def safe_submit(doctype, name):
    time.sleep(0.5)
    r_fetch = session.get(f"{ERPNEXT_URL}/api/resource/{doctype}/{name}")
    doc = r_fetch.json().get("data", {"doctype": doctype, "name": name})
    doc["docstatus"] = 1
    return session.post(f"{ERPNEXT_URL}/api/method/frappe.client.submit", json={"doc": doc})

# --- Wait for master data ---
print("Waiting for ERPNext master data...")
for attempt in range(60):
    if api_get("Company", [["company_name", "=", "Wind Power LLC"]]):
        break
    time.sleep(10)

# --- 1. Create GL Account ---
cash_accs = api_get("Account", [["company", "=", "Wind Power LLC"], ["account_type", "in", ["Bank", "Cash"]]])
parent_acc = cash_accs[0]["parent_account"] if cash_accs else "Current Assets - WP"

gl_acc_name = get_or_create("Account", [["account_name", "=", "First National Bank"]], {
    "account_name": "First National Bank",
    "parent_account": parent_acc,
    "company": "Wind Power LLC",
    "account_type": "Bank",
    "is_group": 0
})
print(f"GL Account: {gl_acc_name}")

# --- 2. Create Bank ---
bank_name = get_or_create("Bank", [["bank_name", "=", "First National Bank"]], {
    "bank_name": "First National Bank"
})
print(f"Bank: {bank_name}")

# --- 3. Create Bank Account ---
bank_acc_name = get_or_create("Bank Account", [["account_name", "=", "First National Bank"]], {
    "account_name": "First National Bank",
    "is_company_account": 1,
    "company": "Wind Power LLC",
    "account": gl_acc_name,
    "bank": bank_name
})
print(f"Bank Account: {bank_acc_name}")

# --- 4. Define Transactions ---
transactions = [
    {"ptype": "Receive", "party_type": "Customer", "party": "Chi-Chis", "amount": 420.0, "ref": "CHK-10042", "desc": "DEPOSIT CHK#10042 CHI-CHIS RESTAURANT"},
    {"ptype": "Pay", "party_type": "Supplier", "party": "Eagle Hardware", "amount": 250.0, "ref": "ACH-88471", "desc": "ACH DEBIT EAGLE HARDWARE SUPPLY CO"},
    {"ptype": "Receive", "party_type": "Customer", "party": "Consumers and Consumers Express", "amount": 280.0, "ref": "WIR-30055", "desc": "WIRE TRANSFER IN CONSUMERS EXPRESS"},
    {"ptype": "Pay", "party_type": "Supplier", "party": "HomeBase", "amount": 150.0, "ref": "CHK-2847", "desc": "CHECK 2847 HOMEBASE INC"},
    {"ptype": "Receive", "party_type": "Customer", "party": "Nelson Enterprise", "amount": 84.0, "ref": "EFT-60219", "desc": "EFT DEPOSIT NELSON ENT"}
]

receivable_acc = api_get("Account", [["account_type", "=", "Receivable"], ["company", "=", "Wind Power LLC"]])[0]["name"]
payable_acc = api_get("Account", [["account_type", "=", "Payable"], ["company", "=", "Wind Power LLC"]])[0]["name"]

# --- 5. Generate Payment Entries and Bank Transactions ---
for i, t in enumerate(transactions):
    # Ensure Party exists
    get_or_create(t["party_type"], [[f"{t['party_type'].lower()}_name", "=", t["party"]]], {
        f"{t['party_type'].lower()}_name": t["party"],
        f"{t['party_type'].lower()}_type": "Company",
        f"{t['party_type'].lower()}_group": f"All {t['party_type']} Groups"
    })

    # Check if BT already exists for this exact setup run
    existing_bt = api_get("Bank Transaction", [["description", "=", t["desc"]]])
    if not existing_bt:
        is_recv = (t["ptype"] == "Receive")
        
        # Payment Entry
        pe = {
            "doctype": "Payment Entry",
            "payment_type": t["ptype"],
            "party_type": t["party_type"],
            "party": t["party"],
            "paid_from": receivable_acc if is_recv else gl_acc_name,
            "paid_to": gl_acc_name if is_recv else payable_acc,
            "paid_amount": t["amount"],
            "received_amount": t["amount"],
            "reference_no": t["ref"],
            "reference_date": str(date.today()),
        }
        r = session.post(f"{ERPNEXT_URL}/api/resource/Payment Entry", json=pe)
        if r.status_code in (200, 201):
            pe_name = r.json()["data"]["name"]
            safe_submit("Payment Entry", pe_name)
            print(f"Created PE: {pe_name} for {t['party']}")
            
        # Bank Transaction
        bt = {
            "doctype": "Bank Transaction",
            "bank_account": bank_acc_name,
            "date": str(date.today()),
            "deposit": t["amount"] if is_recv else 0.0,
            "withdrawal": 0.0 if is_recv else t["amount"],
            "description": t["desc"],
            "status": "Unreconciled"
        }
        session.post(f"{ERPNEXT_URL}/api/resource/Bank Transaction", json=bt)
        print(f"Created BT: {t['desc']}")

# Save baseline
with open("/tmp/bank_recon_baseline.json", "w") as f:
    json.dump({"bank_acc_name": bank_acc_name, "initial_reconciled": 0}, f)
PYEOF

echo "Navigating to Bank Reconciliation Tool..."
DISPLAY=:1 xdotool key ctrl+l
sleep 0.5
DISPLAY=:1 xdotool type --clearmodifiers "http://localhost:8080/app/bank-reconciliation-tool"
sleep 0.5
DISPLAY=:1 xdotool key Return
sleep 5

take_screenshot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="