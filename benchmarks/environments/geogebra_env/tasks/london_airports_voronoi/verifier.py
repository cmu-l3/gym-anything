#!/usr/bin/env python3
import json
import tempfile
import os
import math
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_london_airports_voronoi(traj, env_info, task_info):
    """
    Verifies the London Airports Voronoi task.
    
    Criteria:
    1. File created during task (20 pts)
    2. 6 Airports plotted correctly (+/- tolerance) (30 pts)
    3. List object exists (15 pts)
    4. Voronoi command used (25 pts)
    5. Text annotation present (10 pts)
    
    Pass threshold: 70 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}
    
    # 1. Load results from VM
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}

    score = 0
    feedback = []
    
    # Metadata for expected values
    metadata = task_info.get('metadata', {})
    expected_airports = metadata.get('airports', {
        "LHR": [-26, 3], "LGW": [-2, -42], "STN": [50, 52],
        "LTN": [-36, 53], "LCY": [11, 3], "SEN": [63, 6]
    })
    tolerance = metadata.get('tolerance', 1.5)

    # CRITERION 1: File check (20 pts)
    if result.get('file_found') and result.get('file_created_during_task'):
        score += 20
        feedback.append("File 'london_airports_voronoi.ggb' saved correctly (+20)")
    elif result.get('file_found'):
        feedback.append("File found but not modified during task session (0/20)")
    else:
        feedback.append("File not found (0/20)")

    # CRITERION 2: Points check (30 pts - 5 per airport)
    found_points = result.get('points_found', [])
    matched_count = 0
    matched_codes = []
    
    for code, (ex, ey) in expected_airports.items():
        match = False
        for p in found_points:
            # Distance check
            dist = math.sqrt((p['x'] - ex)**2 + (p['y'] - ey)**2)
            if dist <= tolerance:
                match = True
                break
        if match:
            matched_count += 1
            matched_codes.append(code)
    
    points_score = matched_count * 5
    score += points_score
    feedback.append(f"Airports plotted: {matched_count}/6 ({', '.join(matched_codes)}) (+{points_score})")

    # CRITERION 3: List creation (15 pts)
    if result.get('list_command_found'):
        score += 15
        feedback.append("List of points created (+15)")
    else:
        feedback.append("No list object found. Did you create a list like 'list1={A,B...}'? (0/15)")

    # CRITERION 4: Voronoi Command (25 pts)
    if result.get('voronoi_command_found'):
        score += 25
        feedback.append("Voronoi command applied (+25)")
    else:
        feedback.append("Voronoi command not found (0/25)")

    # CRITERION 5: Text Annotation (10 pts)
    if result.get('text_annotation_found'):
        score += 10
        feedback.append("Text label found (+10)")
    else:
        feedback.append("No text label found (0/10)")

    # VLM Check (Secondary Verification)
    # Using trajectory to confirm visual output if programmatic check is borderline
    # For this specific task, programmatic check is very robust, but we can verify visibility
    # This section is optional logic for the 'verifier.py' pattern
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }