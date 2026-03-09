#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_plumbing_schematic(traj, env_info, task_info):
    """
    Verifies the plumbing schematic task.
    
    Scoring Criteria:
    - Files Exist & Created During Task (15 pts)
    - Fixtures Identified (25 pts)
    - Blue/Cold Lines Present (20 pts)
    - Red/Hot Lines Present (20 pts)
    - Logic: Toilets have NO hot water (20 pts)
    """
    
    # 1. Setup & Copy
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Parse Results
    analysis = result.get('analysis', {})
    files_ok = result.get('file_created_during_task', False) and result.get('png_exists', False)
    
    score = 0
    feedback = []

    # Criterion 1: Files (15 pts)
    if files_ok:
        score += 15
        feedback.append("Files created successfully.")
    else:
        feedback.append("Missing .drawio or .png output files.")

    # Stop if analysis failed (invalid XML or no file)
    if not analysis.get('valid_xml', False):
        return {"passed": False, "score": score, "feedback": " | ".join(feedback) + " Invalid or missing draw.io file."}

    # Criterion 2: Fixtures (25 pts)
    # Expected: Toilets, Sinks, Heater, Meter, Main, Shower
    fixtures = analysis.get('fixtures_found', {})
    total_fixtures = sum(fixtures.values())
    
    # We want at least 1 toilet, 1 sink, 1 heater, 1 meter/main
    has_toilet = fixtures.get('toilet', 0) > 0
    has_sink = fixtures.get('sink', 0) > 0
    has_heater = fixtures.get('heater', 0) > 0
    has_supply = (fixtures.get('main', 0) + fixtures.get('meter', 0)) > 0
    
    if total_fixtures >= 6 and has_toilet and has_sink and has_heater:
        score += 25
        feedback.append(f"Fixtures identified: {total_fixtures}.")
    elif total_fixtures >= 4:
        score += 15
        feedback.append(f"Some fixtures identified ({total_fixtures}), but missing key components.")
    else:
        feedback.append(f"Too few fixtures identified ({total_fixtures}). Did you label them?")

    # Criterion 3: Cold/Blue Lines (20 pts)
    cold_edges = analysis.get('color_counts', {}).get('cold', 0)
    if cold_edges >= 5:
        score += 20
        feedback.append(f"Cold water lines present ({cold_edges}).")
    elif cold_edges > 0:
        score += 10
        feedback.append("Few cold water lines.")
    else:
        feedback.append("No blue/cold lines detected.")

    # Criterion 4: Hot/Red Lines (20 pts)
    hot_edges = analysis.get('color_counts', {}).get('hot', 0)
    if hot_edges >= 3:
        score += 20
        feedback.append(f"Hot water lines present ({hot_edges}).")
    elif hot_edges > 0:
        score += 10
        feedback.append("Few hot water lines.")
    else:
        feedback.append("No red/hot lines detected.")

    # Criterion 5: Logic - Toilet Check (20 pts)
    # Start with full points, deduct for violations
    violations = analysis.get('violations', [])
    logic_score = 20
    
    if has_toilet:
        if violations:
            logic_score = 0
            feedback.append(f"Logic Fail: {violations[0]}")
        else:
            feedback.append("Logic Pass: Toilets are cold-only.")
    else:
        # No toilet found to verify logic against
        logic_score = 0
        feedback.append("Logic Check: No toilets found to verify.")
        
    score += logic_score

    # Final tally
    passed = score >= 60 and files_ok
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }