#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_roundabout_design(traj, env_info, task_info):
    """
    Verifies the Roundabout Design task.
    
    Scoring Criteria:
    1. File creation & validity (10 pts)
    2. Layer Management (15 pts) - ISLAND, ROADWAY, CENTERLINES exist
    3. Central Island (15 pts) - Circle R=4 at 100,100
    4. Trimming & Filleting (60 pts total):
       - Straight leg lines present (10 pts)
       - NO full outer circle (indicates trimming happened) (20 pts)
       - Outer ring segments (arcs R=12) present (15 pts)
       - Fillets (arcs R=6) present (15 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env missing"}

    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Parse Data
    dxf_data = result.get('dxf_analysis', {})
    file_created = result.get('file_created_during_task', False)
    
    score = 0
    feedback = []

    # Criterion 1: File Exists & Valid (10 pts)
    if file_created and dxf_data.get('valid_dxf'):
        score += 10
        feedback.append("Valid DXF file created.")
    else:
        return {"passed": False, "score": 0, "feedback": "No valid DXF file created during task."}

    # Criterion 2: Layers (15 pts)
    found_layers = set(dxf_data.get('layers_found', []))
    required_layers = {"ISLAND", "ROADWAY", "CENTERLINES"}
    missing = required_layers - found_layers
    if not missing:
        score += 15
        feedback.append("All required layers found.")
    else:
        # Partial credit for layers
        earned = 15 - (len(missing) * 5)
        score += max(0, earned)
        feedback.append(f"Missing layers: {', '.join(missing)}.")

    # Criterion 3: Central Island (15 pts)
    if dxf_data.get('island_circle_found'):
        score += 15
        feedback.append("Central island circle (R=4) found.")
    else:
        feedback.append("Central island circle incorrect or missing.")

    # Criterion 4: Trimming & Filleting (60 pts)
    # Sub-check A: Roadway Lines (10 pts)
    if dxf_data.get('roadway_lines_found'):
        score += 10
        feedback.append("Approach leg lines found.")
    else:
        feedback.append("Missing roadway lines.")

    # Sub-check B: Trimming Verification (Outer Circle Untouched?) (20 pts)
    # If outer_circle_untouched is True, they failed to trim.
    if dxf_data.get('outer_circle_untouched'):
        feedback.append("FAIL: Found full Circle R=12. You must TRIM the intersections.")
    else:
        # If we have lines/arcs but NO full circle, that's good.
        if dxf_data.get('valid_dxf'): # basic sanity check
            score += 20
            feedback.append("Outer circle successfully trimmed (full circle not present).")

    # Sub-check C: Outer Ring Segments (15 pts)
    if dxf_data.get('outer_arcs_found'):
        score += 15
        feedback.append("Outer roadway arcs (R=12) found.")
    else:
        feedback.append("Missing outer roadway arc segments.")

    # Sub-check D: Fillets (15 pts)
    if dxf_data.get('fillet_arcs_found'):
        score += 15
        feedback.append("Fillet arcs (R=6) found.")
    else:
        feedback.append("Missing R=6 fillets.")

    # Final Pass Determination
    # Pass threshold: 75 (needs file, layers, island, and SIGNIFICANT trimming progress)
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }