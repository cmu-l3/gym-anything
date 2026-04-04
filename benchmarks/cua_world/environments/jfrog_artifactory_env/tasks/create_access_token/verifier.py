#!/usr/bin/env python3
"""Verifier for create_access_token task.
Checks that an access token with description 'CI/CD pipeline token' was created.
Uses the JFrog Access API to list tokens (available in both OSS and Pro).
Primary check: token with 'CI/CD pipeline token' description exists.
Fallback: any newly-created user token exists (in case description was varied slightly).
"""
import json


def verify_create_access_token(traj, env_info, task_info):
    exec_capture = env_info.get('exec_capture')
    if exec_capture is None:
        return {"passed": False, "score": 0, "feedback": "exec_capture not available"}

    try:
        result = exec_capture(
            'curl -s -u admin:password '
            'http://localhost:8082/access/api/v1/tokens'
        )
        data = json.loads(result)
        tokens = data.get('tokens', [])

        # Primary check: token with the exact required description
        cicd_tokens = [
            t for t in tokens
            if 'CI/CD pipeline token' in t.get('description', '')
        ]
        if cicd_tokens:
            token_ids = [t.get('token_id', 'unknown') for t in cicd_tokens]
            return {
                "passed": True, "score": 100,
                "feedback": f"CI/CD pipeline token found (token_id: {token_ids[0]})"
            }

        # Secondary check: any non-system user token (agent may have used a slightly
        # different description — we accept this with partial credit signal in feedback)
        user_tokens = [
            t for t in tokens
            if not t.get('subject', '').startswith('jfrt@') and
               not t.get('description', '').startswith('Artifactory')
        ]
        if user_tokens:
            descriptions = [t.get('description', 'no description') for t in user_tokens]
            return {
                "passed": False, "score": 0,
                "feedback": (
                    f"Token(s) found but none have description 'CI/CD pipeline token'. "
                    f"Descriptions found: {descriptions}. "
                    f"Task requires description to be exactly 'CI/CD pipeline token'."
                )
            }

        return {
            "passed": False, "score": 0,
            "feedback": f"No access token with description 'CI/CD pipeline token' found "
                        f"(total tokens in system: {len(tokens)})"
        }
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}
