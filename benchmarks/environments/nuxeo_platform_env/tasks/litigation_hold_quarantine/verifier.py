#!/usr/bin/env python3
"""Verifier for litigation_hold_quarantine task.

Checks that the agent correctly implemented the litigation hold per the hold notice:
- 'legal-hold' tag applied to Phoenix-Initiative-Proposal
- 'legal-hold' tag applied to Phoenix-Budget-Analysis
- Hold comment (mentioning case number) added to each in-scope doc
- outside-counsel access removed from in-scope docs
- Collection 'Litigation Hold - Meridian v Acme' created containing both in-scope docs
- Marketing-Campaign-Summary (out-of-scope decoy) NOT tagged 'legal-hold'

Scoring (100 pts total, pass at 60):
  legal-hold tag on Phoenix-Initiative-Proposal:  15 pts
  legal-hold tag on Phoenix-Budget-Analysis:       15 pts
  hold comment on Phoenix-Initiative-Proposal:     10 pts
  hold comment on Phoenix-Budget-Analysis:         10 pts
  outside-counsel removed from in-scope docs:      15 pts
  collection exists and contains both docs:        20 pts
  Marketing-Campaign-Summary NOT tagged (adversarial): 10 pts
  comment references case number 2025-CV-04891:     5 pts
"""

import json

NUXEO_BASE = "http://localhost:8080/nuxeo/api/v1"
AUTH = "Administrator:Administrator"

IN_SCOPE = {
    "Phoenix-Initiative-Proposal": "/default-domain/workspaces/Projects/Phoenix-Initiative-Proposal",
    "Phoenix-Budget-Analysis":     "/default-domain/workspaces/Projects/Phoenix-Budget-Analysis",
}
OUT_OF_SCOPE_PATH = "/default-domain/workspaces/Projects/Marketing-Campaign-Summary"
COLLECTION_TITLE = "Litigation Hold - Meridian v Acme"
CASE_NUMBER = "2025-cv-04891"


def _api(exec_in_env, endpoint):
    cmd = f'curl -s -u {AUTH} -H "X-NXproperties: *" "{NUXEO_BASE}/{endpoint}"'
    raw = exec_in_env(cmd)
    try:
        return json.loads(raw)
    except Exception:
        return {}


def _get_doc(exec_in_env, path):
    return _api(exec_in_env, f"path{path}")


def _get_tags(exec_in_env, path):
    data = _api(exec_in_env, f"path{path}/@tagging")
    return [t.get("label", "").lower() for t in data.get("entries", [])]


def _get_comments(exec_in_env, uid):
    data = _api(exec_in_env, f"id/{uid}/@comment")
    return data.get("entries", [])


def _get_acl(exec_in_env, path):
    """Return ACE list from @acl endpoint."""
    data = _api(exec_in_env, f"path{path}/@acl")
    aces = []
    if isinstance(data, list):
        aces = data
    elif isinstance(data, dict):
        # Nuxeo @acl returns "acl" (singular) in some versions, "acls" in others
        acl_list = data.get("acl") or data.get("acls") or []
        for acl_entry in acl_list:
            aces.extend(acl_entry.get("ace") or acl_entry.get("aces") or [])
    return aces


def _outside_counsel_has_access(exec_in_env, path):
    """Return True if outside-counsel appears as a granted ACE."""
    aces = _get_acl(exec_in_env, path)
    for ace in aces:
        if not isinstance(ace, dict):
            continue
        principal = ace.get("username") or ace.get("id") or ace.get("principal", "")
        granted = ace.get("granted", True)
        if "outside-counsel" in principal.lower() and granted:
            return True
    # Raw text check as fallback
    raw = exec_in_env(f'curl -s -u {AUTH} "{NUXEO_BASE}/path{path}/@acl"')
    return "outside-counsel" in raw and '"granted":true' in raw


def _find_collection(exec_in_env, title):
    safe = title.replace(" ", "+").replace("'", "%27").replace("-", "-")
    data = _api(exec_in_env,
                f"search/lang/NXQL/execute?query=SELECT+*+FROM+Collection+"
                f"WHERE+dc:title%3D%27{safe}%27+AND+ecm:isTrashed%3D0+AND+ecm:isVersion%3D0")
    entries = data.get("entries", [])
    if entries:
        return entries[0].get("uid", "")
    # Fallback: partial title match
    partial = "Litigation+Hold"
    data2 = _api(exec_in_env,
                 f"search/lang/NXQL/execute?query=SELECT+*+FROM+Collection+"
                 f"WHERE+dc:title+LIKE+%27{partial}%25%27+AND+ecm:isTrashed%3D0+AND+ecm:isVersion%3D0")
    entries2 = data2.get("entries", [])
    return entries2[0].get("uid", "") if entries2 else ""


def _collection_members(exec_in_env, coll_uid):
    data = _api(exec_in_env, f"id/{coll_uid}/contents?pageSize=20")
    return [e.get("title", "").lower() for e in data.get("entries", [])]


def verify_litigation_hold_quarantine(traj, env_info, task_info):
    exec_in_env = env_info.get("exec_in_env") or env_info.get("exec_capture")
    score = 0
    details = []

    try:
        # Collect comment text for case number check
        all_comment_texts = []
        inscope_tagged_count = 0

        for name, path in IN_SCOPE.items():
            # -------------------------------------------------------
            # 1 & 2. legal-hold tag on each in-scope doc (15 pts each)
            # -------------------------------------------------------
            tags = _get_tags(exec_in_env, path)
            if "legal-hold" in tags:
                score += 15
                inscope_tagged_count += 1
                details.append(f"PASS: 'legal-hold' tag on {name}")
            else:
                details.append(f"FAIL: no 'legal-hold' tag on {name} (tags={tags})")

            # -------------------------------------------------------
            # 3 & 4. Hold comment on each in-scope doc (10 pts each)
            # -------------------------------------------------------
            doc = _get_doc(exec_in_env, path)
            uid = doc.get("uid", "")
            if uid:
                comments = _get_comments(exec_in_env, uid)
                if comments:
                    score += 10
                    details.append(f"PASS: comment found on {name}")
                    # Gather comment text for case number check
                    for c in comments:
                        text = c.get("text", "") or c.get("comment", "") or str(c)
                        all_comment_texts.append(text.lower())
                else:
                    details.append(f"FAIL: no comment on {name}")
            else:
                details.append(f"FAIL: could not fetch doc uid for {name}")

        # -------------------------------------------------------
        # 5. Case number mentioned in at least one comment (5 pts)
        # -------------------------------------------------------
        if any(CASE_NUMBER in t or "2025-cv" in t or "04891" in t for t in all_comment_texts):
            score += 5
            details.append("PASS: case number referenced in hold comment")
        else:
            details.append("FAIL: case number 2025-CV-04891 not found in any hold comment")

        # -------------------------------------------------------
        # 6. outside-counsel access removed from in-scope docs (15 pts)
        #    Checks both individual doc ACLs and Projects workspace
        # -------------------------------------------------------
        oc_still_has_access = False
        for name, path in IN_SCOPE.items():
            if _outside_counsel_has_access(exec_in_env, path):
                oc_still_has_access = True
                details.append(f"FAIL: outside-counsel still has access on {name}")

        # Also check Projects workspace level
        projects_oc = _outside_counsel_has_access(exec_in_env, "/default-domain/workspaces/Projects")

        if not oc_still_has_access and not projects_oc:
            score += 15
            details.append("PASS: outside-counsel access removed from in-scope docs")
        elif not oc_still_has_access:
            # Doc-level ACLs are clean but Projects workspace still has it
            score += 8
            details.append("PARTIAL: outside-counsel removed from doc ACLs but Projects workspace ACL still has it")
        else:
            details.append("FAIL: outside-counsel still has access on one or more in-scope documents")

        # -------------------------------------------------------
        # 7. Collection 'Litigation Hold - Meridian v Acme' exists and contains both docs (20 pts)
        # -------------------------------------------------------
        coll_uid = _find_collection(exec_in_env, COLLECTION_TITLE)
        if coll_uid:
            members = _collection_members(exec_in_env, coll_uid)
            phoenix_initiative = any("phoenix" in m and ("initiative" in m or "proposal" in m)
                                     for m in members)
            phoenix_budget = any("phoenix" in m and ("budget" in m or "analysis" in m)
                                  for m in members)
            both_found = phoenix_initiative and phoenix_budget
            either_found = phoenix_initiative or phoenix_budget

            if both_found:
                score += 20
                details.append(f"PASS: Collection '{COLLECTION_TITLE}' has both in-scope docs")
            elif either_found:
                score += 10
                details.append(f"PARTIAL: Collection has 1/2 in-scope docs (members={members[:5]})")
            else:
                score += 3
                details.append(f"PARTIAL: Collection exists but missing in-scope docs (members={members[:5]})")
        else:
            details.append(f"FAIL: Collection '{COLLECTION_TITLE}' not found")

        # -------------------------------------------------------
        # 8. Marketing-Campaign-Summary NOT tagged 'legal-hold' (10 pts adversarial)
        #    Only awarded if agent actually tagged in-scope docs (prevents free points)
        # -------------------------------------------------------
        decoy_tags = _get_tags(exec_in_env, OUT_OF_SCOPE_PATH)
        if inscope_tagged_count > 0:
            if "legal-hold" not in decoy_tags:
                score += 10
                details.append("PASS: Marketing-Campaign-Summary (out-of-scope) correctly not tagged")
            else:
                details.append("FAIL: Marketing-Campaign-Summary incorrectly tagged with 'legal-hold'")
        else:
            details.append("INFO: Adversarial check skipped (no in-scope docs tagged yet)")

        # -------------------------------------------------------
        # Final result
        # -------------------------------------------------------
        passed = score >= 60
        feedback = f"Score: {score}/100. " + " | ".join(details)
        return {"passed": passed, "score": score, "feedback": feedback}

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
