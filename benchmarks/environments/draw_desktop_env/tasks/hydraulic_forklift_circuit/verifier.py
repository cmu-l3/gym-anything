#!/usr/bin/env python3
import json
import os
import sys

def verify_hydraulic_forklift_circuit(traj, env_info, task_info):
    """
    Verifies the creation of a hydraulic circuit diagram in draw.io.
    Checks for file existence, use of correct shape library, and component presence.
    """
    # 1. Retrieve result data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy failed"}

    local_result_path = "task_result.json"
    try:
        copy_from_env("/tmp/final_result.json", local_result_path)
        with open(local_result_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(local_result_path):
            os.remove(local_result_path)

    score = 0
    feedback = []

    # 2. Score Calculation
    
    # Criterion 1: File Saved (10 pts)
    if result.get("file_exists") and result.get("file_modified"):
        score += 10
        feedback.append("Draw.io file saved and modified.")
    else:
        feedback.append("Draw.io file missing or not modified.")

    # Criterion 2: PNG Export (10 pts)
    if result.get("png_exists"):
        score += 10
        feedback.append("PNG export found.")
    else:
        feedback.append("PNG export missing.")

    # Criterion 3: Fluid Power Library Usage (25 pts)
    # We look for specific style signatures in the XML
    fp_shapes = result.get("fluid_power_shapes", 0)
    total_shapes = result.get("shape_count", 0)
    
    if fp_shapes >= 3:
        score += 25
        feedback.append(f"Correct Fluid Power library symbols used ({fp_shapes} found).")
    elif fp_shapes > 0:
        score += 10
        feedback.append(f"Some Fluid Power symbols used ({fp_shapes}), but mixed with generic shapes.")
    else:
        feedback.append("No Fluid Power library symbols detected. Generic shapes used?")

    # Criterion 4: Key Components Presence (25 pts)
    # Pump, Cylinder, Valve are the most critical
    comps = result.get("components_found", {})
    comp_score = 0
    required = ["pump", "cylinder", "valve"]
    found_req = [k for k in required if comps.get(k)]
    
    if len(found_req) == 3:
        comp_score = 25
    else:
        comp_score = len(found_req) * 8
    
    score += comp_score
    feedback.append(f"Components identified: {', '.join(found_req)} ({comp_score}/25 pts).")

    # Criterion 5: Connectivity (20 pts)
    # Check edges. A circuit needs lines connecting things.
    edges = result.get("edge_count", 0)
    conn_score = result.get("connectivity_score", 0) # edges with valid source+target
    
    if conn_score >= 4:
        score += 20
        feedback.append("Components connected properly.")
    elif edges >= 4:
        score += 10
        feedback.append("Lines drawn, but connectivity logic unclear in XML.")
    else:
        feedback.append("Insufficient connections (lines) between components.")

    # Criterion 6: Labels (10 pts)
    labels = result.get("labels_found", [])
    if len(labels) >= 3:
        score += 10
        feedback.append("Text labels detected.")
    else:
        feedback.append("Few or no text labels found.")

    # Final Pass Determination
    # Must have used the library (at least partially) and saved the file
    passed = (score >= 60) and (fp_shapes > 0)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }