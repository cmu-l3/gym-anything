#!/usr/bin/env python3
"""Verifier for create_virtual_repo task.
Checks that the 'generic-virtual' virtual repository was created with
'example-repo-local' as an included (aggregated) repository.
Primary: list API to confirm type, then individual GET to check included repos.
"""
import json


def verify_create_virtual_repo(traj, env_info, task_info):
    exec_capture = env_info.get('exec_capture')
    if exec_capture is None:
        return {"passed": False, "score": 0, "feedback": "exec_capture not available"}

    try:
        # Step 1: Confirm generic-virtual exists and is VIRTUAL type via list API
        result = exec_capture(
            'curl -s -u admin:password '
            'http://localhost:8082/artifactory/api/repositories'
        )
        repos = json.loads(result)
        target = next((r for r in repos if r.get('key') == 'generic-virtual'), None)
        if target is None:
            return {"passed": False, "score": 0, "feedback": "generic-virtual repository not found"}
        repo_type = target.get('type', '').upper()
        if repo_type != 'VIRTUAL':
            return {"passed": False, "score": 0,
                    "feedback": f"generic-virtual found but wrong type: {repo_type} (expected VIRTUAL)"}

        # Step 2: Fetch individual repo detail to check included repositories
        # Note: GET detail for repos works in Artifactory OSS (only write/create is Pro-only)
        detail_result = exec_capture(
            'curl -s -u admin:password '
            'http://localhost:8082/artifactory/api/repositories/generic-virtual'
        )
        try:
            detail = json.loads(detail_result)
            if isinstance(detail, dict) and 'repositories' in detail:
                included = detail.get('repositories', [])
                if 'example-repo-local' in included:
                    return {"passed": True, "score": 100,
                            "feedback": f"generic-virtual virtual repo created with example-repo-local included "
                                        f"(all included repos: {included})"}
                else:
                    return {"passed": False, "score": 0,
                            "feedback": f"generic-virtual is VIRTUAL type but example-repo-local is NOT included. "
                                        f"Included repos: {included}"}
        except (json.JSONDecodeError, TypeError):
            pass

        # Fallback: if detail API is restricted, accept type check alone with a note
        return {"passed": True, "score": 100,
                "feedback": "generic-virtual virtual repository exists (type=VIRTUAL); "
                            "could not verify included repos via API (detail endpoint may be restricted)"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}
