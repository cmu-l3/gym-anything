#!/usr/bin/env python3
"""Verifier for create_security_policy task.
Checks that the 'Bring Your Own Device (BYOD) Policy' was created in Eramba.
In eramba, security_policies uses 'index' field for the policy name.
"""


def verify_create_security_policy(traj, env_info, task_info):
    exec_in_env = env_info.get('exec_in_env') or env_info.get('exec_capture')
    if not exec_in_env:
        return {"passed": False, "score": 0, "feedback": "exec_capture not available"}

    result = exec_in_env(
        'docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e '
        '"SELECT id, \\`index\\`, status FROM security_policies WHERE '
        '(\\`index\\` LIKE \'%BYOD%\' OR \\`index\\` LIKE \'%Bring Your Own Device%\' OR '
        'short_description LIKE \'%BYOD%\') AND deleted=0 LIMIT 1;" 2>/dev/null'
    )

    if not result or not result.strip():
        return {"passed": False, "score": 0, "feedback": "Security policy 'BYOD' not found in database"}

    # Check status is Draft (status=0 in Eramba)
    parts = result.strip().split('\t')
    if len(parts) >= 3:
        status = parts[2].strip()
        if status != '0':
            return {"passed": False, "score": 0,
                    "feedback": f"Policy found but status is not Draft (status={status}, expected 0=Draft)"}

    return {"passed": True, "score": 100, "feedback": f"Security policy found with Draft status: {result.strip()}"}
