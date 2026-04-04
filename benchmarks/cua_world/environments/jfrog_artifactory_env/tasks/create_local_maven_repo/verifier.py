#!/usr/bin/env python3
"""Verifier for create_local_maven_repo task.
Checks that the 'team-releases' Maven local repository was created.
Uses the repository list API (individual repo detail is Pro-only in OSS 7.x).
"""
import json


def verify_create_local_maven_repo(traj, env_info, task_info):
    exec_capture = env_info.get('exec_capture')
    if exec_capture is None:
        return {"passed": False, "score": 0, "feedback": "exec_capture not available"}

    try:
        result = exec_capture(
            'curl -s -u admin:password '
            'http://localhost:8082/artifactory/api/repositories'
        )
        repos = json.loads(result)
        # Find team-releases in the list
        target = next((r for r in repos if r.get('key') == 'team-releases'), None)
        if target is None:
            return {"passed": False, "score": 0, "feedback": "team-releases repository not found"}
        repo_type = target.get('type', '').upper()
        pkg_type = target.get('packageType', '').lower()
        passed = repo_type == 'LOCAL' and pkg_type == 'maven'
        if passed:
            feedback = "team-releases repository created successfully (local Maven)"
        else:
            feedback = f"team-releases found but wrong type: type={repo_type}, packageType={pkg_type}"
        return {"passed": passed, "score": 100 if passed else 0, "feedback": feedback}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}
