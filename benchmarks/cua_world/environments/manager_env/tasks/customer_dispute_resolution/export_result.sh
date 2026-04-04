#!/bin/bash
# Export result for customer_dispute_resolution task.
# Queries Manager.io HTTP API from inside the VM and writes
# a JSON result file that verifier.py will copy out and score.

echo "=== Exporting customer_dispute_resolution result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/customer_dispute_resolution_end.png

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

def invoice_cleared(invoices_html, ref):
    idx = invoices_html.find(ref)
    if idx == -1:
        return False
    chunk = invoices_html[idx:idx + 400]
    return "0.00" in chunk

s, biz_key = login()
if not s:
    result = {"error": "login_failed", "export_timestamp": __import__('datetime').datetime.now().isoformat()}
    with open("/tmp/customer_dispute_resolution_result.json", "w") as f:
        json.dump(result, f)
    sys.exit(1)

print(f"Business key: {biz_key}")

baseline_cn = read_baseline("credit_note_count")
baseline_receipts = read_baseline("receipt_count")

try:
    cn_html = s.get(f"{MANAGER_URL}/credit-notes?{biz_key}", timeout=15).text.replace('&amp;', '&')
    invoices_html = s.get(f"{MANAGER_URL}/sales-invoices?{biz_key}", timeout=15).text.replace('&amp;', '&')
    receipts_html = s.get(f"{MANAGER_URL}/receipts?{biz_key}", timeout=15).text.replace('&amp;', '&')
except Exception as e:
    result = {"error": str(e)}
    with open("/tmp/customer_dispute_resolution_result.json", "w") as f:
        json.dump(result, f)
    sys.exit(1)

current_cn = count_links(cn_html, "credit-note-form")
current_receipts = count_links(receipts_html, "receipt-form")

result = {
    "baseline_credit_notes": baseline_cn,
    "baseline_receipts": baseline_receipts,
    "current_credit_note_count": current_cn,
    "current_receipt_count": current_receipts,
    "new_credit_note_count": current_cn - baseline_cn,
    "new_receipt_count": current_receipts - baseline_receipts,

    # Criterion 1: Full credit note for Alfreds ~$600
    "has_alfreds_credit_note_600": amount_near(cn_html, "Alfreds", 600.0),

    # Criterion 2: Partial credit note for Alfreds ~$60
    "has_alfreds_credit_note_60": amount_near(cn_html, "Alfreds", 60.0),

    # Criterion 3: Ernst receipt allocated (INV-E002 cleared)
    "inv_e002_exists": "INV-E002" in invoices_html,
    "inv_e002_cleared": invoice_cleared(invoices_html, "INV-E002"),
    "ernst_receipt_450_exists": amount_near(receipts_html, "Ernst", 450.0),

    "export_timestamp": __import__('datetime').datetime.now().isoformat()
}

print(json.dumps(result, indent=2))

with open("/tmp/customer_dispute_resolution_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("JSON written to /tmp/customer_dispute_resolution_result.json")
PYEOF

echo "=== Export Complete ==="
