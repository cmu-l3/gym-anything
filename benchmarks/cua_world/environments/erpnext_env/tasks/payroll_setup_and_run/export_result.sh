#!/bin/bash
# Export script for payroll_setup_and_run task
# Queries ERPNext for Salary Structure, Salary Structure Assignments,
# Payroll Entry, and Salary Slips for Engineering department employees.

echo "=== Exporting payroll_setup_and_run results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

take_screenshot /tmp/payroll_setup_and_run_final.png 2>/dev/null || true

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
    with open("/tmp/payroll_setup_and_run_baseline.json") as f:
        baseline = json.load(f)
except Exception:
    baseline = {}

dept = "Engineering"
employee_ids = baseline.get("employees", [])
existing_ss_names = set(baseline.get("existing_salary_structures", []))
existing_pe_names = set(baseline.get("existing_payroll_entries", []))

def api_get(doctype, filters=None, fields=None, limit=50):
    params = {"limit_page_length": limit}
    if filters:
        params["filters"] = json.dumps(filters)
    if fields:
        params["fields"] = json.dumps(fields)
    return session.get(f"{ERPNEXT_URL}/api/resource/{doctype}", params=params).json().get("data", [])

def get_doc(doctype, name):
    return session.get(f"{ERPNEXT_URL}/api/resource/{doctype}/{name}").json().get("data", {})

# --- Salary Structures (new ones, not in baseline) ---
all_ss = api_get("Salary Structure",
                  [["company", "=", "Wind Power LLC"], ["docstatus", "=", 1]],
                  fields=["name", "docstatus"])
new_ss = [s for s in all_ss if s["name"] not in existing_ss_names]

ss_details = []
for ss in new_ss:
    doc = get_doc("Salary Structure", ss["name"])
    earnings = [e for e in doc.get("earnings", [])]
    deductions = [e for e in doc.get("deductions", [])]
    ss_details.append({
        "name": ss["name"],
        "earnings_count": len(earnings),
        "deductions_count": len(deductions),
        "total_components": len(earnings) + len(deductions),
        "earnings": [{"salary_component": e.get("salary_component"),
                       "amount": e.get("amount", 0)} for e in earnings],
        "deductions": [{"salary_component": e.get("salary_component"),
                         "amount": e.get("amount", 0)} for e in deductions]
    })

# --- Salary Structure Assignments for Engineering employees ---
ssa_list = []
for emp_id in employee_ids:
    assignments = api_get("Salary Structure Assignment",
                           [["employee", "=", emp_id], ["docstatus", "=", 1]],
                           fields=["name", "employee", "salary_structure",
                                    "from_date", "base"])
    for a in assignments:
        # Only count assignments to new salary structures
        if a.get("salary_structure") not in existing_ss_names:
            ssa_list.append({
                "assignment_name": a["name"],
                "employee": a.get("employee"),
                "salary_structure": a.get("salary_structure"),
                "from_date": a.get("from_date"),
                "base": a.get("base", 0)
            })

# --- Payroll Entries (new ones) ---
all_pe = api_get("Payroll Entry",
                  [["company", "=", "Wind Power LLC"], ["docstatus", "=", 1]],
                  fields=["name", "department", "start_date", "end_date",
                           "docstatus", "status"])
new_pe = [p for p in all_pe if p["name"] not in existing_pe_names]

pe_details = []
for pe in new_pe:
    doc = get_doc("Payroll Entry", pe["name"])
    employees_in_pe = [e.get("employee") for e in doc.get("employees", [])]
    pe_details.append({
        "pe_name": pe["name"],
        "department": pe.get("department"),
        "start_date": pe.get("start_date"),
        "end_date": pe.get("end_date"),
        "employees": employees_in_pe,
        "employee_count": len(employees_in_pe)
    })

# --- Salary Slips for Engineering employees ---
slip_list = []
for emp_id in employee_ids:
    slips = api_get("Salary Slip",
                     [["employee", "=", emp_id], ["docstatus", "=", 1]],
                     fields=["name", "employee", "employee_name", "gross_pay",
                              "net_pay", "start_date", "end_date", "payroll_entry"])
    for s in slips:
        slip_list.append({
            "slip_name": s["name"],
            "employee": s.get("employee"),
            "employee_name": s.get("employee_name"),
            "gross_pay": s.get("gross_pay", 0),
            "net_pay": s.get("net_pay", 0),
            "payroll_entry": s.get("payroll_entry", "")
        })

# Track which employees have submitted slips
employees_with_slips = list({s["employee"] for s in slip_list})
engineering_covered = [e for e in employee_ids if e in employees_with_slips]

result = {
    "department": dept,
    "employee_ids": employee_ids,
    "new_salary_structures": ss_details,
    "salary_structure_assignments": ssa_list,
    "payroll_entries": pe_details,
    "salary_slips": slip_list,
    "employees_with_submitted_slips": employees_with_slips,
    "engineering_employees_covered": engineering_covered,
    "all_covered": len(engineering_covered) >= len(employee_ids) and len(employee_ids) > 0
}

with open("/tmp/payroll_setup_and_run_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
print("\n=== Export complete: /tmp/payroll_setup_and_run_result.json ===")
PYEOF

echo "=== Export done ==="
