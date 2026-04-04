#!/usr/bin/env python3
"""
Supplementary data setup for Odoo HR environment.

Odoo's OFFICIAL DEMO DATA (bundled in hr/data/hr_demo.xml, hr_holidays/data/hr_holidays_demo.xml)
provides the base dataset:
  - 20 employees: Jeffrey Kelly, Marc Demo, Ronnie Hart, Tina Williamson, Abigail Peterson,
    Audrey Peterson, Eli Lambert, Rachel Perry, Keith Byrd, Doris Cole, Ernest Reed,
    Toni Jimenez, Anita Oliver, Sharlene Rhodes, Randall Lewis, Jennie Fletcher,
    Paul Williams, Walter Horton, Beth Evans (+ Mitchell Admin)
  - Departments: Management, Administration, Sales, Research & Development, R&D USA,
    Long Term Projects, Professional Services
  - Job Positions: CEO, CTO, Consultant, Experienced Developer, HR Manager,
    Marketing and Community Manager, Trainee
  - Employee Tags: Sales, Trainer, Employee, Consultant
  - Leave Types: Paid Time Off, Sick Time Off, Compensatory Days, Parental Leaves,
    Training Time Off
  - Allocations: Paid Time Off and Compensatory allocations for Mitchell Admin

This script ONLY adds what the demo data doesn't include:
  1. A Paid Time Off allocation for Rachel Perry (so she can submit a PTO leave request)
  2. A pending leave request for Rachel Perry (needed for Task 7: approve_leave_request)
  3. A pending leave request for Doris Cole (needed for Task 8: refuse_leave_request)
"""

import xmlrpc.client
import sys
import datetime

url = 'http://localhost:8069'
db = 'odoo_hr'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    if not uid:
        print("ERROR: Authentication failed", file=sys.stderr)
        sys.exit(1)
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
except Exception as e:
    print(f"ERROR: Cannot connect to Odoo: {e}", file=sys.stderr)
    sys.exit(1)


def find_employee(name):
    ids = models.execute_kw(db, uid, 'admin', 'hr.employee', 'search',
                            [[['name', '=', name]]])
    return ids[0] if ids else None


def get_leave_type_by_name(preferred_name):
    """Get a specific leave type by name. Falls back to first no-allocation type."""
    # Try exact name first
    leave_types = models.execute_kw(db, uid, 'admin', 'hr.leave.type', 'search_read',
                                    [[['name', '=', preferred_name]]],
                                    {'fields': ['id', 'name'], 'limit': 1})
    if leave_types:
        return leave_types[0]
    # Fallback: any no-allocation type
    leave_types = models.execute_kw(db, uid, 'admin', 'hr.leave.type', 'search_read',
                                    [[['requires_allocation', '=', 'no']]],
                                    {'fields': ['id', 'name'], 'limit': 1})
    if leave_types:
        return leave_types[0]
    # Final fallback: any leave type
    leave_types = models.execute_kw(db, uid, 'admin', 'hr.leave.type', 'search_read',
                                    [[]], {'fields': ['id', 'name'], 'limit': 1})
    return leave_types[0] if leave_types else None


def ensure_allocation(emp_name, leave_type_name, num_days=10):
    """Ensure the named employee has an approved Paid Time Off allocation."""
    emp_id = find_employee(emp_name)
    if not emp_id:
        return None
    leave_type = get_leave_type_by_name(leave_type_name)
    if not leave_type:
        print(f"WARNING: Leave type '{leave_type_name}' not found", file=sys.stderr)
        return None
    leave_type_id = leave_type['id']

    # Check for existing validated allocation
    existing = models.execute_kw(db, uid, 'admin', 'hr.leave.allocation', 'search',
                                 [[['employee_id', '=', emp_id],
                                   ['holiday_status_id', '=', leave_type_id],
                                   ['state', 'in', ['validate', 'validate1']]]])
    if existing:
        print(f"'{emp_name}' already has approved {leave_type_name} allocation {existing}")
        return existing[0]

    try:
        alloc_id = models.execute_kw(db, uid, 'admin', 'hr.leave.allocation', 'create', [{
            'holiday_status_id': leave_type_id,
            'employee_id': emp_id,
            'number_of_days': num_days,
            'name': f'{leave_type_name} allocation',
            'allocation_type': 'regular',
        }])
        # Approve the allocation
        try:
            models.execute_kw(db, uid, 'admin', 'hr.leave.allocation', 'action_validate', [[alloc_id]])
        except Exception:
            try:
                models.execute_kw(db, uid, 'admin', 'hr.leave.allocation', 'action_confirm', [[alloc_id]])
                models.execute_kw(db, uid, 'admin', 'hr.leave.allocation', 'action_validate', [[alloc_id]])
            except Exception as e2:
                print(f"Warning: Could not validate allocation: {e2}", file=sys.stderr)
        alloc_data = models.execute_kw(db, uid, 'admin', 'hr.leave.allocation', 'read',
                                       [[alloc_id]], {'fields': ['state', 'number_of_days']})
        state = alloc_data[0]['state'] if alloc_data else 'unknown'
        print(f"Created {leave_type_name} allocation for '{emp_name}' (id={alloc_id}, "
              f"days={num_days}, state={state})")
        return alloc_id
    except Exception as e:
        print(f"WARNING: Could not create allocation for '{emp_name}': {e}", file=sys.stderr)
        return None


def ensure_pending_leave(emp_name, description, leave_type_name, days=3):
    """Ensure the named employee has exactly one pending (confirm state) leave request.
    Creates one if none exists. Returns the leave id."""
    emp_id = find_employee(emp_name)
    if not emp_id:
        print(f"WARNING: Employee '{emp_name}' not found — skipping leave creation",
              file=sys.stderr)
        return None

    # Check for existing confirmed leave
    confirmed = models.execute_kw(db, uid, 'admin', 'hr.leave', 'search',
                                  [[['employee_id', '=', emp_id],
                                    ['state', '=', 'confirm']]])
    if confirmed:
        print(f"'{emp_name}' already has pending leave {confirmed}")
        return confirmed[0]

    leave_type = get_leave_type_by_name(leave_type_name)
    if not leave_type:
        print(f"WARNING: No suitable leave type found for {emp_name}", file=sys.stderr)
        return None

    today = datetime.date.today()
    start = today + datetime.timedelta(days=21)
    end = start + datetime.timedelta(days=days - 1)

    try:
        leave_id = models.execute_kw(db, uid, 'admin', 'hr.leave', 'create', [{
            'holiday_status_id': leave_type['id'],
            'employee_id': emp_id,
            'date_from': f'{start} 08:00:00',
            'date_to': f'{end} 17:00:00',
            'name': description,
        }])
        # In Odoo 17, admin-created leaves may already be in 'confirm' state;
        # action_confirm() is a no-op or may fail if already confirmed — both are OK.
        try:
            models.execute_kw(db, uid, 'admin', 'hr.leave', 'action_confirm', [[leave_id]])
        except Exception:
            pass  # Already in confirm state — that's fine
        # Verify leave state
        state_data = models.execute_kw(db, uid, 'admin', 'hr.leave', 'read',
                                       [[leave_id]], {'fields': ['state']})
        state = state_data[0]['state'] if state_data else 'unknown'
        print(f"Created leave for '{emp_name}' (id={leave_id}, state={state}): "
              f"{description} — {leave_type['name']}")
        return leave_id
    except Exception as e:
        print(f"WARNING: Could not create leave for '{emp_name}': {e}", file=sys.stderr)
        return None


print("=== Setting up supplementary HR data ===")
print("(Base data provided by Odoo official demo: 20 employees, 7 departments, etc.)")

# Task 7 (approve_leave_request): Rachel Perry needs a Paid Time Off allocation + pending leave
ensure_allocation('Rachel Perry', 'Paid Time Off', num_days=10)
ensure_pending_leave('Rachel Perry', 'Annual vacation', 'Paid Time Off', days=5)

# Task 8 (refuse_leave_request): Doris Cole needs a pending Unpaid leave
ensure_pending_leave('Doris Cole', 'Personal time off', 'Unpaid', days=3)

print("=== Supplementary data setup complete ===")
