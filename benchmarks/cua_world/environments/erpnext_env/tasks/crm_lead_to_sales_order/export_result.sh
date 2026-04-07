#!/bin/bash
# Export script for crm_lead_to_sales_order task
# Queries ERPNext for the complete Lead -> Opportunity -> Quotation -> Sales Order pipeline
# and writes results to a JSON file for the verifier.

echo "=== Exporting crm_lead_to_sales_order results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Capture final screenshot for visual evidence
take_screenshot /tmp/crm_lead_to_sales_order_final.png 2>/dev/null || true

# Read the start time
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

python3 << PYEOF
import requests, json, sys
from datetime import datetime
import calendar

ERPNEXT_URL = "http://localhost:8080"
session = requests.Session()

# Login
r = session.post(f"{ERPNEXT_URL}/api/method/login",
                 json={"usr": "Administrator", "pwd": "admin"})
if r.status_code != 200:
    print(f"ERROR: Login failed {r.status_code}", file=sys.stderr)
    sys.exit(1)

def api_get(doctype, filters=None, fields=None, limit=10):
    params = {"limit_page_length": limit, "order_by": "creation desc"}
    if filters:
        params["filters"] = json.dumps(filters)
    if fields:
        params["fields"] = json.dumps(fields)
    resp = session.get(f"{ERPNEXT_URL}/api/resource/{doctype}", params=params)
    if resp.status_code == 200:
        return resp.json().get("data", [])
    return []

def get_doc(doctype, name):
    resp = session.get(f"{ERPNEXT_URL}/api/resource/{doctype}/{name}")
    if resp.status_code == 200:
        return resp.json().get("data", {})
    return {}

def dt_to_epoch(dt_str):
    if not dt_str:
        return 0
    try:
        # ERPNext format: "2024-03-11 10:20:30.123456"
        dt_obj = datetime.strptime(dt_str.split(".")[0], "%Y-%m-%d %H:%M:%S")
        return calendar.timegm(dt_obj.timetuple())
    except:
        return 0

# --- 1. Find Lead ---
leads = api_get("Lead", 
                [["company_name", "like", "%Greenfield%"]], 
                ["name", "lead_name", "company_name", "email_id", "source", "territory", "creation"])
lead_doc = leads[0] if leads else {}
if lead_doc:
    lead_doc["creation_epoch"] = dt_to_epoch(lead_doc.get("creation"))

# --- 2. Find Opportunity ---
opp_doc = {}
opp_items = []
if lead_doc:
    opps = api_get("Opportunity", 
                   [["party_name", "=", lead_doc["name"]]], 
                   ["name", "opportunity_from", "party_name", "opportunity_type", "creation"])
    if not opps:
        # Fallback: search by party_name string matching company name
        opps = api_get("Opportunity", 
                       [["party_name", "like", "%Greenfield%"]], 
                       ["name", "opportunity_from", "party_name", "opportunity_type", "creation"])
    if opps:
        opp_doc = opps[0]
        opp_doc["creation_epoch"] = dt_to_epoch(opp_doc.get("creation"))
        full_opp = get_doc("Opportunity", opp_doc["name"])
        for item in full_opp.get("items", []):
            opp_items.append({
                "item_code": item.get("item_code"),
                "qty": item.get("qty", 0)
            })

# --- 3. Find Quotation ---
quot_doc = {}
quot_items = []
quots = api_get("Quotation", 
                [["party_name", "like", "%Greenfield%"]], 
                ["name", "quotation_to", "party_name", "opportunity", "grand_total", "docstatus", "creation"])
if quots:
    quot_doc = quots[0]
    quot_doc["creation_epoch"] = dt_to_epoch(quot_doc.get("creation"))
    full_quot = get_doc("Quotation", quot_doc["name"])
    for item in full_quot.get("items", []):
        quot_items.append({
            "item_code": item.get("item_code"),
            "qty": item.get("qty", 0),
            "rate": item.get("rate", 0),
            "amount": item.get("amount", 0)
        })

# --- 4. Find Sales Order ---
so_doc = {}
so_items = []
sos = api_get("Sales Order", 
              [["customer_name", "like", "%Greenfield%"]], 
              ["name", "customer", "customer_name", "grand_total", "docstatus", "creation"])
if sos:
    so_doc = sos[0]
    so_doc["creation_epoch"] = dt_to_epoch(so_doc.get("creation"))
    full_so = get_doc("Sales Order", so_doc["name"])
    for item in full_so.get("items", []):
        so_items.append({
            "item_code": item.get("item_code"),
            "qty": item.get("qty", 0),
            "rate": item.get("rate", 0),
            "amount": item.get("amount", 0)
        })

result = {
    "task_start_time": int("${TASK_START_TIME}"),
    "lead": lead_doc,
    "opportunity": opp_doc,
    "opportunity_items": opp_items,
    "quotation": quot_doc,
    "quotation_items": quot_items,
    "sales_order": so_doc,
    "sales_order_items": so_items
}

with open("/tmp/crm_lead_to_sales_order_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
print("\n=== Export complete: /tmp/crm_lead_to_sales_order_result.json ===")
PYEOF