#!/usr/bin/env python3
"""Verifier for create_group task.
Checks that the 'developers' group was created in Artifactory.
Primary: GET /api/security/groups/developers — parses JSON body.
Fallback: GET /api/security/groups list — parsed as JSON (not raw string match).
"""
import json


def verify_create_group(traj, env_info, task_info):
    exec_capture = env_info.get('exec_capture')
    if exec_capture is None:
        return {"passed": False, "score": 0, "feedback": "exec_capture not available"}

    try:
        # Primary: fetch individual group and parse JSON body
        result = exec_capture(
            'curl -s -u admin:password '
            'http://localhost:8082/artifactory/api/security/groups/developers'
        )
        try:
            group_data = json.loads(result)
            if isinstance(group_data, dict) and group_data.get('name') == 'developers':
                return {"passed": True, "score": 100,
                        "feedback": "Group 'developers' created successfully"}
            # If the response is an error dict (e.g., {"errors": [...]}) fall through
        except (json.JSONDecodeError, TypeError):
            pass  # Not valid JSON — fall through to list check

        # Fallback: list all groups and search by name using proper JSON parsing
        list_result = exec_capture(
            'curl -s -u admin:password '
            'http://localhost:8082/artifactory/api/security/groups'
        )
        try:
            groups = json.loads(list_result)
            if isinstance(groups, list):
                group_names = [g.get('name', '') for g in groups]
                if 'developers' in group_names:
                    return {"passed": True, "score": 100,
                            "feedback": "Group 'developers' found in groups list"}
                return {"passed": False, "score": 0,
                        "feedback": f"Group 'developers' not found. Groups present: {group_names}"}
        except (json.JSONDecodeError, TypeError):
            pass

        return {"passed": False, "score": 0,
                "feedback": "Cannot verify 'developers' group: individual GET and list API "
                            "both inconclusive (Artifactory OSS 7.x may restrict security APIs)"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}
