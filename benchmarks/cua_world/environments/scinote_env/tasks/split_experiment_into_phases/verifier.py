#!/usr/bin/env python3
"""Verifier for split_experiment_into_phases task."""

import json
import tempfile
import os

def verify_split_experiment_into_phases(traj, env_info, task_info):
    """Verify that experiment was split and renamed."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/split_experiment_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback_parts = []
    
    task_start = int(result.get('task_start', 0))
    orig_exp_id = str(result.get('original_experiment_id', ''))
    orig_exp_name = result.get('original_experiment_current_name', '')
    orig_exp_updated = float(result.get('original_experiment_updated', 0))
    
    new_exp_id = str(result.get('new_experiment_id', ''))
    new_exp_created = float(result.get('new_experiment_created', 0))
    tasks = result.get('tasks', {})
    
    # Criterion 1: Original Experiment renamed (20 pts)
    if orig_exp_name.strip().lower() == 'phase 1: transfection':
        if orig_exp_updated > task_start:
            score += 20
            feedback_parts.append("Original experiment correctly renamed during task")
        else:
            feedback_parts.append("Original experiment has correct name but was not modified during task (anti-gaming)")
    else:
        feedback_parts.append(f"Original experiment name mismatch: expected 'Phase 1: Transfection', got '{orig_exp_name}'")
        
    # Criterion 2: New Experiment created (20 pts)
    if new_exp_id and new_exp_id != "0" and new_exp_id != orig_exp_id:
        if new_exp_created > task_start:
            score += 20
            feedback_parts.append("New experiment 'Phase 2: Selection' created during task")
        else:
            feedback_parts.append("New experiment exists but was created before task started (anti-gaming)")
    else:
        feedback_parts.append("New experiment 'Phase 2: Selection' not found")
        
    # Criterion 3: Task 'Selection' moved (25 pts)
    sel_exp_id = str(tasks.get("Selection", ""))
    if new_exp_id and new_exp_id != "0" and sel_exp_id == new_exp_id:
        score += 25
        feedback_parts.append("Task 'Selection' moved to new experiment")
    elif sel_exp_id == orig_exp_id:
        feedback_parts.append("Task 'Selection' is still in the original experiment")
    else:
        feedback_parts.append("Task 'Selection' not in the expected experiment")
        
    # Criterion 4: Task 'Expansion' moved (25 pts)
    exp_exp_id = str(tasks.get("Expansion", ""))
    if new_exp_id and new_exp_id != "0" and exp_exp_id == new_exp_id:
        score += 25
        feedback_parts.append("Task 'Expansion' moved to new experiment")
    elif exp_exp_id == orig_exp_id:
        feedback_parts.append("Task 'Expansion' is still in the original experiment")
    else:
        feedback_parts.append("Task 'Expansion' not in the expected experiment")
        
    # Criterion 5: Other tasks stayed in original experiment (10 pts)
    stay_tasks = ["Media Prep", "Cell Seeding", "Transfection Mix", "Incubation"]
    stay_correct = True
    for t in stay_tasks:
        if str(tasks.get(t, "")) != orig_exp_id:
            stay_correct = False
            feedback_parts.append(f"Task '{t}' incorrectly moved")
            break
            
    if stay_correct:
        score += 10
        feedback_parts.append("Other 4 tasks correctly remained in the original experiment")
        
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": {
            "renamed_original": orig_exp_name.strip().lower() == 'phase 1: transfection',
            "created_new": bool(new_exp_id and new_exp_id != "0"),
            "moved_selection": bool(new_exp_id and new_exp_id != "0" and sel_exp_id == new_exp_id),
            "moved_expansion": bool(new_exp_id and new_exp_id != "0" and exp_exp_id == new_exp_id),
            "others_stayed": stay_correct
        }
    }