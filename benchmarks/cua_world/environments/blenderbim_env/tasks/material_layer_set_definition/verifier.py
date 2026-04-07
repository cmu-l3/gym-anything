#!/usr/bin/env python3
"""
Verifier for material_layer_set_definition task.

Scoring rubric (100 points total, pass threshold = 65):
  - file_is_new              : 15 pts  (output IFC created/modified during task)
  - layer_sets_count         : 20 pts  (>= 2 IfcMaterialLayerSet; partial at 1)
  - layers_with_thickness    : 25 pts  (>= 6 IfcMaterialLayer with >0 thickness; partials at >=3, >=1)
  - distinct_materials       : 15 pts  (>= 3 distinct IfcMaterial names; partials at >=2, >=1)
  - elements_associated      : 25 pts  (>= 8 elements linked to layer sets; partials at >=4, >=1)
"""

import json
import os
import tempfile


def verify_material_layer_set_definition(traj, env_info, task_info):
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
        copy_from_env("/tmp/material_layers_result.json", tmp_path)
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
                "FAIL: Output IFC file /home/ga/BIMProjects/fzk_envelope_spec.ifc "
                "was not created. Score: 0/100."
            ),
        }

    # ── Check 1: File is newly created during this task session ───────────
    file_mtime = result.get("file_mtime", 0.0)
    task_start = result.get("task_start", 0.0)
    if task_start > 0 and file_mtime > task_start:
        score += 15
        feedback_lines.append("PASS: Output IFC file was saved during this task session. (+15)")
    else:
        feedback_lines.append(
            "FAIL: Output file was not modified during the task "
            f"(file_mtime={file_mtime:.1f}, task_start={task_start:.1f}). (+0)"
        )

    # ── Check 2: At least 2 IfcMaterialLayerSet ──────────────────────────
    n_layer_sets = result.get("n_layer_sets", 0)
    layer_set_names = result.get("layer_set_names", [])
    if n_layer_sets >= 2:
        score += 20
        feedback_lines.append(
            f"PASS: {n_layer_sets} IfcMaterialLayerSet(s) found. (>= 2 required). (+20)"
        )
    elif n_layer_sets == 1:
        score += 10
        feedback_lines.append(
            f"PARTIAL: 1 IfcMaterialLayerSet found out of 2 expected. (+10)"
        )
    else:
        feedback_lines.append(
            "FAIL: No IfcMaterialLayerSet found. (+0)"
        )

    # ── Check 3: At least 6 IfcMaterialLayer (with thickness > 0) ─────────
    n_layers = result.get("n_layers_valid_thickness", 0)
    if n_layers >= 6:
        score += 25
        feedback_lines.append(
            f"PASS: {n_layers} IfcMaterialLayer entities with >0 thickness found (>= 6 required). (+25)"
        )
    elif n_layers >= 3:
        score += 15
        feedback_lines.append(
            f"PARTIAL: {n_layers} IfcMaterialLayer entities with >0 thickness found. (+15)"
        )
    elif n_layers >= 1:
        score += 6
        feedback_lines.append(
            f"PARTIAL: {n_layers} IfcMaterialLayer entities with >0 thickness found. (+6)"
        )
    else:
        feedback_lines.append(
            "FAIL: No valid IfcMaterialLayer entities with >0 thickness found. (+0)"
        )

    # ── Check 4: At least 3 Distinct Materials ───────────────────────────
    n_materials = result.get("n_distinct_materials", 0)
    mat_names = result.get("distinct_material_names", [])
    
    if n_materials >= 3:
        score += 15
        feedback_lines.append(
            f"PASS: {n_materials} distinct materials found (>= 3 required). {mat_names[:5]}... (+15)"
        )
    elif n_materials >= 2:
        score += 8
        feedback_lines.append(
            f"PARTIAL: {n_materials} distinct materials found. (+8)"
        )
    elif n_materials >= 1:
        score += 3
        feedback_lines.append(
            f"PARTIAL: {n_materials} distinct materials found. (+3)"
        )
    else:
        feedback_lines.append(
            "FAIL: No distinct named materials found. (+0)"
        )

    # ── Check 5: Elements associated with Layer Sets ──────────────────────
    n_elements = result.get("elements_with_layer_sets", 0)
    if n_elements >= 8:
        score += 25
        feedback_lines.append(
            f"PASS: {n_elements} elements associated with material layer sets (>= 8 required). (+25)"
        )
    elif n_elements >= 4:
        score += 15
        feedback_lines.append(
            f"PARTIAL: {n_elements} elements associated with material layer sets. (+15)"
        )
    elif n_elements >= 1:
        score += 6
        feedback_lines.append(
            f"PARTIAL: {n_elements} elements associated with material layer sets. (+6)"
        )
    else:
        feedback_lines.append(
            "FAIL: No building elements found associated with material layer sets. (+0)"
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