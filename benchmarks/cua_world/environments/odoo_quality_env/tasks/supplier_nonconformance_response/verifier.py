#!/usr/bin/env python3
"""Verifier for supplier_nonconformance_response task.

Multi-criterion scoring (100 pts total):
  1. Team "Supplier Nonconformance Review Board" exists          (12 pts)
  2. Alert with name containing "Systematic Dimensional Variance" (10 pts)
  3. Alert product is "Acoustic Bloc Screens"                     (10 pts)
  4. Alert priority is Urgent ("2")                               (10 pts)
  5. Corrective action contains key phrases                       (16 pts)
  6. Preventive action contains key phrases                       (16 pts)
  7. "Material Hardness" alert moved to In Progress               (13 pts)
  8. "Screen Frame Scratch" alert priority changed to Urgent      (13 pts)
"""

import json
import os
import shutil
import tempfile


def verify_supplier_nonconformance_response(traj, env_info, task_info):
    score = 0
    feedback_parts = []

    # --- Load result JSON ---
    result = {}
    copy_from_env = env_info.get("copy_from_env") if env_info else None
    if copy_from_env:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        try:
            copy_from_env("/tmp/supplier_nonconformance_response_result.json", tmp.name)
            with open(tmp.name) as f:
                result = json.load(f)
        except Exception as e:
            feedback_parts.append(f"Could not load result: {e}")
            return {"passed": False, "score": 0, "feedback": "; ".join(feedback_parts)}
        finally:
            os.unlink(tmp.name)
    else:
        feedback_parts.append("No copy_from_env available")
        return {"passed": False, "score": 0, "feedback": "; ".join(feedback_parts)}

    # --- Criterion 1: Team exists (12 pts) ---
    if result.get("team_found"):
        score += 12
        feedback_parts.append("Team 'Supplier Nonconformance Review Board' found (+12)")
    else:
        feedback_parts.append("Team 'Supplier Nonconformance Review Board' NOT found")

    # --- Criterion 2: Alert exists (10 pts) ---
    if result.get("alert_found"):
        score += 10
        feedback_parts.append(f"Alert found: '{result.get('alert_name', '')}' (+10)")
    else:
        feedback_parts.append("Alert with 'Systematic Dimensional Variance' NOT found")
        # Early feedback but continue scoring other criteria
        feedback_parts.append("Skipping alert-dependent criteria (3-6)")
        # Still check criteria 7-8

    # --- Criterion 3: Alert product correct (10 pts) ---
    if result.get("alert_found"):
        product_name = result.get("alert_product_name", "").lower()
        if "acoustic" in product_name and "screen" in product_name:
            score += 10
            feedback_parts.append(f"Alert product correct: '{result.get('alert_product_name')}' (+10)")
        else:
            feedback_parts.append(f"Alert product wrong: '{result.get('alert_product_name')}' (expected Acoustic Bloc Screens)")

    # --- Criterion 4: Alert priority Urgent (10 pts) ---
    if result.get("alert_found"):
        if result.get("alert_priority") == "2":
            score += 10
            feedback_parts.append("Alert priority is Urgent (+10)")
        else:
            feedback_parts.append(f"Alert priority is '{result.get('alert_priority')}' (expected '2'/Urgent)")

    # --- Criterion 5: Corrective action keywords (16 pts) ---
    if result.get("alert_found"):
        ca = result.get("alert_corrective_action", "").lower()
        ca_keywords = ["quarantine", "ncr", "cmm"]
        ca_matches = sum(1 for kw in ca_keywords if kw in ca)
        ca_pts = min(16, int(16 * ca_matches / len(ca_keywords)))
        score += ca_pts
        if ca_pts > 0:
            feedback_parts.append(f"Corrective action: {ca_matches}/{len(ca_keywords)} keywords (+{ca_pts})")
        else:
            feedback_parts.append("Corrective action missing or no keywords matched")

    # --- Criterion 6: Preventive action keywords (16 pts) ---
    if result.get("alert_found"):
        pa = result.get("alert_preventive_action", "").lower()
        pa_keywords = ["sampling plan", "ansi", "surveillance"]
        pa_matches = sum(1 for kw in pa_keywords if kw in pa)
        pa_pts = min(16, int(16 * pa_matches / len(pa_keywords)))
        score += pa_pts
        if pa_pts > 0:
            feedback_parts.append(f"Preventive action: {pa_matches}/{len(pa_keywords)} keywords (+{pa_pts})")
        else:
            feedback_parts.append("Preventive action missing or no keywords matched")

    # --- Criterion 7: Material Hardness alert moved to In Progress (13 pts) ---
    mh_stage_name = result.get("mh_stage_name", "").lower()
    mh_stage_id = result.get("mh_stage_id")
    gt_ip_id = result.get("gt_in_progress_stage_id")
    if "progress" in mh_stage_name or (gt_ip_id and mh_stage_id == gt_ip_id):
        score += 13
        feedback_parts.append(f"'Material Hardness' alert moved to In Progress (+13)")
    else:
        feedback_parts.append(f"'Material Hardness' alert stage: '{result.get('mh_stage_name', 'unknown')}' (expected In Progress)")

    # --- Criterion 8: Screen Frame Scratch priority changed to Urgent (13 pts) ---
    sf_priority = result.get("sf_priority", "")
    if sf_priority == "2":
        score += 13
        feedback_parts.append("'Screen Frame Scratch' priority changed to Urgent (+13)")
    else:
        feedback_parts.append(f"'Screen Frame Scratch' priority: '{sf_priority}' (expected '2'/Urgent)")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts),
    }
