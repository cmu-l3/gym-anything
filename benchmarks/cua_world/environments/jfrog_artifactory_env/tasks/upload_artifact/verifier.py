#!/usr/bin/env python3
"""Verifier for upload_artifact task.
Checks that commons-io-2.15.1.jar was uploaded to example-repo-local.
Uses the Artifactory quick search API (available in OSS 7.x).
"""
import json


def verify_upload_artifact(traj, env_info, task_info):
    exec_capture = env_info.get('exec_capture')
    if exec_capture is None:
        return {"passed": False, "score": 0, "feedback": "exec_capture not available"}

    try:
        # Search for the artifact by name in example-repo-local
        result = exec_capture(
            'curl -s -u admin:password '
            '"http://localhost:8082/artifactory/api/search/quick'
            '?name=commons-io-2.15.1.jar&repos=example-repo-local"'
        )
        data = json.loads(result)
        results = data.get('results', [])
        if len(results) > 0:
            return {"passed": True, "score": 100,
                    "feedback": f"commons-io-2.15.1.jar found in example-repo-local ({len(results)} result(s))"}

        # Also try searching by artifact name pattern (in case exact name differs)
        result2 = exec_capture(
            'curl -s -u admin:password '
            '"http://localhost:8082/artifactory/api/search/quick'
            '?name=commons-io*.jar&repos=example-repo-local"'
        )
        data2 = json.loads(result2)
        results2 = data2.get('results', [])
        if len(results2) > 0:
            names = [r.get('uri', '').split('/')[-1] for r in results2]
            return {"passed": True, "score": 100,
                    "feedback": f"Commons-IO JAR found in example-repo-local: {names}"}

        return {"passed": False, "score": 0,
                "feedback": "commons-io-2.15.1.jar not found in example-repo-local"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}
