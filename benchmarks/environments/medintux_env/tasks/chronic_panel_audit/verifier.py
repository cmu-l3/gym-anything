"""
Verifier for chronic_panel_audit task.

The agent must identify and correct 4 planted clinical management gaps
without being told which patients are affected:

1. DUBOIS Marie-Claire: HTA + T2DM documented but no prescription
   → Create prescription with antihypertensive and/or antidiabetic

2. LAMBERT Anne: Atrial fibrillation but only aspirin prescribed (not anticoagulated)
   → Create new prescription containing an anticoagulant

3. PERRIN Martine: COPD, last follow-up 2025-05-15 (>9 months overdue)
   → Schedule a follow-up appointment in agenda

4. NICOLAS Sandrine: Migraine with aura + combined OCP (absolute contraindication)
   → Create new prescription without combined OCP

Scoring (100 pts total):

DUBOIS (25 pts):
  - New prescription created: 15 pts
  - Prescription has antihypertensive OR antidiabetic medication: 10 pts

LAMBERT (25 pts):
  - New prescription created: 10 pts
  - Prescription contains an anticoagulant: 15 pts

PERRIN (25 pts):
  - New agenda follow-up appointment created: 20 pts
  - Appointment date is in the future: 5 pts

NICOLAS (25 pts):
  - New prescription created: 10 pts
  - New prescription does NOT contain combined OCP: 15 pts

Pass threshold: 50/100 (need to correctly handle 2+ issues)
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)


def verify_chronic_panel_audit(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available in env_info."}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        try:
            copy_from_env("/tmp/audit_result.json", tmp.name)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to copy result from VM: {e}"}
        try:
            with open(tmp.name, "r", encoding="utf-8") as f:
                data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to parse result JSON: {e}"}
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    score = 0
    criteria = []

    # ---- Issue 1: DUBOIS Marie-Claire (25 pts) ----
    # HTA + T2DM documented but no prescription → needs new prescription
    dubois = data.get("dubois", {})
    if dubois.get("has_new_prescription"):
        score += 15
        criteria.append("PASS: DUBOIS Marie-Claire — new prescription created (+15)")
        if dubois.get("prescription_has_antihypertensive") or dubois.get("prescription_has_antidiabetic"):
            score += 10
            criteria.append("PASS: DUBOIS Marie-Claire — prescription contains appropriate medication (+10)")
        else:
            criteria.append("FAIL: DUBOIS Marie-Claire — prescription lacks antihypertensive/antidiabetic (0/10)")
    else:
        criteria.append("FAIL: DUBOIS Marie-Claire — no new prescription created (0/25)")

    # ---- Issue 2: LAMBERT Anne (25 pts) ----
    # AF without anticoagulant → needs anticoagulant prescription
    lambert = data.get("lambert", {})
    if lambert.get("has_new_prescription"):
        score += 10
        criteria.append("PASS: LAMBERT Anne — new prescription created (+10)")
        if lambert.get("prescription_has_anticoagulant"):
            score += 15
            criteria.append("PASS: LAMBERT Anne — prescription includes anticoagulant (+15)")
        else:
            criteria.append("FAIL: LAMBERT Anne — prescription lacks anticoagulant drug (0/15)")
    else:
        criteria.append("FAIL: LAMBERT Anne — no new prescription created (0/25)")

    # ---- Issue 3: PERRIN Martine (25 pts) ----
    # COPD overdue for follow-up → needs agenda appointment
    perrin = data.get("perrin", {})
    if perrin.get("has_new_agenda_entry"):
        score += 20
        criteria.append("PASS: PERRIN Martine — follow-up appointment scheduled in agenda (+20)")
        if perrin.get("agenda_date_future"):
            score += 5
            criteria.append("PASS: PERRIN Martine — appointment is scheduled for a future date (+5)")
        else:
            criteria.append("FAIL: PERRIN Martine — appointment date is not in the future (0/5)")
    else:
        criteria.append("FAIL: PERRIN Martine — no follow-up appointment created in agenda (0/25)")

    # ---- Issue 4: NICOLAS Sandrine (25 pts) ----
    # Migraine with aura + combined OCP → needs new prescription without combined OCP
    nicolas = data.get("nicolas", {})
    if nicolas.get("has_new_prescription"):
        score += 10
        criteria.append("PASS: NICOLAS Sandrine — new prescription created (+10)")
        if nicolas.get("new_prescription_lacks_ocp"):
            score += 15
            criteria.append("PASS: NICOLAS Sandrine — new prescription does NOT contain combined OCP (+15)")
        else:
            criteria.append("FAIL: NICOLAS Sandrine — new prescription still contains combined OCP (0/15)")
    else:
        criteria.append("FAIL: NICOLAS Sandrine — no new prescription created (0/25)")

    pass_threshold = task_info.get("metadata", {}).get("pass_threshold", 50)
    passed = score >= pass_threshold

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(criteria),
    }
