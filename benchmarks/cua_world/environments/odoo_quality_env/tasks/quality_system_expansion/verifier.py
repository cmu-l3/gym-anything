#!/usr/bin/env python3
"""Verifier for quality_system_expansion task.

Multi-criterion scoring (100 pts total):
  1. Team "Product Line B - Compliance Unit" exists                (15 pts)
  2. QCP "Surface Finish Verification" exists                      (10 pts)
  3. QCP "Surface Finish" linked to Customizable Desk              (8 pts)
  4. QCP "Surface Finish" failure message has Ra + 1.6              (10 pts)
  5. QCP "Load-Bearing Capacity Test" exists                       (10 pts)
  6. QCP "Load-Bearing" linked to Large Cabinet                    (8 pts)
  7. QCP "Load-Bearing" failure message has 200 kg + EN 14073      (10 pts)
  8. "Desk Height" alert preventive action keywords                (15 pts)
  9. "Chair Foam" alert preventive action keywords                 (14 pts)
"""

import json
import os
import tempfile


def verify_quality_system_expansion(traj, env_info, task_info):
    score = 0
    feedback_parts = []

    result = {}
    copy_from_env = env_info.get("copy_from_env") if env_info else None
    if copy_from_env:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        try:
            copy_from_env("/tmp/quality_system_expansion_result.json", tmp.name)
            with open(tmp.name) as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not load result: {e}"}
        finally:
            os.unlink(tmp.name)
    else:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env available"}

    def _has_product(names, target):
        return any(target.lower() in n.lower() for n in names)

    # --- Criterion 1: Team exists (15 pts) ---
    if result.get("team_found"):
        score += 15
        feedback_parts.append("Team 'Product Line B - Compliance Unit' found (+15)")
    else:
        feedback_parts.append("Team NOT found")

    # --- Criterion 2-4: QCP Surface Finish (10 + 8 + 10 pts) ---
    if result.get("qcp1_found"):
        score += 10
        feedback_parts.append("QCP 'Surface Finish Verification' found (+10)")
        if _has_product(result.get("qcp1_product_names", []), "desk"):
            score += 8
            feedback_parts.append("QCP1 linked to Customizable Desk (+8)")
        else:
            feedback_parts.append("QCP1 not linked to Customizable Desk")
        fm = result.get("qcp1_failure_message", "").lower()
        has_ra = "ra" in fm or "surface finish" in fm
        has_spec = "1.6" in fm or "iso 4287" in fm
        if has_ra and has_spec:
            score += 10
            feedback_parts.append("QCP1 failure message has Ra + spec (+10)")
        elif has_ra or has_spec:
            score += 5
            feedback_parts.append(f"QCP1 failure message partial match (+5)")
        else:
            feedback_parts.append("QCP1 failure message missing Ra/spec keywords")
    else:
        feedback_parts.append("QCP 'Surface Finish Verification' NOT found")

    # --- Criterion 5-7: QCP Load-Bearing (10 + 8 + 10 pts) ---
    if result.get("qcp2_found"):
        score += 10
        feedback_parts.append("QCP 'Load-Bearing Capacity Test' found (+10)")
        if _has_product(result.get("qcp2_product_names", []), "cabinet"):
            score += 8
            feedback_parts.append("QCP2 linked to Large Cabinet (+8)")
        else:
            feedback_parts.append("QCP2 not linked to Large Cabinet")
        fm = result.get("qcp2_failure_message", "").lower()
        has_load = "200" in fm
        has_std = "en 14073" in fm or "load test" in fm
        if has_load and has_std:
            score += 10
            feedback_parts.append("QCP2 failure message has 200 kg + standard (+10)")
        elif has_load or has_std:
            score += 5
            feedback_parts.append(f"QCP2 failure message partial match (+5)")
        else:
            feedback_parts.append("QCP2 failure message missing load/standard keywords")
    else:
        feedback_parts.append("QCP 'Load-Bearing Capacity Test' NOT found")

    # --- Criterion 8: Desk Height preventive action (15 pts) ---
    pa1 = result.get("desk_pa", "").lower()
    pa1_kws = ["linear actuator", "torque test", "50,000" if "50,000" in pa1 else "50000"]
    # Flexible matching for the cycle count
    pa1_matches = 0
    if "linear actuator" in pa1 or "actuator" in pa1:
        pa1_matches += 1
    if "torque" in pa1:
        pa1_matches += 1
    if "ppap" in pa1 or "50" in pa1:
        pa1_matches += 1
    pa1_pts = min(15, int(15 * pa1_matches / 3))
    score += pa1_pts
    if pa1_pts > 0:
        feedback_parts.append(f"Desk Height preventive action: {pa1_matches}/3 keywords (+{pa1_pts})")
    else:
        feedback_parts.append("Desk Height preventive action missing or no keywords")

    # --- Criterion 9: Chair Foam preventive action (14 pts) ---
    pa2 = result.get("chair_pa", "").lower()
    pa2_matches = 0
    if "iso 3386" in pa2 or "3386" in pa2:
        pa2_matches += 1
    if "density" in pa2:
        pa2_matches += 1
    if "supplier" in pa2 or "approved" in pa2:
        pa2_matches += 1
    pa2_pts = min(14, int(14 * pa2_matches / 3))
    score += pa2_pts
    if pa2_pts > 0:
        feedback_parts.append(f"Chair Foam preventive action: {pa2_matches}/3 keywords (+{pa2_pts})")
    else:
        feedback_parts.append("Chair Foam preventive action missing or no keywords")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts),
    }
