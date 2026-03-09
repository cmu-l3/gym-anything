#!/usr/bin/env python3
"""
Verifier for polypharmacy_review_and_update task.

Four patients each have a medication safety issue. The agent must:
1. Identify the specific medication problem in each patient's file
2. Create a corrected prescription (ordonnance) for each patient
3. Add a consultation note documenting the medication change

Scoring (100 points total):
  - MARTIN Sophie   new prescription created:  20 pts
  - BERNARD Pierre  new prescription created:  20 pts
  - MOREAU Francois new prescription created:  20 pts
  - LEROY Isabelle  new prescription created:  20 pts
  - At least 2 consultation notes added:       20 pts
  (bonus: all 4 consultation notes = 20 pts fully awarded)

Pass threshold: 60 points (must update at least 3 of 4 patients' prescriptions)
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_polypharmacy_review_and_update(traj, env_info, task_info):
    """Verify polypharmacy medication safety task."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0,
                "feedback": "copy_from_env function unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_path = tmp.name
        tmp.close()
        try:
            copy_from_env("/tmp/polypharmacy_result.json", tmp_path)
            with open(tmp_path, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
    except FileNotFoundError:
        return {"passed": False, "score": 0,
                "feedback": "Result file not found — export script may not have run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback_parts = []

    # ── Prescription updates (20 pts each) ──────────────────────────────────
    martin_ordo = int(result.get('martin_new_ordo', 0))
    if martin_ordo > 0:
        score += 20
        feedback_parts.append("MARTIN Sophie: new prescription created (+20)")
    else:
        feedback_parts.append("MARTIN Sophie: no new prescription found (0)")

    bernard_ordo = int(result.get('bernard_new_ordo', 0))
    if bernard_ordo > 0:
        score += 20
        feedback_parts.append("BERNARD Pierre: new prescription created (+20)")
    else:
        feedback_parts.append("BERNARD Pierre: no new prescription found (0)")

    moreau_ordo = int(result.get('moreau_new_ordo', 0))
    if moreau_ordo > 0:
        score += 20
        feedback_parts.append("MOREAU Francois: new prescription created (+20)")
    else:
        feedback_parts.append("MOREAU Francois: no new prescription found (0)")

    leroy_ordo = int(result.get('leroy_new_ordo', 0))
    if leroy_ordo > 0:
        score += 20
        feedback_parts.append("LEROY Isabelle: new prescription created (+20)")
    else:
        feedback_parts.append("LEROY Isabelle: no new prescription found (0)")

    # ── Consultation notes (20 pts for at least 2 of 4) ─────────────────────
    cons_count = (
        (1 if int(result.get('martin_new_cons', 0)) > 0 else 0) +
        (1 if int(result.get('bernard_new_cons', 0)) > 0 else 0) +
        (1 if int(result.get('moreau_new_cons', 0)) > 0 else 0) +
        (1 if int(result.get('leroy_new_cons', 0)) > 0 else 0)
    )
    if cons_count >= 4:
        score += 20
        feedback_parts.append(f"Consultation notes: {cons_count}/4 patients documented (+20)")
    elif cons_count >= 2:
        score += 10
        feedback_parts.append(f"Consultation notes: {cons_count}/4 patients documented (+10 partial)")
    else:
        feedback_parts.append(f"Consultation notes: {cons_count}/4 — insufficient documentation (0)")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "martin_new_prescriptions": martin_ordo,
            "bernard_new_prescriptions": bernard_ordo,
            "moreau_new_prescriptions": moreau_ordo,
            "leroy_new_prescriptions": leroy_ordo,
            "consultation_notes_written": cons_count,
        }
    }
