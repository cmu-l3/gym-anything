#!/usr/bin/env python3
"""Stub verifier for add_document_tag task.
Checks that the 'finance' tag is applied to the Annual Report 2023 document.
"""

import json


def verify_add_document_tag(traj, env_info, task_info):
    """Verify that the 'finance' tag was added to Annual Report 2023."""
    exec_in_env = env_info.get("exec_in_env") or env_info.get("exec_capture")

    try:
        # Query document tags via the @tags adapter
        result = exec_in_env(
            "curl -s -u Administrator:Administrator "
            "\"http://localhost:8080/nuxeo/api/v1/path/default-domain/workspaces/Projects/Annual-Report-2023/@tags\""
        )

        try:
            tags_data = json.loads(result)
            # Tags response can be a list of tag objects or strings
            if isinstance(tags_data, list):
                tag_labels = []
                for t in tags_data:
                    if isinstance(t, str):
                        tag_labels.append(t.lower())
                    elif isinstance(t, dict):
                        tag_labels.append(t.get("label", "").lower())
                if "finance" in tag_labels:
                    return {"passed": True, "score": 100, "feedback": f"Tag 'finance' found on document. All tags: {tag_labels}"}
        except Exception:
            pass

        # Fallback: search via NXQL for documents tagged 'finance'
        search_result = exec_in_env(
            "curl -s -u Administrator:Administrator "
            "\"http://localhost:8080/nuxeo/api/v1/search/lang/NXQL/execute?"
            "query=SELECT+*+FROM+Document+WHERE+ecm:tag='finance'"
            "+AND+dc:title='Annual+Report+2023'+AND+ecm:isTrashed=0+AND+ecm:isVersion=0\""
        )
        try:
            data = json.loads(search_result)
            if data.get("entries"):
                return {"passed": True, "score": 100, "feedback": "Tag 'finance' confirmed via NXQL query"}
        except Exception:
            pass

        return {
            "passed": False,
            "score": 0,
            "feedback": f"Tag 'finance' not found on Annual Report 2023. Tags response: {result[:200]}"
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
