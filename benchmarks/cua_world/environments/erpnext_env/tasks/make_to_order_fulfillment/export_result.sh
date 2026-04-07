#!/bin/bash
# Export script for make_to_order_fulfillment task
# Queries ERPNext API for Item, BOM, SO, Work Order, Stock Entries, DN, SINV, PE
# and writes results to /tmp/make_to_order_fulfillment_result.json

echo "=== Exporting make_to_order_fulfillment results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
take_screenshot /tmp/make_to_order_fulfillment_final.png 2>/dev/null || true

python3 << 'PYEOF'
import requests, json, sys

ERPNEXT_URL = "http://localhost:8080"
ITEM_CODE = "WP Industrial Turbine"
CUSTOMER = "Buttrey Food & Drug"

session = requests.Session()

r = session.post(f"{ERPNEXT_URL}/api/method/login",
                 json={"usr": "Administrator", "pwd": "admin"})
if r.status_code != 200:
    print(f"ERROR: Login failed {r.status_code}", file=sys.stderr)
    sys.exit(1)

# Load baseline
try:
    with open("/tmp/make_to_order_fulfillment_baseline.json") as f:
        baseline = json.load(f)
except Exception:
    baseline = {}

def api_get(doctype, filters=None, fields=None, limit=50):
    params = {"limit_page_length": limit}
    if filters:
        params["filters"] = json.dumps(filters)
    if fields:
        params["fields"] = json.dumps(fields)
    try:
        return session.get(f"{ERPNEXT_URL}/api/resource/{doctype}", params=params).json().get("data", [])
    except Exception:
        return []

def get_doc(doctype, name):
    try:
        return session.get(f"{ERPNEXT_URL}/api/resource/{doctype}/{name}").json().get("data", {})
    except Exception:
        return {}

result = {
    "baseline": baseline,
    "item": {},
    "bom": {},
    "sales_order": {},
    "work_order": {},
    "material_transfer_se": {},
    "manufacture_se": {},
    "delivery_note": {},
    "sales_invoice": {},
    "payment_entry": {},
    "outstanding_amount": None
}

# --- Item: WP Industrial Turbine ---
items = api_get("Item", [["item_code", "=", ITEM_CODE]])
if items:
    doc = get_doc("Item", items[0]["name"])
    result["item"] = {
        "name": doc.get("name"),
        "item_code": doc.get("item_code"),
        "item_name": doc.get("item_name"),
        "item_group": doc.get("item_group"),
        "is_stock_item": doc.get("is_stock_item"),
        "stock_uom": doc.get("stock_uom"),
        "standard_rate": doc.get("standard_rate", 0)
    }
    print(f"Found Item: {doc.get('name')}")
else:
    print("Item 'WP Industrial Turbine' not found")

# --- BOM for WP Industrial Turbine (submitted) ---
bom_list = api_get("BOM", [["item", "=", ITEM_CODE], ["docstatus", "=", 1]])
if bom_list:
    doc = get_doc("BOM", bom_list[0]["name"])
    bom_items = []
    for itm in doc.get("items", []):
        bom_items.append({
            "item_code": itm.get("item_code"),
            "qty": float(itm.get("qty", 0)),
            "rate": float(itm.get("rate", 0))
        })
    result["bom"] = {
        "name": doc.get("name"),
        "docstatus": doc.get("docstatus"),
        "item": doc.get("item"),
        "quantity": float(doc.get("quantity", 0)),
        "raw_material_cost": float(doc.get("raw_material_cost", 0)),
        "total_cost": float(doc.get("total_cost", 0)),
        "items": bom_items
    }
    print(f"Found BOM: {doc.get('name')} (docstatus={doc.get('docstatus')})")
else:
    print("No submitted BOM found for WP Industrial Turbine")

# --- Sales Order for Buttrey Food & Drug (submitted, with our item) ---
so_list = api_get("Sales Order",
                   [["customer", "=", CUSTOMER], ["docstatus", "=", 1]],
                   fields=["name", "customer", "grand_total", "status", "per_delivered", "per_billed"])
for so in so_list:
    doc = get_doc("Sales Order", so["name"])
    items = doc.get("items", [])
    has_turbine = any(ITEM_CODE in (i.get("item_code", "") or "") for i in items)
    if has_turbine:
        so_items = []
        for itm in items:
            so_items.append({
                "item_code": itm.get("item_code"),
                "qty": float(itm.get("qty", 0)),
                "rate": float(itm.get("rate", 0)),
                "amount": float(itm.get("amount", 0))
            })
        result["sales_order"] = {
            "name": doc.get("name"),
            "docstatus": doc.get("docstatus"),
            "customer": doc.get("customer"),
            "grand_total": float(doc.get("grand_total", 0)),
            "status": doc.get("status"),
            "items": so_items
        }
        print(f"Found Sales Order: {doc.get('name')}")
        break

# --- Work Order for WP Industrial Turbine ---
wo_list = api_get("Work Order",
                   [["production_item", "=", ITEM_CODE]],
                   fields=["name", "status", "qty", "produced_qty", "bom_no",
                            "sales_order", "docstatus"])
if wo_list:
    wo = wo_list[0]
    doc = get_doc("Work Order", wo["name"])
    result["work_order"] = {
        "name": doc.get("name"),
        "docstatus": doc.get("docstatus"),
        "status": doc.get("status"),
        "production_item": doc.get("production_item"),
        "qty": float(doc.get("qty", 0)),
        "produced_qty": float(doc.get("produced_qty", 0)),
        "bom_no": doc.get("bom_no"),
        "sales_order": doc.get("sales_order"),
        "wip_warehouse": doc.get("wip_warehouse"),
        "fg_warehouse": doc.get("fg_warehouse")
    }
    wo_name = doc.get("name")
    print(f"Found Work Order: {wo_name} (status={doc.get('status')})")

    # --- Stock Entries linked to this Work Order ---
    se_list = api_get("Stock Entry",
                       [["work_order", "=", wo_name], ["docstatus", "=", 1]],
                       fields=["name", "purpose", "stock_entry_type", "docstatus"])

    for se in se_list:
        se_doc = get_doc("Stock Entry", se["name"])
        se_info = {
            "name": se_doc.get("name"),
            "docstatus": se_doc.get("docstatus"),
            "purpose": se_doc.get("purpose", se_doc.get("stock_entry_type", "")),
            "work_order": se_doc.get("work_order"),
            "fg_completed_qty": float(se_doc.get("fg_completed_qty", 0)),
            "items": [{
                "item_code": i.get("item_code"),
                "qty": float(i.get("qty", 0)),
                "s_warehouse": i.get("s_warehouse"),
                "t_warehouse": i.get("t_warehouse")
            } for i in se_doc.get("items", [])]
        }
        purpose = se_doc.get("purpose", se_doc.get("stock_entry_type", ""))
        if "Material Transfer" in purpose:
            result["material_transfer_se"] = se_info
            print(f"Found Material Transfer SE: {se_doc.get('name')}")
        elif purpose == "Manufacture":
            result["manufacture_se"] = se_info
            print(f"Found Manufacture SE: {se_doc.get('name')}")
else:
    print("No Work Order found for WP Industrial Turbine")

# --- Delivery Note for Buttrey Food & Drug ---
dn_list = api_get("Delivery Note",
                   [["customer", "=", CUSTOMER], ["docstatus", "=", 1]],
                   fields=["name", "customer", "grand_total", "status"])
for dn in dn_list:
    doc = get_doc("Delivery Note", dn["name"])
    items = doc.get("items", [])
    has_turbine = any(ITEM_CODE in (i.get("item_code", "") or "") for i in items)
    if has_turbine:
        dn_items = [{
            "item_code": i.get("item_code"),
            "qty": float(i.get("qty", 0)),
            "against_sales_order": i.get("against_sales_order")
        } for i in items]
        result["delivery_note"] = {
            "name": doc.get("name"),
            "docstatus": doc.get("docstatus"),
            "customer": doc.get("customer"),
            "grand_total": float(doc.get("grand_total", 0)),
            "items": dn_items
        }
        print(f"Found Delivery Note: {doc.get('name')}")
        break

# --- Sales Invoice for Buttrey Food & Drug ---
si_list = api_get("Sales Invoice",
                   [["customer", "=", CUSTOMER], ["docstatus", "=", 1],
                    ["is_return", "=", 0]],
                   fields=["name", "customer", "grand_total", "outstanding_amount", "status"])
for si in si_list:
    doc = get_doc("Sales Invoice", si["name"])
    items = doc.get("items", [])
    has_turbine = any(ITEM_CODE in (i.get("item_code", "") or "") for i in items)
    if has_turbine:
        result["sales_invoice"] = {
            "name": doc.get("name"),
            "docstatus": doc.get("docstatus"),
            "customer": doc.get("customer"),
            "grand_total": float(doc.get("grand_total", 0)),
            "outstanding_amount": float(doc.get("outstanding_amount", 0)),
            "status": doc.get("status")
        }
        result["outstanding_amount"] = float(doc.get("outstanding_amount", 0))
        print(f"Found Sales Invoice: {doc.get('name')} (outstanding={doc.get('outstanding_amount')})")
        break

# --- Payment Entry for Buttrey Food & Drug ---
pe_list = api_get("Payment Entry",
                   [["party_type", "=", "Customer"],
                    ["party", "=", CUSTOMER],
                    ["docstatus", "=", 1]],
                   fields=["name", "party", "paid_amount", "received_amount",
                            "payment_type", "docstatus"])
# Find PE that references our invoice
so_name = result.get("sales_order", {}).get("name", "")
si_name = result.get("sales_invoice", {}).get("name", "")
for pe in pe_list:
    doc = get_doc("Payment Entry", pe["name"])
    # Check if PE references our invoice or is recent
    refs = doc.get("references", [])
    linked = any(r.get("reference_name") == si_name for r in refs) if si_name else True
    if linked or not result.get("payment_entry", {}).get("name"):
        result["payment_entry"] = {
            "name": doc.get("name"),
            "docstatus": doc.get("docstatus"),
            "payment_type": doc.get("payment_type"),
            "party": doc.get("party"),
            "paid_amount": float(doc.get("paid_amount", 0)),
            "received_amount": float(doc.get("received_amount", 0)),
            "references": [{"reference_doctype": r.get("reference_doctype"),
                            "reference_name": r.get("reference_name"),
                            "allocated_amount": float(r.get("allocated_amount", 0))}
                           for r in refs]
        }
        print(f"Found Payment Entry: {doc.get('name')}")
        if linked:
            break

# Recheck outstanding after PE
if si_name:
    try:
        si_fresh = get_doc("Sales Invoice", si_name)
        result["outstanding_amount"] = float(si_fresh.get("outstanding_amount", 0))
    except Exception:
        pass

with open("/tmp/make_to_order_fulfillment_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
print("\n=== Export complete: /tmp/make_to_order_fulfillment_result.json ===")
PYEOF

chmod 666 /tmp/make_to_order_fulfillment_result.json 2>/dev/null || sudo chmod 666 /tmp/make_to_order_fulfillment_result.json 2>/dev/null || true

echo "=== Export done ==="
