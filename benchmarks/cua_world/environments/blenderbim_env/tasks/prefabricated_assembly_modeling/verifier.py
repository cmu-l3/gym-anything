#!/usr/bin/env python3
"""
Verifier for prefabricated_assembly_modeling task.

Scoring rubric (100 points total, pass threshold = 70):
  - file_is_new          : 15 pts
  - components_exist     : 30 pts (Assembly=1, Walls>=3, Slab>=1, Terminal>=1)
  - component_aggregation: 30 pts (Sub-components linked to Assembly via IfcRelAggregates)
  - spatial_containment  : 25 pts (Assembly linked to Storey)
"""

import json
import os
import tempfile


def verify_prefabricated_assembly_modeling(traj, env_info, task_info):
    score = 0
    feedback_lines = []

    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0,
                "feedback": "copy_from_env not available in env_info."}

    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as f:
        tmp_path = f.name

    try:
        copy_from_env("/tmp/prefab_result.json", tmp_path)
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
                "FAIL: Output IFC file /home/ga/BIMProjects/prefab_bathroom_pod.ifc "
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

    # ── Check 2: Components existence ─────────────────────────────────────
    n_assemblies = result.get("n_assemblies", 0)
    n_walls = result.get("n_walls", 0)
    n_slabs = result.get("n_slabs", 0)
    n_terminals = result.get("n_terminals", 0)

    has_assembly = n_assemblies >= 1
    has_walls = n_walls >= 3
    has_slab = n_slabs >= 1
    has_terminal = n_terminals >= 1

    components_met = sum([has_assembly, has_walls, has_slab, has_terminal])
    
    if components_met == 4:
        score += 30
        feedback_lines.append(f"PASS: All required component types created (Assembly:{n_assemblies}, Walls:{n_walls}, Slabs:{n_slabs}, Terminals:{n_terminals}). (+30)")
    elif components_met >= 2 and has_assembly:
        score += 15
        feedback_lines.append(f"PARTIAL: Some components missing (Assembly:{n_assemblies}, Walls:{n_walls}, Slabs:{n_slabs}, Terminals:{n_terminals}). (+15)")
    else:
        feedback_lines.append(f"FAIL: Required components not found or Assembly missing (Assembly:{n_assemblies}, Walls:{n_walls}, Slabs:{n_slabs}, Terminals:{n_terminals}). (+0)")

    # ── Check 3: Component Aggregation ────────────────────────────────────
    agg_walls = result.get("aggregated_walls", 0)
    agg_slabs = result.get("aggregated_slabs", 0)
    agg_terminals = result.get("aggregated_terminals", 0)

    agg_has_walls = agg_walls >= 3
    agg_has_slab = agg_slabs >= 1
    agg_has_terminal = agg_terminals >= 1

    agg_met = sum([agg_has_walls, agg_has_slab, agg_has_terminal])

    if agg_met == 3:
        score += 30
        feedback_lines.append(f"PASS: All required components successfully aggregated into the Assembly. (+30)")
    elif agg_met > 0 or (agg_walls + agg_slabs + agg_terminals) > 0:
        score += 15
        feedback_lines.append(f"PARTIAL: Some components aggregated, but not all required. (Aggregated -> Walls:{agg_walls}, Slabs:{agg_slabs}, Terminals:{agg_terminals}). (+15)")
    else:
        feedback_lines.append("FAIL: No components were aggregated into the IfcElementAssembly. (+0)")

    # ── Check 4: Spatial Containment ──────────────────────────────────────
    is_contained = result.get("assembly_is_contained", False)
    if is_contained:
        score += 25
        feedback_lines.append("PASS: IfcElementAssembly is spatially contained in a Storey. (+25)")
    else:
        feedback_lines.append("FAIL: IfcElementAssembly is not spatially contained (IfcRelContainedInSpatialStructure missing). (+0)")

    # ── Final Verdict ─────────────────────────────────────────────────────
    passed = score >= 70
    feedback_lines.append(f"\nTotal score: {score}/100. {'PASSED' if passed else 'FAILED'} (threshold: 70).")

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_lines)
    }