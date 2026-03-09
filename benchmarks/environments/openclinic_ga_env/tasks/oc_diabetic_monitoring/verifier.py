#!/usr/bin/env python3
"""
Verifier: oc_diabetic_monitoring — Diabetes HbA1c Compliance Audit

Reads /tmp/oc_diabetic_monitoring_result.json written by export_result.sh.

Protocol: All patients with GLUC > 126 mg/dL must have HbA1c within 90 days.
  - Ana Ferreira (10001):   GLUC=156, no HbA1c        -> NEEDS order
  - Maria Santos (10005):   GLUC=189, HbA1c 100d ago  -> NEEDS order (stale)
  - Priya Sharma (10007):   GLUC=142, no HbA1c        -> NEEDS order
  - Elena Popescu (10010):  GLUC=135, HbA1c 45d ago   -> do NOT order (current)

Scoring (100 pts):
  C1 (25 pts): New HbA1c ordered for Ana Ferreira (10001)
  C2 (25 pts): New HbA1c ordered for Maria Santos (10005)
  C3 (25 pts): New HbA1c ordered for Priya Sharma (10007)
  C4 (25 pts): Elena Popescu (10010) NOT given additional HbA1c

Pass threshold: 75 / 100
Do-nothing: 25/100 (C4 passes because no new Elena order exists) -> passed=False
"""

import json
import os
import tempfile


RESULT_FILE_IN_VM = "/tmp/oc_diabetic_monitoring_result.json"


def verify_oc_diabetic_monitoring(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0,
                "feedback": "copy_from_env not available"}

    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
        tmp_path = tmp.name
    try:
        copy_from_env(RESULT_FILE_IN_VM, tmp_path)
        with open(tmp_path, "r") as f:
            result = json.load(f)
    except (FileNotFoundError, OSError):
        return {"passed": False, "score": 0,
                "feedback": "Result file not found — export_result.sh may not have run"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0,
                "feedback": f"Result JSON is malformed: {e}"}
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)

    score = 0
    criteria = {}

    # ------------------------------------------------------------------
    # C1: New HbA1c ordered for Ana Ferreira (10001)
    # ------------------------------------------------------------------
    ana_new = result.get("ana_hba1c_new", -1)
    c1_pass = (ana_new >= 1)
    if c1_pass:
        score += 25
        criteria["C1_hba1c_ordered_ana"] = {
            "passed": True, "points": 25,
            "detail": "HbA1c test correctly ordered for Ana Ferreira"
        }
    else:
        criteria["C1_hba1c_ordered_ana"] = {
            "passed": False, "points": 0,
            "detail": "HbA1c NOT ordered for Ana Ferreira — required (GLUC=156, no prior HbA1c)"
        }

    # ------------------------------------------------------------------
    # C2: New HbA1c ordered for Maria Santos (10005)
    # Her prior HbA1c was 100 days ago — stale per 90-day protocol
    # ------------------------------------------------------------------
    maria_new = result.get("maria_hba1c_new", -1)
    c2_pass = (maria_new >= 1)
    if c2_pass:
        score += 25
        criteria["C2_hba1c_ordered_maria"] = {
            "passed": True, "points": 25,
            "detail": "HbA1c test correctly ordered for Maria Santos (prior result 100 days old)"
        }
    else:
        criteria["C2_hba1c_ordered_maria"] = {
            "passed": False, "points": 0,
            "detail": "HbA1c NOT ordered for Maria Santos — prior result 100 days ago exceeds 90-day limit"
        }

    # ------------------------------------------------------------------
    # C3: New HbA1c ordered for Priya Sharma (10007)
    # ------------------------------------------------------------------
    priya_new = result.get("priya_hba1c_new", -1)
    c3_pass = (priya_new >= 1)
    if c3_pass:
        score += 25
        criteria["C3_hba1c_ordered_priya"] = {
            "passed": True, "points": 25,
            "detail": "HbA1c test correctly ordered for Priya Sharma"
        }
    else:
        criteria["C3_hba1c_ordered_priya"] = {
            "passed": False, "points": 0,
            "detail": "HbA1c NOT ordered for Priya Sharma — required (GLUC=142, no prior HbA1c)"
        }

    # ------------------------------------------------------------------
    # C4: Elena Popescu (10010) NOT given additional HbA1c
    # Her HbA1c was 45 days ago — within protocol window; ordering again is wrong
    # ------------------------------------------------------------------
    elena_new = result.get("elena_hba1c_new", -1)
    c4_pass = (elena_new == 0)
    if c4_pass:
        score += 25
        criteria["C4_no_unnecessary_order_elena"] = {
            "passed": True, "points": 25,
            "detail": "Correctly did NOT order HbA1c for Elena Popescu (current result 45 days ago)"
        }
    else:
        criteria["C4_no_unnecessary_order_elena"] = {
            "passed": False, "points": 0,
            "detail": (f"Unnecessary HbA1c order placed for Elena Popescu ({elena_new} new order(s)). "
                       "Her result from 45 days ago is within the 90-day window.")
        }

    passed = score >= 75
    ordered = sum([c1_pass, c2_pass, c3_pass])

    return {
        "passed": passed,
        "score": score,
        "feedback": {
            "total_score": score,
            "pass_threshold": 75,
            "required_orders_placed": f"{ordered}/3",
            "elena_over_ordered": not c4_pass,
            "criteria": criteria,
            "new_order_counts": {
                "ana": ana_new, "maria": maria_new,
                "priya": priya_new, "elena": elena_new
            }
        }
    }
