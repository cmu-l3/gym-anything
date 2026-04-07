#!/usr/bin/env python3
"""
Verifier for spatial_hierarchy_remediation task.

Scoring rubric (100 points total, pass threshold = 80):
  - file_is_new             : 10 pts (output IFC created/modified during task)
  - nomenclature_correct    : 15 pts ("Ground" and "First" found in storey names; 7 pts for one)
  - elevations_distinct     : 10 pts (At least 2 storeys with distinct Z elevations)
  - building_flattened_fixed: 15 pts (IfcBuilding contains exactly 0 direct elements)
  - lower_storey_elements   : 25 pts (>= 10 elements in lower storey)
  - upper_storey_elements   : 25 pts (>= 10 elements in upper storey)

Anti-gaming: If an agent simply creates one storey and dumps all 33 elements into it,
they will score: 10 (file) + 7 (nomenclature) + 0 (elevations) + 15 (building fixed) + 25 (lower elements) + 0 (upper elements) = 57/100, which fails the threshold of 80.
"""

import json
import os
import tempfile

def verify_spatial_hierarchy_remediation(traj, env_info, task_info):
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
        copy_from_env("/tmp/remediation_result.json", tmp_path)
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
                "FAIL: Output IFC file /home/ga/BIMProjects/fzk_repaired.ifc "
                "was not created. Score: 0/100."
            ),
        }

    # ── Check 1: File is newly created during this task session (10 pts) ──
    file_mtime = result.get("file_mtime", 0.0)
    task_start = result.get("task_start", 0.0)
    if task_start > 0 and file_mtime > task_start:
        score += 10
        feedback_lines.append("PASS: Output IFC file was created/saved during this task session. (+10)")
    else:
        feedback_lines.append(
            "FAIL: Output file was not modified during the task "
            f"(file_mtime={file_mtime:.1f}, task_start={task_start:.1f}). (+0)"
        )

    # ── Prepare storey data ───────────────────────────────────────────────
    storeys = result.get("storeys", [])
    storey_names = [s.get("name", "").lower() for s in storeys]
    
    # ── Check 2: Nomenclature (15 pts) ────────────────────────────────────
    has_ground = any("ground" in name for name in storey_names)
    has_first = any("first" in name for name in storey_names)
    
    if has_ground and has_first:
        score += 15
        feedback_lines.append("PASS: Storey nomenclature correct ('Ground' and 'First' present). (+15)")
    elif has_ground or has_first:
        score += 7
        feedback_lines.append(f"PARTIAL: Storey nomenclature partially correct (Found: {storey_names}). (+7)")
    else:
        feedback_lines.append(f"FAIL: Required storey names not found (Found: {storey_names}). (+0)")

    # ── Check 3: Distinct Elevations (10 pts) ─────────────────────────────
    # storeys are already sorted by elevation in the export script
    if len(storeys) >= 2:
        elev1 = storeys[0].get("elevation", 0.0)
        elev2 = storeys[-1].get("elevation", 0.0)
        if abs(elev2 - elev1) > 1.0: # At least 1 meter distinct
            score += 10
            feedback_lines.append(f"PASS: Distinct elevations found ({elev1} and {elev2}). (+10)")
        else:
            feedback_lines.append(f"FAIL: Storeys do not have distinctly separated elevations. (+0)")
    else:
        feedback_lines.append("FAIL: Less than 2 storeys exist, cannot verify elevation split. (+0)")

    # ── Check 4: Building flattened fixed (15 pts) ────────────────────────
    direct_elements = result.get("building_direct_elements", 999)
    if direct_elements == 0:
        score += 15
        feedback_lines.append("PASS: IfcBuilding contains 0 direct geometric elements (hierarchy fixed). (+15)")
    elif direct_elements <= 5:
        score += 7
        feedback_lines.append(f"PARTIAL: IfcBuilding contains {direct_elements} straggler direct elements. (+7)")
    else:
        feedback_lines.append(f"FAIL: IfcBuilding still contains {direct_elements} direct elements. Hierarchy remains corrupted. (+0)")

    # ── Check 5 & 6: Element Assignments (25 pts each) ────────────────────
    lower_count = 0
    upper_count = 0
    
    if len(storeys) >= 2:
        # Assuming sorted by elevation, first is lower, last is upper
        lower_count = storeys[0].get("element_count", 0)
        upper_count = storeys[-1].get("element_count", 0)
    elif len(storeys) == 1:
        # If they dumped everything in one, count it as the lower (or upper depending on elevation, but usually lower)
        lower_count = storeys[0].get("element_count", 0)

    # Lower elements
    if lower_count >= 10:
        score += 25
        feedback_lines.append(f"PASS: Lower storey contains {lower_count} elements (>= 10 expected). (+25)")
    elif lower_count >= 5:
        score += 12
        feedback_lines.append(f"PARTIAL: Lower storey contains {lower_count} elements. (+12)")
    else:
        feedback_lines.append(f"FAIL: Lower storey contains only {lower_count} elements. (+0)")

    # Upper elements
    if upper_count >= 10:
        score += 25
        feedback_lines.append(f"PASS: Upper storey contains {upper_count} elements (>= 10 expected). (+25)")
    elif upper_count >= 5:
        score += 12
        feedback_lines.append(f"PARTIAL: Upper storey contains {upper_count} elements. (+12)")
    else:
        feedback_lines.append(f"FAIL: Upper storey contains only {upper_count} elements. (+0)")

    passed = score >= 80
    feedback_lines.append(
        f"\nTotal score: {score}/100. {'PASSED' if passed else 'FAILED'} (threshold: 80)."
    )

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_lines),
    }