#!/usr/bin/env python3
"""Verifier for add_user task.
Checks that the user 'john_doe' was created in Artifactory.
Tries individual GET endpoint, then falls back to credential-based auth check.
"""


def verify_add_user(traj, env_info, task_info):
    exec_capture = env_info.get('exec_capture')
    if exec_capture is None:
        return {"passed": False, "score": 0, "feedback": "exec_capture not available"}

    try:
        # Try GET /api/security/users/john_doe (works if OSS allows individual user GET)
        result = exec_capture(
            'curl -s -o /dev/null -w "%{http_code}" -u admin:password '
            'http://localhost:8082/artifactory/api/security/users/john_doe'
        )
        http_code = result.strip()
        if http_code == '200':
            return {"passed": True, "score": 100, "feedback": "User 'john_doe' created successfully"}
        if http_code == '404':
            return {"passed": False, "score": 0, "feedback": "User 'john_doe' not found"}

        # If 400 (Pro-only) or other code, try authenticating as john_doe
        # The task instructions specify password JohnDoe@123
        auth_result = exec_capture(
            'curl -s -o /dev/null -w "%{http_code}" -u "john_doe:JohnDoe@123" '
            'http://localhost:8082/artifactory/api/system/ping'
        )
        auth_code = auth_result.strip()
        if auth_code == '200':
            return {"passed": True, "score": 100,
                    "feedback": "User 'john_doe' verified via authentication (REST API restricted in OSS)"}
        return {"passed": False, "score": 0,
                "feedback": f"Cannot verify john_doe: GET={http_code}, auth={auth_code}"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}
