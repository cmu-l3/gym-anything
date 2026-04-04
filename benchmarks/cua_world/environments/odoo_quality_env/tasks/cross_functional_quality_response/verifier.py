#!/usr/bin/env python3
"""Verifier for cross_functional_quality_response task.

Multi-criterion scoring (100 pts total):
  1.  Alert "Field Failure" exists                                (8 pts)
  2.  Alert product is Acoustic Bloc Screens                      (7 pts)
  3.  Alert priority is Urgent ("2")                              (7 pts)
  4.  Alert corrective action keywords (stop shipment, fracto*)   (12 pts)
  5.  Alert preventive action keywords (fillet, ASTM E164)        (12 pts)
  6.  QCP "Bracket Integrity" exists with Pass-Fail type          (8 pts)
  7.  QCP linked to Acoustic Bloc Screens                         (7 pts)
  8.  QCP failure message: CRITICAL REJECT + UT                   (10 pts)
  9.  "Screen Frame Scratch" moved to In Progress                 (10 pts)
  10. "Screen Colour Uniformity Audit" check passed               (10 pts)
  11. New "Bracket UT Inspection" check exists                    (9 pts)
"""

import json
import os
import tempfile


def verify_cross_functional_quality_response(traj, env_info, task_info):
    score = 0
    feedback_parts = []

    result = {}
    copy_from_env = env_info.get("copy_from_env") if env_info else None
    if copy_from_env:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        try:
            copy_from_env("/tmp/cross_functional_quality_response_result.json", tmp.name)
            with open(tmp.name) as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not load result: {e}"}
        finally:
            os.unlink(tmp.name)
    else:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env available"}

    # --- Criterion 1: Alert exists (8 pts) ---
    if result.get("alert_found"):
        score += 8
        feedback_parts.append(f"Alert found: '{result.get('alert_name', '')}' (+8)")
    else:
        feedback_parts.append("Alert with 'Field Failure' NOT found")

    # --- Criterion 2: Alert product (7 pts) ---
    if result.get("alert_found"):
        pn = result.get("alert_product_name", "").lower()
        if "acoustic" in pn and "screen" in pn:
            score += 7
            feedback_parts.append("Alert product correct (+7)")
        else:
            feedback_parts.append(f"Alert product wrong: '{result.get('alert_product_name')}'")

    # --- Criterion 3: Alert priority Urgent (7 pts) ---
    if result.get("alert_found"):
        if result.get("alert_priority") == "2":
            score += 7
            feedback_parts.append("Alert priority Urgent (+7)")
        else:
            feedback_parts.append(f"Alert priority '{result.get('alert_priority')}' (expected '2')")

    # --- Criterion 4: Corrective action (12 pts) ---
    if result.get("alert_found"):
        ca = result.get("alert_corrective_action", "").lower()
        ca_matches = 0
        if "stop shipment" in ca or "halt" in ca:
            ca_matches += 1
        if "fractographic" in ca or "fracto" in ca:
            ca_matches += 1
        if "crack" in ca or "fatigue" in ca:
            ca_matches += 1
        ca_pts = min(12, int(12 * ca_matches / 3))
        score += ca_pts
        feedback_parts.append(f"Corrective action: {ca_matches}/3 keywords (+{ca_pts})")

    # --- Criterion 5: Preventive action (12 pts) ---
    if result.get("alert_found"):
        pa = result.get("alert_preventive_action", "").lower()
        pa_matches = 0
        if "fillet" in pa or "radius" in pa:
            pa_matches += 1
        if "astm e164" in pa or "e164" in pa or "ultrasonic" in pa:
            pa_matches += 1
        if "dwg" in pa or "drawing" in pa or "redesign" in pa:
            pa_matches += 1
        pa_pts = min(12, int(12 * pa_matches / 3))
        score += pa_pts
        feedback_parts.append(f"Preventive action: {pa_matches}/3 keywords (+{pa_pts})")

    # --- Criterion 6: QCP exists with Pass-Fail (8 pts) ---
    if result.get("qcp_found"):
        if result.get("qcp_test_type") == "passfail":
            score += 8
            feedback_parts.append("QCP 'Bracket Integrity' found with Pass-Fail (+8)")
        else:
            score += 4
            feedback_parts.append(f"QCP found but type='{result.get('qcp_test_type')}' (+4)")
    else:
        feedback_parts.append("QCP 'Bracket Integrity' NOT found")

    # --- Criterion 7: QCP product (7 pts) ---
    if result.get("qcp_found"):
        names = result.get("qcp_product_names", [])
        if any("acoustic" in n.lower() for n in names):
            score += 7
            feedback_parts.append("QCP linked to Acoustic Bloc Screens (+7)")
        else:
            feedback_parts.append("QCP not linked to Acoustic Bloc Screens")

    # --- Criterion 8: QCP failure message (10 pts) ---
    if result.get("qcp_found"):
        fm = result.get("qcp_failure_message", "").lower()
        has_critical = "critical" in fm or "reject" in fm
        has_ut = "ut" in fm or "ultrasonic" in fm or "astm" in fm
        if has_critical and has_ut:
            score += 10
            feedback_parts.append("QCP failure message: CRITICAL + UT (+10)")
        elif has_critical or has_ut:
            score += 5
            feedback_parts.append(f"QCP failure message partial (+5)")
        else:
            feedback_parts.append("QCP failure message missing keywords")

    # --- Criterion 9: Screen Frame Scratch moved to In Progress (10 pts) ---
    sf_name = result.get("sf_stage_name", "").lower()
    sf_id = result.get("sf_stage_id")
    gt_ip_id = result.get("gt_in_progress_stage_id")
    if "progress" in sf_name or (gt_ip_id and sf_id == gt_ip_id):
        score += 10
        feedback_parts.append("'Screen Frame Scratch' moved to In Progress (+10)")
    else:
        feedback_parts.append(f"'Screen Frame Scratch' stage='{result.get('sf_stage_name')}' (expected In Progress)")

    # --- Criterion 10: Screen Colour Uniformity check passed (10 pts) ---
    if result.get("cu_state") == "pass":
        score += 10
        feedback_parts.append("'Screen Colour Uniformity Audit' passed (+10)")
    else:
        feedback_parts.append(f"'Screen Colour Uniformity Audit' state='{result.get('cu_state')}' (expected pass)")

    # --- Criterion 11: Bracket UT check exists (9 pts) ---
    if result.get("bracket_check_found"):
        score += 9
        feedback_parts.append(f"'Bracket UT Inspection' check found (+9)")
    else:
        feedback_parts.append("'Bracket UT Inspection' check NOT found")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts),
    }
