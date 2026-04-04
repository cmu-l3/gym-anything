#!/usr/bin/env python3
import json
import os
import sys

def verify_hydraulic_circuit(traj, env_info, task_info):
    """
    Verifies the hydraulic circuit diagram task.
    
    Criteria:
    1. File exists and modified (10 pts)
    2. Fluid Power Library usage (20 pts)
    3. Essential Components: Pump, Tank, Valve, Cylinder (40 pts)
    4. Labels correct (5 pts)
    5. Dashed lines (Pilot/Drain) present (15 pts)
    6. PDF Export exists (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment error: copy unavailable"}

    # Retrieve Result JSON
    import tempfile
    tmp_path = tempfile.mktemp()
    try:
        copy_from_env("/tmp/task_result.json", tmp_path)
        with open(tmp_path, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)

    score = 0
    feedback = []
    
    # 1. File Check (10 pts)
    if data.get("file_exists") and data.get("file_modified"):
        score += 10
    else:
        feedback.append("Diagram file not found or not modified.")

    # 2. PDF Check (10 pts)
    if data.get("pdf_exists"):
        score += 10
    else:
        feedback.append("PDF export not found.")

    analysis = data.get("analysis", {})
    shapes = analysis.get("shapes", [])
    labels = analysis.get("labels", [])
    
    # 3. Fluid Power Library (20 pts)
    if analysis.get("uses_fluid_library"):
        score += 20
    else:
        feedback.append("Did not detect 'Fluid Power' shape library usage.")
    
    # 4. Components (40 pts)
    # Flexible matching
    has_pump = any("pump" in s for s in shapes) or any("P1" in l for l in labels)
    has_valve = any("valve" in s for s in shapes) or any("CV-1" in l for l in labels)
    has_cyl = any("cylinder" in s for s in shapes) or any("CYL-1" in l for l in labels)
    has_tank = any("tank" in s for s in shapes) or any("T1" in l for l in labels)
    
    comps_found = sum([has_pump, has_valve, has_cyl, has_tank])
    score += (comps_found * 10)
    
    if not has_pump: feedback.append("Pump missing.")
    if not has_valve: feedback.append("Control Valve missing.")
    if not has_cyl: feedback.append("Cylinder missing.")
    if not has_tank: feedback.append("Tank missing.")

    # 5. Dashed Lines (15 pts)
    if analysis.get("has_dashed_lines"):
        score += 15
    else:
        feedback.append("No dashed lines (pilot/drain) detected.")

    # 6. Labels (5 pts)
    required_labels = ["P1", "CV-1", "CYL-1"]
    found_labels = 0
    for req in required_labels:
        if any(req in l for l in labels):
            found_labels += 1
    
    if found_labels >= 2:
        score += 5
    elif found_labels == 0:
        feedback.append("Required text labels (P1, CV-1, etc.) missing.")

    # Pass Threshold
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }