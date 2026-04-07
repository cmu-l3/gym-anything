#!/usr/bin/env python3
"""
Verifier for structural_frame_modeling task.

Required elements: >= 4 IfcColumn, >= 4 IfcBeam, >= 1 IfcSlab,
concrete material assigned to structural elements.

Scoring rubric (100 points total, pass threshold = 65):
  - file_is_new              : 15 pts
  - columns_4plus            : 25 pts  (>= 4 IfcColumn; partial at >= 2)
  - beams_4plus              : 20 pts  (>= 4 IfcBeam; partial at >= 2)
  - slab_present             : 15 pts  (>= 1 IfcSlab)
  - concrete_material        : 25 pts  (material with 'Concrete'/'Reinforced' in name,
                                        assigned to >= 1 structural element)
"""

import json
import os
import tempfile


def verify_structural_frame_modeling(traj, env_info, task_info):
    score = 0
    feedback_lines = []

    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0,
                "feedback": "copy_from_env not available in env_info."}

    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as f:
        tmp_path = f.name

    try:
        copy_from_env("/tmp/structural_frame_result.json", tmp_path)
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
                "FAIL: Output IFC file /home/ga/BIMProjects/structural_frame.ifc "
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

    # ── Check 2: At least 4 IfcColumn ─────────────────────────────────────
    n_columns = result.get("n_columns", 0)
    if n_columns >= 4:
        score += 25
        feedback_lines.append(
            f"PASS: {n_columns} IfcColumn found (>= 4 required). (+25)"
        )
    elif n_columns >= 2:
        score += 12
        feedback_lines.append(
            f"PARTIAL: {n_columns}/4 columns found. (+12)"
        )
    elif n_columns == 1:
        score += 5
        feedback_lines.append(
            f"PARTIAL: {n_columns}/4 columns found. (+5)"
        )
    else:
        feedback_lines.append(
            "FAIL: No IfcColumn found. (+0)"
        )

    # ── Check 3: At least 4 IfcBeam ───────────────────────────────────────
    n_beams = result.get("n_beams", 0)
    if n_beams >= 4:
        score += 20
        feedback_lines.append(
            f"PASS: {n_beams} IfcBeam found (>= 4 required). (+20)"
        )
    elif n_beams >= 2:
        score += 10
        feedback_lines.append(
            f"PARTIAL: {n_beams}/4 beams found. (+10)"
        )
    elif n_beams == 1:
        score += 4
        feedback_lines.append(
            f"PARTIAL: {n_beams}/4 beams found. (+4)"
        )
    else:
        feedback_lines.append(
            "FAIL: No IfcBeam found. (+0)"
        )

    # ── Check 4: At least 1 IfcSlab ───────────────────────────────────────
    n_slabs = result.get("n_slabs", 0)
    if n_slabs >= 1:
        score += 15
        feedback_lines.append(
            f"PASS: {n_slabs} IfcSlab found. (+15)"
        )
    else:
        feedback_lines.append(
            "FAIL: No IfcSlab found — ground floor slab not modelled. (+0)"
        )

    # ── Check 5: Concrete material defined and assigned ───────────────────
    concrete_present = result.get("concrete_material_present", False)
    n_with_material = result.get("structural_elements_with_material", 0)
    total_structural = result.get("total_structural_elements", 0)
    mat_names = result.get("material_names", [])

    if concrete_present and n_with_material >= 1:
        score += 25
        feedback_lines.append(
            f"PASS: Concrete material defined ({mat_names}) and assigned to "
            f"{n_with_material}/{total_structural} structural elements. (+25)"
        )
    elif concrete_present:
        score += 12
        feedback_lines.append(
            f"PARTIAL: Concrete material defined ({mat_names}) but not associated "
            f"with structural elements via IfcRelAssociatesMaterial. (+12)"
        )
    elif n_with_material >= 1:
        score += 8
        feedback_lines.append(
            f"PARTIAL: Material association found on {n_with_material} elements "
            f"but no concrete-named material detected. Material names: {mat_names}. (+8)"
        )
    else:
        feedback_lines.append(
            f"FAIL: No concrete material defined or assigned. "
            f"Material names found: {mat_names}. (+0)"
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
