#!/usr/bin/env python3
"""
Verifier for group_membership_audit task.

Injected violations (setup adds these wrongly):
  • Olumide Adeyemi (Meridian Facilities) in IT Department
  • Tomas Guerrero  (Meridian Facilities) in Security Staff
  • Nadia Ivanova   (Meridian Facilities) in Security Staff

Scoring (100 pts total, pass threshold = 70):

  Criterion A – Olumide Adeyemi removed from IT Department: 30 pts
  Criterion B – Tomas Guerrero removed from Security Staff:  30 pts
  Criterion C – Nadia Ivanova removed from Security Staff:   30 pts
  Criterion D – No legitimate BuildingTech employee removed:  10 pts

  max_partial_total check:
    If agent removes only 2 of 3 violations + no collateral: 60+10 = 70 → borderline
    pass. Acceptable: finding and removing 2 of 3 violations is strong partial
    success for a very_hard audit task.
    If agent removes 1 of 3 + no collateral: 30+10 = 40 < 70 ✓
"""

import json
import os
import tempfile

# Known legitimate IT Department members (by email)
LEGIT_IT_EMAILS = {
    "k.asante@buildingtech.com",
    "m.zhang@buildingtech.com",
}
# Known legitimate Security Staff members (by email)
LEGIT_SEC_EMAILS = {
    "v.schulz@secureguard.net",
    "t.kowalski@secureguard.net",
    "l.fischer@secureguard.net",
}

MERIDIAN_EMAILS = {
    "n.ivanova@meridianfacilities.com",
    "t.guerrero@meridianfacilities.com",
    "o.adeyemi@meridianfacilities.com",
}


def _member_emails(group_info):
    return {m.get("email", "").lower() for m in group_info.get("members", [])}


def verify_group_membership_audit(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0,
                "feedback": "copy_from_env not available in env_info"}

    tmp = tempfile.mktemp(suffix=".json")
    try:
        copy_from_env("/tmp/group_membership_audit_result.json", tmp)
    except Exception as e:
        return {"passed": False, "score": 0,
                "feedback": f"Could not retrieve result file: {e}"}

    try:
        with open(tmp) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0,
                "feedback": f"Could not parse result JSON: {e}"}
    finally:
        try:
            os.remove(tmp)
        except Exception:
            pass

    score = 0
    feedback = []

    rg = result.get("restricted_groups", {})
    it_members  = _member_emails(rg.get("IT Department", {}))
    sec_members = _member_emails(rg.get("Security Staff", {}))
    meridian_memberships = result.get("meridian_memberships", {})

    # AC-reachability guard: at least one Meridian user must be found in the system.
    # If AC was offline during export, all users would be "found": False and
    # both groups would appear empty — awarding "contaminating member removed"
    # on empty data would inflate the do-nothing score.
    ac_reachable = any(v.get("found", False) for v in meridian_memberships.values())
    if not ac_reachable:
        feedback.append(
            "INFO: AC appears to have been offline during export — "
            "no Meridian users found in system. Criteria A/B/C not scored."
        )
        return {"passed": False, "score": 0, "feedback": "\n".join(feedback)}

    # ── Criterion A: Olumide Adeyemi out of IT Department ──────────────────
    if "o.adeyemi@meridianfacilities.com" not in it_members:
        score += 30
        feedback.append("PASS: Olumide Adeyemi removed from IT Department (+30)")
    else:
        feedback.append("FAIL: Olumide Adeyemi is still a member of IT Department")

    # ── Criterion B: Tomas Guerrero out of Security Staff ──────────────────
    if "t.guerrero@meridianfacilities.com" not in sec_members:
        score += 30
        feedback.append("PASS: Tomas Guerrero removed from Security Staff (+30)")
    else:
        feedback.append("FAIL: Tomas Guerrero is still a member of Security Staff")

    # ── Criterion C: Nadia Ivanova out of Security Staff ───────────────────
    if "n.ivanova@meridianfacilities.com" not in sec_members:
        score += 30
        feedback.append("PASS: Nadia Ivanova removed from Security Staff (+30)")
    else:
        feedback.append("FAIL: Nadia Ivanova is still a member of Security Staff")

    # ── Criterion D: No legitimate member collaterally removed ─────────────
    collateral = []
    for email in LEGIT_IT_EMAILS:
        if email not in it_members:
            collateral.append(f"{email} removed from IT Department")
    for email in LEGIT_SEC_EMAILS:
        if email not in sec_members:
            collateral.append(f"{email} removed from Security Staff")

    if not collateral:
        score += 10
        feedback.append("PASS: All legitimate group members retained (+10)")
    else:
        feedback.append(
            f"FAIL: {len(collateral)} legitimate member(s) incorrectly removed: {collateral}"
        )

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback),
    }
