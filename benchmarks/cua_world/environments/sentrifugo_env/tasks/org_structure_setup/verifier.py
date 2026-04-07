#!/usr/bin/env python3
"""
Verifier for org_structure_setup task.

The agent must create from scratch:
  1. Department: "Product Management" (under Technology Services BU)
  2. Job titles: "VP of Product", "Senior Product Manager", "Product Manager"
  3. Employees: Marcus Webb (EMP021), Priya Sharma (EMP022), Lucas Fernandez (EMP023)
     — all in Product Management department

Scoring (100 pts total, pass = 60):
  - Department "Product Management" active:          15 pts
  - Job title "VP of Product" active:                10 pts
  - Job title "Senior Product Manager" active:       10 pts
  - Job title "Product Manager" active:              10 pts
  - EMP021 Marcus Webb exists, active, in Product Mgmt dept: 18 pts
  - EMP022 Priya Sharma exists, active, in Product Mgmt dept: 18 pts
  - EMP023 Lucas Fernandez exists, active, in Product Mgmt dept: 19 pts
  Total: 100 pts
"""

_DB_CMD = (
    "docker exec sentrifugo-db mysql -u sentrifugo -psentrifugo123 sentrifugo "
    "-N -B -e \"{query}\""
)

_PASS_THRESHOLD = 60

_EXPECTED_DEPT = 'Product Management'
_EXPECTED_JOB_TITLES = ['VP of Product', 'Senior Product Manager', 'Product Manager']
_EXPECTED_EMPLOYEES = [
    {'empid': 'EMP021', 'firstname': 'Marcus',  'lastname': 'Webb',      'pts': 18},
    {'empid': 'EMP022', 'firstname': 'Priya',   'lastname': 'Sharma',    'pts': 18},
    {'empid': 'EMP023', 'firstname': 'Lucas',   'lastname': 'Fernandez', 'pts': 19},
]


def _query_scalar(exec_env, sql):
    try:
        return exec_env(_DB_CMD.format(query=sql)).strip()
    except Exception:
        return ''


def verify_org_structure_setup(traj, env_info, task_info):
    exec_env = env_info.get('exec_in_env') or env_info.get('exec_capture')
    if exec_env is None:
        return {'passed': False, 'score': 0,
                'feedback': 'exec_in_env not available in env_info'}

    score = 0
    feedback_parts = []

    # ---- Department check ----
    dept_count = _query_scalar(
        exec_env,
        f"SELECT COUNT(*) FROM main_departments WHERE deptname='{_EXPECTED_DEPT}' AND isactive=1;"
    )
    if dept_count and int(dept_count) > 0:
        score += 15
        feedback_parts.append(f'Department "{_EXPECTED_DEPT}": exists (15/15)')
    else:
        feedback_parts.append(f'Department "{_EXPECTED_DEPT}": missing (0/15)')

    # ---- Job title checks ----
    for jt in _EXPECTED_JOB_TITLES:
        jt_count = _query_scalar(
            exec_env,
            f"SELECT COUNT(*) FROM main_jobtitles WHERE jobtitlename='{jt}' AND isactive=1;"
        )
        if jt_count and int(jt_count) > 0:
            score += 10
            feedback_parts.append(f'Job title "{jt}": exists (10/10)')
        else:
            feedback_parts.append(f'Job title "{jt}": missing (0/10)')

    # ---- Employee checks ----
    # Get Product Management department id (may not exist if dept check failed)
    dept_id = _query_scalar(
        exec_env,
        f"SELECT id FROM main_departments WHERE deptname='{_EXPECTED_DEPT}' AND isactive=1 LIMIT 1;"
    )

    for emp in _EXPECTED_EMPLOYEES:
        empid = emp['empid']
        pts = emp['pts']

        # Check employee exists and is active
        user_row = _query_scalar(
            exec_env,
            f"SELECT id, department_id FROM main_users "
            f"WHERE employeeId='{empid}' AND isactive=1 LIMIT 1;"
        )
        if not user_row or '\t' not in user_row:
            # Try alternate: check by first+last name
            alt_row = _query_scalar(
                exec_env,
                f"SELECT id, department_id FROM main_users "
                f"WHERE firstname='{emp['firstname']}' AND lastname='{emp['lastname']}' "
                f"AND isactive=1 LIMIT 1;"
            )
            user_row = alt_row

        if not user_row:
            feedback_parts.append(f'{empid} ({emp["firstname"]} {emp["lastname"]}): not found (0/{pts})')
            continue

        # Check department assignment
        parts = user_row.split('\t') if '\t' in user_row else [user_row, '']
        actual_dept_id = parts[1].strip() if len(parts) > 1 else ''

        emp_in_correct_dept = dept_id and actual_dept_id and actual_dept_id == dept_id
        if emp_in_correct_dept:
            score += pts
            feedback_parts.append(f'{empid}: exists and in correct dept ({pts}/{pts})')
        else:
            feedback_parts.append(
                f'{empid}: exists but dept mismatch (dept_id={actual_dept_id}, '
                f'expected={dept_id}) (0/{pts})')

    passed = score >= _PASS_THRESHOLD
    return {
        'passed': passed,
        'score': score,
        'feedback': '; '.join(feedback_parts),
    }
