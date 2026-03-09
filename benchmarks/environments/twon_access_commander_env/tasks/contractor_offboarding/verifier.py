#!/usr/bin/env python3
"""
Verifier for contractor_offboarding task.

Scoring (100 pts total, pass threshold = 70):

  Criterion A – Each Meridian Facilities user is DISABLED
    30 pts (binary per user: 10 pts × 3); all 3 must be present.

  Criterion B – Each Meridian Facilities user has ZERO credentials
    45 pts (binary per user: 15 pts × 3).

  Criterion C – All 3 Meridian users still exist (not deleted)
    10 pts (binary: all present or 0).

  Criterion D – No non-Meridian user was incorrectly disabled
    15 pts (binary: 0 collateral disabled or full credit).
    NOTE: Only awarded when AC was reachable (≥3 Meridian users found OR ≥10
    non-Meridian users found). Prevents do-nothing inflation when AC is offline.

  max_partial_total analysis:
    Do-nothing (AC offline): 0 pts → FAIL ✓
    Agent disables all 3 but clears 0 credentials: 10+30+0+15 = 55 < 70 ✓
    Agent disables 2 of 3 + clears 2 of 3 + exist + no damage: 10+20+30+15 = 75 → PASS ✓
    Agent disables all 3 + clears all 3 + no damage: 10+30+45+15 = 100 ✓
    Agent disables 1 of 3 + clears 1 of 3 + exist + no damage: 10+10+15+15 = 50 < 70 ✓
"""

import json
import os
import tempfile


def verify_contractor_offboarding(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0,
                "feedback": "copy_from_env not available in env_info"}

    tmp = tempfile.mktemp(suffix=".json")
    try:
        copy_from_env("/tmp/contractor_offboarding_result.json", tmp)
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

    meridian_users = result.get("meridian_users", [])
    non_meridian_users = result.get("non_meridian_users", [])

    # ── Criterion C: All 3 Meridian users still exist ──────────────────────
    if len(meridian_users) >= 3:
        score += 10
        feedback.append("PASS: All 3 Meridian Facilities users still exist (not deleted) (+10)")
    else:
        feedback.append(
            f"FAIL: Expected 3 Meridian Facilities users, found {len(meridian_users)}. "
            "Users may have been deleted instead of disabled."
        )

    # ── Criterion A: Each Meridian user is disabled ─────────────────────────
    for u in meridian_users:
        name = f"{u.get('firstName', '?')} {u.get('lastName', '?')}"
        if not u.get("enabled", True):
            score += 10
            feedback.append(f"PASS: {name} is disabled (+10)")
        else:
            feedback.append(f"FAIL: {name} is still enabled")

    # ── Criterion B: Each Meridian user has 0 credentials ──────────────────
    for u in meridian_users:
        name = f"{u.get('firstName', '?')} {u.get('lastName', '?')}"
        cred_count = u.get("credential_count", 999)
        if cred_count == 0:
            score += 15
            feedback.append(f"PASS: {name} has all credentials revoked (+15)")
        else:
            feedback.append(
                f"FAIL: {name} still has {cred_count} credential(s) — "
                "RFID cards and PINs must be removed"
            )

    # ── Criterion D: No non-Meridian user collaterally disabled ────────────
    # Only award this criterion if the AC was reachable (we found the expected
    # Meridian users). If AC was offline, non_meridian_users will also be empty,
    # and awarding 30 pts for "no collateral" on empty data would inflate do-nothing scores.
    if len(meridian_users) >= 3 or len(non_meridian_users) >= 10:
        disabled_collateral = [
            u for u in non_meridian_users if not u.get("enabled", True)
        ]
        if not disabled_collateral:
            score += 15
            feedback.append("PASS: No non-Meridian users were accidentally disabled (+15)")
        else:
            names = [f"{u.get('firstName', '?')} {u.get('lastName', '?')}"
                     for u in disabled_collateral]
            feedback.append(
                f"FAIL: {len(names)} non-Meridian user(s) incorrectly disabled: {names}"
            )
    else:
        feedback.append(
            "INFO: Collateral check skipped — AC may have been offline during export "
            f"(found {len(meridian_users)} Meridian users, {len(non_meridian_users)} others)"
        )

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback),
    }
