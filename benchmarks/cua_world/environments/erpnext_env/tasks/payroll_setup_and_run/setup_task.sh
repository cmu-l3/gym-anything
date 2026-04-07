#!/bin/bash
# Setup script for payroll_setup_and_run task
# Creates Engineering department, two employees (Michał Sobczak, Vakhita Ryzaev),
# and a Payroll Period for the current month.
# Agent must: create salary components → salary structure → assignments → payroll entry → submit slips.

set -e
echo "=== Setting up payroll_setup_and_run ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "Waiting for ERPNext..."
wait_for_erpnext 300

python3 << 'PYEOF'
import requests, json, sys, time
from datetime import date

ERPNEXT_URL = "http://localhost:8080"
session = requests.Session()

r = session.post(f"{ERPNEXT_URL}/api/method/login",
                 json={"usr": "Administrator", "pwd": "admin"})
if r.status_code != 200:
    print(f"ERROR: Login failed {r.status_code}", file=sys.stderr)
    sys.exit(1)
print("Logged in successfully")

def api_get(doctype, filters=None, fields=None, limit=1):
    params = {"limit_page_length": limit}
    if filters:
        params["filters"] = json.dumps(filters)
    if fields:
        params["fields"] = json.dumps(fields)
    return session.get(f"{ERPNEXT_URL}/api/resource/{doctype}", params=params).json().get("data", [])

# --- Wait for ERPNext master data (before_tests completion check) ---
print("Waiting for ERPNext master data (Company, Warehouses)...")
master_ready = False
for attempt in range(100):  # up to 25 minutes
    try:
        companies = api_get("Company", [["company_name", "=", "Wind Power LLC"]])
        warehouses = api_get("Warehouse", [["warehouse_name", "=", "Stores"]])
        if companies and warehouses:
            print(f"  Master data ready after {attempt * 15}s")
            master_ready = True
            break
    except Exception:
        pass
    print(f"  Master data not ready yet... ({attempt * 15}s elapsed)", flush=True)
    time.sleep(15)

if not master_ready:
    print("ERROR: ERPNext master data not available after 10 minutes", file=sys.stderr)
    sys.exit(1)

# Re-login after waiting
session.post(f"{ERPNEXT_URL}/api/method/login",
             json={"usr": "Administrator", "pwd": "admin"})

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
        name = existing[0]["name"]
        print(f"  Found existing {doctype}: {name}")
        return name
    r = session.post(f"{ERPNEXT_URL}/api/resource/{doctype}", json=values)
    if r.status_code in (200, 201):
        name = r.json().get("data", {}).get("name", "unknown")
        print(f"  Created {doctype}: {name}")
        return name
    print(f"  ERROR creating {doctype}: {r.status_code} {r.text[:300]}", file=sys.stderr)
    return None

# --- Department ---
print("Setting up Engineering department...")
get_or_create("Department",
              [["department_name", "=", "Engineering"]],
              {"department_name": "Engineering",
               "company": "Wind Power LLC",
               "parent_department": "All Departments"})

# --- Employees ---
EMPLOYEES = [
    {
        "employee_name": "Michał Sobczak",
        "first_name": "Michał",
        "last_name": "Sobczak",
        "gender": "Male",
        "date_of_birth": "1982-07-03",
        "date_of_joining": "2006-06-10",
        "company": "Wind Power LLC",
        "department": "Engineering",
        "status": "Active"
    },
    {
        "employee_name": "Vakhita Ryzaev",
        "first_name": "Vakhita",
        "last_name": "Ryzaev",
        "gender": "Male",
        "date_of_birth": "1982-09-03",
        "date_of_joining": "2005-09-06",
        "company": "Wind Power LLC",
        "department": "Engineering",
        "status": "Active"
    }
]

employee_ids = []
for emp in EMPLOYEES:
    existing = api_get("Employee",
                        [["employee_name", "=", emp["employee_name"]]],
                        fields=["name", "department"])
    if existing:
        emp_id = existing[0]["name"]
        print(f"  Found existing Employee: {emp_id} ({emp['employee_name']})")
        # Update department if needed
        if existing[0].get("department") != "Engineering":
            session.put(f"{ERPNEXT_URL}/api/resource/Employee/{emp_id}",
                        json={"department": "Engineering"})
            print(f"    Updated department to Engineering")
    else:
        r = session.post(f"{ERPNEXT_URL}/api/resource/Employee", json=emp)
        if r.status_code in (200, 201):
            emp_id = r.json()["data"]["name"]
            print(f"  Created Employee: {emp_id} ({emp['employee_name']})")
        else:
            print(f"  ERROR creating Employee {emp['employee_name']}: {r.text[:200]}", file=sys.stderr)
            emp_id = None
    if emp_id:
        employee_ids.append(emp_id)

# --- Payroll Period ---
today = date.today()
period_start = str(today.replace(day=1))
# Last day of current month
import calendar
last_day = calendar.monthrange(today.year, today.month)[1]
period_end = str(today.replace(day=last_day))
period_name = f"Engineering Payroll {today.strftime('%B %Y')}"

existing_period = api_get("Payroll Period",
                            [["start_date", "=", period_start],
                             ["end_date", "=", period_end]],
                            fields=["name"])
if existing_period:
    period_name = existing_period[0]["name"]
    print(f"  Found existing Payroll Period: {period_name}")
else:
    r = session.post(f"{ERPNEXT_URL}/api/resource/Payroll Period", json={
        "payroll_period_name": period_name,
        "company": "Wind Power LLC",
        "start_date": period_start,
        "end_date": period_end
    })
    if r.status_code in (200, 201):
        period_name = r.json()["data"]["name"]
        print(f"  Created Payroll Period: {period_name}")
    else:
        print(f"  WARNING: Could not create Payroll Period: {r.text[:200]}", file=sys.stderr)
        period_name = None

# --- Record baseline ---
existing_ss = api_get("Salary Structure",
                        [["company", "=", "Wind Power LLC"]],
                        fields=["name"], limit=50)
existing_ss_names = [s["name"] for s in existing_ss]

existing_pe = api_get("Payroll Entry",
                        [["company", "=", "Wind Power LLC"], ["docstatus", "=", 1]],
                        fields=["name"], limit=50)
existing_pe_names = [p["name"] for p in existing_pe]

baseline = {
    "department": "Engineering",
    "employees": employee_ids,
    "employee_names": ["Michał Sobczak", "Vakhita Ryzaev"],
    "payroll_period_name": period_name,
    "period_start": period_start,
    "period_end": period_end,
    "existing_salary_structures": existing_ss_names,
    "existing_payroll_entries": existing_pe_names,
    "setup_date": str(today)
}
with open("/tmp/payroll_setup_and_run_baseline.json", "w") as f:
    json.dump(baseline, f, indent=2)

print(f"\n=== Setup Summary ===")
print(f"Department:      Engineering")
print(f"Employees:       {', '.join(employee_ids)}")
print(f"Payroll Period:  {period_name} ({period_start} to {period_end})")
print(f"Existing SS:     {len(existing_ss_names)} (agent must create new ones)")
print(f"Status: Employees exist, no salary structure assigned — agent must set up payroll")
PYEOF

date +%s > /tmp/task_start_timestamp

ensure_firefox_at "http://localhost:8080/app/salary-structure"
sleep 3
take_screenshot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Setup complete: Engineering employees ready, agent must configure and run payroll ==="
