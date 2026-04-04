#!/bin/bash
# Export result for inventory_product_cycle task.
# Queries Manager.io HTTP API from inside the VM and writes
# a JSON result file that verifier.py will copy out and score.

echo "=== Exporting inventory_product_cycle result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/inventory_product_cycle_end.png

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
    result = {"error": "login_failed"}
    with open("/tmp/inventory_product_cycle_result.json", "w") as f:
        json.dump(result, f)
    sys.exit(1)

print(f"Business key: {biz_key}")

baseline_items = read_baseline("inventory_item_count")
baseline_invoices = read_baseline("sales_invoice_count")
baseline_receipts = read_baseline("receipt_count")
baseline_cn = read_baseline("credit_note_count")

try:
    items_html = s.get(f"{MANAGER_URL}/inventory-items?{biz_key}", timeout=15).text.replace('&amp;', '&')
    invoices_html = s.get(f"{MANAGER_URL}/sales-invoices?{biz_key}", timeout=15).text.replace('&amp;', '&')
    receipts_html = s.get(f"{MANAGER_URL}/receipts?{biz_key}", timeout=15).text.replace('&amp;', '&')
    cn_html = s.get(f"{MANAGER_URL}/credit-notes?{biz_key}", timeout=15).text.replace('&amp;', '&')
except Exception as e:
    result = {"error": str(e)}
    with open("/tmp/inventory_product_cycle_result.json", "w") as f:
        json.dump(result, f)
    sys.exit(1)

current_items = count_links(items_html, "inventory-item-form")
current_invoices = count_links(invoices_html, "sales-invoice-form")
current_receipts = count_links(receipts_html, "receipt-form")
current_cn = count_links(cn_html, "credit-note-form")

result = {
    "baseline_items": baseline_items,
    "baseline_invoices": baseline_invoices,
    "baseline_receipts": baseline_receipts,
    "baseline_cn": baseline_cn,
    "current_item_count": current_items,
    "current_invoice_count": current_invoices,
    "current_receipt_count": current_receipts,
    "current_cn_count": current_cn,
    "new_item_count": current_items - baseline_items,
    "new_invoice_count": current_invoices - baseline_invoices,
    "new_receipt_count": current_receipts - baseline_receipts,
    "new_cn_count": current_cn - baseline_cn,

    # Criterion 1: Chai Tea with price ~$19.50
    "has_chai_tea_19_50": amount_near(items_html, "Chai Tea", 19.50),
    "chai_tea_exists": "Chai Tea" in items_html,

    # Criterion 2: English Breakfast Tea with price ~$16.00
    "has_english_breakfast_16_00": (
        amount_near(items_html, "English Breakfast", 16.00)
        or amount_near(items_html, "English Breakfast Tea", 16.00)
    ),
    "english_breakfast_exists": "English Breakfast" in items_html,

    # Criterion 3: Darjeeling Reserve with price ~$34.00
    "has_darjeeling_34_00": amount_near(items_html, "Darjeeling", 34.00),
    "darjeeling_exists": "Darjeeling" in items_html,

    # Criterion 4: Sales invoice for Alfreds ~$257.50
    "has_invoice_alfreds_257_50": amount_near(invoices_html, "Alfreds", 257.50),

    # Criterion 5: Receipt ~$128.75
    "has_receipt_128_75": amount_in(receipts_html, 128.75),

    # Criterion 6: Credit note ~$39.00
    "has_credit_note_39_00": (
        amount_near(cn_html, "Alfreds", 39.00) or amount_in(cn_html, 39.00)
    ),

    "export_timestamp": __import__('datetime').datetime.now().isoformat()
}

print(json.dumps(result, indent=2))

with open("/tmp/inventory_product_cycle_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("JSON written to /tmp/inventory_product_cycle_result.json")
PYEOF

echo "=== Export Complete ==="
