#!/bin/bash
# Export script for sales_order_driven_project_template task
# Queries ERPNext for Project Templates, Sales Orders, Projects, and Tasks.
# Writes results to /tmp/sales_order_project_result.json.

echo "=== Exporting sales_order_driven_project_template results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
take_screenshot /tmp/sales_order_project_final.png 2>/dev/null || true

python3 << 'PYEOF'
import requests, json, sys, os

ERPNEXT_URL = "http://localhost:8080"
session = requests.Session()

r = session.post(f"{ERPNEXT_URL}/api/method/login",
                 json={"usr": "Administrator", "pwd": "admin"})
if r.status_code != 200:
    print(f"ERROR: Login failed {r.status_code}", file=sys.stderr)
    sys.exit(1)

# Load baseline and timestamps
try:
    with open("/tmp/sales_order_project_baseline.json") as f:
        baseline = json.load(f)
except Exception:
    baseline = {}

try:
    with open("/tmp/task_start_time.txt") as f:
        task_start = int(f.read().strip())
except Exception:
    task_start = 0

def api_get(doctype, filters=None, fields=None, limit=100):
    params = {"limit_page_length": limit}
    if filters:
        params["filters"] = json.dumps(filters)
    if fields:
        params["fields"] = json.dumps(fields)
    return session.get(f"{ERPNEXT_URL}/api/resource/{doctype}", params=params).json().get("data", [])

def get_doc(doctype, name):
    return session.get(f"{ERPNEXT_URL}/api/resource/{doctype}/{name}").json().get("data", {})

# 1. Project Templates
templates = api_get("Project Template", fields=["name", "creation"])
template_info = []
for t in templates:
    if t["name"] not in baseline.get("existing_project_templates", []):
        doc = get_doc("Project Template", t["name"])
        tasks = doc.get("tasks", [])
        template_info.append({
            "name": doc.get("name"),
            "creation": doc.get("creation"),
            "task_subjects": [tk.get("subject", "").lower().strip() for tk in tasks],
            "task_count": len(tasks)
        })

# 2. Sales Orders for Apex Energy
sales_orders = api_get("Sales Order",
                        [["customer", "=", "Apex Energy"]],
                        fields=["name", "docstatus", "creation"])
so_info = []
for so in sales_orders:
    if so["name"] not in baseline.get("existing_sales_orders", []):
        doc = get_doc("Sales Order", so["name"])
        items = doc.get("items", [])
        so_info.append({
            "name": doc.get("name"),
            "docstatus": doc.get("docstatus"),
            "creation": doc.get("creation"),
            "items": [i.get("item_code") for i in items]
        })

# 3. Projects
projects = api_get("Project", fields=["name", "sales_order", "project_template", "creation"])
proj_info = []
for p in projects:
    if p["name"] not in baseline.get("existing_projects", []):
        doc = get_doc("Project", p["name"])
        proj_info.append({
            "name": doc.get("name"),
            "sales_order": doc.get("sales_order"),
            "project_template": doc.get("project_template"),
            "creation": doc.get("creation")
        })

# 4. Tasks
tasks = api_get("Task", fields=["name", "subject", "project", "status", "creation"])
task_info = []
for tk in tasks:
    # Only grab tasks linked to the new projects
    if tk.get("project") in [p["name"] for p in proj_info]:
        task_info.append({
            "name": tk.get("name"),
            "subject": tk.get("subject", ""),
            "project": tk.get("project"),
            "status": tk.get("status")
        })

result = {
    "task_start_time": task_start,
    "templates": template_info,
    "sales_orders": so_info,
    "projects": proj_info,
    "tasks": task_info,
    "app_running": True
}

with open("/tmp/sales_order_project_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
print("\n=== Export complete: /tmp/sales_order_project_result.json ===")
PYEOF

echo "=== Export done ==="