#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_human_factors_experiment(traj, env_info, task_info):
    """
    Verify the generation of experimental scenarios.
    
    Criteria:
    1. Directory structure exists (Main dir + 4 condition subdirs).
    2. Visibility is correct in environment.ini for all 4.
    3. Traffic count is correct in othership.ini for all 4.
    4. Manifest CSV exists and contains correct data.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata expectations
    metadata = task_info.get('metadata', {})
    expected_conditions = metadata.get('conditions', {
        "Cond_A_LoVis_LoTraf": {"vis": 0.5, "count": 1},
        "Cond_B_LoVis_HiTraf": {"vis": 0.5, "count": 4},
        "Cond_C_HiVis_LoTraf": {"vis": 12.0, "count": 1},
        "Cond_D_HiVis_HiTraf": {"vis": 12.0, "count": 4}
    })

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    max_score = 100
    feedback = []
    
    # 1. Check Directory Structure (10 pts)
    if result.get('structure_correct', False):
        score += 10
        feedback.append("Root directory structure correct.")
    else:
        feedback.append("Root directory missing or invalid.")
        return {"passed": False, "score": 0, "feedback": "Root directory not found."}

    # 2. Check Scenarios (Factors A & B)
    # Total 70 points available here (17.5 per scenario)
    scenarios = result.get('scenarios', {})
    
    all_vis_correct = True
    all_count_correct = True
    
    for cond_name, expected in expected_conditions.items():
        actual = scenarios.get(cond_name, {})
        
        if not actual.get('exists'):
            feedback.append(f"Missing scenario: {cond_name}")
            all_vis_correct = False
            all_count_correct = False
            continue

        # Check Visibility (20 pts total, 5 per scenario)
        act_vis = actual.get('vis')
        if act_vis is not None and abs(act_vis - expected['vis']) < 0.1:
            score += 5
        else:
            feedback.append(f"{cond_name}: Visibility mismatch (Expected {expected['vis']}, Got {act_vis})")
            all_vis_correct = False

        # Check Traffic Count (30 pts total, 7.5 per scenario)
        act_count = actual.get('ship_count')
        if act_count == expected['count']:
            score += 7.5
        else:
            feedback.append(f"{cond_name}: Ship count mismatch (Expected {expected['count']}, Got {act_count})")
            all_count_correct = False
            
        # Check files modified/created (integrity check) (20 pts total, 5 per scenario)
        if actual.get('modified_during_task'):
             score += 5
        else:
             feedback.append(f"{cond_name}: Files not modified during task time.")

    # 3. Check Manifest (20 pts)
    manifest = result.get('manifest', {})
    if manifest.get('exists'):
        score += 10
        rows = manifest.get('rows', [])
        if len(rows) >= 4:
            score += 10
            feedback.append("Manifest CSV exists and has data.")
        else:
            score += 5
            feedback.append("Manifest exists but seems incomplete (less than 4 rows).")
    else:
        feedback.append("Manifest CSV not found.")

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }