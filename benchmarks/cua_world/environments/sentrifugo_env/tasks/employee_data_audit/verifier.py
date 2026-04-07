#!/usr/bin/env python3
"""
Verifier for employee_data_audit task.

The setup injected wrong department and job title for 4 employees:
  EMP003 David Nguyen:   correct = Finance Manager / Finance & Accounting
  EMP007 Robert Patel:   correct = Senior Data Scientist / Data Science
  EMP011 Matthew Garcia: correct = Marketing Specialist / Marketing
  EMP015 Kevin Hernandez: correct = Systems Engineer / DevOps & Infrastructure

Scoring (100 pts total):
  - Each employee correctly fixed: 25 pts
    - Department correct:  15 pts
    - Job title correct:   10 pts
  Pass threshold: 70 pts (at least 3 employees fully fixed, or 4 with both fields)
"""

_DB_CMD = (
    "docker exec sentrifugo-db mysql -u sentrifugo -psentrifugo123 sentrifugo "
    "-N -B -e \"{query}\""
)

_CORRECT = {
    'EMP003': {'dept': 'Finance & Accounting', 'jobtitle': 'Finance Manager'},
    'EMP007': {'dept': 'Data Science',         'jobtitle': 'Senior Data Scientist'},
    'EMP011': {'dept': 'Marketing',            'jobtitle': 'Marketing Specialist'},
    'EMP015': {'dept': 'DevOps & Infrastructure', 'jobtitle': 'Systems Engineer'},
}

_PASS_THRESHOLD = 70


def _query_employee(exec_env, empid):
    """Return (dept_name, jobtitle_name) for the given employeeId, or (None, None)."""
    sql = (
        "SELECT d.deptname, j.jobtitlename "
        "FROM main_users u "
        "JOIN main_departments d ON u.department_id = d.id "
        "JOIN main_jobtitles j ON u.jobtitle_id = j.id "
        f"WHERE u.employeeId='{empid}' AND u.isactive=1 LIMIT 1;"
    )
    try:
        raw = exec_env(_DB_CMD.format(query=sql)).strip()
    except Exception:
        return None, None
    if not raw or '\t' not in raw:
        return None, None
    parts = raw.split('\t', 1)
    return parts[0].strip(), parts[1].strip()


def verify_employee_data_audit(traj, env_info, task_info):
    exec_env = env_info.get('exec_in_env') or env_info.get('exec_capture')
    if exec_env is None:
        return {'passed': False, 'score': 0,
                'feedback': 'exec_in_env not available in env_info'}

    score = 0
    feedback_parts = []

    for empid, expected in _CORRECT.items():
        actual_dept, actual_title = _query_employee(exec_env, empid)

        if actual_dept is None:
            feedback_parts.append(f'{empid}: could not read record (0/25)')
            continue

        dept_ok = actual_dept == expected['dept']
        title_ok = actual_title == expected['jobtitle']

        emp_score = 0
        if dept_ok:
            emp_score += 15
        if title_ok:
            emp_score += 10

        score += emp_score

        if dept_ok and title_ok:
            feedback_parts.append(f'{empid}: fully correct (25/25)')
        elif dept_ok:
            feedback_parts.append(
                f'{empid}: dept OK but title wrong — got "{actual_title}", '
                f'expected "{expected["jobtitle"]}" (15/25)')
        elif title_ok:
            feedback_parts.append(
                f'{empid}: title OK but dept wrong — got "{actual_dept}", '
                f'expected "{expected["dept"]}" (10/25)')
        else:
            feedback_parts.append(
                f'{empid}: both wrong — dept="{actual_dept}", title="{actual_title}" (0/25)')

    passed = score >= _PASS_THRESHOLD
    return {
        'passed': passed,
        'score': score,
        'feedback': '; '.join(feedback_parts),
    }
