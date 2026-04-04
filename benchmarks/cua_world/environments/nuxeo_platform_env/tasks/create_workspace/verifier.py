#!/usr/bin/env python3
"""Stub verifier for create_workspace task.
Actual verification is done externally via VLM evaluators.

Checks if 'Marketing Materials' workspace exists in Nuxeo via REST API.
"""

import urllib.request
import urllib.error
import base64
import json


def verify_create_workspace(traj, env_info, task_info):
    """Verify that the 'Marketing Materials' workspace was created."""
    exec_in_env = env_info.get("exec_in_env") or env_info.get("exec_capture")

    try:
        # Check via REST API whether the workspace exists
        result = exec_in_env(
            "curl -s -o /dev/null -w '%{http_code}' -u Administrator:Administrator "
            "http://localhost:8080/nuxeo/api/v1/path/default-domain/workspaces/Marketing-Materials"
        )
        http_code = result.strip().strip("'") if result else ""

        if http_code == "200":
            # Also verify the title
            doc_json = exec_in_env(
                "curl -s -u Administrator:Administrator "
                "-H 'X-NXproperties: dublincore' "
                "http://localhost:8080/nuxeo/api/v1/path/default-domain/workspaces/Marketing-Materials"
            )
            try:
                doc = json.loads(doc_json)
                title = doc.get("properties", {}).get("dc:title", "")
                if "Marketing Materials" in title:
                    return {
                        "passed": True,
                        "score": 100,
                        "feedback": f"Workspace 'Marketing Materials' found with correct title: '{title}'"
                    }
                else:
                    return {
                        "passed": False,
                        "score": 50,
                        "feedback": f"Workspace exists but title is '{title}', expected 'Marketing Materials'"
                    }
            except Exception:
                return {
                    "passed": True,
                    "score": 80,
                    "feedback": "Workspace 'Marketing Materials' exists (title verification skipped)"
                }
        else:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Workspace 'Marketing Materials' not found (HTTP {http_code})"
            }
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
