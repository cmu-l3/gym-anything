#!/bin/bash
# Export result for supplier_payment_run task.
# Queries Manager.io HTTP API from inside the VM and writes
# a JSON result file that verifier.py will copy out and score.

echo "=== Exporting supplier_payment_run result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/supplier_payment_run_end.png

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

def amount_near(html, name, amount, window=3000):
    idx = html.find(name)
    if idx == -1:
        return False
    chunk = html[max(0, idx - window):idx + window]
    return amount_in(chunk, amount)

s, biz_key = login()
if not s:
    result = {"error": "login_failed", "export_timestamp": __import__('datetime').datetime.now().isoformat()}
    with open("/tmp/supplier_payment_run_result.json", "w") as f:
        json.dump(result, f)
    print("ERROR: Login failed")
    sys.exit(1)

print(f"Business key: {biz_key}")

baseline_payments = read_baseline("payment_count")
baseline_debit_notes = read_baseline("debit_note_count")

try:
    payments_html = s.get(f"{MANAGER_URL}/payments?{biz_key}", timeout=15).text.replace('&amp;', '&')
    debit_notes_html = s.get(f"{MANAGER_URL}/debit-notes?{biz_key}", timeout=15).text.replace('&amp;', '&')
    purchase_invoices_html = s.get(f"{MANAGER_URL}/purchase-invoices?{biz_key}", timeout=15).text.replace('&amp;', '&')
except Exception as e:
    result = {"error": str(e)}
    with open("/tmp/supplier_payment_run_result.json", "w") as f:
        json.dump(result, f)
    sys.exit(1)

current_payments = count_links(payments_html, "payment-form")
current_debit_notes = count_links(debit_notes_html, "debit-note-form")

result = {
    "baseline_payments": baseline_payments,
    "baseline_debit_notes": baseline_debit_notes,
    "current_payment_count": current_payments,
    "current_debit_note_count": current_debit_notes,
    "new_payment_count": current_payments - baseline_payments,
    "new_debit_note_count": current_debit_notes - baseline_debit_notes,

    # Criterion 1: Debit note for Pavlova ~$200
    "has_pavlova_debit_note_200": amount_near(debit_notes_html, "Pavlova", 200.0),

    # Criterion 2: Payment to Pavlova ~$1,320 (after debit note)
    "has_pavlova_payment_1320": amount_near(payments_html, "Pavlova", 1320.0),

    # Criterion 3: Payment to Specialty Biscuits ~$2,430
    "has_specialty_biscuits_payment_2430": (
        amount_near(payments_html, "Specialty Biscuits", 2430.0)
        or amount_near(payments_html, "Specialty", 2430.0)
    ),

    # Criterion 4: Payment to Grandma Kelly's ~$1,890
    "has_grandma_kellys_payment_1890": (
        amount_near(payments_html, "Grandma Kelly", 1890.0)
        or amount_near(payments_html, "Kelly", 1890.0)
    ),

    # Criterion 5: Non-overdue invoices NOT paid
    "no_pavlova_875_payment": not amount_near(payments_html, "Pavlova", 875.0, window=5000),
    "no_exotic_1080_payment": (
        "Exotic" not in payments_html
        or not amount_near(payments_html, "Exotic", 1080.0, window=5000)
    ),

    "export_timestamp": __import__('datetime').datetime.now().isoformat()
}

print(json.dumps(result, indent=2))

with open("/tmp/supplier_payment_run_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("JSON written to /tmp/supplier_payment_run_result.json")
PYEOF

echo "=== Export Complete ==="
