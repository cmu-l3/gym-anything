#!/usr/bin/env python3
"""Verifier for create_remote_repo task.
Checks that the 'maven-central-proxy' remote repository was created.
Uses the repository list API (individual repo detail is Pro-only in OSS 7.x).
"""
import json


def verify_create_remote_repo(traj, env_info, task_info):
    exec_capture = env_info.get('exec_capture')
    if exec_capture is None:
        return {"passed": False, "score": 0, "feedback": "exec_capture not available"}

    try:
        result = exec_capture(
            'curl -s -u admin:password '
            'http://localhost:8082/artifactory/api/repositories'
        )
        repos = json.loads(result)
        target = next((r for r in repos if r.get('key') == 'maven-central-proxy'), None)
        if target is None:
            return {"passed": False, "score": 0, "feedback": "maven-central-proxy repository not found"}
        repo_type = target.get('type', '').upper()
        if repo_type != 'REMOTE':
            return {"passed": False, "score": 0,
                    "feedback": f"maven-central-proxy found but wrong type: type={repo_type} (expected REMOTE)"}
        url = target.get('url', '')
        # Verify the remote URL points to Maven Central
        maven_central_url = 'repo1.maven.org/maven2'
        url_correct = maven_central_url in url
        if url_correct:
            feedback = f"maven-central-proxy remote repository created with correct URL: {url}"
        else:
            feedback = (f"maven-central-proxy is REMOTE type but URL does not point to Maven Central "
                        f"(got: '{url}', expected URL containing '{maven_central_url}')")
        return {"passed": url_correct, "score": 100 if url_correct else 0, "feedback": feedback}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}
