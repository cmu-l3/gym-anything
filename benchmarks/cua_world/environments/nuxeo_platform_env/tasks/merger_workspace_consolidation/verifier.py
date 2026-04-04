#!/usr/bin/env python3
"""Verifier for merger_workspace_consolidation task.

Checks that the agent consolidated two legacy division workspaces per the Merger
Integration Plan:
- 'Integrated Operations' workspace created
- 'Product Development' sub-workspace created under Integrated Operations
- 'Corporate Services' sub-workspace created under Integrated Operations
- Project/roadmap docs migrated to Product Development
- Budget/metrics docs migrated to Corporate Services
- All migrated docs have descriptions >= 20 characters
- 'integrated-team' group created with all members from alpha-team + beta-team
- integrated-team has ReadWrite access on Integrated Operations

Scoring (100 pts total, pass at 60):
  Integrated Operations workspace exists:          10 pts
  Product Development sub-workspace exists:         8 pts
  Corporate Services sub-workspace exists:          8 pts
  Project/roadmap docs in Product Development:     12 pts
  Budget/metrics docs in Corporate Services:       12 pts
  All migrated docs have desc >= 20 chars:         10 pts
  integrated-team group exists:                    10 pts
  integrated-team has all 4 expected members:      15 pts
  integrated-team ReadWrite on Integrated Ops:     15 pts
"""

import json

NUXEO_BASE = "http://localhost:8080/nuxeo/api/v1"
AUTH = "Administrator:Administrator"

# Members that should be in integrated-team (from alpha-team + beta-team)
EXPECTED_MEMBERS = {"acohen", "jsmith", "mgarcia", "tchen"}


def _api(exec_in_env, endpoint):
    cmd = f'curl -s -u {AUTH} -H "X-NXproperties: *" "{NUXEO_BASE}/{endpoint}"'
    raw = exec_in_env(cmd)
    try:
        return json.loads(raw)
    except Exception:
        return {}


def _nxql(exec_in_env, query):
    safe = query.replace(" ", "+").replace("'", "%27")
    return _api(exec_in_env, f"search/lang/NXQL/execute?query={safe}&pageSize=50")


def _children(exec_in_env, path):
    data = _api(exec_in_env, f"path{path}/@children?pageSize=50")
    return data.get("entries", [])


def _get_doc(exec_in_env, path):
    return _api(exec_in_env, f"path{path}")


def _get_group(exec_in_env, groupname):
    cmd = f'curl -s -u {AUTH} "{NUXEO_BASE}/group/{groupname}"'
    raw = exec_in_env(cmd)
    try:
        return json.loads(raw)
    except Exception:
        return {}


def _get_acl(exec_in_env, path):
    data = _api(exec_in_env, f"path{path}/@acl")
    aces = []
    if isinstance(data, list):
        aces = data
    elif isinstance(data, dict):
        # Nuxeo @acl returns "acl" (singular) in some versions, "acls" in others
        acl_list = data.get("acl") or data.get("acls") or []
        for acl in acl_list:
            aces.extend(acl.get("ace") or acl.get("aces") or [])
    return aces


def verify_merger_workspace_consolidation(traj, env_info, task_info):
    exec_in_env = env_info.get("exec_in_env") or env_info.get("exec_capture")
    score = 0
    details = []

    try:
        # -------------------------------------------------------
        # 1. Integrated Operations workspace exists (10 pts)
        # -------------------------------------------------------
        io_path = "/default-domain/workspaces/Integrated-Operations"
        io_doc = _get_doc(exec_in_env, io_path)
        io_uid = io_doc.get("uid", "")
        io_title = (io_doc.get("title") or "").lower()

        if not io_uid:
            # Try NXQL search for workspace with title
            result = _nxql(exec_in_env,
                "SELECT * FROM Workspace WHERE dc:title = 'Integrated Operations' "
                "AND ecm:isTrashed = 0 AND ecm:isVersion = 0")
            entries = result.get("entries", [])
            if entries:
                io_uid = entries[0].get("uid", "")
                io_title = (entries[0].get("title") or "").lower()
                io_path = entries[0].get("path", io_path)

        if io_uid and "integrated" in io_title:
            score += 10
            details.append(f"PASS: 'Integrated Operations' workspace found (uid={io_uid})")
        else:
            details.append("FAIL: 'Integrated Operations' workspace not found")

        # -------------------------------------------------------
        # 2 & 3. Product Development + Corporate Services sub-workspaces (8 pts each)
        # -------------------------------------------------------
        pd_uid = ""
        cs_uid = ""
        pd_path = ""
        cs_path = ""

        if io_uid:
            children = _children(exec_in_env, io_path)
            for child in children:
                child_title = (child.get("title") or "").lower()
                if "product" in child_title and "development" in child_title:
                    pd_uid = child.get("uid", "")
                    pd_path = child.get("path", "")
                    score += 8
                    details.append(f"PASS: 'Product Development' sub-workspace found")
                elif "corporate" in child_title or "services" in child_title:
                    cs_uid = child.get("uid", "")
                    cs_path = child.get("path", "")
                    score += 8
                    details.append(f"PASS: 'Corporate Services' sub-workspace found")

            if not pd_uid:
                details.append("FAIL: 'Product Development' sub-workspace not found")
            if not cs_uid:
                details.append("FAIL: 'Corporate Services' sub-workspace not found")
        else:
            details.append("SKIP: Cannot check sub-workspaces (parent workspace not found)")

        # -------------------------------------------------------
        # 4. Project/roadmap docs migrated to Product Development (12 pts)
        # -------------------------------------------------------
        if pd_uid:
            pd_children = _children(exec_in_env, pd_path)
            pd_titles = [(c.get("title") or "").lower() for c in pd_children]
            project_found = any("plan" in t or "roadmap" in t or "project" in t or "alpha" in t
                                for t in pd_titles)
            if project_found:
                score += 12
                details.append(f"PASS: Project/roadmap docs in Product Development ({pd_titles[:3]})")
            else:
                details.append(f"FAIL: No project/roadmap docs in Product Development (children={pd_titles[:5]})")
        else:
            details.append("SKIP: Cannot check Product Development docs (sub-workspace not found)")

        # -------------------------------------------------------
        # 5. Budget/metrics docs migrated to Corporate Services (12 pts)
        # -------------------------------------------------------
        if cs_uid:
            cs_children = _children(exec_in_env, cs_path)
            cs_titles = [(c.get("title") or "").lower() for c in cs_children]
            finance_found = any("budget" in t or "metrics" in t or "report" in t or "beta" in t
                                for t in cs_titles)
            if finance_found:
                score += 12
                details.append(f"PASS: Budget/metrics docs in Corporate Services ({cs_titles[:3]})")
            else:
                details.append(f"FAIL: No budget/metrics docs in Corporate Services (children={cs_titles[:5]})")
        else:
            details.append("SKIP: Cannot check Corporate Services docs (sub-workspace not found)")

        # -------------------------------------------------------
        # 6. All migrated docs have description >= 20 chars (10 pts)
        # -------------------------------------------------------
        migrated_docs = []
        if pd_uid:
            migrated_docs.extend(_children(exec_in_env, pd_path))
        if cs_uid:
            migrated_docs.extend(_children(exec_in_env, cs_path))

        if migrated_docs:
            all_have_desc = True
            short_desc_count = 0
            for doc in migrated_docs:
                doc_type = doc.get("type", "")
                if doc_type not in ["Note", "File", "Document"]:
                    continue
                props = doc.get("properties", {})
                desc = (props.get("dc:description") or "").strip()
                if len(desc) < 20:
                    all_have_desc = False
                    short_desc_count += 1

            if all_have_desc:
                score += 10
                details.append(f"PASS: All {len(migrated_docs)} migrated docs have desc >= 20 chars")
            elif short_desc_count == 0:
                score += 10
                details.append("PASS: All migrated docs (workspaces excluded) have adequate descriptions")
            else:
                details.append(f"FAIL: {short_desc_count} migrated docs have description < 20 chars")
        else:
            details.append("SKIP: No migrated docs found to check descriptions")

        # -------------------------------------------------------
        # 7. integrated-team group exists (10 pts)
        # -------------------------------------------------------
        grp = _get_group(exec_in_env, "integrated-team")
        grp_name = grp.get("groupname", "") or grp.get("id", "")
        if grp_name == "integrated-team":
            score += 10
            details.append("PASS: 'integrated-team' group exists")

            # -------------------------------------------------------
            # 8. integrated-team has all expected members (15 pts)
            # -------------------------------------------------------
            member_users = set(grp.get("memberUsers", []))
            # Also check nested sub-groups and 'members' property
            members_prop = grp.get("properties", {})
            if members_prop:
                member_users.update(members_prop.get("members", []))
                member_users.update(members_prop.get("memberUsers", []))

            found = EXPECTED_MEMBERS & member_users
            if len(found) >= 4:
                score += 15
                details.append(f"PASS: integrated-team has all expected members: {found}")
            elif len(found) >= 3:
                score += 10
                details.append(f"PARTIAL: integrated-team has {len(found)}/4 expected members: {found}")
            elif len(found) >= 2:
                score += 5
                details.append(f"PARTIAL: integrated-team has {len(found)}/4 expected members: {found}")
            else:
                details.append(f"FAIL: integrated-team members: {member_users} (expected {EXPECTED_MEMBERS})")
        else:
            details.append(f"FAIL: 'integrated-team' group not found (got: {grp})")

        # -------------------------------------------------------
        # 9. integrated-team has ReadWrite on Integrated Operations (15 pts)
        # -------------------------------------------------------
        if io_uid:
            aces = _get_acl(exec_in_env, io_path)
            rw_perms = {"ReadWrite", "Everything", "Write"}
            for ace in aces:
                if not isinstance(ace, dict):
                    continue
                principal = ace.get("username") or ace.get("id") or ace.get("principal", "")
                permission = ace.get("permission") or ace.get("right", "")
                granted = ace.get("granted", True)
                if ("integrated" in principal.lower() or principal == "integrated-team") and granted:
                    if permission in rw_perms or "write" in permission.lower():
                        score += 15
                        details.append(f"PASS: integrated-team has '{permission}' on Integrated Operations")
                        break
            else:
                # Check if integrated-team appears anywhere in ACL
                acl_raw = exec_in_env(
                    f'curl -s -u {AUTH} "{NUXEO_BASE}/path{io_path}/@acl"'
                )
                if "integrated-team" in acl_raw and ("ReadWrite" in acl_raw or "Write" in acl_raw):
                    score += 15
                    details.append("PASS: integrated-team ReadWrite on Integrated Operations (raw check)")
                else:
                    details.append(f"FAIL: integrated-team does not have ReadWrite on Integrated Operations")
        else:
            details.append("SKIP: Cannot check ACL (Integrated Operations workspace not found)")

        # -------------------------------------------------------
        # Final result
        # -------------------------------------------------------
        passed = score >= 60
        feedback = f"Score: {score}/100. " + " | ".join(details)
        return {"passed": passed, "score": score, "feedback": feedback}

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
