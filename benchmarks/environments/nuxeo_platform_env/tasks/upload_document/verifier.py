#!/usr/bin/env python3
"""Stub verifier for upload_document task.
Actual verification is done externally via VLM evaluators.

Checks that a document titled 'Quarterly Report' (or with name 'Quarterly-Report')
exists in the Projects workspace and has an attached file.
"""

import json


def verify_upload_document(traj, env_info, task_info):
    """Verify that a file document was uploaded to the Projects workspace."""
    exec_in_env = env_info.get("exec_in_env") or env_info.get("exec_capture")

    try:
        # Search for documents with title containing 'Quarterly' in Projects workspace
        result = exec_in_env(
            "curl -s -u Administrator:Administrator "
            "-H 'X-NXproperties: dublincore,file' "
            "\"http://localhost:8080/nuxeo/api/v1/path/default-domain/workspaces/Projects?schemas=dublincore,file\""
        )

        # Check via NXQL search for documents of type File in Projects
        search_result = exec_in_env(
            "curl -s -u Administrator:Administrator "
            "\"http://localhost:8080/nuxeo/api/v1/search/lang/NXQL/execute?"
            "query=SELECT+*+FROM+Document+WHERE+ecm:primaryType='File'"
            "+AND+ecm:path+STARTSWITH+'/default-domain/workspaces/Projects'"
            "+AND+dc:title+LIKE+'%25Quarterly%25'"
            "+AND+ecm:isTrashed=0+AND+ecm:isVersion=0\""
        )

        try:
            search_data = json.loads(search_result)
            entries = search_data.get("entries", [])
            if entries:
                doc = entries[0]
                title = doc.get("properties", {}).get("dc:title", "")
                file_content = doc.get("properties", {}).get("file:content", None)
                has_file = file_content is not None and isinstance(file_content, dict)
                if has_file:
                    return {
                        "passed": True,
                        "score": 100,
                        "feedback": f"File document '{title}' with attachment found in Projects workspace"
                    }
                else:
                    return {
                        "passed": False,
                        "score": 50,
                        "feedback": f"Document '{title}' found but no file attached"
                    }
        except Exception:
            pass

        # Fallback: check by path
        code = exec_in_env(
            "curl -s -o /dev/null -w '%{http_code}' -u Administrator:Administrator "
            "http://localhost:8080/nuxeo/api/v1/path/default-domain/workspaces/Projects/Quarterly-Report"
        )
        if code and "200" in code:
            return {"passed": True, "score": 90, "feedback": "Quarterly Report document found in Projects workspace"}

        return {
            "passed": False,
            "score": 0,
            "feedback": "No document with 'Quarterly' in title found in the Projects workspace"
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
