#!/usr/bin/env python3
"""Verifier for access_control_audit task.

Checks that the agent performed the quarterly access review per the Access Review Policy:
- dpatel (departed employee) has no access on Templates workspace
- lnovak's 'Everything' permission on Projects was downgraded to ReadWrite (or less)
- 'iam-auditors' group was created
- iam-auditors has Read access on Projects workspace
- iam-auditors has Read access on Templates workspace
- Audit trail comment added to at least one modified workspace
- access_review_report.csv (or similar) uploaded to Templates workspace

Setup state:
  Templates workspace local ACL: dpatel (departed, ReadWrite) → must be revoked
  Projects workspace local ACL:  lnovak (contractor, Everything) → must be downgraded

Scoring (100 pts total, pass at 60):
  dpatel removed from Templates:                  20 pts
  lnovak downgraded from 'Everything' on Projects: 15 pts
  iam-auditors group created:                     10 pts
  iam-auditors Read on Projects:                  12 pts
  iam-auditors Read on Templates:                  8 pts
  audit trail comment on workspace(s):            10 pts
  access review CSV uploaded to Templates:        25 pts
"""

import json

NUXEO_BASE = "http://localhost:8080/nuxeo/api/v1"
AUTH = "Administrator:Administrator"


def _api(exec_in_env, endpoint):
    cmd = f'curl -s -u {AUTH} -H "X-NXproperties: *" "{NUXEO_BASE}/{endpoint}"'
    raw = exec_in_env(cmd)
    try:
        return json.loads(raw)
    except Exception:
        return {}


def _get_aces(exec_in_env, path):
    """Return list of ACE dicts from a workspace path."""
    data = _api(exec_in_env, f"path{path}/@acl")
    aces = []
    if isinstance(data, list):
        aces = data
    elif isinstance(data, dict):
        # Nuxeo @acl returns "acl" (singular) in some versions, "acls" in others
        acl_list = data.get("acl") or data.get("acls") or []
        for acl_entry in acl_list:
            # Similarly "ace" (singular) or "aces" (plural)
            aces.extend(acl_entry.get("ace") or acl_entry.get("aces") or [])
    return aces


def _user_in_aces(aces, username, require_granted=True):
    """Return the permission string if user found in ACEs, else None."""
    for ace in aces:
        if not isinstance(ace, dict):
            continue
        principal = ace.get("username") or ace.get("id") or ace.get("principal", "")
        granted = ace.get("granted", True)
        perm = ace.get("permission") or ace.get("right", "")
        if username.lower() in principal.lower():
            if not require_granted or granted:
                return perm
    return None


def _get_group(exec_in_env, groupname):
    cmd = f'curl -s -u {AUTH} "{NUXEO_BASE}/group/{groupname}"'
    raw = exec_in_env(cmd)
    try:
        return json.loads(raw)
    except Exception:
        return {}


def _has_comment(exec_in_env, uid):
    data = _api(exec_in_env, f"id/{uid}/@comment")
    entries = data.get("entries", [])
    # Look for audit-related text in comments
    for e in entries:
        text = (e.get("text", "") or e.get("comment", "") or "").lower()
        if any(kw in text for kw in ["audit", "iam", "revoked", "dpatel", "permission", "access review"]):
            return True
    return len(entries) > 0  # Any comment counts


def _find_uploaded_report(exec_in_env):
    """Search Templates workspace for a File document with 'access' or 'review' or 'audit' in title."""
    data = _api(exec_in_env,
                "search/lang/NXQL/execute?query=SELECT+*+FROM+Document+"
                "WHERE+ecm:path+STARTSWITH+%27/default-domain/workspaces/Templates%27+"
                "AND+(dc:title+LIKE+%27%25access%25%27+OR+dc:title+LIKE+%27%25review%25%27+"
                "OR+dc:title+LIKE+%27%25audit%25%27+OR+dc:title+LIKE+%27%25report%25%27)+"
                "AND+ecm:isTrashed%3D0+AND+ecm:isVersion%3D0")
    entries = data.get("entries", [])
    # Must be a File type (uploaded doc) not a Note
    for e in entries:
        if e.get("type") in ["File", "Document"]:
            return e
    return None


def verify_access_control_audit(traj, env_info, task_info):
    exec_in_env = env_info.get("exec_in_env") or env_info.get("exec_capture")
    score = 0
    details = []

    try:
        projects_path = "/default-domain/workspaces/Projects"
        templates_path = "/default-domain/workspaces/Templates"

        projects_aces = _get_aces(exec_in_env, projects_path)
        templates_aces = _get_aces(exec_in_env, templates_path)

        # -------------------------------------------------------
        # 1. dpatel removed from Templates workspace (20 pts)
        #    Setup seeded dpatel (departed employee) with ReadWrite on Templates
        # -------------------------------------------------------
        dpatel_templates = _user_in_aces(templates_aces, "dpatel")
        if dpatel_templates is None:
            # Also check raw text to confirm absence
            raw_templates = exec_in_env(f'curl -s -u {AUTH} "{NUXEO_BASE}/path{templates_path}/@acl"')
            if "dpatel" not in raw_templates:
                score += 20
                details.append("PASS: dpatel access revoked from Templates workspace")
            else:
                score += 10
                details.append("PARTIAL: dpatel appears in Templates ACL raw but not as explicit ACE")
        else:
            details.append(f"FAIL: dpatel still has '{dpatel_templates}' on Templates workspace")

        # -------------------------------------------------------
        # 2. lnovak downgraded from 'Everything' on Projects (15 pts)
        #    Setup seeded lnovak (contractor) with Everything on Projects
        # -------------------------------------------------------
        lnovak_perm = _user_in_aces(projects_aces, "lnovak")
        if lnovak_perm is None:
            # Fully removed is also acceptable
            score += 15
            details.append("PASS: lnovak access removed from Projects (fully revoked)")
        elif lnovak_perm.lower() in ["readwrite", "read"]:
            score += 15
            details.append(f"PASS: lnovak downgraded to '{lnovak_perm}' on Projects (was Everything)")
        elif lnovak_perm.lower() == "everything":
            details.append("FAIL: lnovak still has 'Everything' on Projects (not downgraded)")
        else:
            score += 7
            details.append(f"PARTIAL: lnovak has '{lnovak_perm}' on Projects")

        # -------------------------------------------------------
        # 4. iam-auditors group created (10 pts)
        # -------------------------------------------------------
        grp = _get_group(exec_in_env, "iam-auditors")
        grp_id = grp.get("groupname", "") or grp.get("id", "")
        if grp_id == "iam-auditors":
            score += 10
            details.append("PASS: 'iam-auditors' group created")
        else:
            details.append("FAIL: 'iam-auditors' group not found")

        # -------------------------------------------------------
        # 5. iam-auditors Read on Projects (12 pts)
        # -------------------------------------------------------
        iam_projects = _user_in_aces(projects_aces, "iam-auditors")
        if iam_projects and iam_projects.lower() in ["read", "readwrite", "everything"]:
            score += 12
            details.append(f"PASS: iam-auditors has '{iam_projects}' on Projects")
        else:
            # Raw fallback check
            raw_projects = exec_in_env(f'curl -s -u {AUTH} "{NUXEO_BASE}/path{projects_path}/@acl"')
            if "iam-auditors" in raw_projects:
                score += 12
                details.append("PASS: iam-auditors found in Projects ACL (raw check)")
            else:
                details.append(f"FAIL: iam-auditors not found in Projects ACL (got: {iam_projects})")

        # -------------------------------------------------------
        # 6. iam-auditors Read on Templates (8 pts)
        # -------------------------------------------------------
        iam_templates = _user_in_aces(templates_aces, "iam-auditors")
        if iam_templates and iam_templates.lower() in ["read", "readwrite", "everything"]:
            score += 8
            details.append(f"PASS: iam-auditors has '{iam_templates}' on Templates")
        else:
            raw_templates = exec_in_env(f'curl -s -u {AUTH} "{NUXEO_BASE}/path{templates_path}/@acl"')
            if "iam-auditors" in raw_templates:
                score += 8
                details.append("PASS: iam-auditors found in Templates ACL (raw check)")
            else:
                details.append(f"FAIL: iam-auditors not found in Templates ACL")

        # -------------------------------------------------------
        # 7. Audit trail comment on at least one modified workspace (10 pts)
        # -------------------------------------------------------
        comment_found = False
        for ws_path in [projects_path, templates_path]:
            ws_doc = _api(exec_in_env, f"path{ws_path}")
            ws_uid = ws_doc.get("uid", "")
            if ws_uid and _has_comment(exec_in_env, ws_uid):
                comment_found = True
                details.append(f"PASS: audit trail comment found on {ws_path}")
                break

        if comment_found:
            score += 10
        else:
            details.append("FAIL: no audit trail comment found on Projects or Templates workspace")

        # -------------------------------------------------------
        # 8. access_review_report.csv uploaded to Templates (25 pts)
        # -------------------------------------------------------
        uploaded = _find_uploaded_report(exec_in_env)
        if uploaded:
            score += 25
            details.append(f"PASS: access review report uploaded to Templates: '{uploaded.get('title', '')}'")
        else:
            details.append("FAIL: no access review report file uploaded to Templates workspace")

        # -------------------------------------------------------
        # Final result
        # -------------------------------------------------------
        passed = score >= 60
        feedback = f"Score: {score}/100. " + " | ".join(details)
        return {"passed": passed, "score": score, "feedback": feedback}

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
