#!/bin/bash
echo "=== Exporting implement_rnd_innovation_day result ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

take_screenshot /tmp/task_final.png

python3 << PYTHON_EOF
import xmlrpc.client
import json
import sys
import datetime

url = 'http://localhost:8069'
db = 'odoo_hr'
username = 'admin'
password = 'admin'

task_start_ts = $TASK_START
task_end_ts = $TASK_END

result = {
    "task_start": task_start_ts,
    "task_end": task_end_ts,
    "leave_type": {
        "found": False,
        "name": None,
        "leave_validation_type": None,
        "requires_allocation": None,
        "responsible_ids": [],
        "create_date": None,
        "write_date_timestamp": 0
    },
    "accrual_plan": {
        "found": False,
        "name": None,
        "level_count": 0,
        "levels": [],
        "create_date": None
    },
    "allocation": {
        "found": False,
        "employee_name": None,
        "leave_type_name": None,
        "allocation_type": None,
        "accrual_plan_name": None,
        "state": None,
        "create_date": None
    },
    "leave_request": {
        "found": False,
        "employee_name": None,
        "leave_type_name": None,
        "date_from": None,
        "state": None,
        "create_date": None
    },
    "error": None
}

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    if not uid:
        result["error"] = "Authentication failed"
        raise Exception("Authentication failed")
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    def exe(model, method, *args, **kwargs):
        return models.execute_kw(db, uid, password, model, method, *args, **kwargs)

    # -------------------------------------------------------
    # 1. Check Leave Type "R&D Innovation Day"
    # -------------------------------------------------------
    lt_data = exe('hr.leave.type', 'search_read',
                  [[['name', 'ilike', 'R&D Innovation Day']]],
                  {'fields': ['id', 'name', 'leave_validation_type', 'requires_allocation',
                              'responsible_ids', 'create_date', 'write_date']})
    if lt_data:
        lt = lt_data[0]
        result["leave_type"]["found"] = True
        result["leave_type"]["name"] = lt.get('name')
        result["leave_type"]["leave_validation_type"] = lt.get('leave_validation_type')
        result["leave_type"]["requires_allocation"] = lt.get('requires_allocation')
        result["leave_type"]["responsible_ids"] = lt.get('responsible_ids', [])
        result["leave_type"]["create_date"] = lt.get('create_date')
        wd = lt.get('write_date', '')
        if wd:
            dt = datetime.datetime.strptime(wd, "%Y-%m-%d %H:%M:%S")
            result["leave_type"]["write_date_timestamp"] = int(dt.replace(
                tzinfo=datetime.timezone.utc).timestamp())
        lt_id = lt['id']
    else:
        lt_id = None

    # -------------------------------------------------------
    # 2. Check Accrual Plan "R&D Innovation Accrual"
    # -------------------------------------------------------
    plan_data = exe('hr.leave.accrual.plan', 'search_read',
                    [[['name', 'ilike', 'R&D Innovation Accrual']]],
                    {'fields': ['id', 'name', 'level_ids', 'create_date']})
    if plan_data:
        plan = plan_data[0]
        result["accrual_plan"]["found"] = True
        result["accrual_plan"]["name"] = plan.get('name')
        result["accrual_plan"]["create_date"] = plan.get('create_date')
        plan_id = plan['id']

        level_ids = plan.get('level_ids', [])
        result["accrual_plan"]["level_count"] = len(level_ids)

        if level_ids:
            levels = exe('hr.leave.accrual.level', 'read', [level_ids],
                         {'fields': ['added_value', 'added_value_type', 'frequency',
                                     'start_count', 'start_type',
                                     'cap_accrued_time', 'maximum_leave',
                                     'sequence']})
            # Sort by sequence or ID to get level ordering
            levels.sort(key=lambda x: (x.get('sequence', 0), x.get('id', 0)))
            result["accrual_plan"]["levels"] = levels
    else:
        plan_id = None

    # -------------------------------------------------------
    # 3. Check Allocation for Eli Lambert
    # -------------------------------------------------------
    emp_ids = exe('hr.employee', 'search', [[['name', '=', 'Eli Lambert']]])
    if emp_ids:
        emp_id = emp_ids[0]

        # Search for accrual allocation with the new leave type
        alloc_domain = [['employee_id', '=', emp_id], ['allocation_type', '=', 'accrual']]
        if lt_id:
            alloc_domain.append(['holiday_status_id', '=', lt_id])

        allocs = exe('hr.leave.allocation', 'search_read', [alloc_domain],
                     {'fields': ['id', 'employee_id', 'holiday_status_id',
                                 'allocation_type', 'accrual_plan_id',
                                 'state', 'create_date']})

        if allocs:
            # Take the most recently created one
            alloc = sorted(allocs, key=lambda x: x.get('id', 0), reverse=True)[0]
            result["allocation"]["found"] = True
            result["allocation"]["employee_name"] = alloc.get('employee_id', [0, ''])[1] if isinstance(alloc.get('employee_id'), list) else str(alloc.get('employee_id'))
            result["allocation"]["leave_type_name"] = alloc.get('holiday_status_id', [0, ''])[1] if isinstance(alloc.get('holiday_status_id'), list) else str(alloc.get('holiday_status_id'))
            result["allocation"]["allocation_type"] = alloc.get('allocation_type')
            result["allocation"]["accrual_plan_name"] = alloc.get('accrual_plan_id', [0, ''])[1] if isinstance(alloc.get('accrual_plan_id'), list) else str(alloc.get('accrual_plan_id'))
            result["allocation"]["accrual_plan_id"] = alloc.get('accrual_plan_id', [0])[0] if isinstance(alloc.get('accrual_plan_id'), list) else alloc.get('accrual_plan_id')
            result["allocation"]["state"] = alloc.get('state')
            result["allocation"]["create_date"] = alloc.get('create_date')

        # -------------------------------------------------------
        # 4. Check Leave Request for Eli Lambert
        # -------------------------------------------------------
        req_domain = [['employee_id', '=', emp_id]]
        if lt_id:
            req_domain.append(['holiday_status_id', '=', lt_id])

        reqs = exe('hr.leave', 'search_read', [req_domain],
                   {'fields': ['id', 'employee_id', 'holiday_status_id',
                               'date_from', 'date_to', 'request_date_from', 'request_date_to',
                               'state', 'create_date']})

        if reqs:
            req = sorted(reqs, key=lambda x: x.get('id', 0), reverse=True)[0]
            result["leave_request"]["found"] = True
            result["leave_request"]["employee_name"] = req.get('employee_id', [0, ''])[1] if isinstance(req.get('employee_id'), list) else str(req.get('employee_id'))
            result["leave_request"]["leave_type_name"] = req.get('holiday_status_id', [0, ''])[1] if isinstance(req.get('holiday_status_id'), list) else str(req.get('holiday_status_id'))
            # request_date_from is the user-facing Date field (YYYY-MM-DD)
            # date_from is the computed Datetime field
            request_date_from = req.get('request_date_from', '')
            if request_date_from:
                result["leave_request"]["date_from"] = request_date_from
            else:
                # Fallback to date_from datetime field, extract date part
                date_from = req.get('date_from', '')
                result["leave_request"]["date_from"] = date_from[:10] if date_from else None
            result["leave_request"]["date_to"] = req.get('request_date_to') or (req.get('date_to', '')[:10] if req.get('date_to') else None)
            result["leave_request"]["state"] = req.get('state')
            result["leave_request"]["create_date"] = req.get('create_date')

    # Store plan_id for cross-referencing in verifier
    if plan_id:
        result["accrual_plan"]["id"] = plan_id

except Exception as e:
    result["error"] = str(e)

# Write result
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2, default=str)

PYTHON_EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="
