#!/usr/bin/env python3
"""Stub verifier for create_note task.
Checks that a Note document with 'Meeting Minutes' and 'October 2023' in the title
exists in the Projects workspace and contains the expected text.
"""

import json


def verify_create_note(traj, env_info, task_info):
    """Verify that the Meeting Minutes note was created with correct content."""
    exec_in_env = env_info.get("exec_in_env") or env_info.get("exec_capture")

    try:
        # Search for Notes in Projects containing "October 2023"
        search_result = exec_in_env(
            "curl -s -u Administrator:Administrator "
            "\"http://localhost:8080/nuxeo/api/v1/search/lang/NXQL/execute?"
            "query=SELECT+*+FROM+Note+WHERE+ecm:path+STARTSWITH"
            "+'/default-domain/workspaces/Projects'"
            "+AND+dc:title+LIKE+'%25October+2023%25'"
            "+AND+ecm:isTrashed=0+AND+ecm:isVersion=0\""
        )

        try:
            data = json.loads(search_result)
            entries = data.get("entries", [])
        except Exception:
            entries = []

        if not entries:
            # Try broader search
            search_result2 = exec_in_env(
                "curl -s -u Administrator:Administrator "
                "\"http://localhost:8080/nuxeo/api/v1/search/lang/NXQL/execute?"
                "query=SELECT+*+FROM+Note+WHERE+ecm:path+STARTSWITH"
                "+'/default-domain/workspaces/Projects'"
                "+AND+dc:title+LIKE+'%25Meeting+Minutes%25'"
                "+AND+ecm:isTrashed=0+AND+ecm:isVersion=0\""
            )
            try:
                data2 = json.loads(search_result2)
                entries = data2.get("entries", [])
            except Exception:
                entries = []

        if not entries:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No Note document with 'Meeting Minutes' and 'October 2023' found in Projects workspace"
            }

        doc = entries[0]
        title = doc.get("properties", {}).get("dc:title", "")
        note_content = doc.get("properties", {}).get("note:note", "")

        # Check title
        title_ok = "Meeting Minutes" in title and "October 2023" in title

        # Check content
        content_ok = "Action items" in note_content or "action items" in note_content or "October 2023" in note_content

        if title_ok and content_ok:
            return {"passed": True, "score": 100, "feedback": f"Note '{title}' with correct content found"}
        elif title_ok:
            return {"passed": True, "score": 80, "feedback": f"Note '{title}' found but expected content not verified"}
        else:
            return {"passed": False, "score": 30, "feedback": f"Found note but title is '{title}', expected to contain 'Meeting Minutes - October 2023'"}

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
