#!/bin/bash
# Setup script for supplier_payment_run task in Manager.io
# Creates additional suppliers (Pavlova Ltd, Specialty Biscuits Ltd,
# Grandma Kelly's Homestead) and seeds overdue/recent purchase invoices.
# Records baseline payment and debit-note counts for anti-gaming.

echo "=== Setting up supplier_payment_run task ==="

source /workspace/scripts/task_utils.sh

wait_for_manager 60

echo "$(date +%s)" > /tmp/manager_task_start_time

# ---------------------------------------------------------------------------
# Python: seed suppliers + purchase invoices with age-based dates
# ---------------------------------------------------------------------------
python3 - << 'PYEOF'
import requests
import re
import json
import sys
from datetime import date, timedelta

MANAGER_URL = "http://localhost:8080"

def login_and_get_bizkey():
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
        return None, None
    biz_key = m.group(1)
    s.get(f"{MANAGER_URL}/start?{biz_key}", allow_redirects=True)
    return s, biz_key

def get_field_name(s, biz_key, endpoint="supplier-form"):
    form_page = s.get(f"{MANAGER_URL}/{endpoint}?{biz_key}").text
    m = re.search(r'name="([a-f0-9-]{36})" value="\{\}"', form_page)
    return m.group(1) if m else None

_UUID_RE = r'[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}'

def post_entity(s, biz_key, endpoint, field_name, data_dict):
    """POST entity form. Returns (status_code, uuid_or_None)."""
    resp = s.post(
        f"{MANAGER_URL}/{endpoint}?{biz_key}",
        files={field_name: (None, json.dumps(data_dict))},
        allow_redirects=True
    )
    # Manager.io redirects to the entity's edit page after creation.
    # The redirect URL contains the new entity's UUID.
    m = re.search(_UUID_RE, resp.url)
    uuid = m.group(0) if m else None
    return resp.status_code, uuid

def get_entity_uuid(s, list_url, entity_name):
    """Find entity UUID by name from the list page HTML."""
    page = s.get(list_url).text.replace('&amp;', '&')
    idx = page.find(entity_name)
    if idx == -1:
        return None
    surrounding = page[max(0, idx - 1200):idx + 400]
    # Find any UUID in the surrounding text
    m = re.search(_UUID_RE, surrounding)
    return m.group(0) if m else None

def count_entity_links(s, list_url, form_name):
    """Count entity links of a given form type on a list page."""
    page = s.get(list_url).text.replace('&amp;', '&')
    matches = re.findall(
        rf'/{form_name}\?[^&"\']+&([a-f0-9-]{{36}})',
        page
    )
    return len(set(matches))

s, biz_key = login_and_get_bizkey()
if not s:
    sys.exit(1)

print(f"Business key: {biz_key}")

field_name = get_field_name(s, biz_key)
if not field_name:
    print("ERROR: Could not get form field name", file=sys.stderr)
    sys.exit(1)
print(f"Form field: {field_name}")

# -----------------------------------------------------------------------
# Create additional suppliers (Exotic Liquids already exists from setup_data.sh)
# -----------------------------------------------------------------------
suppliers_to_create = [
    {
        "Name": "Pavlova, Ltd.",
        "BillingAddress": "74 Rose St.\nMoonie Ponds\nMelbourne 3000\nAustralia",
        "Email": "orders@pavlova.com.au"
    },
    {
        "Name": "Specialty Biscuits, Ltd.",
        "BillingAddress": "29 King's Way\nManchester M14 GSD\nUK",
        "Email": "sales@specialtybiscuits.co.uk"
    },
    {
        "Name": "Grandma Kelly's Homestead",
        "BillingAddress": "707 Oxford Rd.\nAnn Arbor MI 48104\nUSA",
        "Email": "info@grandmakellys.com"
    }
]

# Create suppliers and capture UUID from redirect URL
supplier_uuids = {}
for sup in suppliers_to_create:
    code, uuid = post_entity(s, biz_key, "supplier-form", field_name, sup)
    supplier_uuids[sup['Name']] = uuid
    print(f"  Created supplier {sup['Name']}: HTTP {code}, UUID: {uuid}")

# Get UUID for Exotic Liquids (pre-existing, created by setup_data.sh)
suppliers_list_url = f"{MANAGER_URL}/suppliers?{biz_key}"
exotic_uuid = get_entity_uuid(s, suppliers_list_url, "Exotic Liquids")
# Fallback: also try from list page for newly created suppliers if redirect didn't give UUID
pavlova_uuid = supplier_uuids.get("Pavlova, Ltd.") or get_entity_uuid(s, suppliers_list_url, "Pavlova")
specialty_uuid = supplier_uuids.get("Specialty Biscuits, Ltd.") or get_entity_uuid(s, suppliers_list_url, "Specialty Biscuits")
grandma_uuid = supplier_uuids.get("Grandma Kelly's Homestead") or get_entity_uuid(s, suppliers_list_url, "Grandma Kelly")

print(f"  Pavlova UUID: {pavlova_uuid}")
print(f"  Specialty Biscuits UUID: {specialty_uuid}")
print(f"  Grandma Kelly's UUID: {grandma_uuid}")
print(f"  Exotic Liquids UUID: {exotic_uuid}")

# -----------------------------------------------------------------------
# Create purchase invoices with age-based dates
# -----------------------------------------------------------------------
today = date.today()

invoices = [
    {
        "ref": "PI-PAV-001",
        "supplier_uuid": pavlova_uuid,
        "supplier_name": "Pavlova, Ltd.",
        "days_ago": 40,
        "amount": 1520.00,
        "description": "Pavlova, Alice Mutton — batch order"
    },
    {
        "ref": "PI-PAV-002",
        "supplier_uuid": pavlova_uuid,
        "supplier_name": "Pavlova, Ltd.",
        "days_ago": 12,
        "amount": 875.00,
        "description": "Pavlova — supplemental order"
    },
    {
        "ref": "PI-SB-001",
        "supplier_uuid": specialty_uuid,
        "supplier_name": "Specialty Biscuits, Ltd.",
        "days_ago": 35,
        "amount": 2430.00,
        "description": "Teatime Chocolate Biscuits — bulk order"
    },
    {
        "ref": "PI-GK-001",
        "supplier_uuid": grandma_uuid,
        "supplier_name": "Grandma Kelly's Homestead",
        "days_ago": 45,
        "amount": 1890.00,
        "description": "Boysenberry Spread, Cranberry Sauce — seasonal"
    },
    {
        "ref": "PI-EL-001",
        "supplier_uuid": exotic_uuid,
        "supplier_name": "Exotic Liquids",
        "days_ago": 5,
        "amount": 1080.00,
        "description": "Chai Tea, Aniseed Syrup — standard order"
    },
]

for inv in invoices:
    if not inv["supplier_uuid"]:
        print(f"  SKIP {inv['ref']}: no supplier UUID for {inv['supplier_name']}")
        continue
    inv_date = (today - timedelta(days=inv["days_ago"])).isoformat()
    inv_data = {
        "Date": inv_date,
        "Reference": inv["ref"],
        "Supplier": inv["supplier_uuid"],
        "Lines": [
            {
                "Description": inv["description"],
                "Qty": 1.0,
                "UnitPrice": inv["amount"]
            }
        ]
    }
    code = post_entity(s, biz_key, "purchase-invoice-form", field_name, inv_data)
    print(f"  Created {inv['ref']} ({inv['supplier_name']}, {inv_date}, ${inv['amount']}): HTTP {code}")

# -----------------------------------------------------------------------
# Record baseline counts for anti-gaming
# -----------------------------------------------------------------------
payments_page = s.get(f"{MANAGER_URL}/payments?{biz_key}").text.replace('&amp;', '&')
payment_count = len(set(re.findall(
    r'/payment-form\?[^&"\']+&([a-f0-9-]{36})', payments_page
)))
with open("/tmp/manager_task_payment_count", "w") as f:
    f.write(str(payment_count))
print(f"Baseline payment count: {payment_count}")

debit_notes_page = s.get(f"{MANAGER_URL}/debit-notes?{biz_key}").text.replace('&amp;', '&')
debit_note_count = len(set(re.findall(
    r'/debit-note-form\?[^&"\']+&([a-f0-9-]{36})', debit_notes_page
)))
with open("/tmp/manager_task_debit_note_count", "w") as f:
    f.write(str(debit_note_count))
print(f"Baseline debit note count: {debit_note_count}")

print("Setup complete.")
PYEOF

take_screenshot /tmp/supplier_payment_run_start.png

echo "Opening Manager.io Purchase Invoices module..."
open_manager_at "purchase_invoices"

echo ""
echo "=== supplier_payment_run task setup complete ==="
echo ""
echo "TASK: Process overdue supplier payments for Northwind Traders"
echo ""
echo "Outstanding purchase invoices (agent must discover):"
echo "  PI-PAV-001  Pavlova, Ltd.           40 days old  \$1,520.00  OVERDUE"
echo "  PI-PAV-002  Pavlova, Ltd.           12 days old  \$875.00    NOT overdue"
echo "  PI-SB-001   Specialty Biscuits      35 days old  \$2,430.00  OVERDUE"
echo "  PI-GK-001   Grandma Kelly's         45 days old  \$1,890.00  OVERDUE"
echo "  PI-EL-001   Exotic Liquids           5 days old  \$1,080.00  NOT overdue"
echo ""
echo "  Pavlova credit: \$200.00 (damaged batch) — record debit note first"
echo "  Pavlova net payment: \$1,520 - \$200 = \$1,320.00"
echo ""
echo "Login: administrator / (empty password)"
