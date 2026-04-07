#!/usr/bin/env python3
"""
Verifier for av_it_infrastructure_modeling task.

Agent must model:
  - 2x IfcAudioVisualAppliance (PredefinedType: DISPLAY)
  - 2x IfcCommunicationsAppliance (PredefinedType: ROUTER or NETWORKAPPLIANCE)
All items must have valid Names, 3D Geometry, and Spatial Containment.

Scoring rubric (100 points total, pass threshold = 70):
  - file_saved_during_task : 10 pts
  - av_appliances_typed    : 20 pts (>= 2 = 20 pts, 1 = 10 pts)
  - comms_appliances_typed : 20 pts (>= 2 = 20 pts, 1 = 10 pts)
  - valid_naming           : 10 pts (Checked on valid typed objects)
  - geometry_present       : 20 pts (Checked on valid typed objects)
  - spatial_containment    : 20 pts (Checked on valid typed objects)
"""

import json
import os
import tempfile


def verify_av_it_infrastructure_modeling(traj, env_info, task_info):
    score = 0
    feedback_lines = []

    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available."}

    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as f:
        tmp_path = f.name

    try:
        copy_from_env("/tmp/av_it_result.json", tmp_path)
        with open(tmp_path, "r") as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
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
                "FAIL: Output IFC file /home/ga/BIMProjects/fzk_smart_home.ifc "
                "was not created. Score: 0/100."
            ),
        }

    # ── Criterion 1: File newly created/saved (10 pts) ────────────────────
    file_mtime = result.get("file_mtime", 0.0)
    task_start = result.get("task_start", 0.0)
    if task_start > 0 and file_mtime > task_start:
        score += 10
        feedback_lines.append("PASS: Output IFC was saved during this task session. (+10)")
    else:
        feedback_lines.append("FAIL: Output file not modified during task. (+0)")

    # ── Gather appliances and filter by correct predefined types ──────────
    av_all = result.get("av_appliances", [])
    comms_all = result.get("comms_appliances", [])

    # Valid Typed AVs
    valid_avs = [a for a in av_all if a.get("predefined_type") == "DISPLAY"]
    # Valid Typed Comms
    valid_comms = [c for c in comms_all if c.get("predefined_type") in ("ROUTER", "NETWORKAPPLIANCE")]

    all_valid_items = valid_avs + valid_comms
    total_valid_typed = len(all_valid_items)

    # ── Criterion 2: IfcAudioVisualAppliance (20 pts) ─────────────────────
    if len(valid_avs) >= 2:
        score += 20
        feedback_lines.append(f"PASS: {len(valid_avs)} IfcAudioVisualAppliance(DISPLAY) found. (+20)")
    elif len(valid_avs) == 1:
        score += 10
        feedback_lines.append(f"PARTIAL: 1 IfcAudioVisualAppliance(DISPLAY) found. (+10)")
    else:
        feedback_lines.append("FAIL: No correctly typed IfcAudioVisualAppliance found. (+0)")

    # ── Criterion 3: IfcCommunicationsAppliance (20 pts) ──────────────────
    if len(valid_comms) >= 2:
        score += 20
        feedback_lines.append(f"PASS: {len(valid_comms)} IfcCommunicationsAppliance(ROUTER) found. (+20)")
    elif len(valid_comms) == 1:
        score += 10
        feedback_lines.append(f"PARTIAL: 1 IfcCommunicationsAppliance(ROUTER) found. (+10)")
    else:
        feedback_lines.append("FAIL: No correctly typed IfcCommunicationsAppliance found. (+0)")

    # If no valid items were found, we skip the remaining checks (score remains as calculated)
    if total_valid_typed == 0:
        feedback_lines.append("FAIL: Cannot check naming/geometry/containment because no valid appliances exist. (+0)")
        passed = score >= 70
        return {"passed": passed, "score": score, "feedback": "\n".join(feedback_lines)}

    # ── Criterion 4: Naming (10 pts) ──────────────────────────────────────
    proper_names = 0
    for av in valid_avs:
        name = av.get("name", "").lower()
        if "display" in name or "tv" in name:
            proper_names += 1
            
    for comm in valid_comms:
        name = comm.get("name", "").lower()
        if "router" in name or "ap" in name or "access point" in name or "wifi" in name:
            proper_names += 1

    if proper_names == total_valid_typed:
        score += 10
        feedback_lines.append(f"PASS: All {total_valid_typed} typed appliances have correct keywords in Name. (+10)")
    elif proper_names > 0:
        score += 5
        feedback_lines.append(f"PARTIAL: {proper_names}/{total_valid_typed} appliances have correct keywords. (+5)")
    else:
        feedback_lines.append("FAIL: No appliances have correct keywords (Display/TV/Router/AP). (+0)")

    # ── Criterion 5: Geometry (20 pts) ────────────────────────────────────
    with_geometry = sum(1 for item in all_valid_items if item.get("has_geometry"))
    if with_geometry == total_valid_typed:
        score += 20
        feedback_lines.append(f"PASS: All {total_valid_typed} typed appliances have 3D Representation and ObjectPlacement. (+20)")
    elif with_geometry > 0:
        geom_ratio = with_geometry / total_valid_typed
        pts = int(20 * geom_ratio)
        score += pts
        feedback_lines.append(f"PARTIAL: {with_geometry}/{total_valid_typed} appliances have geometry. (+{pts})")
    else:
        feedback_lines.append("FAIL: None of the appliances possess 3D Representation/Placement. (+0)")

    # ── Criterion 6: Spatial Containment (20 pts) ─────────────────────────
    contained = sum(1 for item in all_valid_items if item.get("contained_in_storey"))
    if contained == total_valid_typed:
        score += 20
        feedback_lines.append(f"PASS: All {total_valid_typed} typed appliances are contained in an IfcBuildingStorey. (+20)")
    elif contained > 0:
        cont_ratio = contained / total_valid_typed
        pts = int(20 * cont_ratio)
        score += pts
        feedback_lines.append(f"PARTIAL: {contained}/{total_valid_typed} appliances are spatially contained. (+{pts})")
    else:
        feedback_lines.append("FAIL: None of the appliances are spatially contained. (+0)")

    passed = score >= 70
    feedback_lines.append(f"\nTotal score: {score}/100. {'PASSED' if passed else 'FAILED'} (threshold: 70).")

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_lines),
    }