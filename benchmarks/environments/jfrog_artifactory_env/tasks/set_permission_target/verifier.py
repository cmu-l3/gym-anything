#!/usr/bin/env python3
"""Verifier for set_permission_target task.
Checks that the 'public-read' permission target was created in Artifactory,
granting the 'anonymous' user Read access to 'example-repo-local'.
Primary: GET /api/security/permissions/public-read — parses JSON body.
Fallback: GET /api/security/permissions list — parsed as JSON (not raw string match).
"""
import json


def verify_set_permission_target(traj, env_info, task_info):
    exec_capture = env_info.get('exec_capture')
    if exec_capture is None:
        return {"passed": False, "score": 0, "feedback": "exec_capture not available"}

    perm_name = "public-read"

    try:
        # Primary: fetch individual permission target and parse JSON body
        result = exec_capture(
            'curl -s -u admin:password '
            'http://localhost:8082/artifactory/api/security/permissions/public-read'
        )
        try:
            perm_data = json.loads(result)
            if isinstance(perm_data, dict) and perm_data.get('name') == perm_name:
                # Also verify example-repo-local is in repos and anonymous has read access
                repos = perm_data.get('repositories', [])
                principals = perm_data.get('principals', {})
                users = principals.get('users', {})
                anon_privs = [p.lower() for p in users.get('anonymous', [])]
                repo_ok = 'example-repo-local' in repos
                read_ok = 'r' in anon_privs
                if repo_ok and read_ok:
                    return {"passed": True, "score": 100,
                            "feedback": f"Permission target '{perm_name}' correctly configured: "
                                        f"repos={repos}, anonymous privileges={anon_privs}"}
                issues = []
                if not repo_ok:
                    issues.append(f"example-repo-local not in repos (got: {repos})")
                if not read_ok:
                    issues.append(f"anonymous does not have Read ('r') privilege (got: {anon_privs})")
                return {"passed": False, "score": 0,
                        "feedback": f"Permission target '{perm_name}' exists but misconfigured: "
                                    f"{'; '.join(issues)}"}
            # Response is an error dict — fall through
        except (json.JSONDecodeError, TypeError):
            pass  # Not valid JSON — fall through to list check

        # Fallback: list all permission targets and search by name using JSON parsing
        list_result = exec_capture(
            'curl -s -u admin:password '
            'http://localhost:8082/artifactory/api/security/permissions'
        )
        try:
            perms = json.loads(list_result)
            if isinstance(perms, list):
                perm_names = [p.get('name', '') for p in perms]
                if perm_name in perm_names:
                    return {"passed": True, "score": 100,
                            "feedback": f"Permission target '{perm_name}' found in permissions list"}
                return {"passed": False, "score": 0,
                        "feedback": f"Permission target '{perm_name}' not found. "
                                    f"Permissions present: {perm_names}"}
        except (json.JSONDecodeError, TypeError):
            pass

        return {"passed": False, "score": 0,
                "feedback": f"Cannot verify '{perm_name}': individual GET and list API "
                            "both inconclusive (Artifactory OSS 7.x may restrict security APIs)"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}
