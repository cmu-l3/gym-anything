#!/usr/bin/env python3
"""Verifier for batch_alert_triage task.

Multi-criterion scoring (100 pts total):
  1. "Cabinet Door Hinge Misalignment" moved to Done         (12 pts)
  2. "Acoustic Panel Bonding Failure" moved to Done           (12 pts)
  3. "Cabinet Coating Thickness Non-Uniform" moved to Done    (12 pts)
  4. "Chair Armrest Cracking" priority = Urgent ("2")         (12 pts)
  5. "Loose Hardware on Shelf Unit" priority = High ("1")     (12 pts)
  6. "Desk Laminate Delamination" corrective action keywords  (15 pts)
  7. New "Q4 2024 Quality Review" alert exists                (15 pts)
  8. Q4 alert has non-empty description                       (10 pts)
"""

import json
import os
import tempfile


def verify_batch_alert_triage(traj, env_info, task_info):
    score = 0
    feedback_parts = []

    result = {}
    copy_from_env = env_info.get("copy_from_env") if env_info else None
    if copy_from_env:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        try:
            copy_from_env("/tmp/batch_alert_triage_result.json", tmp.name)
            with open(tmp.name) as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not load result: {e}"}
        finally:
            os.unlink(tmp.name)
    else:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env available"}

    gt_done_id = result.get("gt_done_stage_id")

    def _is_done(stage_name, stage_id):
        if gt_done_id and stage_id == gt_done_id:
            return True
        nm = (stage_name or "").lower()
        return "done" in nm or "close" in nm

    # --- Criteria 1-3: Stage transitions to Done (12 pts each) ---
    for key, label in [
        ("hinge", "Cabinet Door Hinge Misalignment"),
        ("bonding", "Acoustic Panel Bonding Failure"),
        ("coating", "Cabinet Coating Thickness Non-Uniform"),
    ]:
        sname = result.get(f"{key}_stage_name", "")
        sid = result.get(f"{key}_stage_id")
        if _is_done(sname, sid):
            score += 12
            feedback_parts.append(f"'{label}' moved to Done (+12)")
        else:
            feedback_parts.append(f"'{label}' stage='{sname}' (expected Done)")

    # --- Criterion 4: Chair Armrest priority Urgent (12 pts) ---
    if result.get("armrest_priority") == "2":
        score += 12
        feedback_parts.append("'Chair Armrest Cracking' priority=Urgent (+12)")
    else:
        feedback_parts.append(f"'Chair Armrest Cracking' priority='{result.get('armrest_priority')}' (expected '2')")

    # --- Criterion 5: Loose Hardware priority High (12 pts) ---
    if result.get("hardware_priority") == "1":
        score += 12
        feedback_parts.append("'Loose Hardware on Shelf Unit' priority=High (+12)")
    else:
        feedback_parts.append(f"'Loose Hardware on Shelf Unit' priority='{result.get('hardware_priority')}' (expected '1')")

    # --- Criterion 6: Desk Laminate corrective action (15 pts) ---
    ca = result.get("desk_corrective_action", "").lower()
    ca_kws = ["adhesive", "rework", "humidity"]
    ca_matches = sum(1 for kw in ca_kws if kw in ca)
    ca_pts = min(15, int(15 * ca_matches / len(ca_kws)))
    score += ca_pts
    if ca_pts > 0:
        feedback_parts.append(f"Desk Laminate corrective action: {ca_matches}/{len(ca_kws)} keywords (+{ca_pts})")
    else:
        feedback_parts.append("Desk Laminate corrective action missing or no keywords")

    # --- Criterion 7: Q4 alert exists (15 pts) ---
    if result.get("q4_alert_found"):
        score += 15
        feedback_parts.append("'Q4 2024 Quality Review' alert found (+15)")
    else:
        feedback_parts.append("'Q4 2024 Quality Review' alert NOT found")

    # --- Criterion 8: Q4 alert description non-empty (10 pts) ---
    if result.get("q4_alert_found"):
        desc = result.get("q4_alert_description", "")
        if len(desc) > 20:
            score += 10
            feedback_parts.append(f"Q4 alert description present ({len(desc)} chars) (+10)")
        else:
            feedback_parts.append("Q4 alert description too short or empty")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts),
    }
