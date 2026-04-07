#!/usr/bin/env python3
"""
Verifier for accessibility_clearance_zone_modeling task.

The agent must create IfcVirtualElement entities representing accessibility clearances.

Scoring rubric (100 points total, pass threshold = 70):
  - file_is_new          : 15 pts (output IFC created/modified during this task)
  - model_integrity      : 10 pts (original FZK-Haus walls must be preserved, >= 10 walls)
  - virtual_elements     : 30 pts (>= 3 IfcVirtualElements; partial at 1-2 elements)
  - naming_convention    : 25 pts (proportional based on up to 3 elements having correct keywords)
  - spatial_containment  : 20 pts (proportional based on up to 3 elements contained in a storey)
"""

import json
import os
import tempfile


def verify_accessibility_clearance_zone_modeling(traj, env_info, task_info):
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
        copy_from_env("/tmp/accessibility_result.json", tmp_path)
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
                "FAIL: Output IFC file /home/ga/BIMProjects/fzk_accessibility.ifc "
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
            f"FAIL: Output file was not modified during the task "
            f"(file_mtime={file_mtime:.1f}, task_start={task_start:.1f}). (+0)"
        )

    # ── Check 2: Model Integrity (original walls preserved) ───────────────
    n_walls = result.get("n_walls", 0)
    if n_walls >= 10:
        score += 10
        feedback_lines.append(f"PASS: Model integrity preserved ({n_walls} walls found). (+10)")
    else:
        feedback_lines.append(f"FAIL: Model integrity compromised. Only {n_walls} walls found. (+0)")

    # ── Check 3: At least 3 IfcVirtualElements ───────────────────────────
    n_virtual = result.get("n_virtual_elements", 0)
    if n_virtual >= 3:
        score += 30
        feedback_lines.append(f"PASS: Found {n_virtual} IfcVirtualElement entities (>= 3 required). (+30)")
    elif n_virtual >= 1:
        partial = 15 if n_virtual == 2 else 10
        score += partial
        feedback_lines.append(f"PARTIAL: Found {n_virtual}/3 IfcVirtualElement entities. (+{partial})")
    else:
        feedback_lines.append("FAIL: No IfcVirtualElement entities found. (+0)")

    # ── Check 4 & 5: Naming Convention and Spatial Containment ────────────
    v_data = result.get("virtual_elements_data", [])
    keywords = ["clearance", "turning", "wheelchair", "access"]
    
    valid_named = 0
    valid_contained = 0

    for v in v_data:
        name = v.get("name", "").lower()
        if any(k in name for k in keywords):
            valid_named += 1
        if v.get("contained", False):
            valid_contained += 1

    # Cap at 3 for proportional scoring max
    calc_named = min(3, valid_named)
    calc_contained = min(3, valid_contained)

    if calc_named > 0:
        pts_named = int((calc_named / 3.0) * 25)
        score += pts_named
        feedback_lines.append(f"PASS/PARTIAL: {valid_named} element(s) correctly named with keywords. (+{pts_named})")
    else:
        feedback_lines.append("FAIL: No virtual elements contain the required naming keywords. (+0)")

    if calc_contained > 0:
        pts_contained = int((calc_contained / 3.0) * 20)
        score += pts_contained
        feedback_lines.append(f"PASS/PARTIAL: {valid_contained} element(s) spatially contained in a building storey. (+{pts_contained})")
    else:
        feedback_lines.append("FAIL: No virtual elements are spatially contained in a storey. (+0)")

    passed = score >= 70
    
    # Must have at least one properly classified, named, and contained element to pass
    has_fully_valid_element = (n_virtual >= 1 and valid_named >= 1 and valid_contained >= 1)
    if passed and not has_fully_valid_element:
        passed = False
        feedback_lines.append("\nOVERRIDE FAIL: Score passed threshold, but agent did not fully complete at least one element correctly (name + containment).")

    feedback_lines.append(
        f"\nTotal score: {score}/100. {'PASSED' if passed else 'FAILED'} (threshold: 70)."
    )

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_lines),
    }