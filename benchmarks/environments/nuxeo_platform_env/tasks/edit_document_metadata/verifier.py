#!/usr/bin/env python3
"""Stub verifier for edit_document_metadata task.
Checks that the description of 'Annual Report 2023' contains the expected text.
"""

import json


def verify_edit_document_metadata(traj, env_info, task_info):
    """Verify that the Annual Report 2023 description was updated."""
    exec_in_env = env_info.get("exec_in_env") or env_info.get("exec_capture")

    try:
        result = exec_in_env(
            "curl -s -u Administrator:Administrator "
            "-H 'X-NXproperties: dublincore' "
            "http://localhost:8080/nuxeo/api/v1/path/default-domain/workspaces/Projects/Annual-Report-2023"
        )
        try:
            doc = json.loads(result)
            description = doc.get("properties", {}).get("dc:description", "")
        except Exception:
            return {"passed": False, "score": 0, "feedback": "Could not parse document metadata response"}

        expected_keywords = ["annual", "financial", "fiscal", "2023"]
        found_keywords = [kw for kw in expected_keywords if kw.lower() in description.lower()]

        if len(found_keywords) >= 2 and len(description) > 50:
            return {
                "passed": True,
                "score": 100,
                "feedback": f"Description updated to: '{description[:100]}...'"
            }
        elif len(description) > 20:
            return {
                "passed": True,
                "score": 70,
                "feedback": f"Description updated to: '{description}' — partially matches expected content"
            }
        else:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Description not sufficiently updated (current value: '{description}')"
            }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
