#!/usr/bin/env python3
"""Stub verifier for add_to_collection task.
Checks that Annual Report 2023 is in the 'Q4 2023 Documents' collection.
"""

import json


def verify_add_to_collection(traj, env_info, task_info):
    """Verify that Annual Report 2023 was added to Q4 2023 Documents collection."""
    exec_in_env = env_info.get("exec_in_env") or env_info.get("exec_capture")

    try:
        # Get the collection UID
        coll_result = exec_in_env(
            "curl -s -u Administrator:Administrator "
            "\"http://localhost:8080/nuxeo/api/v1/search/lang/NXQL/execute?"
            "query=SELECT+*+FROM+Collection+WHERE+dc:title='Q4+2023+Documents'"
            "+AND+ecm:isTrashed=0+AND+ecm:isVersion=0\""
        )
        try:
            coll_data = json.loads(coll_result)
            entries = coll_data.get("entries", [])
        except Exception:
            return {"passed": False, "score": 0, "feedback": "Q4 2023 Documents collection not found"}

        if not entries:
            return {"passed": False, "score": 0, "feedback": "Collection 'Q4 2023 Documents' does not exist"}

        coll_uid = entries[0].get("uid", "")

        # Get documents in the collection
        members_result = exec_in_env(
            f"curl -s -u Administrator:Administrator "
            f"\"http://localhost:8080/nuxeo/api/v1/id/{coll_uid}/@collection\""
        )

        try:
            members_data = json.loads(members_result)
            member_entries = members_data.get("entries", [])
            for member in member_entries:
                title = member.get("properties", {}).get("dc:title", "")
                if "Annual Report" in title or "Annual-Report" in member.get("path", ""):
                    return {
                        "passed": True,
                        "score": 100,
                        "feedback": f"Annual Report 2023 found in Q4 2023 Documents collection"
                    }
        except Exception:
            pass

        # Fallback: check if Annual Report references the collection
        doc_result = exec_in_env(
            "curl -s -u Administrator:Administrator "
            "-H 'X-NXproperties: *' "
            "\"http://localhost:8080/nuxeo/api/v1/path/default-domain/workspaces/Projects/Annual-Report-2023\""
        )
        if coll_uid and coll_uid in doc_result:
            return {
                "passed": True,
                "score": 90,
                "feedback": "Annual Report 2023 references the Q4 2023 Documents collection"
            }

        return {
            "passed": False,
            "score": 0,
            "feedback": "Annual Report 2023 not found in Q4 2023 Documents collection"
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
