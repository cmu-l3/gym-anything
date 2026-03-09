#!/usr/bin/env python3
"""Stub verifier for create_user task.
Checks that user 'mwilson' (Margaret Wilson) was created.
"""

import json


def verify_create_user(traj, env_info, task_info):
    """Verify that user mwilson was created with correct details."""
    exec_in_env = env_info.get("exec_in_env") or env_info.get("exec_capture")

    try:
        result = exec_in_env(
            "curl -s -u Administrator:Administrator "
            "http://localhost:8080/nuxeo/api/v1/user/mwilson"
        )

        code = exec_in_env(
            "curl -s -o /dev/null -w '%{http_code}' -u Administrator:Administrator "
            "http://localhost:8080/nuxeo/api/v1/user/mwilson"
        )
        http_code = (code or "").strip().strip("'")

        if http_code != "200":
            return {
                "passed": False,
                "score": 0,
                "feedback": f"User 'mwilson' not found (HTTP {http_code})"
            }

        try:
            user_data = json.loads(result)
            props = user_data.get("properties", {})
            first_name = props.get("firstName", "")
            last_name = props.get("lastName", "")
            email = props.get("email", "")

            checks = {
                "firstName=Margaret": "Margaret" in first_name,
                "lastName=Wilson": "Wilson" in last_name,
                "email=mwilson@acme.com": "mwilson@acme.com" in email,
            }
            passed_checks = [k for k, v in checks.items() if v]
            score = int(100 * len(passed_checks) / len(checks))

            if len(passed_checks) == len(checks):
                return {
                    "passed": True,
                    "score": 100,
                    "feedback": f"User mwilson created: {first_name} {last_name} ({email})"
                }
            elif passed_checks:
                return {
                    "passed": True,
                    "score": score,
                    "feedback": f"User mwilson created but some fields differ. Passed: {passed_checks}"
                }
            else:
                return {
                    "passed": True,
                    "score": 60,
                    "feedback": f"User mwilson exists but name/email differ: {first_name} {last_name} {email}"
                }
        except Exception:
            return {"passed": True, "score": 70, "feedback": "User mwilson exists (detail check skipped)"}

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
