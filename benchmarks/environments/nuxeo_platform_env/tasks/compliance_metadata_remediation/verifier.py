#!/usr/bin/env python3
"""Verifier for compliance_metadata_remediation task.

Checks that non-compliant documents were remediated per the compliance standards:
- compliance-reviewed tag applied to each remediated document
- review comment added to each remediated document
- Project-Proposal description updated (>=50 chars, non-placeholder)
- Annual-Report-2023 coverage and subjects populated
- Contract-Template lifecycle transitioned to 'obsolete'
- Collection 'Q4 2025 Compliance Audit' created and populated with in-scope docs

Scoring (100 pts total, pass at 60):
  compliance-reviewed tag x3 docs: 30 pts
  comment x3 docs:                  15 pts
  Project-Proposal desc fixed:      10 pts
  Annual-Report coverage:            5 pts
  Annual-Report subjects:            5 pts
  Contract-Template obsolete:       15 pts
  Collection exists:                 5 pts
  Collection has all 3 docs:        15 pts
"""

import json

NUXEO_BASE = "http://localhost:8080/nuxeo/api/v1"
AUTH = "Administrator:Administrator"

IN_SCOPE = {
    "Annual-Report-2023":        "/default-domain/workspaces/Projects/Annual-Report-2023",
    "Project-Proposal":          "/default-domain/workspaces/Projects/Project-Proposal",
    "Contract-Template":         "/default-domain/workspaces/Templates/Contract-Template",
}

COLLECTION_TITLE = "Q4 2025 Compliance Audit"


def _api(exec_in_env, endpoint, extra_headers=""):
    cmd = f'curl -s -u {AUTH} -H "X-NXproperties: *" {extra_headers} "{NUXEO_BASE}/{endpoint}"'
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


def _has_comment(exec_in_env, uid):
    data = _api(exec_in_env, f"id/{uid}/@comment")
    return len(data.get("entries", [])) > 0


def _find_collection(exec_in_env, title):
    safe = title.replace(" ", "+").replace("'", "%27")
    data = _api(exec_in_env,
                f"search/lang/NXQL/execute?query=SELECT+*+FROM+Collection+"
                f"WHERE+dc:title%3D%27{safe}%27+AND+ecm:isTrashed%3D0+AND+ecm:isVersion%3D0")
    entries = data.get("entries", [])
    return entries[0].get("uid", "") if entries else ""


def _collection_members(exec_in_env, coll_uid):
    data = _api(exec_in_env, f"id/{coll_uid}/contents?pageSize=20")
    return [e.get("title", "").lower() for e in data.get("entries", [])]


def verify_compliance_metadata_remediation(traj, env_info, task_info):
    exec_in_env = env_info.get("exec_in_env") or env_info.get("exec_capture")
    score = 0
    details = []

    try:
        # -------------------------------------------------------
        # 1. compliance-reviewed tag on each in-scope doc (10 pts each = 30 pts)
        # -------------------------------------------------------
        for name, path in IN_SCOPE.items():
            tags = _get_tags(exec_in_env, path)
            if "compliance-reviewed" in tags:
                score += 10
                details.append(f"PASS: 'compliance-reviewed' tag on {name}")
            else:
                details.append(f"FAIL: no 'compliance-reviewed' tag on {name} (tags={tags})")

        # -------------------------------------------------------
        # 2. Comment added to each in-scope doc (5 pts each = 15 pts)
        # -------------------------------------------------------
        for name, path in IN_SCOPE.items():
            doc = _get_doc(exec_in_env, path)
            uid = doc.get("uid", "")
            if uid and _has_comment(exec_in_env, uid):
                score += 5
                details.append(f"PASS: comment found on {name}")
            else:
                details.append(f"FAIL: no comment found on {name}")

        # -------------------------------------------------------
        # 3. Project-Proposal description updated (10 pts)
        # -------------------------------------------------------
        pp = _get_doc(exec_in_env, IN_SCOPE["Project-Proposal"])
        pp_desc = (pp.get("properties", {}).get("dc:description") or "").strip()
        bad_phrases = ["placeholder", "needs update", "tbd", "todo", ""]
        if len(pp_desc) >= 50 and not any(p in pp_desc.lower() for p in bad_phrases[:3]):
            score += 10
            details.append(f"PASS: Project-Proposal description updated (len={len(pp_desc)})")
        else:
            details.append(f"FAIL: Project-Proposal description inadequate: '{pp_desc[:80]}'")

        # -------------------------------------------------------
        # 4. Annual-Report-2023 coverage (5 pts) and subjects (5 pts)
        # -------------------------------------------------------
        ar = _get_doc(exec_in_env, IN_SCOPE["Annual-Report-2023"])
        ar_props = ar.get("properties", {})
        ar_coverage = (ar_props.get("dc:coverage") or "").strip()
        ar_subjects = ar_props.get("dc:subjects") or []

        if ar_coverage:
            score += 5
            details.append(f"PASS: Annual-Report-2023 coverage set: '{ar_coverage}'")
        else:
            details.append("FAIL: Annual-Report-2023 coverage still empty")

        if ar_subjects:
            score += 5
            details.append(f"PASS: Annual-Report-2023 subjects set: {ar_subjects}")
        else:
            details.append("FAIL: Annual-Report-2023 subjects still empty")

        # -------------------------------------------------------
        # 5. Contract-Template lifecycle → obsolete (15 pts)
        # -------------------------------------------------------
        ct = _get_doc(exec_in_env, IN_SCOPE["Contract-Template"])
        ct_state = (ct.get("state") or "").lower()
        if ct_state == "obsolete":
            score += 15
            details.append("PASS: Contract-Template lifecycle is 'obsolete'")
        else:
            details.append(f"FAIL: Contract-Template lifecycle is '{ct_state}' (expected 'obsolete')")

        # -------------------------------------------------------
        # 6. Collection 'Q4 2025 Compliance Audit' (5 pts exists + 15 pts members)
        # -------------------------------------------------------
        coll_uid = _find_collection(exec_in_env, COLLECTION_TITLE)
        if coll_uid:
            score += 5
            details.append(f"PASS: Collection '{COLLECTION_TITLE}' found")
            members = _collection_members(exec_in_env, coll_uid)
            # Check presence of all 3 in-scope documents by keyword match
            keywords = {"annual": False, "proposal": False, "contract": False}
            for m in members:
                if "annual" in m:
                    keywords["annual"] = True
                if "proposal" in m or "project proposal" in m:
                    keywords["proposal"] = True
                if "contract" in m:
                    keywords["contract"] = True
            matched = sum(keywords.values())
            if matched >= 3:
                score += 15
                details.append(f"PASS: All 3 docs in collection {COLLECTION_TITLE}")
            elif matched >= 2:
                score += 8
                details.append(f"PARTIAL: {matched}/3 in-scope docs in collection (members={members[:5]})")
            elif matched >= 1:
                score += 3
                details.append(f"PARTIAL: {matched}/3 in-scope docs in collection (members={members[:5]})")
            else:
                details.append(f"FAIL: No in-scope docs in collection (members={members[:5]})")
        else:
            details.append(f"FAIL: Collection '{COLLECTION_TITLE}' not found")

        # -------------------------------------------------------
        # Final result
        # -------------------------------------------------------
        passed = score >= 60
        feedback = f"Score: {score}/100. " + " | ".join(details)
        return {"passed": passed, "score": score, "feedback": feedback}

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
