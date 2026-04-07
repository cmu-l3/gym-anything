#!/bin/bash
# Setup script for foreign_currency_revaluation_run task

set -e
echo "=== Setting up foreign_currency_revaluation_run ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "Waiting for ERPNext..."
wait_for_erpnext 300

python3 << 'PYEOF'
import requests, json, sys, time
from datetime import date

ERPNEXT_URL = "http://localhost:8080"
session = requests.Session()

# Login
r = session.post(f"{ERPNEXT_URL}/api/method/login",
                 json={"usr": "Administrator", "pwd": "admin"})
if r.status_code != 200:
    print(f"ERROR: Login failed {r.status_code}", file=sys.stderr)
    sys.exit(1)

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
        return r.json()["data"]["name"]
    print(f"ERROR creating {doctype}: {r.text}", file=sys.stderr)
    return None

def safe_submit(doctype, name):
    time.sleep(1)
    r_fetch = session.get(f"{ERPNEXT_URL}/api/resource/{doctype}/{name}")
    doc = r_fetch.json().get("data", {"doctype": doctype, "name": name})
    r_sub = session.post(f"{ERPNEXT_URL}/api/method/frappe.client.submit", json={"doc": doc})
    return r_sub

# Wait for master data
print("Waiting for ERPNext master data...")
master_ready = False
for attempt in range(60):
    try:
        companies = api_get("Company", [["company_name", "=", "Wind Power LLC"]])
        if companies:
            master_ready = True
            break
    except Exception:
        pass
    time.sleep(5)

if not master_ready:
    sys.exit(1)

# Ensure EUR currency exists
existing_eur = api_get("Currency", [["name", "=", "EUR"]])
if not existing_eur:
    session.post(f"{ERPNEXT_URL}/api/resource/Currency", json={
        "currency_name": "EUR",
        "symbol": "€",
        "fraction": "Cent"
    })

# Parent accounts
income_groups = api_get("Account", [["company", "=", "Wind Power LLC"], ["is_group", "=", 1], ["root_type", "=", "Income"]])
parent_income = income_groups[0]["name"] if income_groups else "Income - WP"

asset_groups = api_get("Account", [["company", "=", "Wind Power LLC"], ["is_group", "=", 1], ["account_type", "=", "Bank"]])
if asset_groups:
    parent_bank = asset_groups[0]["name"]
else:
    curr_assets = api_get("Account", [["company", "=", "Wind Power LLC"], ["is_group", "=", 1], ["account_name", "like", "%Current Asset%"]])
    parent_bank = curr_assets[0]["name"] if curr_assets else "Application of Funds (Assets) - WP"

# Accounts
unrealized_acc = get_or_create("Account",
    [["account_name", "=", "Unrealized Exchange Gain/Loss"]],
    {"account_name": "Unrealized Exchange Gain/Loss",
     "parent_account": parent_income,
     "company": "Wind Power LLC",
     "is_group": 0}
)

eur_bank = get_or_create("Account",
    [["account_name", "=", "EUR Bank"]],
    {"account_name": "EUR Bank",
     "parent_account": parent_bank,
     "company": "Wind Power LLC",
     "is_group": 0,
     "account_type": "Bank",
     "account_currency": "EUR"}
)

# Set company default
session.put(f"{ERPNEXT_URL}/api/resource/Company/Wind Power LLC", json={
    "unrealized_exchange_gain_loss_account": unrealized_acc
})

# Cash account
cash_accs = api_get("Account", [["company", "=", "Wind Power LLC"], ["account_type", "=", "Cash"], ["is_group", "=", 0]])
cash_acc = cash_accs[0]["name"] if cash_accs else None
if not cash_acc:
    cash_accs = api_get("Account", [["company", "=", "Wind Power LLC"], ["account_name", "like", "Cash%"], ["is_group", "=", 0]])
    cash_acc = cash_accs[0]["name"] if cash_accs else None

# Funding JE
funding_je = api_get("Journal Entry", [["user_remark", "=", "Initial EUR Funding"]])
if not funding_je:
    je_doc = {
        "doctype": "Journal Entry",
        "company": "Wind Power LLC",
        "voucher_type": "Journal Entry",
        "posting_date": str(date.today()),
        "user_remark": "Initial EUR Funding",
        "accounts": [
            {
                "account": eur_bank,
                "account_currency": "EUR",
                "exchange_rate": 1.05,
                "debit_in_account_currency": 10000.0,
                "debit": 10500.0
            },
            {
                "account": cash_acc,
                "account_currency": "USD",
                "exchange_rate": 1.0,
                "credit_in_account_currency": 10500.0,
                "credit": 10500.0
            }
        ]
    }
    r = session.post(f"{ERPNEXT_URL}/api/resource/Journal Entry", json=je_doc)
    if r.status_code in (200, 201):
        je_name = r.json()["data"]["name"]
        safe_submit("Journal Entry", je_name)
        print(f"Funded EUR Bank with {je_name}")

# Baseline to track existing Revaluations and JEs
revaluations = api_get("Exchange Rate Revaluation", fields=["name"])
jes = api_get("Journal Entry", [["voucher_type", "=", "Exchange Rate Revaluation"]], fields=["name"])

baseline = {
    "revaluations": [r["name"] for r in revaluations],
    "journal_entries": [j["name"] for j in jes]
}
with open("/tmp/foreign_currency_revaluation_baseline.json", "w") as f:
    json.dump(baseline, f)

print("Setup Complete")
PYEOF

date +%s > /tmp/task_start_time.txt

echo "Navigating to Exchange Rate Revaluation..."
ensure_firefox_at "http://localhost:8080/app/exchange-rate-revaluation"

take_screenshot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="