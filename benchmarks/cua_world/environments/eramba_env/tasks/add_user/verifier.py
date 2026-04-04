#!/usr/bin/env python3
"""Verifier for add_user task.
Checks that user Alexandra Chen (login: achen) was created in Eramba.
"""


def verify_add_user(traj, env_info, task_info):
    exec_in_env = env_info.get('exec_in_env') or env_info.get('exec_capture')
    if not exec_in_env:
        return {"passed": False, "score": 0, "feedback": "exec_capture not available"}

    result = exec_in_env(
        'docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e '
        '"SELECT id, name, login, email FROM users WHERE login=\'achen\' OR '
        '(name LIKE \'%Alexandra%\' AND name LIKE \'%Chen%\') LIMIT 1;" 2>/dev/null'
    )

    if result and result.strip():
        return {"passed": True, "score": 100, "feedback": f"User Alexandra Chen found: {result.strip()}"}

    return {"passed": False, "score": 0, "feedback": "User Alexandra Chen (achen) not found in database"}
