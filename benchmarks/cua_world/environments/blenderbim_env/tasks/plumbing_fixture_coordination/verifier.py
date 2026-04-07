#!/usr/bin/env python3
"""
Verifier for plumbing_fixture_coordination task.

Scoring rubric (100 points total, pass threshold = 65):
  - file_is_new          : 20 pts  (output IFC created/modified during this task)
  - terminal_count       : 20 pts  (>= 3 IfcSanitaryTerminal present; partial 10 pts for 1-2)
  - toilet_typed         : 15 pts  (WCSEAT or TOILETPAN present)
  - sink_typed           : 15 pts  (WASHHANDBASIN or SINK present)
  - bath_typed           : 15 pts  (BATH or SHOWER present)
  - spatial_containment  : 15 pts  (all required terminals are contained in a storey)
"""

import json
import os
import tempfile

def verify_plumbing_fixture_coordination(traj, env_info, task_info):
    score = 0
    feedback_lines = []

    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0,
                "feedback": "copy_from_env not available in env_info."}

    # Copy result JSON from VM
    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as f:
        tmp_path = f.name

    try:
        copy_from_env("/tmp/plumbing_result.json", tmp_path)
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

    # Critical gate: output file must exist
    if not result.get("file_exists", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "FAIL: Output IFC file /home/ga/BIMProjects/fzk_plumbing.ifc "
                "was not created. Score: 0/100."
            ),
        }

    # Check 1: File is newly created during this task session
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

    # Check 2: At least 3 IfcSanitaryTerminal entities
    n_terminals = result.get("n_terminals", 0)
    if n_terminals >= 3:
        score += 20
        feedback_lines.append(f"PASS: Found {n_terminals} IfcSanitaryTerminal entities (>= 3 required). (+20)")
    elif n_terminals >= 1:
        score += 10
        feedback_lines.append(f"PARTIAL: Found {n_terminals}/3 IfcSanitaryTerminal entities. (+10)")
    else:
        feedback_lines.append("FAIL: No IfcSanitaryTerminal entities found. (+0)")

    # Check 3: Toilet PredefinedType
    if result.get("has_toilet", False):
        score += 15
        feedback_lines.append("PASS: Toilet predefined type found (WCSEAT or TOILETPAN). (+15)")
    else:
        feedback_lines.append("FAIL: Missing Toilet predefined type (WCSEAT/TOILETPAN). (+0)")

    # Check 4: Sink PredefinedType
    if result.get("has_sink", False):
        score += 15
        feedback_lines.append("PASS: Sink predefined type found (WASHHANDBASIN or SINK). (+15)")
    else:
        feedback_lines.append("FAIL: Missing Sink predefined type (WASHHANDBASIN/SINK). (+0)")

    # Check 5: Bath/Shower PredefinedType
    if result.get("has_bath", False):
        score += 15
        feedback_lines.append("PASS: Bath predefined type found (BATH or SHOWER). (+15)")
    else:
        feedback_lines.append("FAIL: Missing Bath predefined type (BATH/SHOWER). (+0)")

    # Check 6: Spatial Containment
    n_contained = result.get("n_contained", 0)
    if n_terminals > 0 and n_contained >= min(3, n_terminals):
        score += 15
        feedback_lines.append(f"PASS: {n_contained} terminals are spatially contained in a storey. (+15)")
    elif n_contained > 0:
        score += 7
        feedback_lines.append(f"PARTIAL: Only {n_contained}/{n_terminals} terminals spatially contained. (+7)")
    else:
        feedback_lines.append("FAIL: Sanitary terminals are not spatially contained. (+0)")

    passed = score >= 65
    feedback_lines.append(
        f"\nTotal score: {score}/100. {'PASSED' if passed else 'FAILED'} (threshold: 65)."
    )
    
    # Extra debugging context
    if "predefined_types" in result:
        feedback_lines.append(f"Debug Info - Found Types: {result['predefined_types']}")

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_lines),
    }