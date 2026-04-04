#!/bin/bash
# Setup script for inventory_product_cycle task in Manager.io
# Records baseline counts for inventory items, sales invoices,
# receipts, and credit notes (all should be 0 in a fresh environment).
# Opens Firefox at the Inventory Items module.

echo "=== Setting up inventory_product_cycle task ==="

source /workspace/scripts/task_utils.sh

wait_for_manager 60

echo "$(date +%s)" > /tmp/manager_task_start_time

# ---------------------------------------------------------------------------
# Python: record baseline counts for anti-gaming
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

def count_entities(page_html, form_name):
    matches = re.findall(
        rf'/{form_name}\?[^&"\']+&([a-f0-9-]{{36}})',
        page_html
    )
    return len(set(matches))

pages = {
    "inventory_item_count": (f"{MANAGER_URL}/inventory-items?{biz_key}", "inventory-item-form"),
    "sales_invoice_count": (f"{MANAGER_URL}/sales-invoices?{biz_key}", "sales-invoice-form"),
    "receipt_count": (f"{MANAGER_URL}/receipts?{biz_key}", "receipt-form"),
    "credit_note_count": (f"{MANAGER_URL}/credit-notes?{biz_key}", "credit-note-form"),
}

for key, (url, form) in pages.items():
    html = s.get(url).text.replace('&amp;', '&')
    count = count_entities(html, form)
    with open(f"/tmp/manager_task_{key}", "w") as f:
        f.write(str(count))
    print(f"Baseline {key}: {count}")

print("Baselines recorded.")
PYEOF

take_screenshot /tmp/inventory_product_cycle_start.png

echo "Opening Manager.io Inventory module..."
open_manager_at "inventory"

echo ""
echo "=== inventory_product_cycle task setup complete ==="
echo ""
echo "TASK: Launch new specialty tea product line for Northwind Traders"
echo ""
echo "Step 1 — Create 3 inventory items:"
echo "  Chai Tea          unit=box  sales=\$19.50  purchase=\$7.25"
echo "  English Breakfast unit=box  sales=\$16.00  purchase=\$5.80"
echo "  Darjeeling Reserve unit=box sales=\$34.00  purchase=\$12.00"
echo ""
echo "Step 2 — Create sales invoice for Alfreds Futterkiste:"
echo "  5 × Chai Tea @ \$19.50 = \$97.50"
echo "  10 × English Breakfast @ \$16.00 = \$160.00"
echo "  Total = \$257.50"
echo ""
echo "Step 3 — Record 50% deposit receipt: \$128.75 to Cash on Hand"
echo ""
echo "Step 4 — Issue credit note: 2 × Chai Tea @ \$19.50 = \$39.00 (damaged)"
echo ""
echo "Login: administrator / (empty password)"
