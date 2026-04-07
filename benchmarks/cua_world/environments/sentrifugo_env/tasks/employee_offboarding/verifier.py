#!/usr/bin/env python3
"""
Verifier for employee_offboarding task.

The agent must complete 3 actions per the manifest:
  1. Deactivate 3 departing employees: EMP013, EMP018, EMP020
  2. Add 2 replacement hires: Carlos Reyes (EMP021, Sales), Mia Chen (EMP022, Marketing)
  3. Create "Austin Office Holidays" group with Texas Independence Day and Juneteenth

Scoring (100 pts total, pass = 60):
  Deactivations (30 pts):
    - EMP013 Daniel Wilson deactivated:   10 pts
    - EMP018 Nicole Anderson deactivated: 10 pts
    - EMP020 Lauren Jackson deactivated:  10 pts
  New hires (30 pts):
    - Carlos Reyes exists, in Sales:      15 pts
    - Mia Chen exists, in Marketing:      15 pts
  Holiday group (40 pts):
    - "Austin Office Holidays" group exists:     10 pts
    - Texas Independence Day holiday exists:     15 pts
    - Juneteenth holiday exists:                 15 pts
  Total: 100 pts
"""

import datetime

_DB_CMD = (
    "docker exec sentrifugo-db mysql -u sentrifugo -psentrifugo123 sentrifugo "
    "-N -B -e \"{query}\""
)

_PASS_THRESHOLD = 60

_DEPARTING = [
    ('EMP013', 'Daniel Wilson'),
    ('EMP018', 'Nicole Anderson'),
    ('EMP020', 'Lauren Jackson'),
]

_NEW_HIRES = [
    {'empid': 'EMP021', 'firstname': 'Carlos', 'lastname': 'Reyes', 'dept': 'Sales', 'pts': 15},
    {'empid': 'EMP022', 'firstname': 'Mia',    'lastname': 'Chen',  'dept': 'Marketing', 'pts': 15},
]

_HOLIDAY_GROUP = 'Austin Office Holidays'
_HOLIDAYS = [
    {'name': 'Texas Independence Day', 'pts': 15},
    {'name': 'Juneteenth',             'pts': 15},
]


def _query_scalar(exec_env, sql):
    try:
        return exec_env(_DB_CMD.format(query=sql)).strip()
    except Exception:
        return ''


def verify_employee_offboarding(traj, env_info, task_info):
    exec_env = env_info.get('exec_in_env') or env_info.get('exec_capture')
    if exec_env is None:
        return {'passed': False, 'score': 0,
                'feedback': 'exec_in_env not available in env_info'}

    score = 0
    feedback_parts = []
    current_year = datetime.datetime.now().year

    # ---- Check deactivations ----
    for empid, name in _DEPARTING:
        active_count = _query_scalar(
            exec_env,
            f"SELECT COUNT(*) FROM main_users WHERE employeeId='{empid}' AND isactive=1;"
        )
        if active_count == '0':
            score += 10
            feedback_parts.append(f'{empid} ({name}): deactivated (10/10)')
        else:
            # Check if employee exists at all
            total_count = _query_scalar(
                exec_env,
                f"SELECT COUNT(*) FROM main_users WHERE employeeId='{empid}';"
            )
            if total_count and int(total_count) > 0:
                feedback_parts.append(f'{empid} ({name}): still active — not deactivated (0/10)')
            else:
                feedback_parts.append(f'{empid} ({name}): employee not found (0/10)')

    # ---- Check new hires ----
    for hire in _NEW_HIRES:
        empid = hire['empid']
        expected_dept = hire['dept']
        pts = hire['pts']

        # Find employee by empid or name
        emp_row = _query_scalar(
            exec_env,
            f"SELECT u.id, d.deptname FROM main_users u "
            f"LEFT JOIN main_departments d ON u.department_id = d.id "
            f"WHERE u.employeeId='{empid}' AND u.isactive=1 LIMIT 1;"
        )
        if not emp_row or '\t' not in emp_row:
            # Try by name
            emp_row = _query_scalar(
                exec_env,
                f"SELECT u.id, d.deptname FROM main_users u "
                f"LEFT JOIN main_departments d ON u.department_id = d.id "
                f"WHERE u.firstname='{hire['firstname']}' AND u.lastname='{hire['lastname']}' "
                f"AND u.isactive=1 LIMIT 1;"
            )

        if emp_row and '\t' in emp_row:
            parts = emp_row.split('\t', 1)
            actual_dept = parts[1].strip() if len(parts) > 1 else ''
            if actual_dept == expected_dept:
                score += pts
                feedback_parts.append(
                    f'{empid} ({hire["firstname"]} {hire["lastname"]}): '
                    f'hired and in correct dept "{actual_dept}" ({pts}/{pts})')
            else:
                partial = pts // 2
                score += partial
                feedback_parts.append(
                    f'{empid} ({hire["firstname"]} {hire["lastname"]}): '
                    f'hired but in wrong dept "{actual_dept}" (expected "{expected_dept}") '
                    f'({partial}/{pts})')
        else:
            feedback_parts.append(
                f'{empid} ({hire["firstname"]} {hire["lastname"]}): not found (0/{pts})')

    # ---- Check holiday group ----
    hg_id = _query_scalar(
        exec_env,
        f"SELECT id FROM main_holidaygroups WHERE groupname='{_HOLIDAY_GROUP}' AND isactive=1 LIMIT 1;"
    )
    if hg_id:
        score += 10
        feedback_parts.append(f'Holiday group "{_HOLIDAY_GROUP}": created (10/10)')

        # Check individual holidays
        for holiday in _HOLIDAYS:
            hname = holiday['name']
            hpts = holiday['pts']
            h_count = _query_scalar(
                exec_env,
                f"SELECT COUNT(*) FROM main_holidaydates "
                f"WHERE holidayname='{hname}' AND groupid={hg_id} "
                f"AND isactive=1;"
            )
            if h_count and int(h_count) > 0:
                score += hpts
                feedback_parts.append(f'Holiday "{hname}": added ({hpts}/{hpts})')
            else:
                feedback_parts.append(f'Holiday "{hname}": missing (0/{hpts})')
    else:
        feedback_parts.append(f'Holiday group "{_HOLIDAY_GROUP}": not found (0/40)')

    passed = score >= _PASS_THRESHOLD
    return {
        'passed': passed,
        'score': score,
        'feedback': '; '.join(feedback_parts),
    }
