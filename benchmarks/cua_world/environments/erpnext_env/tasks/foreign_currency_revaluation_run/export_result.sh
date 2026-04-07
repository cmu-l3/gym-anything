#!/bin/bash
# Export script for foreign_currency_revaluation_run task
echo "=== Exporting foreign_currency_revaluation_run results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

take_screenshot /tmp/foreign_currency_revaluation_final.png 2>/dev/null || true

python3 << 'PYEOF'
import requests, json, sys

ERPNEXT_URL = "http://localhost:8080"
session = requests.Session()

r = session.post(f"{ERPNEXT_URL}/api/method/login",
                 json={"usr": "Administrator", "pwd": "admin"})
if r.status_code != 200:
    print(f"ERROR: Login failed {r.status_code}", file=sys.stderr)
    sys.exit(1)

try:
    with open("/tmp/foreign_currency_revaluation_baseline.json") as f:
        baseline = json.load(f)
except Exception:
    baseline = {"revaluations": [], "journal_entries": []}

def api_get(doctype, filters=None, fields=None):
    params = {"limit_page_length": 50}
    if filters:
        params["filters"] = json.dumps(filters)
    if fields:
        params["fields"] = json.dumps(fields)
    return session.get(f"{ERPNEXT_URL}/api/resource/{doctype}", params=params).json().get("data", [])

def get_doc(doctype, name):
    return session.get(f"{ERPNEXT_URL}/api/resource/{doctype}/{name}").json().get("data", {})

revaluations = api_get("Exchange Rate Revaluation", fields=["name", "docstatus", "creation"])
new_revaluations = [r for r in revaluations if r["name"] not in baseline.get("revaluations", [])]

rev_details = []
for r in new_revaluations:
    doc = get_doc("Exchange Rate Revaluation", r["name"])
    accounts = doc.get("accounts") or []
    rev_details.append({
        "name": r["name"],
        "docstatus": r.get("docstatus"),
        "creation": r.get("creation"),
        "accounts": [{
            "account": a.get("account"),
            "new_exchange_rate": a.get("new_exchange_rate"),
            "unrealized_exchange_gain_loss": a.get("unrealized_exchange_gain_loss")
        } for a in accounts]
    })

jes = api_get("Journal Entry", [["voucher_type", "=", "Exchange Rate Revaluation"]], fields=["name", "docstatus", "creation"])
new_jes = [je for je in jes if je["name"] not in baseline.get("journal_entries", [])]

je_details = []
for je in new_jes:
    doc = get_doc("Journal Entry", je["name"])
    accounts = doc.get("accounts") or []
    je_details.append({
        "name": je["name"],
        "docstatus": je.get("docstatus"),
        "creation": je.get("creation"),
        "accounts": [{
            "account": a.get("account"),
            "debit": a.get("debit", 0),
            "credit": a.get("credit", 0)
        } for a in accounts]
    })

result = {
    "revaluations": rev_details,
    "journal_entries": je_details
}

with open("/tmp/foreign_currency_revaluation_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
print("\n=== Export complete: /tmp/foreign_currency_revaluation_result.json ===")
PYEOF

echo "=== Export done ==="