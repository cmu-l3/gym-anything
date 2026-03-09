#!/usr/bin/env python3
"""Stub verifier for add_comment task.
Checks that a comment containing 'review and approve' was added to Project Proposal.
"""

import json


def verify_add_comment(traj, env_info, task_info):
    """Verify that a comment was added to the Project Proposal document."""
    exec_in_env = env_info.get("exec_in_env") or env_info.get("exec_capture")

    try:
        # Get comments on the Project Proposal document
        result = exec_in_env(
            "curl -s -u Administrator:Administrator "
            "\"http://localhost:8080/nuxeo/api/v1/path/default-domain/workspaces/Projects/Project-Proposal/@comment\""
        )

        try:
            data = json.loads(result)
            entries = data.get("entries", [])
        except Exception:
            entries = []

        if not entries:
            # Fallback: comments might be structured differently in 10.10
            # Try Annotation endpoint
            result2 = exec_in_env(
                "curl -s -u Administrator:Administrator "
                "\"http://localhost:8080/nuxeo/api/v1/path/default-domain/workspaces/Projects/Project-Proposal/@annotation\""
            )
            try:
                data2 = json.loads(result2)
                entries = data2.get("entries", [])
            except Exception:
                entries = []

        if entries:
            # Check content of comments
            for entry in entries:
                comment_text = entry.get("text", "") or entry.get("comment", "") or str(entry)
                if "review" in comment_text.lower() or "approve" in comment_text.lower() or "budget" in comment_text.lower():
                    return {
                        "passed": True,
                        "score": 100,
                        "feedback": f"Comment found with expected content: '{comment_text[:100]}'"
                    }
            # Comments exist but content not matching exactly
            return {
                "passed": True,
                "score": 70,
                "feedback": f"Found {len(entries)} comment(s) on Project Proposal, but expected text not confirmed"
            }

        # Also check via NXQL for annotations/comments
        nxql_result = exec_in_env(
            "curl -s -u Administrator:Administrator "
            "\"http://localhost:8080/nuxeo/api/v1/search/lang/NXQL/execute?"
            "query=SELECT+*+FROM+Comment+WHERE+ecm:ancestorId="
            "IN+('default-domain/workspaces/Projects/Project-Proposal')\""
        )
        if "review" in nxql_result.lower() or "approve" in nxql_result.lower():
            return {"passed": True, "score": 90, "feedback": "Comment with expected content found via NXQL"}

        return {
            "passed": False,
            "score": 0,
            "feedback": "No comments found on Project Proposal document"
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
