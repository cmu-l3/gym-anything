#!/usr/bin/env python3
"""Verifier for quarterly_access_review task.

Scoring breakdown (100 points, pass >= 70):
  C1 (15pts): Unauthorized users removed from #finance-reports
  C2 (15pts): Unauthorized users removed from #hr-confidential
  C3 (10pts): Authorized users NOT removed from #finance-reports
  C4 (10pts): Authorized users NOT removed from #hr-confidential
  C5 (10pts): Audit trail messages posted in modified channels
  C6 (10pts): access-review-q1-2026 channel created
  C7 (10pts): Summary report posted in review channel
  C8 (10pts): DM to contractor.smith about access revocation
  C9 (10pts): DM to former.intern about access revocation
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/quarterly_access_review_result.json"

# Who should be removed from each channel
FINANCE_UNAUTHORIZED = {"contractor.smith", "former.intern", "dev.jones", "dev.wilson"}
FINANCE_AUTHORIZED = {"finance.manager", "senior.analyst"}
HR_UNAUTHORIZED = {"contractor.smith", "former.intern", "dev.jones", "dev.wilson", "senior.analyst"}
HR_AUTHORIZED = {"hr.director", "finance.manager"}


def verify_quarterly_access_review(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env(RESULT_PATH, tmp.name)
        with open(tmp.name, "r") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Export error: {result['error']}"}

    score = 0
    feedback = []

    fin = result.get("finance_reports", {})
    hr = result.get("hr_confidential", {})

    fin_initial = set(m.lower() for m in fin.get("initial_members", []))
    fin_current = set(m.lower() for m in fin.get("current_members", []))
    hr_initial = set(m.lower() for m in hr.get("initial_members", []))
    hr_current = set(m.lower() for m in hr.get("current_members", []))

    # --- Do-nothing gate ---
    if fin_current == fin_initial and hr_current == hr_initial:
        review = result.get("review_channel", {})
        if not review.get("exists"):
            return {
                "passed": False,
                "score": 0,
                "feedback": "No members removed and no review channel created. Agent likely did nothing.",
            }

    # --- C1 (15pts): Unauthorized removed from finance-reports ---
    fin_removed = FINANCE_UNAUTHORIZED - fin_current
    fin_still_present = FINANCE_UNAUTHORIZED & fin_current
    c1 = int(len(fin_removed) / len(FINANCE_UNAUTHORIZED) * 15) if FINANCE_UNAUTHORIZED else 0
    score += c1
    feedback.append(
        f"C1: +{c1} Finance unauthorized removed ({len(fin_removed)}/{len(FINANCE_UNAUTHORIZED)}, "
        f"still present: {fin_still_present or 'none'})"
    )

    # --- C2 (15pts): Unauthorized removed from hr-confidential ---
    hr_removed = HR_UNAUTHORIZED - hr_current
    hr_still_present = HR_UNAUTHORIZED & hr_current
    c2 = int(len(hr_removed) / len(HR_UNAUTHORIZED) * 15) if HR_UNAUTHORIZED else 0
    score += c2
    feedback.append(
        f"C2: +{c2} HR unauthorized removed ({len(hr_removed)}/{len(HR_UNAUTHORIZED)}, "
        f"still present: {hr_still_present or 'none'})"
    )

    # --- C3 (10pts): Authorized NOT removed from finance-reports ---
    fin_auth_present = FINANCE_AUTHORIZED & fin_current
    c3 = int(len(fin_auth_present) / len(FINANCE_AUTHORIZED) * 10) if FINANCE_AUTHORIZED else 0
    score += c3
    feedback.append(f"C3: +{c3} Finance authorized retained ({len(fin_auth_present)}/{len(FINANCE_AUTHORIZED)})")

    # --- C4 (10pts): Authorized NOT removed from hr-confidential ---
    hr_auth_present = HR_AUTHORIZED & hr_current
    c4 = int(len(hr_auth_present) / len(HR_AUTHORIZED) * 10) if HR_AUTHORIZED else 0
    score += c4
    feedback.append(f"C4: +{c4} HR authorized retained ({len(hr_auth_present)}/{len(HR_AUTHORIZED)})")

    # --- C5 (10pts): Audit trail messages in modified channels ---
    c5 = 0
    fin_msgs = fin.get("messages", [])
    hr_msgs = hr.get("messages", [])

    fin_has_audit = False
    for msg in fin_msgs:
        text = (msg.get("msg") or "").lower()
        if ("removed" in text or "revoked" in text or "audit" in text or "access review" in text):
            fin_has_audit = True
            break

    hr_has_audit = False
    for msg in hr_msgs:
        text = (msg.get("msg") or "").lower()
        if ("removed" in text or "revoked" in text or "audit" in text or "access review" in text):
            hr_has_audit = True
            break

    if fin_has_audit:
        c5 += 5
    if hr_has_audit:
        c5 += 5
    score += c5
    feedback.append(f"C5: +{c5} Audit trail (finance: {fin_has_audit}, HR: {hr_has_audit})")

    # --- C6 (10pts): Review channel created ---
    review = result.get("review_channel", {})
    c6 = 10 if review.get("exists") else 0
    score += c6
    feedback.append(f"C6: +{c6} Review channel access-review-q1-2026 exists")

    # --- C7 (10pts): Summary report in review channel ---
    c7 = 0
    for msg in review.get("messages", []):
        text = (msg.get("msg") or "").lower()
        mentions_finance = "finance" in text
        mentions_hr = "hr" in text or "confidential" in text
        mentions_removal = "removed" in text or "revoked" in text or "access" in text
        if mentions_finance and mentions_hr and mentions_removal:
            c7 = 10
            break
        elif (mentions_finance or mentions_hr) and mentions_removal:
            c7 = max(c7, 6)
    score += c7
    feedback.append(f"C7: +{c7} Summary report in review channel")

    # --- C8 (10pts): DM to contractor.smith ---
    contractor_dm = result.get("contractor_dm", [])
    c8 = 0
    if len(contractor_dm) > 0:
        c8 = 5
        for msg in contractor_dm:
            text = (msg.get("msg") or "").lower()
            if any(kw in text for kw in ["access", "revoked", "removed", "review", "restricted"]):
                c8 = 10
                break
    score += c8
    feedback.append(f"C8: +{c8} DM to contractor.smith ({len(contractor_dm)} messages)")

    # --- C9 (10pts): DM to former.intern ---
    intern_dm = result.get("intern_dm", [])
    c9 = 0
    if len(intern_dm) > 0:
        c9 = 5
        for msg in intern_dm:
            text = (msg.get("msg") or "").lower()
            if any(kw in text for kw in ["access", "revoked", "removed", "hr", "contact"]):
                c9 = 10
                break
    score += c9
    feedback.append(f"C9: +{c9} DM to former.intern ({len(intern_dm)} messages)")

    passed = score >= 70
    summary = f"Score: {score}/100 (pass >= 70)\n" + "\n".join(feedback)

    return {
        "passed": passed,
        "score": score,
        "feedback": summary,
    }
