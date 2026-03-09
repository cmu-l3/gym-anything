#!/usr/bin/env python3
"""Stub verifier for create_collection task.
Checks that a Collection named '2024 Planning Documents' exists.
"""

import json


def verify_create_collection(traj, env_info, task_info):
    """Verify that the '2024 Planning Documents' collection was created."""
    exec_in_env = env_info.get("exec_in_env") or env_info.get("exec_capture")

    try:
        result = exec_in_env(
            "curl -s -u Administrator:Administrator "
            "\"http://localhost:8080/nuxeo/api/v1/search/lang/NXQL/execute?"
            "query=SELECT+*+FROM+Collection+WHERE+dc:title='2024+Planning+Documents'"
            "+AND+ecm:isTrashed=0+AND+ecm:isVersion=0\""
        )

        try:
            data = json.loads(result)
            entries = data.get("entries", [])
            if entries:
                title = entries[0].get("properties", {}).get("dc:title", "")
                return {
                    "passed": True,
                    "score": 100,
                    "feedback": f"Collection '{title}' found (uid={entries[0].get('uid','')})"
                }
        except Exception:
            pass

        # Try broader search for any collection with "2024 Planning" in title
        result2 = exec_in_env(
            "curl -s -u Administrator:Administrator "
            "\"http://localhost:8080/nuxeo/api/v1/search/lang/NXQL/execute?"
            "query=SELECT+*+FROM+Collection+WHERE+dc:title+LIKE+'%252024+Planning%25'"
            "+AND+ecm:isTrashed=0+AND+ecm:isVersion=0\""
        )
        try:
            data2 = json.loads(result2)
            if data2.get("entries"):
                title = data2["entries"][0].get("properties", {}).get("dc:title", "")
                return {
                    "passed": True,
                    "score": 80,
                    "feedback": f"Collection found with similar title: '{title}'"
                }
        except Exception:
            pass

        return {
            "passed": False,
            "score": 0,
            "feedback": "Collection '2024 Planning Documents' not found"
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
