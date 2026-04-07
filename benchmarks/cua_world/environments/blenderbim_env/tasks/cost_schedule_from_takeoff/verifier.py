#!/usr/bin/env python3
"""
Verifier for cost_schedule_from_takeoff task.

Scoring rubric (100 points total, pass threshold = 65):
  - file_is_new          : 20 pts  (output IFC created/modified during this task)
  - cost_schedule_exists : 25 pts  (at least 1 IfcCostSchedule present)
  - cost_items_complete  : 35 pts  (at least 4 IfcCostItem entities; partial at 2+)
  - cost_values_assigned : 20 pts  (at least 4 IfcCostValue entities; partial at 2+)
"""

import json
import os
import tempfile


def verify_cost_schedule_from_takeoff(traj, env_info, task_info):
    score = 0
    feedback_lines = []

    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0,
                "feedback": "copy_from_env not available in env_info."}

    # ── Copy result JSON from VM ──────────────────────────────────────────
    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as f:
        tmp_path = f.name

    try:
        copy_from_env("/tmp/cost_schedule_result.json", tmp_path)
        with open(tmp_path, "r") as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0,
                "feedback": "Result file not found — export script may not have run."}
    except Exception as e:
        return {"passed": False, "score": 0,
                "feedback": f"Could not read result file: {e}"}
    finally:
        try:
            os.unlink(tmp_path)
        except Exception:
            pass

    # ── Critical gate: output file must exist ─────────────────────────────
    if not result.get("file_exists", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "FAIL: Output IFC file /home/ga/BIMProjects/fzk_cost_schedule.ifc "
                "was not created. Score: 0/100."
            ),
        }

    # ── Check 1: File is newly created during this task session ───────────
    file_mtime = result.get("file_mtime", 0.0)
    task_start = result.get("task_start", 0.0)
    if task_start > 0 and file_mtime > task_start:
        score += 20
        feedback_lines.append("PASS: Output IFC file was created/saved during this task session. (+20)")
    else:
        feedback_lines.append(
            "FAIL: Output file was not modified during the task "
            f"(file_mtime={file_mtime:.1f}, task_start={task_start:.1f}). (+0)"
        )

    # ── Check 2: At least 1 IfcCostSchedule ──────────────────────────────
    n_schedules = result.get("cost_schedules", 0)
    if n_schedules >= 1:
        score += 25
        feedback_lines.append(
            f"PASS: IfcCostSchedule found ({n_schedules} schedule(s) in IFC). (+25)"
        )
    else:
        feedback_lines.append(
            "FAIL: No IfcCostSchedule found in output IFC — "
            "cost schedule was not created or not saved. (+0)"
        )

    # ── Check 3: At least 4 IfcCostItem ──────────────────────────────────
    n_items = result.get("cost_items", 0)
    if n_items >= 4:
        score += 35
        feedback_lines.append(
            f"PASS: IfcCostItem count {n_items} >= 4 required items. (+35)"
        )
    elif n_items >= 2:
        score += 15
        feedback_lines.append(
            f"PARTIAL: IfcCostItem count {n_items}/4 — partial credit for 2-3 items. (+15)"
        )
    elif n_items == 1:
        score += 5
        feedback_lines.append(
            f"PARTIAL: IfcCostItem count {n_items}/4 — minimal credit. (+5)"
        )
    else:
        feedback_lines.append(
            "FAIL: No IfcCostItem found — cost items were not created. (+0)"
        )

    # ── Check 4: At least 4 IfcCostValue (unit rates) ────────────────────
    n_values = result.get("cost_values", 0)
    if n_values >= 4:
        score += 20
        feedback_lines.append(
            f"PASS: IfcCostValue count {n_values} >= 4 unit rates assigned. (+20)"
        )
    elif n_values >= 2:
        score += 8
        feedback_lines.append(
            f"PARTIAL: IfcCostValue count {n_values}/4 — partial credit. (+8)"
        )
    else:
        feedback_lines.append(
            f"FAIL: IfcCostValue count {n_values}/4 — unit rates not assigned. (+0)"
        )

    passed = score >= 65
    feedback_lines.append(
        f"\nTotal score: {score}/100. {'PASSED' if passed else 'FAILED'} (threshold: 65)."
    )

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_lines),
    }
