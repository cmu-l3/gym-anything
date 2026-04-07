#!/usr/bin/env python3
"""Verifier for supplier_nonconformance_capa_protocol task.

Full CAPA lifecycle verification — 100 pts total, pass >= 55.

Scoring breakdown:
  1.  Quality check failed                            (7 pts)
  2.  Alert exists with correct product               (8 pts)
  3.  Alert vendor = Gemini Furniture                  (5 pts)
  4.  Alert priority = Urgent (3 stars)                (4 pts)
  5.  Alert corrective action has key phrases          (5 pts)
  6.  Alert preventive action has key phrases          (5 pts)
  7.  Alert stage = Done                               (8 pts)
  8.  Team "Supplier Incident Response" exists          (10 pts)
  9.  Alert assigned to that team                      (5 pts)
 10.  Measure QCP exists with correct type             (10 pts)
 11.  Measure QCP linked to Cabinet with Doors         (5 pts)
 12.  Measure QCP has instructions text                (3 pts)
 13.  Measure QCP failure message has keywords          (4 pts)
 14.  Pass-Fail QCP exists with correct type            (8 pts)
 15.  Pass-Fail QCP linked to Acoustic Bloc Screens     (4 pts)
 16.  Pass-Fail QCP failure message has keywords         (4 pts)
 17.  Measure QCP has Receipts operation                 (3 pts)
 18.  Pass-Fail QCP has Receipts operation               (2 pts)
"""

import json
import os
import tempfile


def _has_product(names_list, target_substr):
    """Check if any product name contains the target substring."""
    return any(target_substr.lower() in n.lower() for n in (names_list or []))


def verify_supplier_nonconformance_capa_protocol(traj, env_info, task_info):
    score = 0
    feedback_parts = []

    copy_from_env = env_info.get("copy_from_env") if env_info else None
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env("/tmp/supplier_nonconformance_capa_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not load result: {e}"}
    finally:
        os.unlink(tmp.name)

    if "error" in result:
        return {"passed": False, "score": 0,
                "feedback": f"Export error: {result['error']}"}

    gt_gemini_id = result.get("gt_gemini_id")
    gt_cabinet_id = result.get("gt_cabinet_id")
    gt_done_stage_id = result.get("gt_done_stage_id")

    # ---- 1. Quality check failed (7 pts) ----
    if result.get("check_state") == "fail":
        score += 7
        feedback_parts.append("Check 'Visual Inspection - Cabinet Finish' failed (+7)")
    else:
        feedback_parts.append(
            f"Check state='{result.get('check_state')}' (expected 'fail')")

    # ---- 2. Alert exists with correct product (8 pts) ----
    if result.get("alert_found"):
        score += 5
        feedback_parts.append("Alert found (+5)")
        if result.get("alert_product_id") == gt_cabinet_id:
            score += 3
            feedback_parts.append("Alert product = Cabinet with Doors (+3)")
        else:
            feedback_parts.append(
                f"Alert product mismatch (got '{result.get('alert_product_name')}')")
    else:
        feedback_parts.append("Alert NOT found")

    # ---- 3. Alert vendor (5 pts) ----
    if result.get("alert_partner_id") == gt_gemini_id:
        score += 5
        feedback_parts.append("Alert vendor = Gemini Furniture (+5)")
    elif result.get("alert_partner_id"):
        feedback_parts.append(
            f"Alert vendor wrong (got '{result.get('alert_partner_name')}')")
    else:
        feedback_parts.append("Alert vendor not set")

    # ---- 4. Alert priority Urgent / 3 stars (4 pts) ----
    if result.get("alert_priority") == "3":
        score += 4
        feedback_parts.append("Alert priority = Urgent (+4)")
    elif result.get("alert_priority") in ("1", "2"):
        score += 1
        feedback_parts.append(
            f"Alert priority = {result.get('alert_priority')} (expected 3, +1)")
    else:
        feedback_parts.append("Alert priority not elevated")

    # ---- 5. Alert corrective action (5 pts) ----
    ca = (result.get("alert_corrective") or "").lower()
    if "scar" in ca and ("quarantine" in ca or "re-inspect" in ca):
        score += 5
        feedback_parts.append("Corrective action has key phrases (+5)")
    elif "scar" in ca or "quarantine" in ca:
        score += 3
        feedback_parts.append("Corrective action partially matches (+3)")
    elif len(ca) > 20:
        score += 1
        feedback_parts.append("Corrective action has text but missing keywords (+1)")
    else:
        feedback_parts.append("Corrective action empty or missing keywords")

    # ---- 6. Alert preventive action (5 pts) ----
    pa = (result.get("alert_preventive") or "").lower()
    if "first-article" in pa and ("certificate" in pa or "qcp" in pa or "conformance" in pa):
        score += 5
        feedback_parts.append("Preventive action has key phrases (+5)")
    elif "first-article" in pa or "inspection" in pa:
        score += 3
        feedback_parts.append("Preventive action partially matches (+3)")
    elif len(pa) > 20:
        score += 1
        feedback_parts.append("Preventive action has text but missing keywords (+1)")
    else:
        feedback_parts.append("Preventive action empty or missing keywords")

    # ---- 7. Alert stage = Done (8 pts) ----
    if result.get("alert_stage_id") == gt_done_stage_id:
        score += 8
        feedback_parts.append("Alert stage = Done (+8)")
    elif result.get("alert_stage_name", "").lower() in ("done", "closed"):
        score += 8
        feedback_parts.append("Alert stage = Done (by name, +8)")
    elif "progress" in (result.get("alert_stage_name") or "").lower():
        score += 4
        feedback_parts.append("Alert stage = In Progress (partial +4)")
    else:
        feedback_parts.append(
            f"Alert stage='{result.get('alert_stage_name')}' (expected Done)")

    # ---- 8. Team exists (10 pts) ----
    if result.get("team_found"):
        score += 10
        feedback_parts.append("Team 'Supplier Incident Response' exists (+10)")
    else:
        feedback_parts.append("Team 'Supplier Incident Response' NOT found")

    # ---- 9. Alert assigned to team (5 pts) ----
    if result.get("team_found") and result.get("alert_team_id") == result.get("team_id"):
        score += 5
        feedback_parts.append("Alert assigned to Supplier Incident Response (+5)")
    elif result.get("alert_team_id"):
        score += 2
        feedback_parts.append(
            f"Alert assigned to different team '{result.get('alert_team_name')}' (+2)")
    else:
        feedback_parts.append("Alert not assigned to any team")

    # ---- 10. Measure QCP exists with type (10 pts) ----
    if result.get("measure_qcp_found"):
        if result.get("measure_qcp_test_type") == "measure":
            score += 10
            feedback_parts.append("Measure QCP found with type=measure (+10)")
        else:
            score += 4
            feedback_parts.append(
                f"Measure QCP found but type='{result.get('measure_qcp_test_type')}' (+4)")
    else:
        feedback_parts.append("Measure QCP NOT found")

    # ---- 11. Measure QCP product (5 pts) ----
    if _has_product(result.get("measure_qcp_product_names"), "cabinet"):
        score += 5
        feedback_parts.append("Measure QCP linked to Cabinet with Doors (+5)")
    elif result.get("measure_qcp_found"):
        feedback_parts.append("Measure QCP not linked to correct product")

    # ---- 12. Measure QCP instructions (3 pts) ----
    mnote = (result.get("measure_qcp_note") or "").lower()
    if "weld" in mnote or "dwg" in mnote or "bead" in mnote:
        score += 3
        feedback_parts.append("Measure QCP has instructions with key content (+3)")
    elif len(mnote) > 10:
        score += 1
        feedback_parts.append("Measure QCP has instructions text (+1)")
    elif result.get("measure_qcp_found"):
        feedback_parts.append("Measure QCP missing instructions")

    # ---- 13. Measure QCP failure message (4 pts) ----
    mfm = (result.get("measure_qcp_failure_message") or "").lower()
    if "ncr" in mfm or "qp-ncr" in mfm:
        score += 4
        feedback_parts.append("Measure QCP failure message has NCR keyword (+4)")
    elif "reject" in mfm or "quarantine" in mfm:
        score += 2
        feedback_parts.append("Measure QCP failure message partial match (+2)")
    elif result.get("measure_qcp_found"):
        feedback_parts.append("Measure QCP failure message missing keywords")

    # ---- 14. Pass-Fail QCP exists with type (8 pts) ----
    if result.get("passfail_qcp_found"):
        if result.get("passfail_qcp_test_type") == "passfail":
            score += 8
            feedback_parts.append("Pass-Fail QCP found with type=passfail (+8)")
        else:
            score += 3
            feedback_parts.append(
                f"Pass-Fail QCP found but type='{result.get('passfail_qcp_test_type')}' (+3)")
    else:
        feedback_parts.append("Pass-Fail QCP NOT found")

    # ---- 15. Pass-Fail QCP product (4 pts) ----
    if _has_product(result.get("passfail_qcp_product_names"), "acoustic"):
        score += 4
        feedback_parts.append("Pass-Fail QCP linked to Acoustic Bloc Screens (+4)")
    elif result.get("passfail_qcp_found"):
        feedback_parts.append("Pass-Fail QCP not linked to correct product")

    # ---- 16. Pass-Fail QCP failure message (4 pts) ----
    pfm = (result.get("passfail_qcp_failure_message") or "").lower()
    if "sf-003" in pfm:
        score += 4
        feedback_parts.append("Pass-Fail QCP failure message has SF-003 (+4)")
    elif "surface" in pfm or "defect" in pfm:
        score += 2
        feedback_parts.append("Pass-Fail QCP failure message partial match (+2)")
    elif result.get("passfail_qcp_found"):
        feedback_parts.append("Pass-Fail QCP failure message missing keywords")

    # ---- 17. Measure QCP has Receipts operation (3 pts) ----
    if result.get("measure_qcp_picking_type_ids"):
        score += 3
        feedback_parts.append("Measure QCP has operation type set (+3)")
    elif result.get("measure_qcp_found"):
        feedback_parts.append("Measure QCP missing operation type")

    # ---- 18. Pass-Fail QCP has Receipts operation (2 pts) ----
    if result.get("passfail_qcp_picking_type_ids"):
        score += 2
        feedback_parts.append("Pass-Fail QCP has operation type set (+2)")
    elif result.get("passfail_qcp_found"):
        feedback_parts.append("Pass-Fail QCP missing operation type")

    passed = score >= 55
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts),
    }
