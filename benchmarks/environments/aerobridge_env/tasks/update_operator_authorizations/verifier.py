#!/usr/bin/env python3
"""Verifier for update_operator_authorizations task.

Checks that the Electric Inspection operator was updated with:
  1. 'videotaping' added to authorized_activities
  2. 'SORA' added to operational_authorizations
  3. operator_type changed to Non-LUC (2)

Scoring (100 points total):
  - videotaping in activities:   25 pts
  - SORA in authorizations:      25 pts
  - operator_type == Non-LUC:    30 pts
  - correct target (not a different operator): guard (score=0 if wrong)

Pass threshold: 50 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

EXPECTED_OPERATOR_ID = "566d63bb-cb1c-42dc-9a51-baef0d0a8d04"
EXPECTED_COMPANY = "Electric Inspection"


def verify_update_operator_authorizations(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # ── Copy result from VM ───────────────────────────────────────────────────
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp_path = tmp.name
    tmp.close()
    try:
        copy_from_env("/tmp/update_operator_authorizations_result.json", tmp_path)
        with open(tmp_path) as f:
            data = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found in VM. Export script may not have run."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        try:
            os.unlink(tmp_path)
        except Exception:
            pass

    if data.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Export error: {data['error']}"}

    op = data.get("operator")
    if not op:
        return {"passed": False, "score": 0, "feedback": "Operator record not found in database."}

    # ── Anti-gaming: wrong target check ──────────────────────────────────────
    if op.get("company_full_name") != EXPECTED_COMPANY:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"WRONG TARGET: expected '{EXPECTED_COMPANY}', got '{op.get('company_full_name')}'"
        }

    score = 0
    feedback_parts = []

    # ── Check 1: videotaping in authorized_activities (25 pts) ───────────────
    activities = [a.lower() for a in op.get("authorized_activities", [])]
    if "videotaping" in activities:
        score += 25
        feedback_parts.append("✓ 'videotaping' added to authorized_activities (+25)")
    else:
        feedback_parts.append(
            f"✗ 'videotaping' not in authorized_activities (found: {op.get('authorized_activities', [])})"
        )

    # ── Check 2: SORA in operational_authorizations (25 pts) ─────────────────
    auths = [a.lower() for a in op.get("operational_authorizations", [])]
    if "sora" in auths:
        score += 25
        feedback_parts.append("✓ 'SORA' added to operational_authorizations (+25)")
    else:
        feedback_parts.append(
            f"✗ 'SORA' not in operational_authorizations (found: {op.get('operational_authorizations', [])})"
        )

    # ── Check 3: operator_type == Non-LUC (2) (30 pts) ───────────────────────
    op_type = op.get("operator_type")
    if op_type == 2:
        score += 30
        feedback_parts.append("✓ operator_type set to 'Non-LUC' (2) (+30)")
    else:
        type_names = {0: "NA", 1: "LUC", 2: "Non-LUC", 3: "AUTH", 4: "DEC"}
        current_name = type_names.get(op_type, str(op_type))
        feedback_parts.append(f"✗ operator_type is '{current_name}' ({op_type}), expected 'Non-LUC' (2)")

    # ── Bonus: SORA V2 still present (sanity check) ───────────────────────────
    if "sora v2" in auths:
        feedback_parts.append("✓ 'SORA V2' still present (not accidentally removed)")
    else:
        feedback_parts.append("! WARNING: 'SORA V2' was removed (it should have been kept)")

    # ── Bonus: photographing still present ───────────────────────────────────
    if "photographing" in activities:
        feedback_parts.append("✓ 'photographing' still present (not accidentally removed)")

    passed = score >= 50
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\nTotal score: {score}/100 ({'PASSED' if passed else 'FAILED'}, threshold 50)"

    return {"passed": passed, "score": score, "feedback": feedback}
