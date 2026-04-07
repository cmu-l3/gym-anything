#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_task_tracker(traj, env_info, task_info):
    """
    Verify the Sprint tasks and dashboard creation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    metadata = task_info.get('metadata', {})
    expected_tasks = metadata.get('expected_tasks', [])
    
    tasks_data = result.get('tasks', {})
    all_tagged = True
    correct_tasks_count = 0
    
    # 1. Verify the 5 tasks and their custom fields
    for task_meta in expected_tasks:
        title = task_meta['title']
        t_data = tasks_data.get(title, {})
        
        if not t_data.get('exists'):
            feedback_parts.append(f"Task '{title}' not found")
            all_tagged = False
            continue
            
        if not t_data.get('has_tag'):
            feedback_parts.append(f"Task '{title}' missing 'Sprint-Tasks' tag")
            all_tagged = False
            
        if not t_data.get('created_after'):
            feedback_parts.append(f"Task '{title}' not created/modified during session (anti-gaming)")
            
        fields_correct = True
        for field in ['priority', 'assignee', 'status', 'due_date']:
            expected = str(task_meta[field]).strip().lower()
            actual = str(t_data.get(field, "")).strip().lower()
            if actual != expected:
                fields_correct = False
                feedback_parts.append(f"Task '{title}' field '{field}' incorrect: expected '{expected}', got '{actual}'")
                
        if fields_correct and t_data.get('created_after'):
            correct_tasks_count += 1
            score += 10
            feedback_parts.append(f"Task '{title}' has correct fields (+10)")
            
    # 2. Verify tagging requirement
    if all_tagged and len(expected_tasks) > 0 and correct_tasks_count > 0:
        score += 10
        feedback_parts.append("All tasks correctly tagged 'Sprint-Tasks' (+10)")
        
    # 3. Verify Sprint Board structure
    sb = result.get('sprint_board', {})
    if sb.get('exists'):
        if sb.get('created_after'):
            score += 5
            feedback_parts.append("Sprint Board tiddler exists (+5)")
            
            if sb.get('has_list_widget') and sb.get('has_open_filter'):
                score += 10
                feedback_parts.append("Sprint Board has open-tasks filter (+10)")
            else:
                feedback_parts.append("Sprint Board missing open-tasks filter")
                
            if sb.get('has_list_widget') and sb.get('has_high_filter'):
                score += 10
                feedback_parts.append("Sprint Board has high-priority filter (+10)")
            else:
                feedback_parts.append("Sprint Board missing high-priority filter")
                
            if sb.get('has_open_heading') and sb.get('has_high_heading'):
                score += 5
                feedback_parts.append("Sprint Board has section headings (+5)")
            else:
                feedback_parts.append("Sprint Board missing headings")
        else:
            feedback_parts.append("Sprint Board was not created/modified during session")
    else:
        feedback_parts.append("Sprint Board tiddler not found")
        
    # 4. VLM visual trajectory validation
    vlm_scored = False
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        frames = sample_trajectory_frames(traj, n=3)
        if frames:
            prompt = 'The user is using TiddlyWiki to create tiddlers with custom fields (priority, status, assignee). Look at these frames. Do you see evidence of the user interacting with the custom field interface (typically at the bottom of the tiddler editor, with input boxes for field name and field value, and an "add" button) or editing tiddler content? Reply with JSON: {"workflow_observed": true/false}'
            vlm_res = query_vlm(images=frames, prompt=prompt)
            if vlm_res and vlm_res.get('success') and vlm_res.get('parsed', {}).get('workflow_observed'):
                score += 10
                vlm_scored = True
                feedback_parts.append("VLM verified workflow (+10)")
            else:
                feedback_parts.append("VLM could not verify workflow")
    except Exception as e:
        logger.warning(f"VLM verification skipped/failed: {e}")
        
    if not vlm_scored and result.get('gui_save'):
        score += 10
        feedback_parts.append("GUI save detected (VLM fallback) (+10)")
            
    # Verification pass thresholds
    passed = (
        score >= 60 and 
        correct_tasks_count >= 3 and 
        sb.get('exists', False) and 
        (sb.get('has_open_filter', False) or sb.get('has_high_filter', False))
    )
    
    return {
        "passed": bool(passed),
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }