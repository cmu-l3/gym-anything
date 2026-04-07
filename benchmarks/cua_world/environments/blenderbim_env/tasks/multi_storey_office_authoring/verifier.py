#!/usr/bin/env python3
"""
Verifier for multi_storey_office_authoring task.

Scoring rubric (100 points total, pass threshold = 65):
  - file_is_new          : 15 pts  (output IFC created during this task)
  - project_name_correct : 15 pts  ('Meridian' in project name, case-insensitive)
  - storeys_3plus        : 25 pts  (at least 3 IfcBuildingStorey entities)
  - upper_floors_correct : 20 pts  (storeys have non-zero elevations / upper floors exist)
  - walls_12plus         : 25 pts  (at least 12 IfcWall entities across all storeys;
                                    partial credit at 4+)
"""

import json
import os
import tempfile


def verify_multi_storey_office_authoring(traj, env_info, task_info):
    score = 0
    feedback_lines = []

    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0,
                "feedback": "copy_from_env not available in env_info."}

    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as f:
        tmp_path = f.name

    try:
        copy_from_env("/tmp/office_authoring_result.json", tmp_path)
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
                "FAIL: Output IFC file /home/ga/BIMProjects/meridian_office.ifc "
                "was not created. Score: 0/100."
            ),
        }

    # ── Check 1: File is newly created during this task session ───────────
    file_mtime = result.get("file_mtime", 0.0)
    task_start = result.get("task_start", 0.0)
    if task_start > 0 and file_mtime > task_start:
        score += 15
        feedback_lines.append("PASS: Output IFC was created during this task session. (+15)")
    else:
        feedback_lines.append(
            f"FAIL: Output file not modified during task "
            f"(file_mtime={file_mtime:.1f}, task_start={task_start:.1f}). (+0)"
        )

    # ── Check 2: Project name contains 'Meridian' ─────────────────────────
    project_name = result.get("project_name", "")
    if "meridian" in project_name.lower():
        score += 15
        feedback_lines.append(
            f"PASS: Project name '{project_name}' contains 'Meridian' as required. (+15)"
        )
    else:
        feedback_lines.append(
            f"FAIL: Project name '{project_name}' does not contain 'Meridian'. "
            "Expected 'Meridian Office Tower'. (+0)"
        )

    # ── Check 3: At least 3 IfcBuildingStorey entities ───────────────────
    n_storeys = result.get("n_storeys", 0)
    if n_storeys >= 3:
        score += 25
        feedback_lines.append(
            f"PASS: {n_storeys} IfcBuildingStorey found (>= 3 required). (+25)"
        )
    elif n_storeys == 2:
        score += 10
        feedback_lines.append(
            f"PARTIAL: {n_storeys}/3 storeys found — partial credit. (+10)"
        )
    elif n_storeys == 1:
        score += 4
        feedback_lines.append(
            f"PARTIAL: {n_storeys}/3 storeys found — minimal credit. (+4)"
        )
    else:
        feedback_lines.append(
            "FAIL: No IfcBuildingStorey found — storeys were not created. (+0)"
        )

    # ── Check 4: Upper floors have non-zero elevations ───────────────────
    has_upper = result.get("has_upper_floor", False)
    has_second = result.get("has_second_floor", False)
    elevations = result.get("storey_elevations", [])

    if has_second:
        score += 20
        feedback_lines.append(
            f"PASS: Two upper floors modelled (elevations: {elevations}). (+20)"
        )
    elif has_upper:
        score += 10
        feedback_lines.append(
            f"PARTIAL: At least one upper floor found (elevations: {elevations}). (+10)"
        )
    else:
        feedback_lines.append(
            f"FAIL: No upper floor elevations detected "
            f"(elevations: {elevations}). Expected storeys at ~3.5m and ~7.0m. (+0)"
        )

    # ── Check 5: At least 12 walls across all storeys ────────────────────
    n_walls = result.get("n_walls", 0)
    if n_walls >= 12:
        score += 25
        feedback_lines.append(
            f"PASS: {n_walls} IfcWall found (>= 12 required). (+25)"
        )
    elif n_walls >= 8:
        score += 18
        feedback_lines.append(
            f"PARTIAL: {n_walls}/12 walls found — good progress. (+18)"
        )
    elif n_walls >= 4:
        score += 10
        feedback_lines.append(
            f"PARTIAL: {n_walls}/12 walls found — partial credit. (+10)"
        )
    elif n_walls >= 1:
        score += 4
        feedback_lines.append(
            f"PARTIAL: {n_walls}/12 walls found — minimal credit. (+4)"
        )
    else:
        feedback_lines.append(
            "FAIL: No IfcWall found — walls were not modelled. (+0)"
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
