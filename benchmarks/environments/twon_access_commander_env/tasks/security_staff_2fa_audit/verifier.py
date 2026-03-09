#!/usr/bin/env python3
"""
Verifier for security_staff_2fa_audit task.

Policy 1 — Security Staff 2FA: Victor Schulz, Tamara Kowalski, Leon Fischer
  must each gain a PIN credential (9911) without losing their RFID card.

Policy 2 — Disabled account hygiene: Priya Nair and Carlos Mendoza
  (disabled accounts) must have ALL credentials revoked (0 credentials).

Scoring (100 pts total, pass threshold = 70):

  Policy 1 — per Security Staff member (3 members × 15 pts = 45 pts):
    • Member has PIN credential:    10 pts
    • Member still has RFID card:    5 pts

  Policy 2 — per disabled user (2 users × 25 pts = 50 pts):
    • User has 0 credentials:       25 pts

  Collateral check — no enabled non-target user lost credentials: 5 pts

  Total: 45 + 50 + 5 = 100 pts

  max_partial_total analysis:
    Agent does only Policy 1 (all 3 with PIN + card): 45 < 70 ✓
    Agent does only Policy 2 (both disabled cleaned): 50 < 70 ✓
    Agent does Policy 1 (all 3) + Policy 2 (1 of 2) + collateral: 45+25+5 = 75 → PASS ✓
    Agent does all: 100 ✓
    Agent does Policy 1 + collateral but no Policy 2: 45+5 = 50 < 70 ✓
"""

import json
import os
import tempfile

SECURITY_STAFF_EMAILS = {
    "v.schulz@secureguard.net",
    "t.kowalski@secureguard.net",
    "l.fischer@secureguard.net",
}
DISABLED_TARGETS = {"Priya Nair", "Carlos Mendoza"}


def verify_security_staff_2fa_audit(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0,
                "feedback": "copy_from_env not available in env_info"}

    tmp = tempfile.mktemp(suffix=".json")
    try:
        copy_from_env("/tmp/security_staff_2fa_audit_result.json", tmp)
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

    sec_members  = result.get("security_staff_members", [])
    disabled_map = result.get("disabled_users", {})

    # ── Policy 1: Security Staff 2FA ───────────────────────────────────────
    # We look for the 3 known Security Staff emails. If the export found them
    # in the group, score them. If the group is empty (agent removed them from
    # Security Staff), we fall back to known names.
    scored_sec_emails = set()

    for m in sec_members:
        email = m.get("email", "").lower()
        name  = f"{m.get('firstName', '?')} {m.get('lastName', '?')}"

        if email not in SECURITY_STAFF_EMAILS:
            # Non-target member in Security Staff — skip
            continue
        scored_sec_emails.add(email)

        has_pin  = m.get("has_pin", False)
        has_card = m.get("has_card", False)

        if has_pin:
            score += 10
            feedback.append(f"PASS: {name} has PIN credential (+10)")
            # Card-retention points only awarded when PIN was also assigned
            # (prevents trivially passing this criterion before any agent action)
            if has_card:
                score += 5
                feedback.append(f"PASS: {name} retains RFID card (+5)")
            else:
                feedback.append(f"FAIL: {name} — RFID card was removed (should be kept)")
        else:
            feedback.append(f"FAIL: {name} — no PIN credential (should have '9911')")
            if not has_card:
                feedback.append(f"FAIL: {name} — RFID card was also removed")

    # Account for Security Staff members not found in the export
    # (e.g. if agent removed them from the group by mistake)
    for email in SECURITY_STAFF_EMAILS - scored_sec_emails:
        feedback.append(
            f"FAIL: Security Staff member with email {email} not found in "
            "Security Staff group — they may have been removed from the group"
        )

    # ── Policy 2: Disabled account credential hygiene ──────────────────────
    for name in DISABLED_TARGETS:
        info = disabled_map.get(name)
        if not info:
            feedback.append(f"FAIL: {name} — not found in export (user may have been deleted)")
            continue

        is_enabled = info.get("enabled", True)
        cred_count = info.get("credential_count", 999)

        if is_enabled:
            # Account was re-enabled — that's a separate concern but not what we test
            feedback.append(
                f"INFO: {name} — account was re-enabled (was expected disabled). "
                f"Credential count: {cred_count}"
            )
            # Still check credentials
        if cred_count == 0:
            score += 25
            feedback.append(
                f"PASS: {name} — all credentials revoked (0 remaining) (+25)"
            )
        else:
            feedback.append(
                f"FAIL: {name} — still has {cred_count} credential(s): "
                f"{info.get('credentials', [])}"
            )

    # ── Collateral check: Security Staff cards intact after PIN assignment ──
    # Only awarded if at least one PIN was successfully assigned (the agent
    # actually did the task). Prevents awarding 5 pts for doing nothing.
    pins_assigned = sum(
        1 for m in sec_members
        if m.get("email", "").lower() in SECURITY_STAFF_EMAILS and m.get("has_pin", False)
    )
    sec_cards_intact = all(
        m.get("has_card", False)
        for m in sec_members
        if m.get("email", "").lower() in SECURITY_STAFF_EMAILS
    )
    if pins_assigned > 0 and sec_cards_intact and scored_sec_emails:
        score += 5
        feedback.append("PASS: Security Staff RFID cards were not collaterally removed (+5)")
    elif not scored_sec_emails:
        feedback.append("INFO: Could not assess collateral check — no Security Staff found in group")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback),
    }
