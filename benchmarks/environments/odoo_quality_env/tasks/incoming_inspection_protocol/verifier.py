#!/usr/bin/env python3
"""Verifier for incoming_inspection_protocol task.

Multi-criterion scoring (100 pts total):
  1. QCP "Structural Integrity" exists with Pass-Fail type          (10 pts)
  2. QCP "Structural Integrity" linked to Cabinet with Doors        (8 pts)
  3. QCP "Acoustic Attenuation" exists with Measure type            (10 pts)
  4. QCP "Acoustic Attenuation" linked to Acoustic Bloc Screens     (8 pts)
  5. QCP "Ergonomic Compliance" exists with Instructions type       (10 pts)
  6. QCP "Ergonomic Compliance" linked to Office Chair              (8 pts)
  7. QCP "Ergonomic Compliance" failure message contains BIFMA      (12 pts)
  8. Check "Visual Inspection - Cabinet Finish" passed              (17 pts)
  9. Check "Dimension Verification - Screen Width" failed           (17 pts)
"""

import json
import os
import tempfile


def verify_incoming_inspection_protocol(traj, env_info, task_info):
    score = 0
    feedback_parts = []

    result = {}
    copy_from_env = env_info.get("copy_from_env") if env_info else None
    if copy_from_env:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        try:
            copy_from_env("/tmp/incoming_inspection_protocol_result.json", tmp.name)
            with open(tmp.name) as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not load result: {e}"}
        finally:
            os.unlink(tmp.name)
    else:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env available"}

    def _has_product(names_list, target_substr):
        return any(target_substr.lower() in n.lower() for n in names_list)

    # --- QCP 1: Structural Integrity (10 + 8 pts) ---
    if result.get("qcp1_found"):
        if result.get("qcp1_test_type") == "passfail":
            score += 10
            feedback_parts.append("QCP 'Structural Integrity' found with Pass-Fail type (+10)")
        else:
            score += 4
            feedback_parts.append(f"QCP 'Structural Integrity' found but type='{result.get('qcp1_test_type')}' (expected passfail, +4)")
        if _has_product(result.get("qcp1_product_ids_names", []), "cabinet"):
            score += 8
            feedback_parts.append("QCP1 linked to Cabinet with Doors (+8)")
        else:
            feedback_parts.append("QCP1 not linked to Cabinet with Doors")
    else:
        feedback_parts.append("QCP 'Structural Integrity' NOT found")

    # --- QCP 2: Acoustic Attenuation (10 + 8 pts) ---
    if result.get("qcp2_found"):
        if result.get("qcp2_test_type") == "measure":
            score += 10
            feedback_parts.append("QCP 'Acoustic Attenuation' found with Measure type (+10)")
        else:
            score += 4
            feedback_parts.append(f"QCP 'Acoustic Attenuation' found but type='{result.get('qcp2_test_type')}' (+4)")
        if _has_product(result.get("qcp2_product_ids_names", []), "acoustic"):
            score += 8
            feedback_parts.append("QCP2 linked to Acoustic Bloc Screens (+8)")
        else:
            feedback_parts.append("QCP2 not linked to Acoustic Bloc Screens")
    else:
        feedback_parts.append("QCP 'Acoustic Attenuation' NOT found")

    # --- QCP 3: Ergonomic Compliance (10 + 8 + 12 pts) ---
    if result.get("qcp3_found"):
        if result.get("qcp3_test_type") == "instructions":
            score += 10
            feedback_parts.append("QCP 'Ergonomic Compliance' found with Instructions type (+10)")
        else:
            score += 4
            feedback_parts.append(f"QCP 'Ergonomic Compliance' found but type='{result.get('qcp3_test_type')}' (+4)")
        if _has_product(result.get("qcp3_product_ids_names", []), "chair"):
            score += 8
            feedback_parts.append("QCP3 linked to Office Chair (+8)")
        else:
            feedback_parts.append("QCP3 not linked to Office Chair")
        fm = result.get("qcp3_failure_message", "").lower()
        if "bifma" in fm and ("reject" in fm or "quarantine" in fm):
            score += 12
            feedback_parts.append("QCP3 failure message contains BIFMA + reject/quarantine (+12)")
        elif "bifma" in fm:
            score += 8
            feedback_parts.append("QCP3 failure message contains BIFMA (+8)")
        else:
            feedback_parts.append("QCP3 failure message missing BIFMA keyword")
    else:
        feedback_parts.append("QCP 'Ergonomic Compliance' NOT found")

    # --- Quality check: Cabinet Finish passed (17 pts) ---
    if result.get("check_cabinet_state") == "pass":
        score += 17
        feedback_parts.append("'Visual Inspection - Cabinet Finish' passed (+17)")
    else:
        feedback_parts.append(f"'Visual Inspection - Cabinet Finish' state='{result.get('check_cabinet_state')}' (expected pass)")

    # --- Quality check: Screen Width failed (17 pts) ---
    if result.get("check_screen_state") == "fail":
        score += 17
        feedback_parts.append("'Dimension Verification - Screen Width' failed (+17)")
    else:
        feedback_parts.append(f"'Dimension Verification - Screen Width' state='{result.get('check_screen_state')}' (expected fail)")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts),
    }
