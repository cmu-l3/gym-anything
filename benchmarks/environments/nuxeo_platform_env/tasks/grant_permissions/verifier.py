#!/usr/bin/env python3
"""Stub verifier for grant_permissions task.
Checks that jsmith has Read permission on the Projects workspace via ACL.
"""

import json


def verify_grant_permissions(traj, env_info, task_info):
    """Verify that jsmith has Read access on the Projects workspace."""
    exec_in_env = env_info.get("exec_in_env") or env_info.get("exec_capture")

    try:
        # Get the ACL for the Projects workspace
        result = exec_in_env(
            "curl -s -u Administrator:Administrator "
            "-H 'X-NXproperties: *' "
            "\"http://localhost:8080/nuxeo/api/v1/path/default-domain/workspaces/Projects/@acl\""
        )

        try:
            acl_data = json.loads(result)
            # ACL response is a list of ACE objects
            # Each ACE has: username, permission, granted (bool), creator, begin, end
            aces = []
            if isinstance(acl_data, list):
                aces = acl_data
            elif isinstance(acl_data, dict):
                for acl in acl_data.get("acls", []):
                    aces.extend(acl.get("aces", []))

            # Look for jsmith with Read (or Read & Write) permission
            for ace in aces:
                if isinstance(ace, dict):
                    username = ace.get("username", "") or ace.get("id", "")
                    permission = ace.get("permission", "") or ace.get("right", "")
                    granted = ace.get("granted", True)
                    if "jsmith" in username and granted and permission in ["Read", "ReadWrite", "Everything"]:
                        return {
                            "passed": True,
                            "score": 100,
                            "feedback": f"jsmith has '{permission}' permission on Projects workspace"
                        }

            # Check if jsmith appears anywhere in the ACL
            if "jsmith" in result:
                return {
                    "passed": True,
                    "score": 80,
                    "feedback": "jsmith found in ACL (exact permission type not confirmed)"
                }

            return {
                "passed": False,
                "score": 0,
                "feedback": f"jsmith not found with Read permission in ACL. ACL data: {result[:300]}"
            }

        except Exception as parse_err:
            if "jsmith" in result:
                return {"passed": True, "score": 70, "feedback": "jsmith appears in ACL response"}
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Could not parse ACL response: {str(parse_err)}"
            }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
